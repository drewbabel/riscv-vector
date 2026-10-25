`default_nettype none

module embench_boot_tb ();

  import cache_pkg::*;

  localparam int XLEN = arch_pkg::XLEN;
  localparam int DEPTH = 16384;
  localparam int IdxW = $clog2(DEPTH / LineWords);
  localparam int FastClkHz = arch_pkg::BoardClkHz;
  localparam int ClkDiv = 4;
  localparam int MemLat = arch_pkg::MemLatency;
  localparam int CoreClkHz = FastClkHz / ClkDiv;
  localparam int BaudRate = arch_pkg::BaudRate;
  localparam int ClksPerBit = (FastClkHz + BaudRate / 2) / BaudRate;
  localparam int RxBitFast = ((CoreClkHz + BaudRate / 2) / BaudRate) * ClkDiv;
  localparam int BootCycles = 2000;
  localparam int DrainCycles = 5000;
  localparam int TimeoutCycles = 2_000_000_000;
  localparam logic [15:0] Sentinel = 16'hC0DE;
  localparam int MinChecks = 40;

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
  string hexfile;

  always #5 clk = ~clk;

  board_top #(
      .DEPTH(DEPTH),
      .ClkDiv(ClkDiv),
      .MemLatency(MemLat)
  ) dut (
      .clk    (clk),
      .rst    (rst),
      .sw     (sw),
      .led    (led),
      .uart_rx(uart_rx),
      .uart_tx(uart_tx)
  );

  task automatic check(input string name, input logic got, input logic exp);
    checks++;
    if (got !== exp) begin
      errors++;
      $display("FAIL %s: got %h, expected %h", name, got, exp);
      if (errors == max_errors) $fatal(1, "TB STOPPED: %0d mismatches", errors);
    end
  endtask  // Automatic

  task automatic load_image(input string path);
    logic [LineBits-1:0] pline;
    for (int k = 0; k < DEPTH; k++) img[k] = '0;
    $readmemh(path, img);
    if (img[0] == '0) $fatal(1, "%s missing or empty, run make -C sw/embench all", path);
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

  task automatic recv_byte(output logic [7:0] c);
    @(negedge uart_tx);
    repeat (RxBitFast / 2) @(negedge clk);
    check("start bit", uart_tx, 1'b0);
    for (int i = 0; i < $bits(c); i++) begin
      repeat (RxBitFast) @(negedge clk);
      c[i] = uart_tx;
    end
    repeat (RxBitFast) @(negedge clk);
    check("stop bit", uart_tx, 1'b1);
  endtask  // Automatic

  // Serial monitor
  task automatic monitor();
    logic [7:0] c;
    forever begin
      recv_byte(c);
      $write("%c", c);
      $fflush();
    end
  endtask  // Automatic

  task automatic wait_sentinel();
    wait (led == Sentinel);
    repeat (DrainCycles) @(posedge clk);
    $display("\n[embench_boot_tb] %s finished (LED sentinel 0xC0DE)", hexfile);
  endtask  // Automatic

  task automatic watchdog();
    repeat (TimeoutCycles) @(posedge clk);
    $fatal(1, "TIMEOUT before Embench completion");
  endtask  // Automatic

  task automatic do_verdict();
    if (checks < MinChecks)
      $fatal(1, "TB UNDER-RAN: %0d checks, expected at least %0d", checks, MinChecks);
    if (errors == 0) $display("PASS: %0d checks, %0d mismatches", checks, errors);
    else $fatal(1, "FAIL: %0d mismatches, %0d checks", errors, checks);
    $finish;
  endtask  // Automatic

  task automatic read_args();
    if (!$value$plusargs("HEX=%s", hexfile)) hexfile = "sw/embench/crc32.hex";
    void'($value$plusargs("max_errors=%d", max_errors));
  endtask  // Automatic

  initial begin
    read_args();
    load_image(hexfile);
    do_reset();
    start_core();
    wait_sentinel();
    do_verdict();
  end

  initial monitor();

  initial watchdog();

endmodule

`default_nettype wire
