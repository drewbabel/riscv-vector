`default_nettype none

module vec_slide
  import vec_pkg::*;
#(
    parameter  int XLEN   = arch_pkg::XLEN,
    parameter  int AWIDTH = arch_pkg::RegAddrW,
    parameter  int VLEN   = arch_pkg::VLEN,
    localparam int VlW    = $clog2(VLEN + 1)
) (
    input wire clk,
    input wire rst_n,
    input wire core_en,

    // Issued instruction
    input wire                       start,
    input wire vec_op_e              op,
    input wire                       vm,
    input wire          [AWIDTH-1:0] vs2,
    input wire          [AWIDTH-1:0] vd,
    input wire          [   VlW-1:0] vl,
    input wire          [       2:0] vsew,
    input wire          [       2:0] vlmul,
    input wire          [  XLEN-1:0] offset,
    input wire          [  XLEN-1:0] scalar,

    // Register file
    input  wire  [  VLEN-1:0] v0,
    input  wire  [  VLEN-1:0] rdata_lo,
    input  wire  [  VLEN-1:0] rdata_hi,
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
