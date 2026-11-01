`default_nettype none

module freertos_boot_tb ();

  import cache_pkg::*;

  localparam int XLEN = arch_pkg::XLEN;
  localparam int DEPTH = 16384;
  localparam int IdxW = $clog2(DEPTH / LineWords);
  localparam int FastClkHz = arch_pkg::BoardClkHz;
  localparam int BaudRate = arch_pkg::BaudRate;
  localparam int ClksPerBit = (FastClkHz + BaudRate / 2) / BaudRate;
  localparam int SettleCycles = 6_000_000;
  localparam int BootCycles = 2000;
  localparam logic [XLEN-1:0] Unwritten = 32'hDEADBEEF;
  localparam int MinChecks = 2;

  int checks = 0;
  int errors = 0;
  int max_errors = 0;

  logic clk = 1'b0;
  logic rst = 1'b1;
  logic [15:0] sw;
  logic [15:0] led;
  logic uart_rx = 1'b1;
  logic uart_tx;
  logic [XLEN-1:0] img[DEPTH];

  always #5 clk = ~clk;

  board_top #(
      .DEPTH(DEPTH)
  ) dut (
      .clk(clk),
      .rst(rst),
      .sw(sw),
      .led(led),
      .uart_rx(uart_rx),
      .uart_tx(uart_tx),
      .sim_branch(),
      .sim_branch_taken(),
      .sim_mispredict(),
      .sim_muldiv_hold(),
      .sim_tx_valid(),
      .sim_tx_data()
  );

  task automatic check(input string name, input logic [$bits(led)-1:0] got,
                       input logic [$bits(led)-1:0] exp);
    checks++;
    if (got !== exp) begin
      errors++;
      $display("FAIL %s: got %h, expected %h", name, got, exp);
      if (errors == max_errors) $fatal(1, "TB STOPPED: %0d mismatches", errors);
    end
  endtask  // Automatic

  task automatic load_image(input string path);
    logic [LineBits-1:0] pline;
    for (int k = 0; k < DEPTH; k++) img[k] = Unwritten;
    $readmemh(path, img);
    if (img[0] == Unwritten) $fatal(1, "%s missing or empty, run make -C sw/freertos all", path);
    for (int l = 0; l < DEPTH / LineWords; l++) begin
      for (int w = 0; w < LineWords; w++) pline[XLEN*w+:XLEN] = img[l*LineWords+w];
      @(negedge clk);
      dut.imem_inst.u_line.bd_idx  = IdxW'(l);
      dut.imem_inst.u_line.bd_data = pline;
      dut.imem_inst.u_line.bd_we   = 1'b1;
      dut.dmem_inst.u_line.bd_idx  = IdxW'(l);
      dut.dmem_inst.u_line.bd_data = pline;
      dut.dmem_inst.u_line.bd_we   = 1'b1;
    end
    @(negedge clk);
    dut.imem_inst.u_line.bd_we = 1'b0;
    dut.dmem_inst.u_line.bd_we = 1'b0;
  endtask  // Automatic

  task automatic do_reset();
    rst = 1'b1;
    sw = '0;
    uart_rx = 1'b1;
    repeat (2) @(posedge clk);
    @(negedge clk);
    rst = 1'b0;
  endtask  // Automatic

  task automatic send_byte(input logic [7:0] b);
    @(negedge clk);
    uart_rx = 1'b0;
    repeat (ClksPerBit) @(negedge clk);
    for (int i = 0; i < $bits(b); i++) begin
      uart_rx = b[i];
      repeat (ClksPerBit) @(negedge clk);
    end
    uart_rx = 1'b1;
    repeat (ClksPerBit) @(negedge clk);
  endtask  // Automatic

  // Zero length boot
  task automatic start_core();
    repeat (BootCycles) @(posedge clk);
    repeat (XLEN / 8) send_byte('0);
  endtask  // Automatic

  task automatic drive_switches(input logic [$bits(sw)-1:0] pattern);
    @(negedge clk);
    sw = pattern;
  endtask  // Automatic

  // Switches reach LEDs
  task automatic expect_leds(input string name, input logic [$bits(led)-1:0] pattern);
    for (int i = 0; i < SettleCycles && led !== pattern; i++) @(negedge clk);
    check(name, led, pattern);
  endtask  // Automatic

  task automatic queue_pattern(input string name, input logic [$bits(sw)-1:0] pattern);
    drive_switches(pattern);
    expect_leds(name, pattern);
  endtask  // Automatic

  task automatic do_verdict();
    if (checks < MinChecks)
      $fatal(1, "TB UNDER-RAN: %0d checks, expected at least %0d", checks, MinChecks);
    if (errors == 0) $display("PASS: %0d checks, %0d mismatches", checks, errors);
    else $fatal(1, "FAIL: %0d mismatches, %0d checks", errors, checks);
    $finish;
  endtask  // Automatic

  initial void'($value$plusargs("max_errors=%d", max_errors));

  initial begin
    load_image("sw/freertos/freertos_sim.hex");
    do_reset();
    start_core();
    queue_pattern("queue_pattern_a", 16'hA5A5);
    queue_pattern("queue_pattern_b", 16'h3C3C);
    do_verdict();
  end

endmodule

`default_nettype wire
