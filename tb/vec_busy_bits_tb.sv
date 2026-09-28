`default_nettype none

module vec_busy_bits_tb ();

  localparam int NREGS  = 32;
  localparam int AddrW  = $clog2(NREGS);
  localparam int CountW = AddrW + 1;

  int                checks = 0;
  int                errors = 0;

  logic              clk = 1'b0;
  logic              rst_n = 1'b1;
  logic              core_en = 1'b1;
  logic              start = 1'b0;
  logic [ AddrW-1:0] vd = '0;
  logic [CountW-1:0] vd_regs = '0;
  logic [ AddrW-1:0] vs1 = '0;
  logic [CountW-1:0] vs1_regs = '0;
  logic [ AddrW-1:0] vs2 = '0;
  logic [CountW-1:0] vs2_regs = '0;
  logic              masked = 1'b0;
  logic              clear = 1'b0;
  logic [ AddrW-1:0] clear_addr = '0;
  logic              ready;

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
      .ready(ready)
  );

  // Reference model
  logic model[NREGS];

  task automatic check(input string name, input logic got, input logic exp);
    checks++;
    if (got !== exp) begin
      errors++;
      $error("%s: got %b, expected %b", name, got, exp);
    end
  endtask  // Automatic

  task automatic do_reset();
    rst_n = 0;
    for (int i = 0; i < NREGS; i++) model[i] = 1'b0;
    repeat (2) @(posedge clk);
    #1;
    rst_n = 1;
  endtask  // Automatic

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

  task automatic operands(input int d, input int dn, input int a, input int an, input int b,
                          input int bn, input logic m);
    vd = AddrW'(d);
    vd_regs = CountW'(dn);
    vs1 = AddrW'(a);
    vs1_regs = CountW'(an);
    vs2 = AddrW'(b);
    vs2_regs = CountW'(bn);
    masked = m;
  endtask  // Automatic

  task automatic step(input logic want_start, input logic do_clear, input int addr);
    logic started;
    clear = do_clear;
    clear_addr = AddrW'(addr);
    #1;
    check("Ready", ready, exp_ready());
    started = want_start && ready;
    start   = started;
    do @(posedge clk); while (!core_en);
    #1;
    if (do_clear) model[addr] = 1'b0;
    if (started) begin
      for (int i = int'(vd); i < int'(vd) + int'(vd_regs) && i < NREGS; i++) model[i] = 1'b1;
    end
    start = 1'b0;
    clear = 1'b0;
  endtask  // Automatic

  task automatic expect_busy(input int r, input logic exp);
    operands(0, 0, r, 1, 0, 0, 1'b0);
    #1;
    check($sformatf("Busy v%0d", r), !ready, exp);
  endtask  // Automatic

  task automatic scan();
    for (int r = 0; r < NREGS; r++) expect_busy(r, model[r]);
  endtask  // Automatic

  task automatic pause(input int n);
    core_en = 1'b0;
    repeat (n) @(posedge clk);
    #1;
    core_en = 1'b1;
  endtask  // Automatic

  task automatic test_empty();
    scan();
    operands(8, 8, 16, 8, 24, 8, 1'b1);
    #1;
    check("Empty ready", ready, 1'b1);
  endtask  // Automatic

  task automatic test_group_sets();
    operands(8, 4, 0, 0, 0, 0, 1'b0);
    step(1'b1, 1'b0, 0);
    scan();
    operands(0, 0, 12, 1, 0, 0, 1'b0);
    #1;
    check("Past group", ready, 1'b1);
    operands(0, 0, 0, 0, 10, 2, 1'b0);
    #1;
    check("Source overlap", ready, 1'b0);
    operands(11, 1, 0, 0, 0, 0, 1'b0);
    #1;
    check("Dest overlap", ready, 1'b0);
    do_reset();
  endtask  // Automatic

  task automatic test_clear_one();
    operands(8, 4, 0, 0, 0, 0, 1'b0);
    step(1'b1, 1'b0, 0);
    operands(0, 0, 0, 0, 0, 0, 1'b0);
    step(1'b0, 1'b1, 8);
    scan();
    operands(0, 0, 8, 1, 0, 0, 1'b0);
    #1;
    check("Cleared v8", ready, 1'b1);
    operands(0, 0, 9, 1, 0, 0, 1'b0);
    #1;
    check("Still v9", ready, 1'b0);
    do_reset();
  endtask  // Automatic

  task automatic test_mask();
    operands(0, 1, 0, 0, 0, 0, 1'b0);
    step(1'b1, 1'b0, 0);
    operands(4, 1, 8, 1, 12, 1, 1'b0);
    #1;
    check("Unmasked", ready, 1'b1);
    masked = 1'b1;
    #1;
    check("Masked", ready, 1'b0);
    do_reset();
  endtask  // Automatic

  task automatic test_unused();
    operands(8, 8, 0, 0, 0, 0, 1'b0);
    step(1'b1, 1'b0, 0);
    operands(0, 1, 8, 0, 12, 0, 1'b0);
    #1;
    check("Zero count", ready, 1'b1);
    do_reset();
  endtask  // Automatic

  task automatic test_top_edge();
    operands(24, 8, 0, 0, 0, 0, 1'b0);
    step(1'b1, 1'b0, 0);
    scan();
    do_reset();
  endtask  // Automatic

  task automatic test_clear_and_start();
    operands(8, 2, 0, 0, 0, 0, 1'b0);
    step(1'b1, 1'b0, 0);
    operands(16, 2, 0, 0, 0, 0, 1'b0);
    step(1'b1, 1'b1, 9);
    scan();
    do_reset();
  endtask  // Automatic

  task automatic test_paused();
    operands(8, 2, 0, 0, 0, 0, 1'b0);
    start = 1'b1;
    clear = 1'b0;
    pause(2);
    start = 1'b0;
    scan();
    operands(8, 2, 0, 0, 0, 0, 1'b0);
    step(1'b1, 1'b0, 0);
    clear = 1'b1;
    clear_addr = AddrW'(8);
    pause(2);
    clear = 1'b0;
    scan();
    do_reset();
  endtask  // Automatic

  task automatic test_reset_mid();
    operands(0, 8, 0, 0, 0, 0, 1'b0);
    step(1'b1, 1'b0, 0);
    do_reset();
    scan();
  endtask  // Automatic

  function automatic int rand_regs();
    return 1 << $urandom_range(0, 3);
  endfunction

  function automatic int rand_base(input int n);
    return (n == 0) ? $urandom_range(0, NREGS - 1) : $urandom_range(0, NREGS / n - 1) * n;
  endfunction

  task automatic test_random();
    int dn, an, bn, addr;
    logic do_clear;
    int   pick;
    repeat (4000) begin
      dn = ($urandom_range(0, 4) == 0) ? 0 : rand_regs();
      an = ($urandom_range(0, 3) == 0) ? 0 : rand_regs();
      bn = ($urandom_range(0, 3) == 0) ? 0 : rand_regs();
      operands(rand_base(dn), dn, rand_base(an), an, rand_base(bn), bn, 1'($urandom_range(0, 1)));
      addr = $urandom_range(0, NREGS - 1);
      do_clear = 1'($urandom_range(0, 1));
      pick = $urandom_range(0, 7);
      case (pick)
        0: pause(1);
        1: scan();
        default: step(1'($urandom_range(0, 3) != 0), do_clear, addr);
      endcase
    end
    scan();
  endtask  // Automatic

  task automatic verdict();
    @(posedge clk);
    if (errors == 0) $display("PASS: %0d checks, %0d mismatches", checks, errors);
    else $fatal(1, "FAIL: %0d mismatches, %0d checks", errors, checks);
    $finish;
  endtask  // Automatic

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
    test_random();

    verdict();
  end

endmodule

`default_nettype wire
