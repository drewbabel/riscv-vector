`default_nettype none

module vec_write_slots #(
    parameter  int DEPTH  = 4,
    localparam int DepthW = $clog2(DEPTH + 1)
) (
    input  wire               clk,
    input  wire               rst_n,
    input  wire               core_en,
    input  wire               start,
    input  wire  [DepthW-1:0] depth,
    output logic              free
);

  logic [(1<<DepthW)-1:0] booked;  // Slot per depth
  assign free = !booked[depth];

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      booked <= '0;
    end else if (core_en) begin
      booked <= booked >> 1;
      if (start && depth > 1) booked[depth-1] <= 1'b1;  // Row shifts same edge
    end
  end

endmodule

`default_nettype wire
