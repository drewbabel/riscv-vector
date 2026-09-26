`default_nettype none

module vec_slide
  import vec_pkg::*;
#(
    parameter int AWIDTH = 5,
    parameter int VLEN   = 128
) (
    input logic clk,
    input logic rst_n,
    input logic core_en,

    // Issued instruction
    input logic                 start,
    input vec_op_e              op,
    input logic                 vm,
    input logic    [AWIDTH-1:0] vs2,
    input logic    [AWIDTH-1:0] vd,
    input logic    [       7:0] vl,
    input logic    [       2:0] vsew,
    input logic    [       2:0] vlmul,
    input logic    [      31:0] offset,
    input logic    [      31:0] scalar,

    // Register file
    input  logic [  VLEN-1:0] v0,
    input  logic [  VLEN-1:0] rdata_lo,
    input  logic [  VLEN-1:0] rdata_hi,
    output logic [AWIDTH-1:0] raddr_lo,
    output logic [AWIDTH-1:0] raddr_hi,
    output logic              wen,
    output logic [AWIDTH-1:0] waddr,
    output logic [  VLEN-1:0] wstrb,
    output logic [  VLEN-1:0] wdata,

    output logic busy,
    output logic done
);

endmodule

`default_nettype wire
