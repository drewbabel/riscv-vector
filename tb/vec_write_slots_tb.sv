`default_nettype none

module vec_write_slots_tb ();

  localparam int DEPTH  = 4;
  localparam int DepthW = $clog2(DEPTH + 1);
  localparam int Slots  = 1 << DepthW;

  int                checks = 0;
  int                errors = 0;

  logic              clk = 1'b0;
  logic              rst_n = 1'b1;
  logic              core_en = 1'b1;
  logic              start = 1'b0;
  logic [DepthW-1:0] depth = '0;
  logic              free;

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

  logic [$bits(depth)-1:0] timer[Slots];
  logic writing[Slots];
  logic books[Slots];  // Depth above one
  int count;

  task automatic do_reset();
    rst_n = 0;
    for (int i = 0; i < $size(timer); i++) begin
      timer[i] = '0;
    end
    repeat (2) @(posedge clk);
    rst_n = 1;
  endtask  // Automatic

  task automatic check(input string name, input logic got, input logic exp);
    checks++;
    if (got !== exp) begin
      errors++;
      $error("%s: got %b, expected %b", name, got, exp);
    end
  endtask  // Automatic

  task automatic load(input logic [$bits(depth)-1:0] time_amount);
    int i;
    load_free(time_amount);
    start = free;
    do @(posedge clk); while (!core_en);
    #1;
    if (start) begin
      i = add_timer();
      check("Max timers", i >= 0, 1'b1);
      if (i >= 0) begin
        timer[i] = time_amount;
        books[i] = time_amount > 1;
      end
    end
    start = 1'b0;
  endtask  // Automatic

  task automatic load_free(input logic [$bits(depth)-1:0] time_amount);
    logic exp_free;
    depth = time_amount;
    #1;
    exp_free = 1'b1;
    for (int i = 0; i < $size(timer); i++) begin
      if (books[i] && timer[i] == time_amount + 1) exp_free = 1'b0;
    end
    check("Load free", free, exp_free);
  endtask  // Automatic

  function automatic int add_timer();
    for (int i = 0; i < $size(timer); i++) begin
      if (timer[i] == 0) return i;
    end
    return -1;
  endfunction

  task automatic idle(input int n);
    start = 1'b0;
    repeat (n) begin
      do @(posedge clk); while (!core_en);
      #1;
    end
  endtask  // Automatic

  task automatic pause(input int n);
    core_en = 1'b0;
    repeat (n) @(posedge clk);
    #1;
    core_en = 1'b1;
  endtask  // Automatic

  task automatic expect_free(input logic [$bits(depth)-1:0] d, input logic exp);
    depth = d;
    #1;
    check($sformatf("Free at depth %0d", d), free, exp);
  endtask  // Automatic

  task automatic test_example();
    load(4);
    expect_free(3, 1'b0);
    load(3);
    expect_free(3, 1'b1);
    load(3);
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
    load(4);
    do_reset();
    expect_free(1, 1'b1);
    load(1);
    idle(DEPTH);
  endtask  // Automatic

  task automatic test_core_paused();
    load(4);
    pause(3);
    expect_free(3, 1'b0);
    load(3);
    expect_free(3, 1'b1);
    idle(DEPTH);

    // Start while paused
    depth = 3;
    start = 1'b1;
    pause(2);
    start = 1'b0;
    expect_free(2, 1'b1);
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

  task automatic test_random();
    repeat (2000) begin
      case ($urandom_range(
          0, 3
      ))
        0: idle(1);
        1: pause(1);
        default: load(DepthW'($urandom_range(0, Slots - 1)));
      endcase
    end
    idle(DEPTH);
  endtask  // Automatic

  task automatic verdict();
    @(posedge clk);
    if (errors == 0) $display("PASS: %0d checks, %0d mismatches", checks, errors);
    else $fatal(1, "FAIL: %0d mismatches, %0d checks", errors, checks);
    $finish;
  endtask  // Automatic

  initial begin
    $dumpfile("vec_write_slots_tb.vcd");
    $dumpvars(0, vec_write_slots_tb);
    do_reset();

    test_example();
    test_empty_row();
    test_depth_one();
    test_reset_mid();
    test_core_paused();
    test_every_depth();
    test_random();

    verdict();
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

  always_comb begin
    for (int i = 0; i < $size(writing); i++) begin
      writing[i] = (timer[i] == 1) && rst_n;
    end
  end

  always @(posedge clk) begin
    if (rst_n && core_en) begin
      for (int i = 0; i < $size(timer); i++) begin
        if (timer[i] > 0) timer[i]--;
      end
    end
  end

endmodule

`default_nettype wire
