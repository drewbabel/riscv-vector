`default_nettype none

module imem #(
    parameter int XLEN = 32,
    parameter int DEPTH = 64,
    localparam int AddrWidth = $clog2(DEPTH)
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

  // 2 bits = divide by 4
  assign instr = mem[addr[AddrWidth+1:2]];

  always_ff @(posedge clk) begin
    if (we) mem[waddr[AddrWidth+1:2]] <= wdata;
  end

endmodule

`default_nettype wire
