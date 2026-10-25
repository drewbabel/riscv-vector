`default_nettype none

module gpio_tb;

  localparam int MinChecks = 9;
  localparam int Xlen = arch_pkg::XLEN;
  localparam int StrbW = Xlen / 8;
  localparam int Width = 16;
  localparam int TagW = $bits(arch_pkg::GpioTag);
  localparam logic [Xlen-1:0] Base = {arch_pkg::GpioTag, {(Xlen - TagW) {1'b0}}};
  localparam logic [Xlen-1:0] LedAddr = Base;
  localparam logic [Xlen-1:0] SwAddr = Base | Xlen'('h4);

  int checks = 0;
  int errors = 0;
  int max_errors = 0;

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
      $display("FAIL %s: got %h, expected %h", name, got, exp);
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
    mmio_write(LedAddr, Xlen'('hBEEF), '1);
    check_led("led_after_write", Width'('hBEEF));
    check_read("led_readback", LedAddr, Xlen'('hBEEF));
  endtask  // Automatic

  task automatic test_switches();
    set_switches(Width'('hA5A5));
    check_read("sw_read", SwAddr, Xlen'('hA5A5));
    mmio_write(SwAddr, Xlen'('h1234), '1);
    check_led("sw_write_ignored", Width'('hBEEF));
  endtask  // Automatic

  task automatic test_write_guards();
    mmio_write(LedAddr, Xlen'('h0F0F), '0);
    check_led("no_strobe_ignored", Width'('hBEEF));
    mmio_write(LedAddr, Xlen'('h00FF), '1);
    check_led("led_second_write", Width'('h00FF));
    bus_write(1'b0, LedAddr, Xlen'('hDEAD), '1);
    check_led("deselected_write_ignored", Width'('h00FF));
  endtask  // Automatic

  task automatic test_reset_clears();
    do_reset();
    check_led("led_cleared_by_reset", '0);
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
    $dumpfile("gpio_tb.vcd");
    $dumpvars(0, gpio_tb);
    do_reset();

    test_led_write();
    test_switches();
    test_write_guards();
    test_reset_clears();

    do_verdict();
  end

endmodule

`default_nettype wire
