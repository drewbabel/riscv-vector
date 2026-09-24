`default_nettype none

module vec_div_lane
  import vec_pkg::*;
#(
    parameter int ELEN = 32
) (
    input  logic               clk,
    input  logic               rst_n,
    input  logic               core_en,
    input  logic               start,
    input  vec_op_e            op,
    input  logic    [     2:0] vsew,
    input  logic    [ELEN-1:0] a,
    input  logic    [ELEN-1:0] b,
    output logic    [ELEN-1:0] result,
    output logic               busy,
    output logic               done
);

endmodule

`default_nettype wire
