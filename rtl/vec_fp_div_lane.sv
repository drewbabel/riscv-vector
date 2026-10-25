`default_nettype none

module vec_fp_div_lane
  import vec_pkg::*;
  import fp_pkg::FlagW, fp_pkg::RmW;
#(
    parameter  int ExpW  = fp_pkg::ExpW,
    parameter  int FracW = fp_pkg::FracW,
    localparam int FLEN  = 1 + ExpW + FracW
) (
    input  wire                       clk,
    input  wire                       rst_n,
    input  wire                       core_en,
    input  wire                       start,
    input  wire vec_fop_e             op,
    input  wire           [  RmW-1:0] rm,
    input  wire           [ FLEN-1:0] a,
    input  wire           [ FLEN-1:0] b,
    output logic          [ FLEN-1:0] result,
    output logic          [FlagW-1:0] fflags,
    output logic                      busy,
    output logic                      done
);

  logic            take;
  logic            root;
  logic            swap;
  logic [FLEN-1:0] x;
  logic [FLEN-1:0] y;

  assign take = start && !busy && !done;
  assign root = op == VEC_FSQRT;
  assign swap = op == VEC_FRDIV;
  assign x    = swap ? b : a;
  assign y    = swap ? a : b;

  fp_div_sqrt #(
      .ExpW (ExpW),
      .FracW(FracW)
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
