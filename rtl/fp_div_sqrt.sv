`default_nettype none

module fp_div_sqrt (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         core_en,
    input  wire         start,
    input  wire         sqrt,
    input  wire  [ 2:0] rm,
    input  wire  [31:0] a,
    input  wire  [31:0] b,
    output logic [31:0] result,
    output logic [ 4:0] fflags,
    output logic        busy,
    output logic        done
);

endmodule

`default_nettype wire
