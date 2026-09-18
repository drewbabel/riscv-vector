`default_nettype none

module rr_arbiter_tb ();

  int checks = 0;
  int errors = 0;

  localparam int N = 4;

  logic clk = 1'b0;
  logic rst_n = 1'b1;
  logic [N-1:0] req = '0;
  logic hold = 1'b0;
  logic [N-1:0] grant;
  logic grant_valid;

  always #5 clk = !clk;

  int exp_last_idx;
  logic exp_holding;
  logic [N-1:0] exp_held_grant;
  logic [N-1:0] exp_grant;

  logic core_en = 1'b1;

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

  task automatic do_reset();
    rst_n = 1'b0;
    req   = '0;
    hold  = 1'b0;
    @(posedge clk);
    #1 rst_n = 1'b1;
    @(posedge clk);
  endtask  // Automatic

  task automatic do_verdict();
    @(posedge clk);
    if (errors == 0) begin
      $display("PASS: %0d checks, %0d mismatches", checks, errors);
    end else begin
      $fatal(1, "FAIL: %0d mismatches, %0d checks", errors, checks);
    end
    $finish;
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

  task automatic check_int(input string name, input int got, input int exp);
    checks++;
    if (got !== exp) begin
      errors++;
      $error("t=%0t %s mismatch: got=%0d exp=%0d", $time, name, got, exp);
    end
  endtask  // Automatic

  task automatic check_bit(input string name, input logic got, input logic exp);
    checks++;
    if (got !== exp) begin
      errors++;
      $error("t=%0t %s mismatch: got=%b exp=%b", $time, name, got, exp);
    end
  endtask  // Automatic

  task automatic check(input string name, input logic [N-1:0] got, input logic [N-1:0] exp);
    checks++;
    if (got !== exp) begin
      errors++;
      $error("t=%0t %s mismatch: got=%b exp=%b", $time, name, got, exp);
    end
  endtask  // Automatic

  // Requesters keep req asserted for entire burst, per AXI-Stream
  task automatic drive(input logic [N-1:0] req_in, input logic hold_in, input int burst);
    #1 req = req_in;
    hold = hold_in;
    @(posedge clk);
    if (hold_in) begin
      repeat (burst - 1) @(posedge clk);
      #1 hold = 1'b0;
      @(posedge clk);
    end
  endtask  // Automatic

  initial begin
    $dumpfile("tb.vcd");
    $dumpvars(0, rr_arbiter_tb);
    do_reset();

    // Directed cases
    drive(4'b0001, 1'b0, 1);  // Bit 0 wins, rotation now points at bit 1
    drive(4'b0000, 1'b0, 1);  // Idle
    drive(4'b0011, 1'b0, 1);  // Correct: bit 1, lowest-bit: bit 0

    // Full input range
    for (int i = 0; i < 4; i++) begin
      for (int j = 0; j < (1 << N); j++) begin
        drive(j[N-1:0], 1'($urandom), 2 + ($urandom % 3));
      end
    end

    // Random sweep
    for (int i = 0; i < 5000; i++) begin
      drive((N)'($urandom), 1'($urandom), 2 + ($urandom % 3));
    end

    do_verdict();
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
  always @(negedge clk) if (rst_n) check("grant", grant, exp_grant);

  // grant_valid and grant agree
  always @(negedge clk) begin
    if (rst_n) check_bit("grant_valid agreement", grant_valid, |grant);
  end

  // grant only includes bits in req
  always @(negedge clk) begin
    if (rst_n) begin
      for (int i = 0; i < $bits(grant); i++) begin
        if (grant[i]) check_bit($sformatf("grant/req bit %0d", i), grant[i], req[i]);
      end
    end
  end

  // grant is one-hot
  always @(negedge clk) begin
    if (rst_n) begin
      int cnt;
      cnt = 0;
      for (int i = 0; i < $bits(grant); i++) begin
        if (grant[i]) cnt++;
      end
      if (cnt !== 0) check_int("grant one-hot", cnt, 1);
    end
  end

  // Watchdog
  initial begin
    #200_000_000 $fatal(1, "TIMEOUT: sim exceeded max time");
  end

endmodule

`default_nettype wire
