`default_nettype none

module uart_formal ();

  localparam int ClksPerOversample = 1;
  localparam int Oversample = 16;
  localparam int BaudRate = 1;
  localparam int ClkFreqHz = ClksPerOversample * Oversample * BaudRate;
  localparam int DataBits = arch_pkg::UartDataBits;
  localparam int ClksPerBit = ClkFreqHz / BaudRate;
  localparam int FrameMax = (DataBits + 3) * ClksPerBit;
  localparam int AgeW = $clog2(FrameMax + 2);

  logic                clk;

  (* anyseq *)logic                core_en;
  (* anyseq *)logic [DataBits-1:0] tx_data;
  (* anyseq *)logic                tx_valid;

  logic                tx_ready;
  logic                serial;
  logic [DataBits-1:0] rx_data;
  logic                rx_valid;
  logic                rx_error;

  logic                rst_n;
  logic [         1:0] t = 2'd0;
  logic                f_past_valid = 1'b0;

  initial assume (t == 2'd0);
  always @(posedge clk) begin
    t <= (t == 2'd3) ? 2'd3 : t + 2'd1;
    f_past_valid <= 1'b1;
  end
  assign rst_n = (t != 2'd0);

  // Reset sees enable
  always @(posedge clk) if (!rst_n) assume (core_en);

  uart_tx #(
      .CLK_FREQ_HZ(ClkFreqHz),
      .BAUD_RATE  (BaudRate),
      .DATA_BITS  (DataBits)
  ) u_tx (
      .clk(clk),
      .core_en(core_en),
      .rst_n(rst_n),
      .tx_data(tx_data),
      .tx_valid(tx_valid),
      .tx_ready(tx_ready),
      .tx_serial(serial)
  );

  uart_rx #(
      .CLK_FREQ_HZ(ClkFreqHz),
      .BAUD_RATE  (BaudRate),
      .OVERSAMPLE (Oversample),
      .DATA_BITS  (DataBits)
  ) u_rx (
      .clk(clk),
      .core_en(core_en),
      .rst_n(rst_n),
      .rx_serial(serial),
      .rx_data(rx_data),
      .rx_valid(rx_valid),
      .rx_error(rx_error)
  );

  // Byte in flight
  logic                f_sent;
  logic                f_pend;
  logic [DataBits-1:0] f_byte;
  logic [    AgeW-1:0] f_age;
  logic [         1:0] f_got;

  assign f_sent = rst_n && core_en && tx_valid && tx_ready;

  always @(posedge clk) begin
    if (!rst_n) begin
      f_pend <= 1'b0;
      f_age  <= '0;
      f_got  <= 2'd0;
    end else if (core_en) begin
      if (rx_valid && f_got != 2'd3) f_got <= f_got + 1'b1;
      if (f_sent) begin
        f_pend <= 1'b1;
        f_byte <= tx_data;
        f_age  <= '0;
      end else if (rx_valid) begin
        f_pend <= 1'b0;
      end else if (f_pend) begin
        f_age <= f_age + 1'b1;
      end
    end
  end

  always @(posedge clk)
    if (rst_n && f_past_valid) begin
      assert (!rx_error);
      if (rx_valid) assert (f_pend && rx_data == f_byte);
      if (f_sent) assert (!f_pend || rx_valid);
      assert (f_age <= AgeW'(FrameMax));
    end

  // Covers
  logic [AgeW-1:0] f_since;
  logic            f_stall;

  always @(posedge clk) begin
    if (!rst_n) f_since <= '0;
    else if (core_en) begin
      if (f_sent) f_since <= '0;
      else if (f_since != '1) f_since <= f_since + 1'b1;
    end
  end

  always @(posedge clk) begin
    if (!rst_n || f_sent) f_stall <= 1'b0;
    else if (f_pend && !core_en) f_stall <= 1'b1;
  end

  always @(posedge clk)
    if (rst_n && f_past_valid) begin
      cover (rx_valid && f_got == 2'd0 && rx_data == 8'hA5);
      cover (rx_valid && f_stall && rx_data == 8'h5A);
      cover (f_sent && f_got == 2'd1 && f_since == AgeW'(10 * ClksPerBit - 1));
    end

endmodule

`default_nettype wire
