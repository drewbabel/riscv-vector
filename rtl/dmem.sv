`default_nettype none

module dmem
  import cache_pkg::*;
#(
    parameter  int XLEN     = arch_pkg::XLEN,
    parameter  int DEPTH    = arch_pkg::SimMemWords,
    localparam int Lines    = DEPTH / LineWords,
    localparam int LineIdxW = $clog2(Lines)
) (
    input  wire                  clk,
    input  wire  [LineBytes-1:0] wstrb,
    input  wire  [     XLEN-1:0] addr,
    input  wire  [ LineBits-1:0] wdata,
    output logic [ LineBits-1:0] rdata
);

  logic [LineBits-1:0] mem         [Lines];
  logic                unused_addr;

  assign unused_addr = ^{addr[XLEN-1:IdxLsb+LineIdxW], addr[IdxLsb-1:0]};

  assign rdata = mem[addr[IdxLsb+:LineIdxW]];

  genvar i;

  generate
    for (i = 0; i < LineBytes; i++) begin : g_we
      always_ff @(posedge clk) begin
        if (wstrb[i]) mem[addr[IdxLsb+:LineIdxW]][8*i+:8] <= wdata[8*i+:8];
      end
    end
  endgenerate

endmodule

`default_nettype wire
