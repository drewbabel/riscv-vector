`default_nettype none

module vec_sat_lane
  import vec_pkg::*;
(
    input  vec_op_e        op,
    input  logic    [ 2:0] vsew,
    input  logic    [ 1:0] vxrm,
    input  logic    [31:0] a,
    input  logic    [31:0] b,
    input  logic    [63:0] product,
    output logic    [31:0] result,
    output logic           sat
);

endmodule

`default_nettype wire
