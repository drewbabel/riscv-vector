`default_nettype none

module gpio_tb ();

  localparam int MinChecks = 9;

  int checks;
  int errors;
  int max_errors;
  int live_errors;

  gpio_bench #(.WIDTH(8)) w8_bench ();

  gpio_bench #(.WIDTH(16)) w16_bench ();

  gpio_bench #(.WIDTH(32)) w32_bench ();

  task automatic check_floor(input string name, input int got, input int floor);
    if (got < floor)
      $fatal(1, "TB UNDER-RAN: %s %0d checks, expected at least %0d", name, got, floor);
  endtask  // Automatic

  task automatic do_verdict();
    checks = w8_bench.checks + w16_bench.checks + w32_bench.checks;
    errors = w8_bench.errors + w16_bench.errors + w32_bench.errors;
    check_floor("w8_bench", w8_bench.checks, MinChecks);
    check_floor("w16_bench", w16_bench.checks, MinChecks);
    check_floor("w32_bench", w32_bench.checks, MinChecks);
    if (errors == 0) $display("PASS: %0d checks, %0d mismatches", checks, errors);
    else $fatal(1, "FAIL: %0d mismatches, %0d checks", errors, checks);
    $finish;
  endtask  // Automatic

  initial begin
    $dumpfile("gpio_tb.vcd");
    $dumpvars(0, gpio_tb);
    wait (w8_bench.done && w16_bench.done && w32_bench.done);
    do_verdict();
  end

  always_comb live_errors = w8_bench.errors + w16_bench.errors + w32_bench.errors;

  initial begin
    if ($value$plusargs("max_errors=%d", max_errors) && max_errors > 0) begin
      wait (live_errors >= max_errors);
      $fatal(1, "TB STOPPED: %0d mismatches", live_errors);
    end
  end

endmodule

module gpio_bench #(
    parameter int WIDTH = 16
) ();

  localparam int Xlen = arch_pkg::XLEN;
  localparam int StrbW = Xlen / 8;
  localparam int Width = WIDTH;
  localparam int TagW = $bits(arch_pkg::GpioTag);
  localparam logic [Xlen-1:0] Base = {arch_pkg::GpioTag, {(Xlen - TagW) {1'b0}}};
  localparam logic [Xlen-1:0] LedAddr = Base;
  localparam logic [Xlen-1:0] SwAddr = Base | Xlen'('h4);

  int checks = 0;
  int errors = 0;
  int max_errors = 0;
  logic done = 1'b0;

  logic clk = 1'b0;
  logic rst_n = 1'b1;
  logic sel;
  logic [StrbW-1:0] wstrb;
  logic [Xlen-1:0] addr;
  logic [Xlen-1:0] wdata;
  logic [Xlen-1:0] rdata;
  logic [Width-1:0] sw;
  logic [Width-1:0] led;

  always #5 clk = ~clk;

  gpio #(
      .XLEN (Xlen),
      .WIDTH(Width)
  ) dut (
      .clk    (clk),
      .core_en(1'b1),
      .rst_n  (rst_n),
      .sel    (sel),
      .wstrb  (wstrb),
      .addr   (addr),
      .wdata  (wdata),
      .rdata  (rdata),
      .sw     (sw),
      .led    (led)
  );

  task automatic check(input string name, input logic [Xlen-1:0] got, input logic [Xlen-1:0] exp);
    checks++;
    if (got !== exp) begin
      errors++;
      $display("FAIL %m %s: got %h, expected %h", name, got, exp);
      if (errors == max_errors) $fatal(1, "TB STOPPED: %0d mismatches", errors);
    end
  endtask  // Automatic

  task automatic do_reset();
    @(negedge clk);
    rst_n = 1'b0;
    sel   = 1'b0;
    wstrb = '0;
    addr  = '0;
    wdata = '0;
    sw    = '0;
    repeat (2) @(posedge clk);
    @(negedge clk);
    rst_n = 1'b1;
  endtask  // Automatic

  task automatic bus_write(input logic s, input logic [Xlen-1:0] a, input logic [Xlen-1:0] d,
                           input logic [StrbW-1:0] strb);
    sel   = s;
    wstrb = strb;
    addr  = a;
    wdata = d;
    @(negedge clk);
    sel   = 1'b0;
    wstrb = '0;
  endtask  // Automatic

  task automatic mmio_write(input logic [Xlen-1:0] a, input logic [Xlen-1:0] d,
                            input logic [StrbW-1:0] strb);
    bus_write(1'b1, a, d, strb);
  endtask  // Automatic

  task automatic set_switches(input logic [Width-1:0] value);
    sw = value;
  endtask  // Automatic

  task automatic check_read(input string name, input logic [Xlen-1:0] a,
                            input logic [Xlen-1:0] exp);
    sel  = 1'b1;
    addr = a;
    @(posedge clk);
    check(name, rdata, exp);
    @(negedge clk);
    sel = 1'b0;
  endtask  // Automatic

  task automatic check_led(input string name, input logic [Width-1:0] exp);
    check(name, Xlen'(led), Xlen'(exp));
  endtask  // Automatic

  task automatic test_led_write();
    check_led("led_at_reset", '0);
    mmio_write(LedAddr, Xlen'('hCAFE_BEEF), '1);
    check_led("led_after_write", Width'('hCAFE_BEEF));
    check_read("led_readback", LedAddr, Xlen'(Width'('hCAFE_BEEF)));
  endtask  // Automatic

  task automatic test_switches();
    set_switches(Width'('h5A5A_A5A5));
    check_read("sw_read", SwAddr, Xlen'(Width'('h5A5A_A5A5)));
    mmio_write(SwAddr, Xlen'('h5678_1234), '1);
    check_led("sw_write_ignored", Width'('hCAFE_BEEF));
  endtask  // Automatic

  task automatic test_write_guards();
    mmio_write(LedAddr, Xlen'('hF0F0_0F0F), '0);
    check_led("no_strobe_ignored", Width'('hCAFE_BEEF));
    mmio_write(LedAddr, Xlen'('hFF00_00FF), '1);
    check_led("led_second_write", Width'('hFF00_00FF));
    bus_write(1'b0, LedAddr, Xlen'('h0BAD_DEAD), '1);
    check_led("deselected_write_ignored", Width'('hFF00_00FF));
  endtask  // Automatic

  task automatic test_reset_clears();
    do_reset();
    check_led("led_cleared_by_reset", '0);
  endtask  // Automatic

  task automatic finish();
    @(negedge clk);
    done = 1'b1;
  endtask  // Automatic

  initial void'($value$plusargs("max_errors=%d", max_errors));

  initial begin
    do_reset();

    test_led_write();
    test_switches();
    test_write_guards();
    test_reset_clears();

    finish();
  end

endmodule

`default_nettype wire
