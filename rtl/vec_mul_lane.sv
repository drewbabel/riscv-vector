`default_nettype none

module vec_mul_lane
  import vec_pkg::*;
(
    input  wire vec_op_e        op,
    input  wire          [ 2:0] vsew,
    input  wire          [31:0] a,
    input  wire          [31:0] b,
    input  wire          [31:0] c,
    output logic         [31:0] result,
    output logic         [63:0] product
);

endmodule

`default_nettype wire
