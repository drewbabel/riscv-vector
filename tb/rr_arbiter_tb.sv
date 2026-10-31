`default_nettype none

module rr_arbiter_tb ();

  localparam int MinChecksMax  = 72000;
  localparam int MinChecksSpan = 16000;

  int checks;
  int errors;
  int max_errors;
  int live_errors;

  rr_arbiter_bench #(.N(2)) n2_bench ();

  rr_arbiter_bench #(.N(3)) n3_bench ();

  rr_arbiter_bench #(.N(4)) n4_bench ();

  rr_arbiter_bench #(.N(8)) n8_bench ();

  task automatic check_floor(input string name, input int got, input int floor);
    if (got < floor)
      $fatal(1, "TB UNDER-RAN: %s %0d checks, expected at least %0d", name, got, floor);
  endtask  // Automatic

  function automatic int min_checks(input int n);
    return MinChecksMax - MinChecksSpan / n;
  endfunction

  task automatic do_verdict();
    checks = n2_bench.checks + n3_bench.checks + n4_bench.checks + n8_bench.checks;
    errors = n2_bench.errors + n3_bench.errors + n4_bench.errors + n8_bench.errors;
    check_floor("n2_bench", n2_bench.checks, min_checks(2));
    check_floor("n3_bench", n3_bench.checks, min_checks(3));
    check_floor("n4_bench", n4_bench.checks, min_checks(4));
    check_floor("n8_bench", n8_bench.checks, min_checks(8));
    if (errors == 0) $display("PASS: %0d checks, %0d mismatches", checks, errors);
    else $fatal(1, "FAIL: %0d mismatches, %0d checks", errors, checks);
    $finish;
  endtask  // Automatic

  initial begin
    $dumpfile("tb.vcd");
    $dumpvars(0, rr_arbiter_tb);
    wait (n2_bench.done && n3_bench.done && n4_bench.done && n8_bench.done);
    do_verdict();
  end

  always_comb live_errors = n2_bench.errors + n3_bench.errors + n4_bench.errors + n8_bench.errors;

  initial begin
    if ($value$plusargs("max_errors=%d", max_errors) && max_errors > 0) begin
      wait (live_errors >= max_errors);
      $fatal(1, "TB STOPPED: %0d mismatches", live_errors);
    end
  end

endmodule

module rr_arbiter_bench #(
    parameter int N = 4
) ();

  localparam int TimeoutCycles = 20_000_000;

  int checks = 0;
  int errors = 0;
  int max_errors = 0;
  logic done = 1'b0;

  logic clk = 1'b0;
  logic rst_n = 1'b1;
  logic core_en = 1'b1;
  logic [N-1:0] req = '0;
  logic hold = 1'b0;
  logic [N-1:0] grant;
  logic grant_valid;

  int exp_last_idx;
  logic exp_holding;
  logic [N-1:0] exp_held_grant;
  logic [N-1:0] exp_grant;

  always #5 clk = !clk;

  rr_arbiter #(
      .N(N)
  ) dut (
      .clk(clk),
      .rst_n(rst_n),
      .core_en(core_en),
      .req(req),
      .hold(hold),
      .grant(grant),
      .grant_valid(grant_valid)
  );

  task automatic check(input string name, input logic [N-1:0] got, input logic [N-1:0] exp);
    checks++;
    if (got !== exp) begin
      errors++;
      $display("FAIL %m %s: got %h, expected %h", name, got, exp);
      if (errors == max_errors) $fatal(1, "TB STOPPED: %0d mismatches", errors);
    end
  endtask  // Automatic

  task automatic do_reset();
    rst_n = 1'b0;
    req   = '0;
    hold  = 1'b0;
    @(posedge clk);
    @(negedge clk);
    rst_n = 1'b1;
  endtask  // Automatic

  task automatic watchdog(input int cycles);
    repeat (cycles) @(posedge clk);
    $fatal(1, "TIMEOUT: sim exceeded max time");
  endtask  // Automatic

  // First set bit at or after start, wrapping (returns -1 when none)
  function automatic int first_set_idx(input logic [N-1:0] in, input int start);
    for (int i = start; i < (start + N); i++) if (in[i%N]) return i % N;
    return -1;
  endfunction

  function automatic logic [N-1:0] idx_to_onehot(input int in);
    logic [N-1:0] out;
    for (int i = 0; i < N; i++) out[i] = (i == in);
    return out;
  endfunction

  // Sticky burst requests
  task automatic drive(input logic [N-1:0] req_in, input logic hold_in, input int burst);
    @(negedge clk);
    req  = req_in;
    hold = hold_in;
    if (hold_in) begin
      repeat (burst) @(negedge clk);
      hold = 1'b0;
    end
  endtask  // Automatic

  task automatic directed();
    drive(N'('b0001), 1'b0, 1);
    drive(N'('b0000), 1'b0, 1);
    drive(N'('b0011), 1'b0, 1);
  endtask  // Automatic

  task automatic full_range(input int passes);
    repeat (passes) begin
      for (int j = 0; j < (1 << N); j++) drive(N'(j), 1'($urandom), $urandom_range(4, 2));
    end
  endtask  // Automatic

  task automatic random_sweep(input int n);
    repeat (n) drive(N'($urandom), 1'($urandom), $urandom_range(4, 2));
  endtask  // Automatic

  task automatic finish();
    @(posedge clk);
    done = 1'b1;
  endtask  // Automatic

  initial void'($value$plusargs("max_errors=%d", max_errors));

  initial watchdog(TimeoutCycles);

  initial begin
    do_reset();
    directed();
    full_range(N);
    random_sweep(5000);
    finish();
  end

  // Reference model

  always_comb begin
    if (exp_holding) exp_grant = exp_held_grant;
    else exp_grant = idx_to_onehot(first_set_idx(req, (exp_last_idx + 1) % N));
  end

  always @(posedge clk) begin
    if (!rst_n) begin
      exp_holding  <= 1'b0;
      exp_last_idx <= N - 1;  // Next turn: (exp_last_idx + 1) % N = 0
    end else if (|exp_grant) begin
      exp_last_idx <= first_set_idx(exp_grant, 0);
      exp_holding  <= hold;
      if (!exp_holding) exp_held_grant <= exp_grant;
    end
  end

  // Compare against DUT
  always @(posedge clk) if (rst_n) check("grant", grant, exp_grant);

  // grant_valid and grant agree
  always @(posedge clk) begin
    if (rst_n) check("grant_valid agreement", N'(grant_valid), N'(|grant));
  end

  // grant only includes bits in req
  always @(posedge clk) begin
    if (rst_n) begin
      for (int i = 0; i < $bits(grant); i++) begin
        if (grant[i]) check($sformatf("grant/req bit %0d", i), N'(grant[i]), N'(req[i]));
      end
    end
  end

  // grant is one-hot
  always @(posedge clk) begin
    if (rst_n && grant != '0) check("grant one-hot", N'($onehot(grant)), N'(1));
  end

endmodule

`default_nettype wire
