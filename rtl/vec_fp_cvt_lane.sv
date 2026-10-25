`default_nettype none

module vec_fp_cvt_lane
  import vec_pkg::*;
  import fp_pkg::RmRtz;
(
    input  wire                  clk,
    input  wire                  rst_n,
    input  wire                  core_en,
    input  wire                  valid,
    input  wire vec_fop_e        op,
    input  wire vec_eew_e        eew,
    input  wire           [ 2:0] vsew,
    input  wire           [ 2:0] rm,
    input  wire           [31:0] a,
    output logic          [31:0] result,
    output logic          [ 4:0] fflags,
    output logic                 result_valid
);

  localparam int Latency = VecFpLatency;

  logic       to_int_d;
  logic       uns_d;
  logic       half_d;
  logic [2:0] rm_d;

  always_comb begin
    to_int_d = 1'b1;
    uns_d    = 1'b0;
    rm_d     = rm;
    case (op)
      VEC_FCVT_XU_F: uns_d = 1'b1;
      VEC_FCVT_RTZ_XU_F: begin
        uns_d = 1'b1;
        rm_d  = RmRtz;
      end
      VEC_FCVT_RTZ_X_F: rm_d = RmRtz;
      VEC_FCVT_F_XU: begin
        to_int_d = 1'b0;
        uns_d    = 1'b1;
      end
      VEC_FCVT_F_X: to_int_d = 1'b0;
      default: ;
    endcase
  end

  // Sixteen bit integers
  assign half_d = (eew != VEC_EEW_SAME) && (vsew == 3'd1);

  logic        to_int_q;
  logic        uns_q;
  logic        half_q;
  logic [ 2:0] rm_q;
  logic [31:0] a_q;

  always_ff @(posedge clk) begin
    if (core_en) begin
      to_int_q <= to_int_d;
      uns_q    <= uns_d;
      half_q   <= half_d;
      rm_q     <= rm_d;
      a_q      <= a;
    end
  end

  logic [31:0] cvt_res;
  logic [ 4:0] cvt_flags;

  fp_cvt #(
      .XLEN (32),
      .ExpW (8),
      .FracW(23)
  ) u_cvt (
      .to_int(to_int_q),
      .is_unsigned(uns_q),
      .half(half_q),
      .rm(rm_q),
      .a(a_q),
      .result(cvt_res),
      .fflags(cvt_flags)
  );

  logic [36:0] pipe[Latency-1];

  always_comb pipe[0] = {cvt_flags, cvt_res};

  always_ff @(posedge clk) begin
    if (core_en) begin
      for (int i = 1; i < Latency - 1; i++) pipe[i] <= pipe[i-1];
    end
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
      {fflags, result} <= pipe[Latency-2];
    end
  end

  assign result_valid = vld_q[Latency-1];

endmodule

`default_nettype wire
