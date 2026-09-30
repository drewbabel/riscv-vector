`default_nettype none

module gpio #(
    parameter int XLEN  = arch_pkg::XLEN,
    parameter int WIDTH = 16
) (
    input wire clk,
    input wire core_en,
    input wire rst_n,

    input  wire               sel,
    input  wire  [XLEN/8-1:0] wstrb,
    input  wire  [  XLEN-1:0] addr,
    input  wire  [  XLEN-1:0] wdata,
    output logic [  XLEN-1:0] rdata,

    input  wire  [WIDTH-1:0] sw,
    output logic [WIDTH-1:0] led
);

  logic [WIDTH-1:0] led_reg;

  always_ff @(posedge clk) begin
    if (!rst_n) led_reg <= '0;
    else if (core_en && sel && !addr[2] && |wstrb) led_reg <= wdata[WIDTH-1:0];
  end

  assign rdata = addr[2] ? {{(XLEN - WIDTH) {1'b0}}, sw} : {{(XLEN - WIDTH) {1'b0}}, led_reg};
  assign led   = led_reg;

endmodule

`default_nettype wire
