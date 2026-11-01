`default_nettype none

module vec_fp_lane
  import vec_pkg::*;
  import fp_pkg::Funct5Fsgnj, fp_pkg::Funct5Fminmax, fp_pkg::Funct5Fcmp, fp_pkg::Funct5FmvXW;
  import fp_pkg::Funct3Fsgnj, fp_pkg::Funct3Fsgnjn, fp_pkg::Funct3Fsgnjx;
  import fp_pkg::Funct3Fmin, fp_pkg::Funct3Fmax;
  import fp_pkg::Funct3Fle, fp_pkg::Funct3Flt, fp_pkg::Funct3Feq, fp_pkg::Funct3Fclass;
  import fp_pkg::FpAddLatency, fp_pkg::FpMulLatency, fp_pkg::FpFmaLatency;
  import fp_pkg::FlagW, fp_pkg::RmW;
#(
    parameter  int ExpW  = fp_pkg::ExpW,
    parameter  int FracW = fp_pkg::FracW,
    localparam int FLEN  = 1 + ExpW + FracW
) (
    input  wire                       clk,
    input  wire                       rst_n,
    input  wire                       core_en,
    input  wire                       valid,
    input  wire vec_fop_e             op,
    input  wire           [  RmW-1:0] rm,
    input  wire           [ FLEN-1:0] a,
    input  wire           [ FLEN-1:0] b,
    input  wire           [ FLEN-1:0] c,
    output logic          [ FLEN-1:0] result,
    output logic          [FlagW-1:0] fflags,
    output logic                      result_valid
);

  localparam int Latency = VecFpLatency;
  localparam int UnitLatency = VecFpUnitLatency;
  localparam int AddPad = UnitLatency - FpAddLatency;
  localparam int MulPad = UnitLatency - FpMulLatency;
  localparam int FmaPad = UnitLatency - FpFmaLatency;

  typedef enum logic [2:0] {
    SEL_ADD,
    SEL_MUL,
    SEL_FMA,
    SEL_MISC,
    SEL_MOVE,
    SEL_EST
  } sel_t;

  sel_t            sel_d;
  logic            sub_d;
  logic            neg_prod_d;
  logic            neg_add_d;
  logic            inv_d;
  logic            root_d;
  logic [     4:0] funct5_d;
  logic [     2:0] funct3_d;
  logic [FLEN-1:0] x_d;
  logic [FLEN-1:0] y_d;
  logic [FLEN-1:0] z_d;

  always_comb begin
    sel_d      = SEL_MISC;
    sub_d      = 1'b0;
    neg_prod_d = 1'b0;
    neg_add_d  = 1'b0;
    inv_d      = 1'b0;
    root_d     = 1'b0;
    funct5_d   = Funct5Fcmp;
    funct3_d   = Funct3Feq;
    x_d        = a;
    y_d        = b;
    z_d        = c;
    case (op)
      VEC_FADD:  sel_d = SEL_ADD;
      VEC_FSUB: begin
        sel_d = SEL_ADD;
        sub_d = 1'b1;
      end
      VEC_FRSUB: begin
        sel_d = SEL_ADD;
        sub_d = 1'b1;
        x_d   = b;
        y_d   = a;
      end
      VEC_FMUL:  sel_d = SEL_MUL;
      VEC_FMACC, VEC_FNMACC, VEC_FMSAC, VEC_FNMSAC: begin
        sel_d      = SEL_FMA;
        neg_prod_d = (op == VEC_FNMACC) || (op == VEC_FNMSAC);
        neg_add_d  = (op == VEC_FNMACC) || (op == VEC_FMSAC);
      end
      VEC_FMADD, VEC_FNMADD, VEC_FMSUB, VEC_FNMSUB: begin
        sel_d      = SEL_FMA;
        neg_prod_d = (op == VEC_FNMADD) || (op == VEC_FNMSUB);
        neg_add_d  = (op == VEC_FNMADD) || (op == VEC_FMSUB);
        x_d        = b;
        y_d        = c;
        z_d        = a;
      end
      VEC_FMIN: begin
        funct5_d = Funct5Fminmax;
        funct3_d = Funct3Fmin;
      end
      VEC_FMAX: begin
        funct5_d = Funct5Fminmax;
        funct3_d = Funct3Fmax;
      end
      VEC_FSGNJ: begin
        funct5_d = Funct5Fsgnj;
        funct3_d = Funct3Fsgnj;
      end
      VEC_FSGNJN: begin
        funct5_d = Funct5Fsgnj;
        funct3_d = Funct3Fsgnjn;
      end
      VEC_FSGNJX: begin
        funct5_d = Funct5Fsgnj;
        funct3_d = Funct3Fsgnjx;
      end
      VEC_MFEQ:  ;
      VEC_MFNE:  inv_d = 1'b1;
      VEC_MFLT:  funct3_d = Funct3Flt;
      VEC_MFLE:  funct3_d = Funct3Fle;
      VEC_MFGT: begin
        funct3_d = Funct3Flt;
        x_d      = b;
        y_d      = a;
      end
      VEC_MFGE: begin
        funct3_d = Funct3Fle;
        x_d      = b;
        y_d      = a;
      end
      VEC_FCLASS: begin
        funct5_d = Funct5FmvXW;
        funct3_d = Funct3Fclass;
      end
      VEC_FREC7: sel_d = SEL_EST;
      VEC_FRSQRT7: begin
        sel_d  = SEL_EST;
        root_d = 1'b1;
      end
      VEC_FMV:   sel_d = SEL_MOVE;
      default:   sel_d = SEL_MOVE;
    endcase
  end

  sel_t            sel_q;
  logic            sub_q;
  logic            neg_prod_q;
  logic            neg_add_q;
  logic            inv_q;
  logic            root_q;
  logic [     4:0] funct5_q;
  logic [     2:0] funct3_q;
  logic [ RmW-1:0] rm_q;
  logic [FLEN-1:0] x_q;
  logic [FLEN-1:0] y_q;
  logic [FLEN-1:0] z_q;

  always_ff @(posedge clk) begin
    if (core_en) begin
      sel_q      <= sel_d;
      sub_q      <= sub_d;
      neg_prod_q <= neg_prod_d;
      neg_add_q  <= neg_add_d;
      inv_q      <= inv_d;
      root_q     <= root_d;
      funct5_q   <= funct5_d;
      funct3_q   <= funct3_d;
      rm_q       <= rm;
      x_q        <= x_d;
      y_q        <= y_d;
      z_q        <= z_d;
    end
  end

  logic [ FLEN-1:0] add_res;
  logic [ FLEN-1:0] mul_res;
  logic [ FLEN-1:0] fma_res;
  logic [ FLEN-1:0] misc_res;
  logic [FlagW-1:0] add_flags;
  logic [FlagW-1:0] mul_flags;
  logic [FlagW-1:0] fma_flags;
  logic [FlagW-1:0] misc_flags;
  logic [ FLEN-1:0] est_res;
  logic [FlagW-1:0] est_flags;

  fp_add #(
      .ExpW (ExpW),
      .FracW(FracW)
  ) u_add (
      .clk(clk),
      .rst_n(rst_n),
      .core_en(core_en),
      .sub(sub_q),
      .rm(rm_q),
      .a(x_q),
      .b(y_q),
      .result(add_res),
      .fflags(add_flags)
  );

  fp_mul #(
      .ExpW (ExpW),
      .FracW(FracW)
  ) u_mul (
      .clk(clk),
      .rst_n(rst_n),
      .core_en(core_en),
      .rm(rm_q),
      .a(x_q),
      .b(y_q),
      .result(mul_res),
      .fflags(mul_flags)
  );

  fp_fma #(
      .ExpW (ExpW),
      .FracW(FracW)
  ) u_fma (
      .clk(clk),
      .rst_n(rst_n),
      .core_en(core_en),
      .neg_prod(neg_prod_q),
      .neg_add(neg_add_q),
      .rm(rm_q),
      .a(x_q),
      .b(y_q),
      .c(z_q),
      .result(fma_res),
      .fflags(fma_flags)
  );

  fp_misc #(
      .ExpW (ExpW),
      .FracW(FracW)
  ) u_misc (
      .funct5(funct5_q),
      .funct3(funct3_q),
      .a(x_q),
      .b(y_q),
      .result(misc_res),
      .fflags(misc_flags)
  );

  fp_rec7 #(
      .ExpW (ExpW),
      .FracW(FracW)
  ) u_est (
      .sqrt(root_q),
      .rm(rm_q),
      .a(x_q),
      .result(est_res),
      .fflags(est_flags)
  );

  logic [ FLEN-1:0] misc_out;
  logic [ FLEN-1:0] side_res;
  logic [FlagW-1:0] side_flags;

  assign misc_out = misc_res ^ FLEN'(inv_q);

  always_comb begin
    case (sel_q)
      SEL_MOVE: begin
        side_res   = x_q;
        side_flags = '0;
      end
      SEL_EST: begin
        side_res   = est_res;
        side_flags = est_flags;
      end
      default: begin
        side_res   = misc_out;
        side_flags = misc_flags;
      end
    endcase
  end

  logic [FlagW+FLEN-1:0] add_pipe [     AddPad+1];
  logic [FlagW+FLEN-1:0] mul_pipe [     MulPad+1];
  logic [FlagW+FLEN-1:0] fma_pipe [     FmaPad+1];
  logic [FlagW+FLEN-1:0] side_pipe[UnitLatency+1];
  sel_t                  sel_pipe [UnitLatency+1];

  always_comb begin
    add_pipe[0]  = {add_flags, add_res};
    mul_pipe[0]  = {mul_flags, mul_res};
    fma_pipe[0]  = {fma_flags, fma_res};
    side_pipe[0] = {side_flags, side_res};
    sel_pipe[0]  = sel_q;
  end

  always_ff @(posedge clk) begin
    if (core_en) begin
      for (int i = 1; i <= AddPad; i++) add_pipe[i] <= add_pipe[i-1];
      for (int i = 1; i <= MulPad; i++) mul_pipe[i] <= mul_pipe[i-1];
      for (int i = 1; i <= FmaPad; i++) fma_pipe[i] <= fma_pipe[i-1];
      for (int i = 1; i <= UnitLatency; i++) begin
        side_pipe[i] <= side_pipe[i-1];
        sel_pipe[i]  <= sel_pipe[i-1];
      end
    end
  end

  logic [FlagW+FLEN-1:0] aligned;

  always_comb begin
    case (sel_pipe[UnitLatency])
      SEL_ADD: aligned = add_pipe[AddPad];
      SEL_MUL: aligned = mul_pipe[MulPad];
      SEL_FMA: aligned = fma_pipe[FmaPad];
      default: aligned = side_pipe[UnitLatency];
    endcase
  end

  logic [Latency-1:0] vld_q;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      vld_q <= '0;
    end else if (core_en) begin
      vld_q <= {vld_q[Latency-2:0], valid};
    end
  end

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      result <= '0;
      fflags <= '0;
    end else if (core_en) begin
      {fflags, result} <= aligned;
    end
  end

  assign result_valid = vld_q[Latency-1];

endmodule

`default_nettype wire
