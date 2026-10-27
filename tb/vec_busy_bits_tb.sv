`default_nettype none

module vec_busy_bits_tb ();

  localparam int NREGS = arch_pkg::NumRegs;
  localparam int AddrW = $clog2(NREGS);
  localparam int CountW = AddrW + 1;
  localparam int MinChecks = 22000;

  int                checks = 0;
  int                errors = 0;
  int                max_errors = 0;

  logic              clk = 1'b0;
  logic              rst_n;
  logic              core_en;
  logic              start;
  logic [ AddrW-1:0] vd;
  logic [CountW-1:0] vd_regs;
  logic [ AddrW-1:0] vs1;
  logic [CountW-1:0] vs1_regs;
  logic [ AddrW-1:0] vs2;
  logic [CountW-1:0] vs2_regs;
  logic              masked;
  logic              clear;
  logic [ AddrW-1:0] clear_addr;
  logic              ready;
  logic              any;
  logic              model          [NREGS];

  always #5 clk = ~clk;

  vec_busy_bits #(
      .NREGS(NREGS)
  ) dut (
      .clk(clk),
      .rst_n(rst_n),
      .core_en(core_en),
      .start(start),
      .vd(vd),
      .vd_regs(vd_regs),
      .vs1(vs1),
      .vs1_regs(vs1_regs),
      .vs2(vs2),
      .vs2_regs(vs2_regs),
      .masked(masked),
      .clear(clear),
      .clear_addr(clear_addr),
      .ready(ready),
      .any(any)
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
    @(negedge clk);
    rst_n      = 1'b0;
    core_en    = 1'b1;
    start      = 1'b0;
    clear      = 1'b0;
    clear_addr = '0;
    operands(0, 0, 0, 0, 0, 0, 1'b0);
    for (int i = 0; i < NREGS; i++) model[i] = 1'b0;
    repeat (2) @(posedge clk);
    @(negedge clk);
    rst_n = 1'b1;
  endtask  // Automatic

  task automatic operands(input int d, input int dn, input int a, input int an, input int b,
                          input int bn, input logic m);
    vd       = AddrW'(d);
    vd_regs  = CountW'(dn);
    vs1      = AddrW'(a);
    vs1_regs = CountW'(an);
    vs2      = AddrW'(b);
    vs2_regs = CountW'(bn);
    masked   = m;
  endtask  // Automatic

  // Cycle without writes
  task automatic settle();
    start = 1'b0;
    clear = 1'b0;
    @(negedge clk);
  endtask  // Automatic

  task automatic step(input logic want_start, input logic do_clear, input int addr);
    logic started;
    settle();
    check("Ready", ready, exp_ready());
    check("Any", any, exp_any());
    started    = want_start && ready;
    start      = started;
    clear      = do_clear;
    clear_addr = AddrW'(addr);
    @(negedge clk);
    if (do_clear) model[addr] = 1'b0;
    if (started) begin
      for (int i = int'(vd); i < int'(vd) + int'(vd_regs) && i < NREGS; i++) model[i] = 1'b1;
    end
    start = 1'b0;
    clear = 1'b0;
  endtask  // Automatic

  task automatic pause(input int n, input logic s, input logic c, input int addr);
    core_en    = 1'b0;
    start      = s;
    clear      = c;
    clear_addr = AddrW'(addr);
    repeat (n) begin
      @(negedge clk);
      check("Paused any", any, exp_any());
    end
    core_en = 1'b1;
    start   = 1'b0;
    clear   = 1'b0;
  endtask  // Automatic

  task automatic expect_ready(input string name, input int d, input int dn, input int a,
                              input int an, input int b, input int bn, input logic m,
                              input logic exp);
    operands(d, dn, a, an, b, bn, m);
    settle();
    check(name, ready, exp);
  endtask  // Automatic

  task automatic expect_busy(input int r, input logic exp);
    operands(0, 0, r, 1, 0, 0, 1'b0);
    settle();
    check($sformatf("Busy v%0d", r), !ready, exp);
  endtask  // Automatic

  task automatic scan();
    for (int r = 0; r < NREGS; r++) expect_busy(r, model[r]);
  endtask  // Automatic

  task automatic issue(input int d, input int dn);
    operands(d, dn, 0, 0, 0, 0, 1'b0);
    step(1'b1, 1'b0, 0);
  endtask  // Automatic

  task automatic test_empty();
    scan();
    expect_ready("Empty ready", 8, 8, 16, 8, 24, 8, 1'b1, 1'b1);
  endtask  // Automatic

  task automatic test_group_sets();
    issue(8, 4);
    scan();
    expect_ready("Past group", 0, 0, 12, 1, 0, 0, 1'b0, 1'b1);
    expect_ready("Source overlap", 0, 0, 0, 0, 10, 2, 1'b0, 1'b0);
    expect_ready("Dest overlap", 11, 1, 0, 0, 0, 0, 1'b0, 1'b0);
    do_reset();
  endtask  // Automatic

  task automatic test_clear_one();
    issue(8, 4);
    operands(0, 0, 0, 0, 0, 0, 1'b0);
    step(1'b0, 1'b1, 8);
    scan();
    expect_ready("Cleared v8", 0, 0, 8, 1, 0, 0, 1'b0, 1'b1);
    expect_ready("Still v9", 0, 0, 9, 1, 0, 0, 1'b0, 1'b0);
    do_reset();
  endtask  // Automatic

  task automatic test_mask();
    issue(0, 1);
    expect_ready("Unmasked", 4, 1, 8, 1, 12, 1, 1'b0, 1'b1);
    expect_ready("Masked", 4, 1, 8, 1, 12, 1, 1'b1, 1'b0);
    do_reset();
  endtask  // Automatic

  task automatic test_unused();
    issue(8, 8);
    expect_ready("Zero count", 0, 1, 8, 0, 12, 0, 1'b0, 1'b1);
    do_reset();
  endtask  // Automatic

  task automatic test_top_edge();
    issue(NREGS - 8, 8);
    scan();
    do_reset();
  endtask  // Automatic

  task automatic test_clear_and_start();
    issue(8, 2);
    operands(16, 2, 0, 0, 0, 0, 1'b0);
    step(1'b1, 1'b1, 9);
    scan();
    do_reset();
  endtask  // Automatic

  task automatic test_paused();
    operands(8, 2, 0, 0, 0, 0, 1'b0);
    pause(2, 1'b1, 1'b0, 0);
    scan();
    issue(8, 2);
    pause(2, 1'b0, 1'b1, 8);
    scan();
    do_reset();
  endtask  // Automatic

  task automatic test_reset_mid();
    issue(0, 8);
    do_reset();
    scan();
  endtask  // Automatic

  task automatic test_random(input int n);
    int dn, an, bn, addr;
    logic do_clear;
    repeat (n) begin
      dn = ($urandom_range(4) == 0) ? 0 : rand_regs();
      an = ($urandom_range(3) == 0) ? 0 : rand_regs();
      bn = ($urandom_range(3) == 0) ? 0 : rand_regs();
      operands(rand_base(dn), dn, rand_base(an), an, rand_base(bn), bn, 1'($urandom));
      addr = int'(AddrW'($urandom));
      do_clear = 1'($urandom);
      case ($urandom_range(
          7
      ))
        0: pause(1, 1'($urandom), do_clear, addr);
        1: scan();
        default: step($urandom_range(3) != 0, do_clear, addr);
      endcase
    end
    scan();
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
    $dumpfile("vec_busy_bits_tb.vcd");
    $dumpvars(0, vec_busy_bits_tb);
    do_reset();

    test_empty();
    test_group_sets();
    test_clear_one();
    test_mask();
    test_unused();
    test_top_edge();
    test_clear_and_start();
    test_paused();
    test_reset_mid();
    test_random(4000);

    do_verdict();
  end

  function automatic int rand_regs();
    return 1 << $urandom_range(3);
  endfunction

  function automatic int rand_base(input int n);
    return (n == 0) ? int'(AddrW'($urandom)) : $urandom_range(NREGS / n - 1) * n;
  endfunction

  function automatic logic group_busy(input int base, input int regs);
    logic hit;
    hit = 1'b0;
    for (int i = base; i < base + regs && i < NREGS; i++) begin
      if (model[i]) hit = 1'b1;
    end
    return hit;
  endfunction

  function automatic logic exp_ready();
    return !(group_busy(int'(vd), int'(vd_regs)) || group_busy(int'(vs1), int'(vs1_regs)) ||
             group_busy(int'(vs2), int'(vs2_regs)) || (masked && model[0]));
  endfunction

  function automatic logic exp_any();
    logic hit;
    hit = 1'b0;
    for (int i = 0; i < NREGS; i++) begin
      if (model[i]) hit = 1'b1;
    end
    return hit;
  endfunction

endmodule

`default_nettype wire
