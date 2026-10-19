`default_nettype none

module fp_unit
  import fp_pkg::*;
#(
    parameter  int XLEN   = arch_pkg::XLEN,
    parameter  int NREGS  = arch_pkg::NumRegs,
    localparam int AddrW  = $clog2(NREGS),
    localparam int MaxLat = FpMaxLatency
) (
    input wire clk,
    input wire rst_n,
    input wire core_en,

    input wire                  start,
    input wire                  xstart,
    input wire                  xack,
    input fp_unit_e             unit,
    input wire                  sub,
    input wire                  neg_prod,
    input wire                  neg_add,
    input wire                  to_int,
    input wire                  is_unsigned,
    input wire                  sqrt,
    input wire      [      4:0] funct5,
    input wire      [      2:0] funct3,
    input wire      [      2:0] rm,
    input wire      [AddrW-1:0] rd,
    input wire      [ FLEN-1:0] a,
    input wire      [ FLEN-1:0] b,
    input wire      [ FLEN-1:0] c,
    input wire      [ XLEN-1:0] xa,

    output logic ready,
    output logic idle,
    output logic [NREGS-1:0] reg_busy,

    output logic             wb_valid,
    output logic [AddrW-1:0] wb_rd,
    output logic [ FLEN-1:0] wb_data,
    output logic [      4:0] wb_flags,

    output logic            xvalid,
    output logic [XLEN-1:0] xresult,
    output logic [     4:0] xflags
);

  localparam int CvtW = (FLEN > XLEN) ? FLEN : XLEN;
  localparam int LatW = $clog2(MaxLat + 1);

  typedef enum logic [1:0] {
    SRC_ADD,
    SRC_MUL,
    SRC_FMA,
    SRC_ONE
  } src_e;

  logic [FLEN-1:0] add_result, mul_result, fma_result, misc_result, div_result;
  logic [4:0] add_flags, mul_flags, fma_flags, misc_flags, cvt_flags, div_flags;
  logic [CvtW-1:0] cvt_a, cvt_result;
  logic div_start, div_busy, div_done;

  logic             fixed;
  logic [ LatW-1:0] lat;
  src_e             src;
  logic             fixed_free;
  logic             div_free;

  logic [ MaxLat:0] bk;
  src_e             bk_src      [MaxLat+1];
  logic [AddrW-1:0] bk_rd       [MaxLat+1];

  logic [ FLEN-1:0] one_data;
  logic [      4:0] one_flags;
  logic [ FLEN-1:0] one_d;
  logic [      4:0] one_flags_d;

  logic             div_wait;
  logic             div_pend;
  logic [AddrW-1:0] div_rd;
  logic             div_write;

  logic [NREGS-1:0] busy_q;
  logic [NREGS-1:0] clr_bits;

  fp_add u_add (
      .clk    (clk),
      .rst_n  (rst_n),
      .core_en(core_en),
      .sub    (sub),
      .rm     (rm),
      .a      (a),
      .b      (b),
      .result (add_result),
      .fflags (add_flags)
  );

  fp_mul u_mul (
      .clk    (clk),
      .rst_n  (rst_n),
      .core_en(core_en),
      .rm     (rm),
      .a      (a),
      .b      (b),
      .result (mul_result),
      .fflags (mul_flags)
  );

  fp_fma u_fma (
      .clk     (clk),
      .rst_n   (rst_n),
      .core_en (core_en),
      .neg_prod(neg_prod),
      .neg_add (neg_add),
      .rm      (rm),
      .a       (a),
      .b       (b),
      .c       (c),
      .result  (fma_result),
      .fflags  (fma_flags)
  );

  fp_misc u_misc (
      .funct5(funct5),
      .funct3(funct3),
      .a     (a),
      .b     (b),
      .result(misc_result),
      .fflags(misc_flags)
  );

  assign cvt_a = to_int ? CvtW'(a) : CvtW'(xa);

  fp_cvt #(
      .XLEN(XLEN)
  ) u_cvt (
      .to_int     (to_int),
      .is_unsigned(is_unsigned),
      .half       (1'b0),
      .rm         (rm),
      .a          (cvt_a),
      .result     (cvt_result),
      .fflags     (cvt_flags)
  );

  fp_div_sqrt u_div (
      .clk    (clk),
      .rst_n  (rst_n),
      .core_en(core_en),
      .start  (div_start),
      .sqrt   (sqrt),
      .rm     (rm),
      .a      (a),
      .b      (b),
      .result (div_result),
      .fflags (div_flags),
      .busy   (div_busy),
      .done   (div_done)
  );

  always_comb begin
    fixed       = 1'b1;
    lat         = LatW'(1);
    src         = SRC_ONE;
    one_d       = misc_result;
    one_flags_d = misc_flags;
    case (unit)
      FP_ADD: begin
        lat = LatW'(FpAddLatency);
        src = SRC_ADD;
      end
      FP_MUL: begin
        lat = LatW'(FpMulLatency);
        src = SRC_MUL;
      end
      FP_FMA: begin
        lat = LatW'(FpFmaLatency);
        src = SRC_FMA;
      end
      FP_CVT: begin
        one_d       = FLEN'(cvt_result);
        one_flags_d = cvt_flags;
      end
      FP_MV_W_X: begin
        one_d       = FLEN'(xa);
        one_flags_d = '0;
      end
      FP_DIV_SQRT: fixed = 1'b0;
      default: ;
    endcase
  end

  assign fixed_free = !bk[lat] && !div_wait;
  assign div_free = !div_busy && (!div_wait || div_write);
  assign ready = fixed ? fixed_free : div_free;
  assign div_start = start && !fixed;

  assign div_wait = div_done || div_pend;
  assign div_write = div_wait && !bk[0];

  always_comb begin
    wb_valid = bk[0] || div_write;
    wb_rd    = bk[0] ? bk_rd[0] : div_rd;
    wb_data  = div_result;
    wb_flags = div_flags;
    if (bk[0]) begin
      case (bk_src[0])
        SRC_ADD: begin
          wb_data  = add_result;
          wb_flags = add_flags;
        end
        SRC_MUL: begin
          wb_data  = mul_result;
          wb_flags = mul_flags;
        end
        SRC_FMA: begin
          wb_data  = fma_result;
          wb_flags = fma_flags;
        end
        default: begin
          wb_data  = one_data;
          wb_flags = one_flags;
        end
      endcase
    end
  end

  assign clr_bits = wb_valid ? (NREGS'(1) << wb_rd) : '0;
  assign reg_busy = busy_q & ~clr_bits;
  assign idle = (busy_q == '0);

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      bk       <= '0;
      div_pend <= 1'b0;
      div_rd   <= '0;
      busy_q   <= '0;
      for (int i = 0; i <= MaxLat; i++) begin
        bk_src[i] <= SRC_ONE;
        bk_rd[i]  <= '0;
      end
    end else if (core_en) begin
      for (int i = 0; i < MaxLat; i++) begin
        bk[i]     <= bk[i+1];
        bk_src[i] <= bk_src[i+1];
        bk_rd[i]  <= bk_rd[i+1];
      end
      bk[MaxLat] <= 1'b0;
      if (start && fixed) begin
        bk[lat-1]     <= 1'b1;
        bk_src[lat-1] <= src;
        bk_rd[lat-1]  <= rd;
      end
      if (div_start) div_rd <= rd;
      div_pend <= div_wait && !div_write;
      busy_q   <= (busy_q & ~clr_bits) | (start ? (NREGS'(1) << rd) : '0);
    end
  end

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      one_data  <= '0;
      one_flags <= '0;
    end else if (core_en && start && fixed && (src == SRC_ONE)) begin
      one_data  <= one_d;
      one_flags <= one_flags_d;
    end
  end

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      xvalid  <= 1'b0;
      xresult <= '0;
      xflags  <= '0;
    end else if (core_en) begin
      if (xstart) begin
        xvalid <= 1'b1;
        case (unit)
          FP_MV_X_W: begin
            xresult <= XLEN'(a);
            xflags  <= '0;
          end
          FP_CVT: begin
            xresult <= XLEN'(cvt_result);
            xflags  <= cvt_flags;
          end
          default: begin
            xresult <= XLEN'(misc_result);
            xflags  <= misc_flags;
          end
        endcase
      end else if (xack) begin
        xvalid <= 1'b0;
      end
    end
  end

endmodule

`default_nettype wire
