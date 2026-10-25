`default_nettype none

module vec_write_slots_tb ();

  localparam int MinChecks = 7500;

  int checks = 0;
  int errors = 0;
  int max_errors = 0;

  vec_write_slots_bench #(.DEPTH(2)) depth2_bench ();

  vec_write_slots_bench #(.DEPTH(4)) depth4_bench ();

  vec_write_slots_bench #(.DEPTH(5)) depth5_bench ();

  vec_write_slots_bench #(.DEPTH(8)) depth8_bench ();

  task automatic do_verdict();
    checks = depth2_bench.checks + depth4_bench.checks + depth5_bench.checks + depth8_bench.checks;
    errors = depth2_bench.errors + depth4_bench.errors + depth5_bench.errors + depth8_bench.errors;
    if (depth2_bench.checks < MinChecks || depth4_bench.checks < MinChecks ||
        depth5_bench.checks < MinChecks || depth8_bench.checks < MinChecks)
      $fatal(
          1,
          "TB UNDER-RAN: %0d, %0d, %0d and %0d checks, expected at least %0d each",
          depth2_bench.checks,
          depth4_bench.checks,
          depth5_bench.checks,
          depth8_bench.checks,
          MinChecks
      );
    if (errors == 0) $display("PASS: %0d checks, %0d mismatches", checks, errors);
    else $fatal(1, "FAIL: %0d mismatches, %0d checks", errors, checks);
    $finish;
  endtask  // Automatic

  initial begin
    $dumpfile("vec_write_slots_tb.vcd");
    $dumpvars(0, vec_write_slots_tb);
    wait (depth2_bench.done && depth4_bench.done && depth5_bench.done && depth8_bench.done);
    do_verdict();
  end

  initial begin
    if ($value$plusargs("max_errors=%d", max_errors) && max_errors > 0) begin
      wait (depth2_bench.errors + depth4_bench.errors + depth5_bench.errors + depth8_bench.errors >=
            max_errors);
      $fatal(1, "TB STOPPED: %0d mismatches",
             depth2_bench.errors + depth4_bench.errors + depth5_bench.errors + depth8_bench.errors);
    end
  end

endmodule

module vec_write_slots_bench #(
    parameter int DEPTH = 4
) ();

  localparam int DepthW = $clog2(DEPTH + 1);
  localparam int Slots  = 1 << DepthW;

  int                checks = 0;
  int                errors = 0;
  logic              done = 1'b0;
  int                count;

  logic              clk = 1'b0;
  logic              rst_n;
  logic              core_en;
  logic              start;
  logic [DepthW-1:0] depth;
  logic              free;

  logic [DepthW-1:0] timer       [Slots];
  logic              writing     [Slots];
  logic              books       [Slots];  // Depth above one

  always #5 clk = ~clk;

  vec_write_slots #(
      .DEPTH(DEPTH)
  ) dut (
      .clk(clk),
      .rst_n(rst_n),
      .core_en(core_en),
      .start(start),
      .depth(depth),
      .free(free)
  );

  task automatic check(input string name, input logic got, input logic exp);
    checks++;
    if (got !== exp) begin
      errors++;
      $display("FAIL DEPTH %0d %s: got %h, expected %h", DEPTH, name, got, exp);
    end
  endtask  // Automatic

  task automatic do_reset();
    rst_n   = 1'b0;
    core_en = 1'b1;
    start   = 1'b0;
    depth   = '0;
    for (int i = 0; i < $size(timer); i++) begin
      timer[i] = '0;
      books[i] = 1'b0;
    end
    repeat (2) @(posedge clk);
    @(negedge clk);
    rst_n = 1'b1;
  endtask  // Automatic

  task automatic tick(input logic [DepthW-1:0] d, input logic want_start);
    logic exp_free;
    depth = d;
    exp_free = model_free(d);
    start = want_start && exp_free;
    @(posedge clk);
    check($sformatf("Free at depth %0d", d), free, exp_free);
    if (core_en) begin
      advance();
      if (start) book(d);
    end
    @(negedge clk);
    start = 1'b0;
  endtask  // Automatic

  task automatic load(input logic [DepthW-1:0] time_amount);
    tick(time_amount, 1'b1);
  endtask  // Automatic

  // State frozen
  task automatic probe(input logic [DepthW-1:0] d, input logic exp);
    logic keep_en;
    keep_en = core_en;
    core_en = 1'b0;
    depth   = d;
    @(posedge clk);
    check($sformatf("Probe free at depth %0d", d), free, exp);
    @(negedge clk);
    core_en = keep_en;
  endtask  // Automatic

  task automatic load_free(input logic [DepthW-1:0] d);
    probe(d, model_free(d));
  endtask  // Automatic

  task automatic expect_free(input logic [DepthW-1:0] d, input logic exp);
    probe(d, exp);
  endtask  // Automatic

  task automatic idle(input int n);
    repeat (n) tick(depth, 1'b0);
  endtask  // Automatic

  task automatic pause(input int n);
    core_en = 1'b0;
    repeat (n) begin
      @(posedge clk);
      check("Paused free", free, model_free(depth));
      @(negedge clk);
    end
    core_en = 1'b1;
  endtask  // Automatic

  task automatic pause_start(input logic [DepthW-1:0] d, input int n);
    depth = d;
    start = 1'b1;
    pause(n);
    start = 1'b0;
  endtask  // Automatic

  task automatic test_example();
    load(DepthW'(DEPTH));
    expect_free(DepthW'(DEPTH - 1), 1'b0);
    load(DepthW'(DEPTH - 1));
    expect_free(DepthW'(DEPTH - 1), 1'b1);
    load(DepthW'(DEPTH - 1));
    idle(DEPTH);
  endtask  // Automatic

  task automatic test_empty_row();
    for (int d = 1; d <= DEPTH; d++) begin
      expect_free(DepthW'(d), 1'b1);
      load(DepthW'(d));
      idle(DEPTH);
    end
  endtask  // Automatic

  task automatic test_depth_one();
    repeat (8) begin
      expect_free(1, 1'b1);
      load(1);
    end
    load(2);
    expect_free(1, 1'b0);
    load(1);
    idle(DEPTH);
  endtask  // Automatic

  task automatic test_reset_mid();
    load(DepthW'(DEPTH));
    do_reset();
    expect_free(1, 1'b1);
    load(1);
    idle(DEPTH);
  endtask  // Automatic

  task automatic test_core_paused();
    load(DepthW'(DEPTH));
    pause(3);
    expect_free(DepthW'(DEPTH - 1), 1'b0);
    load(DepthW'(DEPTH - 1));
    expect_free(DepthW'(DEPTH - 1), 1'b1);
    idle(DEPTH);

    // Start while paused
    pause_start(DepthW'(DEPTH - 1), 2);
    expect_free(DepthW'(DEPTH - 2), 1'b1);
    idle(DEPTH);
  endtask  // Automatic

  task automatic test_every_depth();
    for (int d = 0; d < Slots; d++) begin
      expect_free(DepthW'(d), 1'b1);
      load(DepthW'(d));
      repeat (Slots) begin
        for (int p = 0; p < Slots; p++) load_free(DepthW'(p));
        idle(1);
      end
    end

    // Every depth pair
    for (int a = 0; a < Slots; a++) begin
      for (int b = 0; b < Slots; b++) begin
        load(DepthW'(a));
        load(DepthW'(b));
        idle(Slots);
      end
    end
  endtask  // Automatic

  task automatic test_random(input int n);
    repeat (n) begin
      case ($urandom_range(
          3
      ))
        0: idle(1);
        1: pause(1);
        default: load(DepthW'($urandom));
      endcase
    end
    idle(DEPTH);
  endtask  // Automatic

  task automatic finish();
    @(posedge clk);
    done = 1'b1;
  endtask  // Automatic

  initial begin
    do_reset();

    test_example();
    test_empty_row();
    test_depth_one();
    test_reset_mid();
    test_core_paused();
    test_every_depth();
    test_random(2000);

    finish();
  end

  function automatic int add_timer();
    for (int i = 0; i < $size(timer); i++) begin
      if (timer[i] == 0) return i;
    end
    return -1;
  endfunction

  function automatic logic model_free(input logic [DepthW-1:0] d);
    for (int i = 0; i < $size(timer); i++) begin
      if (books[i] && timer[i] == d + 1) return 1'b0;
    end
    return 1'b1;
  endfunction

  task automatic advance();
    for (int i = 0; i < $size(timer); i++) begin
      if (timer[i] > 0) timer[i]--;
    end
  endtask  // Automatic

  task automatic book(input logic [DepthW-1:0] time_amount);
    int i;
    i = add_timer();
    check("Max timers", i >= 0, 1'b1);
    if (i >= 0) begin
      timer[i] = time_amount;
      books[i] = time_amount > 1;
    end
  endtask  // Automatic

  always_comb begin
    for (int i = 0; i < $size(writing); i++) begin
      writing[i] = (timer[i] == 1) && rst_n;
    end
  end

  // No concurrent writes
  always @(negedge clk) begin
    if (rst_n) begin
      count = 0;
      for (int i = 0; i < $size(writing); i++) begin
        if (writing[i]) count++;
      end
      check("Concurrent writes", count <= 1, 1'b1);
    end
  end

endmodule

`default_nettype wire
