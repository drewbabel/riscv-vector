`default_nettype none

module pc_tb ();

  localparam int Xlen = arch_pkg::XLEN;
  localparam int MinChecks = 1000;

  int checks;
  int errors;
  int max_errors;

  pc_bench #(.RESET_ADDR('0)) zero_bench ();

  pc_bench #(.RESET_ADDR(Xlen'(256))) high_bench ();

  pc_bench #(.RESET_ADDR(Xlen'(32'h8000_0000))) top_bench ();

  task automatic do_verdict();
    checks = zero_bench.checks + high_bench.checks + top_bench.checks;
    errors = zero_bench.errors + high_bench.errors + top_bench.errors;
    if (zero_bench.checks < MinChecks || high_bench.checks < MinChecks ||
        top_bench.checks < MinChecks)
      $fatal(
          1,
          "TB UNDER-RAN: %0d, %0d and %0d checks, expected at least %0d each",
          zero_bench.checks,
          high_bench.checks,
          top_bench.checks,
          MinChecks
      );
    if (errors == 0) $display("PASS: %0d checks, %0d mismatches", checks, errors);
    else $fatal(1, "FAIL: %0d mismatches, %0d checks", errors, checks);
    $finish;
  endtask  // Automatic

  initial begin
    $dumpfile("pc_tb.vcd");
    $dumpvars(0, pc_tb);
    wait (zero_bench.done && high_bench.done && top_bench.done);
    do_verdict();
  end

  initial begin
    if ($value$plusargs("max_errors=%d", max_errors) && max_errors > 0) begin
      wait (zero_bench.errors + high_bench.errors + top_bench.errors >= max_errors);
      $fatal(1, "TB STOPPED: %0d mismatches",
             zero_bench.errors + high_bench.errors + top_bench.errors);
    end
  end

endmodule

module pc_bench #(
    parameter logic [arch_pkg::XLEN-1:0] RESET_ADDR = '0
) ();

  localparam int Xlen = arch_pkg::XLEN;
  localparam logic [Xlen-1:0] ResetAddr = RESET_ADDR;
  localparam int ResetEvery = 6;

  int checks = 0;
  int errors = 0;
  logic done = 1'b0;

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
      $display("FAIL RESET_ADDR %0h %s: got %h, expected %h", ResetAddr, name, got, exp);
    end
  endtask  // Automatic

  task automatic do_reset();
    rst_n   = 0;
    pc_next = '0;
    repeat (2) @(posedge clk);
    @(negedge clk);
    rst_n = 1;
  endtask  // Automatic

  task automatic finish();
    @(posedge clk);
    done = 1'b1;
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

  initial begin
    do_reset();
    soak(1000);
    finish();
  end

endmodule

`default_nettype wire
