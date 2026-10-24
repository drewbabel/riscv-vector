`default_nettype none

module vec_fp_div_lane
  import vec_pkg::*;
(
    input  wire                  clk,
    input  wire                  rst_n,
    input  wire                  core_en,
    input  wire                  start,
    input  wire vec_fop_e        op,
    input  wire           [ 2:0] rm,
    input  wire           [31:0] a,
    input  wire           [31:0] b,
    output logic          [31:0] result,
    output logic          [ 4:0] fflags,
    output logic                 busy,
    output logic                 done
);

  logic        take;
  logic        root;
  logic        swap;
  logic [31:0] x;
  logic [31:0] y;

  assign take = start && !busy && !done;
  assign root = op == VEC_FSQRT;
  assign swap = op == VEC_FRDIV;
  assign x    = swap ? b : a;
  assign y    = swap ? a : b;

  fp_div_sqrt #(
      .ExpW (8),
      .FracW(23)
  ) u_div (
      .clk(clk),
      .rst_n(rst_n),
      .core_en(core_en),
      .start(take),
      .sqrt(root),
      .rm(rm),
      .a(x),
      .b(y),
      .result(result),
      .fflags(fflags),
      .busy(busy),
      .done(done)
  );

endmodule

`default_nettype wire
