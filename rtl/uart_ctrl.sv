`default_nettype none

module uart_ctrl #(
    parameter  int XLEN      = arch_pkg::XLEN,
    parameter  int DATA_BITS = arch_pkg::UartDataBits,
    localparam int WordLsb   = $clog2(XLEN / 8)
) (
    input wire clk,
    input wire core_en,
    input wire rst_n,

    // Bus
    input  wire               sel,
    input  wire               req,
    input  wire  [XLEN/8-1:0] wstrb,
    input  wire  [  XLEN-1:0] addr,
    input  wire  [  XLEN-1:0] wdata,
    output logic [  XLEN-1:0] rdata,

    // Receiver
    input wire                 rx_valid,
    input wire [DATA_BITS-1:0] rx_data,

    // Transmitter
    input  wire                  tx_ready,
    output logic                 tx_valid,
    output logic [DATA_BITS-1:0] tx_data,

    // Core
    output logic irq
);

  localparam int OffW = 2;
  localparam logic [OffW-1:0] TxDataOff = 2'd0;
  localparam logic [OffW-1:0] StatusOff = 2'd1;
  localparam logic [OffW-1:0] RxDataOff = 2'd2;
  localparam logic [OffW-1:0] CtrlOff = 2'd3;

  if (DATA_BITS > XLEN) begin : g_data_bits
    $error("DATA_BITS must not exceed XLEN");
  end

  if (DATA_BITS < XLEN) begin : g_wdata_high
    logic unused_wdata_high;
    assign unused_wdata_high = ^wdata[XLEN-1:DATA_BITS];
  end

  logic [     OffW-1:0] off;
  logic                 wr_stb;
  logic                 rd_stb;
  logic                 rx_take;

  logic [DATA_BITS-1:0] rx_byte;
  logic                 rx_full;
  logic                 rx_overrun;
  logic                 rx_ie;
  logic                 unused_addr;

  assign off         = addr[WordLsb+:OffW];
  assign unused_addr = ^{addr[XLEN-1:WordLsb+OffW], addr[WordLsb-1:0]};
  assign wr_stb      = core_en && sel && |wstrb;
  assign rd_stb      = core_en && sel && req && !(|wstrb);

  assign tx_valid    = wr_stb && (off == TxDataOff);
  assign tx_data     = wdata[DATA_BITS-1:0];

  always_comb begin
    case (off)
      StatusOff: rdata = XLEN'({rx_overrun, rx_full, tx_ready});
      RxDataOff: rdata = XLEN'(rx_byte);
      CtrlOff:   rdata = XLEN'(rx_ie);
      default:   rdata = XLEN'(tx_ready);
    endcase
  end

  assign rx_take = rd_stb && (off == RxDataOff);

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      rx_byte    <= '0;
      rx_full    <= 1'b0;
      rx_overrun <= 1'b0;
      rx_ie      <= 1'b0;
    end else if (core_en) begin
      if (rx_valid && (!rx_full || rx_take)) rx_byte <= rx_data;

      if (rx_valid) rx_full <= 1'b1;
      else if (rx_take) rx_full <= 1'b0;

      if (rx_valid && rx_full && !rx_take) rx_overrun <= 1'b1;
      else if (rx_take) rx_overrun <= 1'b0;

      if (wr_stb && (off == CtrlOff)) rx_ie <= wdata[0];
    end
  end

  assign irq = rx_full && rx_ie;

endmodule

`default_nettype wire
