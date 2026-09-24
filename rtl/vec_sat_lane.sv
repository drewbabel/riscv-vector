`default_nettype none

module vec_sat_lane
  import vec_pkg::*;
#(
    parameter int ELEN = 32
) (
    input  vec_op_e              op,
    input  logic    [       2:0] vsew,
    input  logic    [       1:0] vxrm,
    input  logic    [  ELEN-1:0] a,
    input  logic    [  ELEN-1:0] b,
    input  logic    [2*ELEN-1:0] product,
    output logic    [  ELEN-1:0] result,
    output logic                 sat
);

endmodule

`default_nettype wire
