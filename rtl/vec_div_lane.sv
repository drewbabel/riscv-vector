`default_nettype none

module vec_div_lane
  import vec_pkg::*;
(
    input  logic           clk,
    input  logic           rst_n,
    input  logic           core_en,
    input  logic           start,
    input  vec_op_e        op,
    input  logic    [ 2:0] vsew,
    input  logic    [31:0] a,
    input  logic    [31:0] b,
    output logic    [31:0] result,
    output logic           busy,
    output logic           done
);

endmodule

`default_nettype wire
