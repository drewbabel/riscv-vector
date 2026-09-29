`default_nettype none

module imem #(
    parameter int XLEN = arch_pkg::XLEN,
    parameter int DEPTH = 64,
    localparam int AddrWidth = $clog2(DEPTH),
    localparam int WordLsb = $clog2(XLEN / 8)
) (
    input wire clk,
    input wire we,
    input wire [XLEN-1:0] waddr,
    input wire [XLEN-1:0] wdata,
    input wire [XLEN-1:0] addr,
    output logic [XLEN-1:0] instr
);

  logic [XLEN-1:0] mem[DEPTH];

`ifdef IMEM_INIT
  initial $readmemh(`IMEM_INIT, mem);
`endif

  // Drop byte offset
  assign instr = mem[addr[AddrWidth+WordLsb-1:WordLsb]];

  always_ff @(posedge clk) begin
    if (we) mem[waddr[AddrWidth+WordLsb-1:WordLsb]] <= wdata;
  end

endmodule

`default_nettype wire
