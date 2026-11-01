`default_nettype none

module synchronizer_tb ();

  localparam int MinChecks = 100;

  int   errors = 0;
  int   max_errors = 0;
  int   checks = 0;

  logic clk = 0;
  logic d;
  logic q;
  logic d1;
  logic d2;

  always #5 clk = ~clk;

  synchronizer dut (
      .clk(clk),
      .core_en(1'b1),
      .d(d),
      .q(q)
  );

  task automatic check(input string name, input logic got, input logic exp);
    checks++;
    if (got !== exp) begin
      errors++;
      $display("FAIL %s: got %h, expected %h", name, got, exp);
      if (errors == max_errors) $fatal(1, "TB STOPPED: %0d mismatches", errors);
    end
  endtask  // Automatic

  task automatic do_reset();
    d = 1'b0;
    repeat (2) @(posedge clk);
  endtask  // Automatic

  task automatic drive_random(input int n);
    repeat (n) begin
      @(negedge clk);
      d = 1'($urandom);
    end
    @(posedge clk);
  endtask  // Automatic

  task automatic do_verdict();
    @(posedge clk);
    if (checks < MinChecks)
      $fatal(1, "TB UNDER-RAN: %0d checks, expected at least %0d", checks, MinChecks);
    if (errors == 0) $display("PASS: %0d checks, %0d mismatches", checks, errors);
    else $fatal(1, "FAIL: %0d mismatches, %0d checks", errors, checks);
    $finish;
  endtask  // Automatic

  initial void'($value$plusargs("max_errors=%d", max_errors));

  // Stimulus
  initial begin
    $dumpfile("synchronizer_tb.vcd");
    $dumpvars(0, synchronizer_tb);
    do_reset();
    drive_random(100);
    do_verdict();
  end

  // Reference model
  always @(posedge clk) begin
    d1 <= d;
    d2 <= d1;
  end

  // Comparison to DUT
  always @(negedge clk) begin
    check("ff2", q, d2);
  end

endmodule

`default_nettype wire
