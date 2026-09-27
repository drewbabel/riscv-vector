`default_nettype none

module fp_misc (
    input  wire  [ 4:0] funct5,
    input  wire  [ 2:0] funct3,
    input  wire  [31:0] a,
    input  wire  [31:0] b,
    output logic [31:0] result,
    output logic [ 4:0] fflags
);

endmodule

`default_nettype wire
