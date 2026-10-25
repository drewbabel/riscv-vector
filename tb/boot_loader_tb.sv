`default_nettype none

module boot_loader_tb ();

  localparam int MinChecks = 32000;
  localparam int MinClampChecks = 66;
  localparam int Depth = 20000;
  localparam int SmallDepth = 32;
  localparam int Words = 16400;

  int checks;
  int errors;
  int max_errors;

  boot_loader_bench #(
      .DEPTH(Depth),
      .WORDS(Words)
  ) deep_bench ();

  // Depth clamps load
  boot_loader_bench #(
      .DEPTH(SmallDepth),
      .WORDS(Words)
  ) small_bench ();

  task automatic do_verdict();
    checks = deep_bench.checks + small_bench.checks;
    errors = deep_bench.errors + small_bench.errors;
    if (deep_bench.checks < MinChecks || small_bench.checks < MinClampChecks)
      $fatal(
          1,
          "TB UNDER-RAN: %0d and %0d checks, expected at least %0d and %0d",
          deep_bench.checks,
          small_bench.checks,
          MinChecks,
          MinClampChecks
      );
    if (errors == 0) $display("PASS: %0d checks, %0d mismatches", checks, errors);
    else $fatal(1, "FAIL: %0d mismatches, %0d checks", errors, checks);
    $finish;
  endtask  // Automatic

  initial begin
    $dumpfile("boot_loader_tb.vcd");
    $dumpvars(0, boot_loader_tb);
    wait (deep_bench.done && small_bench.done);
    do_verdict();
  end

  initial begin
    if ($value$plusargs("max_errors=%d", max_errors) && max_errors > 0) begin
      wait (deep_bench.errors + small_bench.errors >= max_errors);
      $fatal(1, "TB STOPPED: %0d mismatches", deep_bench.errors + small_bench.errors);
    end
  end

endmodule

module boot_loader_bench #(
    parameter int DEPTH = 16384,
    parameter int WORDS = 16400
) ();

  localparam int XLEN = arch_pkg::XLEN;
  localparam int WordBytes = XLEN / 8;
  localparam int OldCap = 16384;
  localparam int Loads = (WORDS < DEPTH) ? WORDS : DEPTH;

  int checks = 0;
  int errors = 0;
  int max_errors = 0;
  logic done = 1'b0;

  logic clk = 1'b0;
  logic rst_n = 1'b1;
  logic rx_valid;
  logic [7:0] rx_data;
  logic we;
  logic [XLEN-1:0] waddr;
  logic [XLEN-1:0] wdata;
  logic loading;

  logic [XLEN-1:0] prog[];
  logic [XLEN-1:0] write_idx = '0;

  always #5 clk = ~clk;

  boot_loader #(
      .XLEN (XLEN),
      .DEPTH(DEPTH)
  ) dut (
      .clk     (clk),
      .core_en (1'b1),
      .rst_n   (rst_n),
      .rx_valid(rx_valid),
      .rx_data (rx_data),
      .we      (we),
      .waddr   (waddr),
      .wdata   (wdata),
      .loading (loading)
  );

  task automatic check(input string name, input logic [XLEN-1:0] got, input logic [XLEN-1:0] exp);
    checks++;
    if (got !== exp) begin
      errors++;
      $display("FAIL DEPTH %0d %s: got %h, expected %h", DEPTH, name, got, exp);
      if (errors == max_errors) $fatal(1, "TB STOPPED: %0d mismatches", errors);
    end
  endtask  // Automatic

  task automatic do_reset();
    @(negedge clk);
    rst_n    = 1'b0;
    rx_valid = 1'b0;
    rx_data  = '0;
    repeat (2) @(posedge clk);
    @(negedge clk);
    rst_n = 1'b1;
  endtask  // Automatic

  task automatic send_byte(input logic [7:0] data);
    rx_data  = data;
    rx_valid = 1'b1;
    @(negedge clk);
    rx_valid = 1'b0;
  endtask  // Automatic

  task automatic send_word(input logic [XLEN-1:0] w);
    for (int j = 0; j < XLEN; j += $bits(rx_data)) send_byte(w[j+:$bits(rx_data)]);
  endtask  // Automatic

  // Past old cap
  task automatic build_prog(input int n);
    prog = new[n];
    prog[0] = XLEN'('hAABB_CCDD);
    for (int i = 1; i < n; i++) prog[i] = XLEN'($urandom);
    if (n > OldCap) begin
      prog[OldCap-1] = XLEN'('h1234_5678);
      prog[OldCap]   = XLEN'('h9ABC_DEF0);
    end
  endtask  // Automatic

  task automatic load_data();
    send_word(XLEN'(prog.size()));
    for (int i = 0; i < prog.size(); i++) send_word(prog[i]);
  endtask  // Automatic

  task automatic check_finished();
    repeat (2) @(posedge clk);
    check("loading", XLEN'(loading), '0);
    check("write_idx", write_idx, XLEN'(Loads));
  endtask  // Automatic

  task automatic mark_done();
    done = 1'b1;
  endtask  // Automatic

  initial void'($value$plusargs("max_errors=%d", max_errors));

  initial begin
    do_reset();

    build_prog(WORDS);
    load_data();
    check_finished();
    mark_done();
  end

  always @(posedge clk) begin
    if (we) begin
      check("waddr", waddr, write_idx * WordBytes);
      check("wdata", wdata, prog[write_idx]);
      write_idx++;
    end
  end

endmodule

`default_nettype wire
