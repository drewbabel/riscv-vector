`default_nettype none

module fp_div_sqrt (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        core_en,
    input  logic        start,
    input  logic        sqrt,
    input  logic [ 2:0] rm,
    input  logic [31:0] a,
    input  logic [31:0] b,
    output logic [31:0] result,
    output logic [ 4:0] fflags,
    output logic        busy,
    output logic        done
);

endmodule

`default_nettype wire
