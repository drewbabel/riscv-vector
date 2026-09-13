`default_nettype none

module vec_regfile #(
    parameter  int AWIDTH = 5,
    parameter  int VLEN   = 128,
    localparam int Depth  = 2 ** AWIDTH
) (
    input  logic              clk,
    input  logic              core_en,
    input  logic              we,
    input  logic [  VLEN-1:0] wstrb,
    input  logic [AWIDTH-1:0] waddr,
    input  logic [  VLEN-1:0] wdata,
    input  logic [AWIDTH-1:0] raddr1,
    input  logic [AWIDTH-1:0] raddr2,
    input  logic [AWIDTH-1:0] raddr3,
    output logic [  VLEN-1:0] rdata1,
    output logic [  VLEN-1:0] rdata2,
    output logic [  VLEN-1:0] rdata3
);

  // Per bit slices
  for (genvar b = 0; b < VLEN; b++) begin : g_bit
    (* ram_style = "distributed" *) logic bmem[Depth];

    // Zero init
    initial for (int i = 0; i < Depth; i++) bmem[i] = 1'b0;

    always_ff @(posedge clk) begin
      if (core_en && we && wstrb[b]) bmem[waddr] <= wdata[b];
    end

    // Read first
    assign rdata1[b] = bmem[raddr1];
    assign rdata2[b] = bmem[raddr2];
    assign rdata3[b] = bmem[raddr3];
  end

endmodule

`default_nettype wire
