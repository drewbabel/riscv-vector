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
  localparam int BitEn = (ClkFreqHz + BaudRate / 2) / BaudRate;
  localparam int BitFast = BitEn * ClkDiv;
  localparam int RandomBytes = 24;
  localparam int TimeoutCycles = 2 * (8 + 4 * RandomBytes) * (DataBits + 2) * BitFast;

  int checks = 0;
  int errors = 0;
  int max_errors = 0;
  logic done = 1'b0;

  logic clk = 1'b0;
  logic core_en = 1'b0;
  logic rst_n;
  logic [DataBits-1:0] tx_data;
  logic tx_valid;
  logic tx_ready;
  logic tx_serial;

  always #5 clk = ~clk;

  // Random core enable
  always @(negedge clk) core_en = $urandom_range(ClkDiv - 1) == 0;

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

  task automatic en_cycle();
    do @(posedge clk); while (!core_en);
  endtask  // Automatic

  task automatic do_reset();
    rst_n = 0;
    tx_valid = 0;
    tx_data = '0;
    repeat (2) en_cycle();
    @(negedge clk);
    rst_n = 1;
    repeat (4) @(negedge clk);
  endtask  // Automatic

  task automatic send(input logic [DataBits-1:0] b);
    @(negedge clk);
    tx_data  = b;
    tx_valid = 1'b1;
    do @(posedge clk); while (!(core_en && tx_ready));
    @(negedge clk);
    tx_valid = 1'b0;
  endtask  // Automatic

  task automatic recv(output logic [DataBits-1:0] b);
    logic steady;
    int   t;
    @(negedge tx_serial);
    t = 0;
    for (int i = 0; i < DataBits; i++) begin
      for (; t < (i + 1) * BitEn + BitEn / 4; t++) en_cycle();
      b[i]   = tx_serial;
      steady = 1'b1;
      for (; t < (i + 1) * BitEn + 3 * BitEn / 4; t++) begin
        en_cycle();
        steady = steady && (tx_serial === b[i]);
      end
      check($sformatf("bit %0d steady", i), DataBits'(steady), DataBits'(1));
    end
    for (; t < (DataBits + 1) * BitEn + BitEn / 2; t++) en_cycle();
    check("stop bit", DataBits'(tx_serial), DataBits'(1));
    repeat (BitEn / 2) en_cycle();
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
    logic [DataBits-1:0] pat[4];
    pat = '{DataBits'('h41), DataBits'('h55), '0, '1};
    fork
      foreach (pat[i]) send(pat[i]);
      foreach (pat[i]) recv_check($sformatf("byte%0d", i), pat[i]);
    join
  endtask  // Automatic

  task automatic stream_random();
    logic [DataBits-1:0] pat[RandomBytes];
    foreach (pat[i]) pat[i] = DataBits'($urandom);
    fork
      foreach (pat[i]) begin
        if (1'($urandom)) repeat ($urandom_range(3 * BitFast)) @(negedge clk);
        send(pat[i]);
      end
      foreach (pat[i]) recv_check($sformatf("random byte %0d", i), pat[i]);
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
    stream_random();
    finish();
  end

endmodule

`default_nettype wire
