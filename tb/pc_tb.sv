`default_nettype none

module pc_tb ();

  localparam int Xlen = arch_pkg::XLEN;
  localparam logic [Xlen-1:0] ResetAddr = '0;
  localparam int ResetEvery = 6;
  localparam int MinChecks = 1000;

  int checks = 0;
  int errors = 0;
  int max_errors = 0;

  logic clk = 0;
  logic rst_n;
  logic [Xlen-1:0] pc_next;
  logic [Xlen-1:0] pc_q;

  always #5 clk = ~clk;

  pc #(
      .XLEN(Xlen),
      .RESET_ADDR(ResetAddr)
  ) dut (
      .clk(clk),
      .core_en(1'b1),
      .rst_n(rst_n),
      .pc_next(pc_next),
      .pc_q(pc_q)
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
    rst_n   = 0;
    pc_next = '0;
    repeat (2) @(posedge clk);
    @(negedge clk);
    rst_n = 1;
  endtask  // Automatic

  task automatic do_verdict();
    @(posedge clk);
    if (checks < MinChecks)
      $fatal(1, "TB UNDER-RAN: %0d checks, expected at least %0d", checks, MinChecks);
    if (errors == 0) $display("PASS: %0d checks, %0d mismatches", checks, errors);
    else $fatal(1, "FAIL: %0d mismatches, %0d checks", errors, checks);
    $finish;
  endtask  // Automatic

  task automatic pc_suite(input logic rst_in, input logic [Xlen-1:0] exp_pc, input logic reg_check);
    @(negedge clk);
    rst_n   = rst_in;
    pc_next = exp_pc;
    @(negedge clk);
    if (reg_check) pc_next = Xlen'($urandom);
    @(posedge clk);
    check(rst_in ? "pc_q" : "pc_q reset", pc_q, rst_in ? exp_pc : ResetAddr);
  endtask  // Automatic

  task automatic soak(input int n);
    for (int i = 0; i < n; i++) pc_suite(1'((i % ResetEvery) != 0), Xlen'($urandom), 1'($urandom));
  endtask  // Automatic

  initial void'($value$plusargs("max_errors=%d", max_errors));

  initial begin
    $dumpfile("pc_tb.vcd");
    $dumpvars(0, pc_tb);
    do_reset();
    soak(1000);
    do_verdict();
  end
endmodule

`default_nettype wire
