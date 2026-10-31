`default_nettype none

// RAM abstracted one index
module bram_watch #(
    parameter  int Width = 8,
    parameter  int Depth = 256,
    parameter  bit Block = 1'b1,
    localparam int AddrW = $clog2(Depth),
    localparam int Lanes = (Width + 7) / 8
) (
    input  wire              clk,
    input  wire              we,
    input  wire  [Lanes-1:0] wlane,
    input  wire  [AddrW-1:0] widx,
    input  wire  [Width-1:0] wdata,
    input  wire              re,
    input  wire  [AddrW-1:0] ridx,
    output logic [Width-1:0] rdata
);

  (* anyconst *)logic [AddrW-1:0] w_idx;
  (* anyseq *)logic [Width-1:0] w_free;

  logic             unused_block;
  logic [Width-1:0] w_data = '0;

  assign unused_block = Block;

  always_ff @(posedge clk) begin
    for (int i = 0; i < Width; i++) begin
      if (we && wlane[i/8] && widx == w_idx) w_data[i] <= wdata[i];
    end
    if (re) rdata <= (ridx == w_idx) ? w_data : w_free;
  end

endmodule

`default_nettype wire
