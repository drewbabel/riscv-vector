`default_nettype none

module dmem
  import cache_pkg::*;
#(
    parameter  int XLEN     = 32,
    parameter  int DEPTH    = 64,
    localparam int Lines    = DEPTH / LineWords,
    localparam int LineIdxW = $clog2(Lines)
) (
    input  wire                  clk,
    input  wire  [LineBytes-1:0] wstrb,
    input  wire  [     XLEN-1:0] addr,
    input  wire  [ LineBits-1:0] wdata,
    output logic [ LineBits-1:0] rdata
);

  logic [LineBits-1:0] mem[Lines];

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
