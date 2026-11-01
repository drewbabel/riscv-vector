`default_nettype none

module uart_tx_tb ();

  localparam int MinChecks = 6;

  int checks;
  int errors;
  int max_errors;
  int live_errors;

  uart_tx_bench core_bench ();

  uart_tx_bench #(.CLK_DIV(32)) slow_bench ();

  uart_tx_bench #(.DATA_BITS(7)) seven_bench ();

  uart_tx_bench #(.DATA_BITS(9)) nine_bench ();

  task automatic check_floor(input string name, input int got, input int floor);
    if (got < floor)
      $fatal(1, "TB UNDER-RAN: %s %0d checks, expected at least %0d", name, got, floor);
  endtask  // Automatic

  task automatic do_verdict();
    checks = core_bench.checks + slow_bench.checks + seven_bench.checks + nine_bench.checks;
    errors = core_bench.errors + slow_bench.errors + seven_bench.errors + nine_bench.errors;
    check_floor("core_bench", core_bench.checks, MinChecks);
    check_floor("slow_bench", slow_bench.checks, MinChecks);
    check_floor("seven_bench", seven_bench.checks, MinChecks);
    check_floor("nine_bench", nine_bench.checks, MinChecks);
    if (errors == 0) $display("PASS: %0d checks, %0d mismatches", checks, errors);
    else $fatal(1, "FAIL: %0d mismatches, %0d checks", errors, checks);
    $finish;
  endtask  // Automatic

  initial begin
    $dumpfile("uart_tx_tb.vcd");
    $dumpvars(0, uart_tx_tb);
    wait (core_bench.done && slow_bench.done && seven_bench.done && nine_bench.done);
    do_verdict();
  end

  always_comb
    live_errors = core_bench.errors + slow_bench.errors + seven_bench.errors + nine_bench.errors;

  initial begin
    if ($value$plusargs("max_errors=%d", max_errors) && max_errors > 0) begin
      wait (live_errors >= max_errors);
      $fatal(1, "TB STOPPED: %0d mismatches", live_errors);
    end
  end

endmodule

module uart_tx_bench #(
    parameter int CLK_DIV   = arch_pkg::ClkDiv,
    parameter int DATA_BITS = arch_pkg::UartDataBits
) ();

  localparam int ClkDiv = CLK_DIV;
  localparam int ClkFreqHz = arch_pkg::BoardClkHz / ClkDiv;
  localparam int BaudRate = arch_pkg::BaudRate;
  localparam int DataBits = DATA_BITS;
  localparam int BitFast = ((ClkFreqHz + BaudRate / 2) / BaudRate) * ClkDiv;
  localparam int TimeoutCycles = 8 * (DataBits + 2) * BitFast;

  int checks = 0;
  int errors = 0;
  int max_errors = 0;
  logic done = 1'b0;

  logic clk = 1'b0;
  logic core_en;
  logic rst_n;
  logic [DataBits-1:0] tx_data;
  logic tx_valid;
  logic tx_ready;
  logic tx_serial;
  logic [$clog2(ClkDiv)-1:0] div = '0;

  always #5 clk = ~clk;

  // Core enable pulse
  always_ff @(posedge clk) div <= div + 1'b1;
  assign core_en = (div == '0);

  uart_tx #(
      .CLK_FREQ_HZ(ClkFreqHz),
      .BAUD_RATE  (BaudRate),
      .DATA_BITS  (DataBits)
  ) dut (
      .clk      (clk),
      .core_en  (core_en),
      .rst_n    (rst_n),
      .tx_data  (tx_data),
      .tx_valid (tx_valid),
      .tx_ready (tx_ready),
      .tx_serial(tx_serial)
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
    rst_n = 0;
    tx_valid = 0;
    tx_data = '0;
    repeat (2) @(posedge clk);
    @(negedge clk);
    rst_n = 1;
    repeat (4) @(negedge clk);
  endtask  // Automatic

  task automatic send(input logic [DataBits-1:0] b);
    do @(negedge clk); while (!tx_ready);
    tx_data  = b;
    tx_valid = 1'b1;
    do @(posedge clk); while (!(core_en && tx_ready));
    @(negedge clk);
    tx_valid = 1'b0;
  endtask  // Automatic

  task automatic recv(output logic [DataBits-1:0] b);
    @(negedge tx_serial);
    repeat (BitFast / 2) @(posedge clk);
    for (int i = 0; i < DataBits; i++) begin
      repeat (BitFast) @(posedge clk);
      b[i] = tx_serial;
    end
    repeat (BitFast) @(posedge clk);
  endtask  // Automatic

  task automatic recv_check(input string name, input logic [DataBits-1:0] exp);
    logic [DataBits-1:0] got;
    recv(got);
    check(name, got, exp);
  endtask  // Automatic

  task automatic check_idle();
    check("idle_high", DataBits'(tx_serial), DataBits'(1));
    check("ready_after_reset", DataBits'(tx_ready), DataBits'(1));
  endtask  // Automatic

  task automatic stream_bytes();
    logic [DataBits-1:0] pat[4] = '{DataBits'('h41), DataBits'('h55), '0, '1};
    fork
      foreach (pat[i]) send(pat[i]);
      foreach (pat[i]) recv_check($sformatf("byte%0d", i), pat[i]);
    join
  endtask  // Automatic

  task automatic watchdog(input int cycles);
    repeat (cycles) @(posedge clk);
    $fatal(1, "TIMEOUT: %0d cycles", cycles);
  endtask  // Automatic

  task automatic finish();
    @(negedge clk);
    done = 1'b1;
  endtask  // Automatic

  initial void'($value$plusargs("max_errors=%d", max_errors));

  initial watchdog(TimeoutCycles);

  initial begin
    do_reset();
    check_idle();
    stream_bytes();
    finish();
  end

endmodule

`default_nettype wire
