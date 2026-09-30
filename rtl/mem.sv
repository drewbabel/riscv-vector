`default_nettype none

module mem #(
    parameter int XLEN = arch_pkg::XLEN,
    parameter int DEPTH = 8192,
    localparam int AddrWidth = $clog2(DEPTH),
    localparam int WordBytes = XLEN / 8,
    localparam int WordLsb = $clog2(WordBytes)
) (
    input  wire                  clk,
    input  wire                  core_en,
    // Fetch read port
    input  wire  [     XLEN-1:0] iaddr,
    output logic [     XLEN-1:0] instr,
    // Data port
    input  wire  [WordBytes-1:0] wstrb,
    input  wire  [     XLEN-1:0] daddr,
    input  wire  [     XLEN-1:0] wdata,
    output logic [     XLEN-1:0] rdata
);

  // Byte-lane BRAMs
  genvar b;
  generate
    for (b = 0; b < WordBytes; b++) begin : g_lane
      logic [7:0] bmem[DEPTH];
      // Zero init like bram
      initial for (int i = 0; i < DEPTH; i++) bmem[i] = '0;
      // Fetch read
      always_ff @(posedge clk) instr[8*b+:8] <= bmem[iaddr[AddrWidth+WordLsb-1:WordLsb]];
      // Gated write
      always_ff @(posedge clk) begin
        if (core_en && wstrb[b]) bmem[daddr[AddrWidth+WordLsb-1:WordLsb]] <= wdata[8*b+:8];
        rdata[8*b+:8] <= bmem[daddr[AddrWidth+WordLsb-1:WordLsb]];
      end
    end
  endgenerate

endmodule

`default_nettype wire
