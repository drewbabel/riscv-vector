`default_nettype none

module tick_gen_tb ();

  localparam int Divisor   = 4;
  localparam int MinChecks = 250;

  int   errors = 0;
  int   max_errors = 0;
  int   checks = 0;

  logic clk = 0;
  logic rst_n;
  logic clr = 0;
  logic tick;

  int   phase;  // Reference divisor phase: rst_n or clr clears it, else count and wrap

  always #5 clk = ~clk;

  tick_gen #(
      .DIVISOR(Divisor)
  ) dut (
      .clk(clk),
      .core_en(1'b1),
      .rst_n(rst_n),
      .clr(clr),
      .tick(tick)
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
    rst_n = 1'b0;
    clr   = 1'b0;
    repeat (2) @(posedge clk);
    @(negedge clk);
    rst_n = 1'b1;
  endtask  // Automatic

  task automatic do_verdict();
    if (checks < MinChecks)
      $fatal(1, "TB UNDER-RAN: %0d checks, expected at least %0d", checks, MinChecks);
    if (errors == 0) $display("PASS: %0d checks, %0d mismatches", checks, errors);
    else $fatal(1, "FAIL: %0d mismatches, %0d checks", errors, checks);
    $finish;
  endtask  // Automatic

  task automatic idle(input int n);
    repeat (n) @(negedge clk);
  endtask  // Automatic

  task automatic pulse_clr();
    clr = 1'b1;
    @(negedge clk);
    clr = 1'b0;
  endtask  // Automatic

  task automatic resync_mid_phase();
    idle(2);
    pulse_clr();
    idle(100);
  endtask  // Automatic

  task automatic back_to_back_clr();
    pulse_clr();
    pulse_clr();
    idle(50);
  endtask  // Automatic

  initial void'($value$plusargs("max_errors=%d", max_errors));

  initial begin
    $dumpfile("tick_gen_tb.vcd");
    $dumpvars(0, tick_gen_tb);
    do_reset();
    idle(100);
    resync_mid_phase();
    back_to_back_clr();
    do_verdict();
  end

  // Reference model
  always @(posedge clk) begin
    if (!rst_n) phase <= 0;
    else if (clr) phase <= 0;
    else phase <= (phase == Divisor - 1) ? 0 : phase + 1;
  end

  always @(negedge clk) begin
    if (rst_n) check("tick", tick, (phase == Divisor - 1));
  end
endmodule

`default_nettype wire
