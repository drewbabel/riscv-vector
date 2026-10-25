`default_nettype none

module board_top_tb ();

  localparam int MinChecks = 3;
  localparam int XLEN = arch_pkg::XLEN;
  localparam int FastClkHz = arch_pkg::BoardClkHz;
  localparam int ClkDiv = 32;
  localparam int CoreClkHz = FastClkHz / ClkDiv;
  localparam int BaudRate = arch_pkg::BaudRate;
  localparam int Depth = 1024;
  localparam int ResetCycles = 200;
  localparam int LedWait = 60_000;

  // Bit period
  localparam int ClksPerBit = (FastClkHz + BaudRate / 2) / BaudRate;

  localparam int NWords = 12;

  int checks = 0;
  int errors = 0;
  int max_errors = 0;

  logic clk = 1'b0;
  logic rst = 1'b1;
  logic [15:0] sw;
  logic [15:0] led;
  logic uart_rx = 1'b1;
  logic uart_tx;

  localparam int LedW = $bits(led);
  localparam logic [LedW-1:0] LoadingLed = LedW'('h5555);
  localparam logic [LedW-1:0] MemtestLed = LedW'('hABCD);

  logic [XLEN-1:0] prog[NWords];

  always #5 clk = ~clk;

  board_top #(
      .DEPTH (Depth),
      .ClkDiv(ClkDiv)
  ) dut (
      .clk    (clk),
      .rst    (rst),
      .sw     (sw),
      .led    (led),
      .uart_rx(uart_rx),
      .uart_tx(uart_tx)
  );

  task automatic check(input string name, input logic [LedW-1:0] got, input logic [LedW-1:0] exp);
    checks++;
    if (got !== exp) begin
      errors++;
      $display("FAIL %s: got %h, expected %h", name, got, exp);
      if (errors == max_errors) $fatal(1, "TB STOPPED: %0d mismatches", errors);
    end
  endtask  // Automatic

  task automatic do_reset();
    @(negedge clk);
    rst     = 1'b1;
    sw      = '0;
    uart_rx = 1'b1;
    repeat (2) @(posedge clk);
    @(negedge clk);
    rst = 1'b0;
    repeat (ResetCycles) @(negedge clk);
  endtask  // Automatic

  task automatic load_image();
    $readmemh("tests/memtest.hex", prog);
    if ($isunknown(prog[0]) || prog[0] == '0)
      $fatal(1, "memtest.hex missing or empty, run make hex PROG=memtest");
  endtask  // Automatic

  task automatic send_byte(input logic [7:0] b);
    uart_rx = 1'b0;
    repeat (ClksPerBit) @(negedge clk);
    for (int i = 0; i < $bits(b); i++) begin
      uart_rx = b[i];
      repeat (ClksPerBit) @(negedge clk);
    end
    uart_rx = 1'b1;
    repeat (ClksPerBit) @(negedge clk);
  endtask  // Automatic

  task automatic send_word(input logic [XLEN-1:0] w);
    for (int j = 0; j < XLEN; j += 8) send_byte(w[j+:8]);
  endtask  // Automatic

  task automatic boot_program();
    check("loading led", led, LoadingLed);
    send_word(XLEN'(NWords));
    for (int i = 0; i < NWords; i++) send_word(prog[i]);
  endtask  // Automatic

  task automatic wait_led(input logic [LedW-1:0] exp, input int cycles);
    int i = 0;
    while (led !== exp && i < cycles) begin
      @(negedge clk);
      i++;
    end
  endtask  // Automatic

  task automatic wait_loaded();
    while (led === LoadingLed) @(negedge clk);
  endtask  // Automatic

  task automatic check_leds();
    wait_loaded();
    wait_led(MemtestLed, LedWait);
    check("led", led, MemtestLed);
    wait_led(LedW'(CoreClkHz), LedWait);
    check("core_clk_hz", led, LedW'(CoreClkHz));
  endtask  // Automatic

  task automatic do_verdict();
    if (checks < MinChecks)
      $fatal(1, "TB UNDER-RAN: %0d checks, expected at least %0d", checks, MinChecks);
    if (errors == 0) $display("PASS: %0d checks, %0d mismatches", checks, errors);
    else $fatal(1, "FAIL: %0d mismatches, %0d checks", errors, checks);
    $finish;
  endtask  // Automatic

  initial void'($value$plusargs("max_errors=%d", max_errors));

  // Word round trip
  initial begin
    $dumpfile("board_top_tb.vcd");
    $dumpvars(0, board_top_tb);
    load_image();
    do_reset();

    boot_program();
    check_leds();

    do_verdict();
  end

endmodule

`default_nettype wire
