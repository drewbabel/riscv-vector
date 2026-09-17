`default_nettype none

module vec_mul_lane
  import vec_pkg::*;
(
    input  vec_op_e        op,
    input  logic    [ 2:0] vsew,
    input  logic    [31:0] a,
    input  logic    [31:0] b,
    input  logic    [31:0] c,
    output logic    [31:0] result,
    output logic    [63:0] product
);

endmodule

`default_nettype wire
