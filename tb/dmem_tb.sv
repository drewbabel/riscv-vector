`default_nettype none

module dmem_tb ();

  localparam int MinChecks = 1000;

  int checks;
  int errors;
  int max_errors;
  int live_errors;

  dmem_bench #(.DEPTH(16)) depth16_bench ();

  dmem_bench #(.DEPTH(64)) depth64_bench ();

  dmem_bench #(.DEPTH(256)) depth256_bench ();

  task automatic check_floor(input string name, input int got, input int floor);
    if (got < floor)
      $fatal(1, "TB UNDER-RAN: %s %0d checks, expected at least %0d", name, got, floor);
  endtask  // Automatic

  task automatic do_verdict();
    checks = depth16_bench.checks + depth64_bench.checks + depth256_bench.checks;
    errors = depth16_bench.errors + depth64_bench.errors + depth256_bench.errors;
    check_floor("depth16_bench", depth16_bench.checks, MinChecks);
    check_floor("depth64_bench", depth64_bench.checks, MinChecks);
    check_floor("depth256_bench", depth256_bench.checks, MinChecks);
    if (errors == 0) $display("PASS: %0d checks, %0d mismatches", checks, errors);
    else $fatal(1, "FAIL: %0d mismatches, %0d checks", errors, checks);
    $finish;
  endtask  // Automatic

  initial begin
    $dumpfile("dmem_tb.vcd");
    $dumpvars(0, dmem_tb);
    wait (depth16_bench.done && depth64_bench.done && depth256_bench.done);
    do_verdict();
  end

  always_comb live_errors = depth16_bench.errors + depth64_bench.errors + depth256_bench.errors;

  initial begin
    if ($value$plusargs("max_errors=%d", max_errors) && max_errors > 0) begin
      wait (live_errors >= max_errors);
      $fatal(1, "TB STOPPED: %0d mismatches", live_errors);
    end
  end

endmodule

module dmem_bench #(
    parameter int DEPTH = 64
) ();

  import cache_pkg::*;

  localparam int XLEN = arch_pkg::XLEN;
  localparam int AddrWidth = $clog2(DEPTH);

  int checks = 0;
  int errors = 0;
  int max_errors = 0;
  logic done = 1'b0;

  logic clk = 1'b0;
  logic [LineBytes-1:0] wstrb;
  logic [XLEN-1:0] addr;
  logic [LineBits-1:0] wdata;
  logic [LineBits-1:0] rdata;
  logic [XLEN-1:0] rword;

  logic [XLEN-1:0] shadow[DEPTH];

  function automatic int word_of(input logic [XLEN-1:0] a);
    return int'(a >> WordLsb) % LineWords;
  endfunction

  assign rword = rdata[word_of(addr)*XLEN+:XLEN];

  always #5 clk = ~clk;

  dmem #(
      .XLEN (XLEN),
      .DEPTH(DEPTH)
  ) dut (
      .clk  (clk),
      .wstrb(wstrb),
      .addr (addr),
      .wdata(wdata),
      .rdata(rdata)
  );

  task automatic check(input string name, input logic [XLEN-1:0] got, input logic [XLEN-1:0] exp);
    checks++;
    if (got !== exp) begin
      errors++;
      $display("FAIL %m %s: got %h, expected %h", name, got, exp);
      if (errors == max_errors) $fatal(1, "TB STOPPED: %0d mismatches", errors);
    end
  endtask  // Automatic

  task automatic do_reset();
    @(negedge clk);
    wstrb = '0;
    addr  = '0;
    wdata = '0;
    repeat (2) @(posedge clk);
    @(negedge clk);
  endtask  // Automatic

  task automatic write_bytes(input logic [XLEN-1:0] a, input logic [XLEN-1:0] data,
                             input logic [WordBytes-1:0] strb);
    addr  = a;
    wdata = {LineWords{data}};
    wstrb = LineBytes'(strb) << (WordBytes * word_of(a));
    @(negedge clk);
    wstrb = '0;
  endtask  // Automatic

  task automatic write_mem(input logic [XLEN-1:0] a, input logic [XLEN-1:0] data);
    write_bytes(a, data, '1);
  endtask  // Automatic

  task automatic write_line(input logic [XLEN-1:0] a, input logic [LineBits-1:0] data);
    addr  = a;
    wdata = data;
    wstrb = '1;
    @(negedge clk);
    wstrb = '0;
  endtask  // Automatic

  // Drive a cycle with wstrb zero, memory must not change
  task automatic write_blocked(input logic [XLEN-1:0] a, input logic [XLEN-1:0] data);
    write_bytes(a, data, '0);
  endtask  // Automatic

  task automatic check_read(input logic [XLEN-1:0] a);
    addr = a;
    @(posedge clk);
    check($sformatf("read %h", a), rword, shadow[a[AddrWidth+WordLsb-1:WordLsb]]);
    @(negedge clk);
  endtask  // Automatic

  task automatic clear_memory();
    for (int i = 0; i < DEPTH; i++) write_mem(XLEN'(i * WordBytes), '0);
  endtask  // Automatic

  task automatic test_words();
    write_mem(XLEN'('h4), XLEN'('hDEAD_BEEF));
    check_read(XLEN'('h4));
    write_mem(XLEN'('h8), XLEN'('hCAFE_F00D));
    check_read(XLEN'('h8));
    check_read(XLEN'('h4));
    write_blocked(XLEN'('h4), '1);
    check_read(XLEN'('h4));
  endtask  // Automatic

  task automatic test_line();
    write_line(XLEN'(LineBytes), line_of(XLEN'('h1111_0000)));
    for (int w = 0; w < LineWords; w++) check_read(XLEN'(LineBytes + w * WordBytes));
  endtask  // Automatic

  task automatic random_sweep(input int n);
    repeat (n) begin
      write_bytes(XLEN'($urandom_range(DEPTH - 1) * WordBytes), XLEN'($urandom),
                  WordBytes'($urandom));
      check_read(XLEN'($urandom_range(DEPTH - 1) * WordBytes));
    end
  endtask  // Automatic

  task automatic finish();
    @(negedge clk);
    done = 1'b1;
  endtask  // Automatic

  initial void'($value$plusargs("max_errors=%d", max_errors));

  initial begin
    do_reset();

    clear_memory();
    test_words();
    test_line();
    random_sweep(1000);

    finish();
  end

  function automatic logic [LineBits-1:0] line_of(input logic [XLEN-1:0] seed);
    for (int w = 0; w < LineWords; w++) line_of[w*XLEN+:XLEN] = seed + XLEN'(w);
  endfunction

  // Reference model
  always @(posedge clk) begin
    for (int b = 0; b < LineBytes; b++) begin
      if (wstrb[b]) begin
        shadow[int'(addr[AddrWidth+WordLsb-1:IdxLsb])*LineWords+b/WordBytes][8*(b%WordBytes)+:8]
            <= wdata[8*b+:8];
      end
    end
  end

endmodule

`default_nettype wire
