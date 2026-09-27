`default_nettype none

module sc_regfile #(
    parameter int AWIDTH = 5,
    parameter int XLEN   = 32
) (
    input wire clk,
    input wire core_en,
    input wire rst_n,
    input wire we,
    input wire [AWIDTH-1:0] waddr,
    input wire [XLEN-1:0] wdata,
    input wire [AWIDTH-1:0] raddr1,
    input wire [AWIDTH-1:0] raddr2,
    output logic [XLEN-1:0] rdata1,
    output logic [XLEN-1:0] rdata2
);

  localparam int Depth = 2 ** AWIDTH;

  logic [XLEN-1:0] regfile_mem[Depth];

  assign rdata1 = (raddr1 == 0) ? '0 : regfile_mem[raddr1];
  assign rdata2 = (raddr2 == 0) ? '0 : regfile_mem[raddr2];

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      for (int i = 0; i < Depth; i++) begin
        regfile_mem[i] <= '0;
      end
    end else if (core_en) begin
      if (we && waddr != 0) begin
        regfile_mem[waddr] <= wdata;
      end
    end
  end

endmodule

`default_nettype wire
