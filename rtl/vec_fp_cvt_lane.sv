`default_nettype none

module vec_fp_cvt_lane
  import vec_pkg::*;
(
    input  wire                  clk,
    input  wire                  rst_n,
    input  wire                  core_en,
    input  wire                  valid,
    input  wire vec_fop_e        op,
    input  wire vec_eew_e        eew,
    input  wire           [ 2:0] vsew,
    input  wire           [ 2:0] rm,
    input  wire           [31:0] a,
    output logic          [31:0] result,
    output logic          [ 4:0] fflags,
    output logic                 result_valid
);

endmodule

`default_nettype wire
