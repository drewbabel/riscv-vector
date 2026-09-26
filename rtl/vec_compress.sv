`default_nettype none

module vec_compress #(
    parameter int AWIDTH = 5,
    parameter int VLEN   = 128
) (
    input logic clk,
    input logic rst_n,
    input logic core_en,

    // Issued instruction
    input logic              start,
    input logic [AWIDTH-1:0] vs1,
    input logic [AWIDTH-1:0] vs2,
    input logic [AWIDTH-1:0] vd,
    input logic [       7:0] vl,
    input logic [       2:0] vsew,

    // Register file
    input  logic [  VLEN-1:0] rdata_mask,
    input  logic [  VLEN-1:0] rdata_src,
    output logic [AWIDTH-1:0] raddr_mask,
    output logic [AWIDTH-1:0] raddr_src,
    output logic              wen,
    output logic [AWIDTH-1:0] waddr,
    output logic [  VLEN-1:0] wstrb,
    output logic [  VLEN-1:0] wdata,

    output logic busy,
    output logic done
);

endmodule

`default_nettype wire
