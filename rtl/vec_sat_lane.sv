`default_nettype none

module vec_sat_lane
  import vec_pkg::*;
#(
    parameter int ELEN = 32
) (
    input  wire vec_op_e              op,
    input  wire          [       2:0] vsew,
    input  wire          [       1:0] vxrm,
    input  wire          [  ELEN-1:0] a,
    input  wire          [  ELEN-1:0] b,
    input  wire          [2*ELEN-1:0] product,
    output logic         [  ELEN-1:0] result,
    output logic                      sat
);

endmodule

`default_nettype wire
