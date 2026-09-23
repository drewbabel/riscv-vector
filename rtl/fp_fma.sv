`default_nettype none

module fp_fma (
    input  logic        neg_prod,
    input  logic        neg_add,
    input  logic [ 2:0] rm,
    input  logic [31:0] a,
    input  logic [31:0] b,
    input  logic [31:0] c,
    output logic [31:0] result,
    output logic [ 4:0] fflags
);

endmodule

`default_nettype wire
