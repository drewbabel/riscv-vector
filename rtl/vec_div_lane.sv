`default_nettype none

module vec_div_lane
  import vec_pkg::*;
#(
    parameter int ELEN = 32
) (
    input  wire                     clk,
    input  wire                     rst_n,
    input  wire                     core_en,
    input  wire                     start,
    input  wire vec_op_e            op,
    input  wire          [     2:0] vsew,
    input  wire          [ELEN-1:0] a,
    input  wire          [ELEN-1:0] b,
    output logic         [ELEN-1:0] result,
    output logic                    busy,
    output logic                    done
);

endmodule

`default_nettype wire
