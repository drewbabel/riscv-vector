`default_nettype none

module fp_misc (
    input  logic [ 4:0] funct5,
    input  logic [ 2:0] funct3,
    input  logic [31:0] a,
    input  logic [31:0] b,
    output logic [31:0] result,
    output logic [ 4:0] fflags
);

endmodule

`default_nettype wire
