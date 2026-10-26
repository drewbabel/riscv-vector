`default_nettype none

module uart_rx_tb ();

  localparam int Budget = 64 * 1736;

  int checks;
  int errors;
  int max_errors;
  int live_errors;

  uart_rx_bench #(
      .CLK_FREQ_HZ(100_000_000),
      .BAUD_RATE  (115_200),
      .DATA_BITS  (8)
  ) fast_bench ();

  uart_rx_bench #(.BUDGET(Budget)) core_bench ();

  uart_rx_bench #(
      .OVERSAMPLE(8),
      .BUDGET(Budget)
  ) os8_bench ();

  uart_rx_bench #(
      .OVERSAMPLE(4),
      .BUDGET(Budget)
  ) os4_bench ();

  uart_rx_bench #(
      .DATA_BITS(7),
      .BUDGET(Budget)
  ) seven_bench ();

  uart_rx_bench #(
      .DATA_BITS(9),
      .BUDGET(Budget)
  ) nine_bench ();

  task automatic check_floor(input string name, input int got, input int floor);
    if (got < floor)
      $fatal(1, "TB UNDER-RAN: %s %0d checks, expected at least %0d", name, got, floor);
  endtask  // Automatic

  task automatic do_verdict();
    if (!(fast_bench.counted && core_bench.counted && os8_bench.counted && os4_bench.counted &&
          seven_bench.counted && nine_bench.counted))
      $fatal(1, "TB UNDER-RAN: flag or byte count short of frames sent");
    checks = fast_bench.checks + core_bench.checks + os8_bench.checks + os4_bench.checks +
        seven_bench.checks + nine_bench.checks;
    errors = fast_bench.errors + core_bench.errors + os8_bench.errors + os4_bench.errors +
        seven_bench.errors + nine_bench.errors;
    check_floor("fast_bench", fast_bench.checks, fast_bench.MinChecks);
    check_floor("core_bench", core_bench.checks, core_bench.MinChecks);
    check_floor("os8_bench", os8_bench.checks, os8_bench.MinChecks);
    check_floor("os4_bench", os4_bench.checks, os4_bench.MinChecks);
    check_floor("seven_bench", seven_bench.checks, seven_bench.MinChecks);
    check_floor("nine_bench", nine_bench.checks, nine_bench.MinChecks);
    if (errors == 0) $display("PASS: %0d checks, %0d mismatches", checks, errors);
    else $fatal(1, "FAIL: %0d mismatches, %0d checks", errors, checks);
    $finish;
  endtask  // Automatic

  initial begin
    $dumpfile("uart_rx_tb.vcd");
    $dumpvars(0, uart_rx_tb);
    wait (fast_bench.done && core_bench.done && os8_bench.done && os4_bench.done &&
          seven_bench.done && nine_bench.done);
    do_verdict();
  end

  always_comb
    live_errors = fast_bench.errors + core_bench.errors + os8_bench.errors + os4_bench.errors +
        seven_bench.errors + nine_bench.errors;

  initial begin
    if ($value$plusargs("max_errors=%d", max_errors) && max_errors > 0) begin
      wait (live_errors >= max_errors);
      $fatal(1, "TB STOPPED: %0d mismatches", live_errors);
    end
  end

endmodule

module uart_rx_bench #(
    parameter int CLK_FREQ_HZ = arch_pkg::CoreClkHz,
    parameter int BAUD_RATE   = arch_pkg::BaudRate,
    parameter int OVERSAMPLE  = 16,
    parameter int DATA_BITS   = arch_pkg::UartDataBits,
    parameter int BUDGET      = 0
) ();

  localparam int ClkFreqHz = CLK_FREQ_HZ;
  localparam int BaudRate = BAUD_RATE;
  localparam int Oversample = OVERSAMPLE;
  localparam int DataBits = DATA_BITS;

  localparam int ClksPerBit = (ClkFreqHz + BaudRate / 2) / BaudRate;
  localparam int ClksPerOversample = (ClksPerBit + Oversample / 2) / Oversample;

  // TX bit period for baud-mismatch tests
  localparam int ClksPerBitFast = (ClksPerBit * 98) / 100;
  localparam int ClksPerBitSlow = (ClksPerBit * 102) / 100;
  localparam int Exhaustive = 2 ** DataBits;
  localparam int Scaled = BUDGET / ClksPerBit;
  localparam int Values = (BUDGET == 0 || Scaled >= Exhaustive) ? Exhaustive :
      (Scaled < 16) ? 16 : Scaled;
  localparam int Step = Exhaustive / Values;
  localparam int MinChecks = 40 * Values;

  int checks = 0;
  int errors = 0;
  int max_errors = 0;
  logic done = 1'b0;
  logic counted = 1'b0;
  int frames_sent = 0;
  int valid_frames = 0;
  int flag_events = 0;
  int data_events = 0;
  int tx_bit = ClksPerBit;

  logic clk = 0;
  logic rst_n;
  logic rx_serial;
  logic [DataBits-1:0] rx_data;
  logic rx_valid;
  logic rx_error;

  logic exp_error;
  logic exp_valid;
  logic [DataBits-1:0] exp_data;
  logic exp_corrupt;

  always #5 if (!done) clk = ~clk;

  uart_rx #(
      .CLK_FREQ_HZ(ClkFreqHz),
      .BAUD_RATE  (BaudRate),
      .OVERSAMPLE (Oversample),
      .DATA_BITS  (DataBits)
  ) dut (
      .clk(clk),
      .core_en(1'b1),
      .rst_n(rst_n),
      .rx_serial(rx_serial),
      .rx_data(rx_data),
      .rx_valid(rx_valid),
      .rx_error(rx_error)
  );

  task automatic check(input string name, input logic [DataBits-1:0] got,
                       input logic [DataBits-1:0] exp);
    checks++;
    if (got !== exp) begin
      errors++;
      $display("FAIL %m %s: got %h, expected %h", name, got, exp);
      if (errors == max_errors) $fatal(1, "TB STOPPED: %0d mismatches", errors);
    end
  endtask  // Automatic

  task automatic do_reset();
    rst_n = 1'b0;
    rx_serial = 1'b1;
    repeat (2) @(posedge clk);
    @(negedge clk);
    rst_n = 1'b1;
  endtask  // Automatic

  task automatic send_data(input logic [DataBits-1:0] data, input logic corrupt);
    // Start bit (low)
    rx_serial = 1'b0;
    repeat (tx_bit) @(negedge clk);

    // Data bits
    for (int i = 0; i < $bits(data); i++) begin
      rx_serial = data[i];
      repeat (tx_bit) @(negedge clk);
    end

    // Stop bit (high)
    if (corrupt) begin
      rx_serial = 1'b0;
      repeat (tx_bit) @(negedge clk);
      rx_serial = 1'b1;
      repeat (tx_bit) @(negedge clk);
    end else begin
      rx_serial = 1'b1;
      repeat (tx_bit) @(negedge clk);
    end

    frames_sent++;
    if (!corrupt) valid_frames++;
  endtask  // Automatic

  task automatic check_flag_len(input int len);  // Reads live DUT signals, prevents stale args
    repeat (len) @(posedge clk);
    @(negedge clk);
    check($sformatf("flag held over %0d cycle(s)", len), DataBits'(rx_valid || rx_error), '0);
  endtask  // Automatic

  task automatic finish();
    repeat (2) @(posedge clk);
    counted = (flag_events == frames_sent) && (data_events == valid_frames);
    done = 1'b1;
  endtask  // Automatic

  // Exhaustive value (valid + corrupt) and randomized-corrupt sweep
  task automatic run_suite(input int bit_clks);
    tx_bit = bit_clks;
    for (int i = 0; i < 2; i++) begin
      for (int j = 0; j < Values; j++) begin
        exp_data = value_at(j);
        exp_corrupt = 1'(i);
        send_data(exp_data, exp_corrupt);
      end
    end

    for (int j = 0; j < Values; j++) begin
      exp_data = value_at(j);
      exp_corrupt = 1'($urandom);
      send_data(exp_data, exp_corrupt);
    end
  endtask  // Automatic

  function automatic logic [DataBits-1:0] value_at(input int j);
    return (j == Values - 1) ? '1 : DataBits'(j * Step);
  endfunction

  initial void'($value$plusargs("max_errors=%d", max_errors));

  initial begin
    do_reset();
    run_suite(ClksPerBit);
    run_suite(ClksPerBitFast);
    run_suite(ClksPerBitSlow);
    finish();
  end

  assign exp_valid = ~exp_corrupt;
  assign exp_error = exp_corrupt;

  always @(posedge rx_valid, posedge rx_error) begin
    flag_events++;
    check("flag type (valid)", DataBits'(rx_valid), DataBits'(exp_valid));
    check("flag type (error)", DataBits'(rx_error), DataBits'(exp_error));
    check_flag_len(1);
  end

  always @(posedge rx_valid) begin
    data_events++;
    check("data", rx_data, exp_data);
  end

  always @(posedge clk) begin
    if (rst_n && (rx_valid || rx_error))
      check("rx_valid and rx_error exclusive", DataBits'(rx_valid && rx_error), '0);
  end

endmodule

`default_nettype wire
