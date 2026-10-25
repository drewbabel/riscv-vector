`default_nettype none

module gpio #(
    parameter  int XLEN    = arch_pkg::XLEN,
    parameter  int WIDTH   = 16,
    localparam int WordLsb = $clog2(XLEN / 8)
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

  if (WIDTH > XLEN) begin : g_width
    $error("WIDTH must not exceed XLEN");
  end

  logic [WIDTH-1:0] led_reg;
  logic             sw_sel;

  assign sw_sel = addr[WordLsb];

  always_ff @(posedge clk) begin
    if (!rst_n) led_reg <= '0;
    else if (core_en && sel && !sw_sel && |wstrb) led_reg <= wdata[WIDTH-1:0];
  end

  assign rdata = sw_sel ? XLEN'(sw) : XLEN'(led_reg);
  assign led   = led_reg;

endmodule

`default_nettype wire
