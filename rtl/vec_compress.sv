`default_nettype none

module vec_compress #(
    parameter  int AWIDTH = arch_pkg::RegAddrW,
    parameter  int VLEN   = arch_pkg::VLEN,
    localparam int VlW    = $clog2(VLEN + 1)
) (
    input wire clk,
    input wire rst_n,
    input wire core_en,

    // Issued instruction
    input wire              start,
    input wire [AWIDTH-1:0] vs1,
    input wire [AWIDTH-1:0] vs2,
    input wire [AWIDTH-1:0] vd,
    input wire [   VlW-1:0] vl,
    input wire [       2:0] vsew,

    // Register file
    input  wire  [  VLEN-1:0] rdata_mask,
    input  wire  [  VLEN-1:0] rdata_src,
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
