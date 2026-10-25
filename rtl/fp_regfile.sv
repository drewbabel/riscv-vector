`default_nettype none

module fp_regfile #(
    parameter int AWIDTH = arch_pkg::RegAddrW,
    parameter int FLEN   = fp_pkg::FLEN
) (
    input wire clk,
    input wire core_en,
    input wire rst_n,
    input wire we,
    input wire [AWIDTH-1:0] waddr,
    input wire [FLEN-1:0] wdata,
    input wire we2,
    input wire [AWIDTH-1:0] waddr2,
    input wire [FLEN-1:0] wdata2,
    input wire [AWIDTH-1:0] raddr1,
    input wire [AWIDTH-1:0] raddr2,
    input wire [AWIDTH-1:0] raddr3,
    output logic [FLEN-1:0] rdata1,
    output logic [FLEN-1:0] rdata2,
    output logic [FLEN-1:0] rdata3
);

  localparam int Depth = 2 ** AWIDTH;

  logic [FLEN-1:0] regfile_mem[Depth];

  always_comb begin
    if (we2 && (waddr2 == raddr1)) begin
      rdata1 = wdata2;
    end else if (we && (waddr == raddr1)) begin
      rdata1 = wdata;
    end else begin
      rdata1 = regfile_mem[raddr1];
    end

    if (we2 && (waddr2 == raddr2)) begin
      rdata2 = wdata2;
    end else if (we && (waddr == raddr2)) begin
      rdata2 = wdata;
    end else begin
      rdata2 = regfile_mem[raddr2];
    end

    if (we2 && (waddr2 == raddr3)) begin
      rdata3 = wdata2;
    end else if (we && (waddr == raddr3)) begin
      rdata3 = wdata;
    end else begin
      rdata3 = regfile_mem[raddr3];
    end
  end

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      for (int i = 0; i < Depth; i++) begin
        regfile_mem[i] <= '0;
      end
    end else if (core_en) begin
      if (we) begin
        regfile_mem[waddr] <= wdata;
      end
      // Second port wins ties
      if (we2) begin
        regfile_mem[waddr2] <= wdata2;
      end
    end
  end

endmodule

`default_nettype wire
