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

endmodule

`default_nettype wire
