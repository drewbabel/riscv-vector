`default_nettype none

module fp_fma (
    input  wire         neg_prod,
    input  wire         neg_add,
    input  wire  [ 2:0] rm,
    input  wire  [31:0] a,
    input  wire  [31:0] b,
    input  wire  [31:0] c,
    output logic [31:0] result,
    output logic [ 4:0] fflags
);

endmodule

`default_nettype wire
