`default_nettype none

module vec_regfile #(
    parameter  int AWIDTH = 5,
    parameter  int VLEN   = 128,
    localparam int Depth  = 2 ** AWIDTH
) (
    input  wire               clk,
    input  wire               core_en,
    input  wire               we,
    input  wire  [  VLEN-1:0] wstrb,
    input  wire  [AWIDTH-1:0] waddr,
    input  wire  [  VLEN-1:0] wdata,
    input  wire  [AWIDTH-1:0] raddr1,
    input  wire  [AWIDTH-1:0] raddr2,
    input  wire  [AWIDTH-1:0] raddr3,
    output logic [  VLEN-1:0] rdata1,
    output logic [  VLEN-1:0] rdata2,
    output logic [  VLEN-1:0] rdata3,
    output logic [  VLEN-1:0] rdata0
);

  // Per bit slices
  for (genvar b = 0; b < VLEN; b++) begin : g_bit
    (* ram_style = "distributed" *) logic bmem[Depth];

    // Zero init
    initial for (int i = 0; i < Depth; i++) bmem[i] = 1'b0;

    // Masked write
    always_ff @(posedge clk) begin
      if (core_en && we && wstrb[b]) bmem[waddr] <= wdata[b];
    end

    // Read first
    assign rdata1[b] = bmem[raddr1];
    assign rdata2[b] = bmem[raddr2];
    assign rdata3[b] = bmem[raddr3];
    assign rdata0[b] = bmem[0];
  end

endmodule

`default_nettype wire
