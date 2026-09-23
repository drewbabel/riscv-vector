`default_nettype none

module fp_cvt (
    input  logic        to_int,
    input  logic        is_unsigned,
    input  logic [ 2:0] iw,
    input  logic [ 2:0] rm,
    input  logic [31:0] a,
    output logic [31:0] result,
    output logic [ 4:0] fflags
);

endmodule

`default_nettype wire
