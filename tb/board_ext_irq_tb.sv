`default_nettype none

module board_ext_irq_tb ();

  localparam int MinChecks = 1;
  localparam int XLEN = arch_pkg::XLEN;
  localparam int FastClkHz = arch_pkg::BoardClkHz;
  localparam int ClkDiv = 32;
  localparam int CoreClkHz = FastClkHz / ClkDiv;
  localparam int BaudRate = arch_pkg::BaudRate;
  localparam int DataBits = arch_pkg::UartDataBits;
  localparam int Depth = 1024;
  localparam int ResetCycles = 200;
  localparam int TimeoutCycles = 6_000_000;

  localparam int ClksPerBit = (FastClkHz + BaudRate / 2) / BaudRate;
  localparam int RxBitFast = ((CoreClkHz + BaudRate / 2) / BaudRate) * ClkDiv;

  localparam int NWords = 20;
  localparam logic [7:0] SentByte = 8'h4B;

  int checks = 0;
  int errors = 0;
  int max_errors = 0;

  logic clk = 1'b0;
  logic rst = 1'b1;
  logic [15:0] sw;
  logic [15:0] led;
  logic uart_rx = 1'b1;
  logic uart_tx;

  logic [XLEN-1:0] prog[NWords];
  logic [7:0] echoed;

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

  task automatic check(input string name, input logic [DataBits-1:0] got,
                       input logic [DataBits-1:0] exp);
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
    $readmemh("tests/uart_irq.hex", prog);
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
    send_word(XLEN'(NWords));
    for (int i = 0; i < NWords; i++) send_word(prog[i]);
  endtask  // Automatic

  // Sample bit centers
  task automatic recv_byte(output logic [7:0] b);
    @(negedge uart_tx);
    repeat (RxBitFast / 2) @(posedge clk);
    for (int i = 0; i < $bits(b); i++) begin
      repeat (RxBitFast) @(posedge clk);
      b[i] = uart_tx;
    end
    repeat (RxBitFast) @(posedge clk);
  endtask  // Automatic

  task automatic check_echo();
    fork
      send_byte(SentByte);
      recv_byte(echoed);
    join
    check("echo", echoed, SentByte);
  endtask  // Automatic

  task automatic watchdog(input int n);
    repeat (n) @(posedge clk);
    $fatal(1, "TIMEOUT before the echo arrived");
  endtask  // Automatic

  task automatic do_verdict();
    if (checks < MinChecks)
      $fatal(1, "TB UNDER-RAN: %0d checks, expected at least %0d", checks, MinChecks);
    if (errors == 0) $display("PASS: %0d checks, %0d mismatches", checks, errors);
    else $fatal(1, "FAIL: %0d mismatches, %0d checks", errors, checks);
    $finish;
  endtask  // Automatic

  initial void'($value$plusargs("max_errors=%d", max_errors));

  // Watchdog
  initial watchdog(TimeoutCycles);

  initial begin
    $dumpfile("board_ext_irq_tb.vcd");
    $dumpvars(0, board_ext_irq_tb);
    load_image();
    do_reset();

    boot_program();
    check_echo();

    do_verdict();
  end

endmodule

`default_nettype wire
