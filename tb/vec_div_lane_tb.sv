`default_nettype none

module vec_div_lane_tb
  import vec_pkg::*;
();

  localparam int ELEN = arch_pkg::ELEN;
  localparam int Timeout = 2000000;

  int                 checks = 0;
  int                 errors = 0;
  int                 max_errors = 0;
  int                 latency_checks = 0;
  bit                 latency_active = 1'b0;
  int                 enabled_cycles = 0;
  int                 target_cycles = 0;
  int                 accepted_width = 0;
  vec_op_e            accepted_op = VEC_DIVU;

  logic               clk = 1'b0;
  logic               rst_n = 1'b0;
  logic               core_en = 1'b1;
  logic               start = 1'b0;
  vec_op_e            op = VEC_DIVU;
  logic    [     2:0] vsew = 3'd0;
  logic    [ELEN-1:0] a = '0;
  logic    [ELEN-1:0] b = '0;
  logic    [ELEN-1:0] result;
  logic               busy;
  logic               done;

  int                 stall_pct = 0;
  logic               manual_stalls = 1'b0;

  always #5 clk = ~clk;

  vec_div_lane #(
      .ELEN(ELEN)
  ) dut (
      .clk(clk),
      .rst_n(rst_n),
      .core_en(core_en),
      .start(start),
      .op(op),
      .vsew(vsew),
      .a(a),
      .b(b),
      .result(result),
      .busy(busy),
      .done(done)
  );

  vec_op_e ops[4];

  initial begin
    ops[0] = VEC_DIVU;
    ops[1] = VEC_DIV;
    ops[2] = VEC_REMU;
    ops[3] = VEC_REM;
  end

  // Random stalls
  always @(negedge clk) if (!manual_stalls) core_en <= ($urandom_range(99) >= stall_pct);

  // Handshake rule
  always @(posedge clk)
    if (rst_n && busy && done) begin
      errors++;
      $display("FAIL busy and done both high at %0t", $time);
      if (errors == max_errors) $fatal(1, "TB STOPPED: %0d mismatches", errors);
    end

  // Width helpers
  function automatic longint umask(input int w);
    umask = (64'sd1 <<< w) - 64'sd1;
  endfunction

  function automatic longint uval(input logic [ELEN-1:0] x, input int w);
    uval = longint'({{(64 - ELEN) {1'b0}}, x}) & umask(w);
  endfunction

  function automatic longint sval(input logic [ELEN-1:0] x, input int w);
    longint u;
    u    = uval(x, w);
    sval = u[w-1] ? (u - (64'sd1 <<< w)) : u;
  endfunction

  // Reference model
  function automatic logic [ELEN-1:0] ref_lane(input vec_op_e o, input int w,
                                               input logic [ELEN-1:0] x, input logic [ELEN-1:0] y);
    longint ux;
    longint uy;
    longint sx;
    longint sy;
    longint smin;
    longint t;
    ux   = uval(x, w);
    uy   = uval(y, w);
    sx   = sval(x, w);
    sy   = sval(y, w);
    smin = -(64'sd1 <<< (w - 1));
    case (o)
      VEC_DIVU: t = (uy == 0) ? umask(w) : ux / uy;
      VEC_REMU: t = (uy == 0) ? ux : ux % uy;
      VEC_DIV:  t = (sy == 0) ? -1 : (sx == smin && sy == -1) ? sx : sx / sy;
      default:  t = (sy == 0) ? sx : (sx == smin && sy == -1) ? 0 : sx % sy;
    endcase
    ref_lane = ELEN'(t & umask(w));
  endfunction

  // Enabled edges after start acceptance: one per bit, then completion.
  function automatic int expected_latency(input vec_op_e o, input int w, input logic [ELEN-1:0] x,
                                          input logic [ELEN-1:0] y);
    if (uval(y, w) == 0) expected_latency = 1;
    else if (((o == VEC_DIV) || (o == VEC_REM)) && (sval(
            x, w
        ) == -(64'sd1 <<< (w - 1))) && (sval(
            y, w
        ) == -1))
      expected_latency = 1;
    else expected_latency = w + 1;
  endfunction

  // Observe only the interface; count core_en before the edge and done after NBA.
  // This checks all operations, including random stalls, and discards reset aborts.
  always @(posedge clk) begin
    if (!rst_n) begin
      latency_active = 1'b0;
    end else if (core_en) begin
      if (start && !busy && !done) begin
        latency_active = 1'b1;
        enabled_cycles = 0;
        accepted_width = 8 << vsew;
        accepted_op    = op;
        target_cycles  = expected_latency(op, accepted_width, a, b);
      end else if (latency_active) begin
        enabled_cycles++;
      end
    end
    #1;
    if (latency_active && done) begin
      checks++;
      latency_checks++;
      if (enabled_cycles != target_cycles) begin
        errors++;
        $display("FAIL %s sew=%0d enabled cycles=%0d exp=%0d", accepted_op.name(), accepted_width,
                 enabled_cycles, target_cycles);
        if (errors == max_errors) $fatal(1, "TB STOPPED: %0d mismatches", errors);
      end
      latency_active = 1'b0;
    end
  end

  // Junk above the element
  function automatic logic [ELEN-1:0] junk(input logic [ELEN-1:0] x, input int w);
    logic [ELEN-1:0] keep;
    keep = ELEN'(umask(w));
    junk = (x & keep) | (ELEN'($urandom) & ~keep);
  endfunction

  // Raise start until an enabled edge takes it
  task automatic launch(input vec_op_e o, input logic [2:0] sew, input logic [ELEN-1:0] x,
                        input logic [ELEN-1:0] y);
    logic taken;
    @(negedge clk);
    // The lane only takes start in IDLE (same rule as datapath.sv: !busy && !done)
    while (busy || done) @(negedge clk);
    op    = o;
    vsew  = sew;
    a     = x;
    b     = y;
    start = 1'b1;
    do begin
      @(posedge clk);
      taken = core_en;
      @(negedge clk);
    end while (!taken);
    start = 1'b0;
    // Scramble inputs: the lane must not depend on them after start
    op    = (o == VEC_DIVU) ? VEC_REM : VEC_DIVU;
    vsew  = 3'($urandom);
    a     = ELEN'($urandom);
    b     = ELEN'($urandom);
  endtask

  // One divide
  task automatic check(input vec_op_e o, input logic [2:0] sew, input logic [ELEN-1:0] x,
                       input logic [ELEN-1:0] y);
    logic [ELEN-1:0] exp_res;
    exp_res = ref_lane(o, 8 << sew, x, y);
    launch(o, sew, x, y);
    if (stall_pct == 0 && busy !== 1'b1) begin
      errors++;
      $display("FAIL %s sew=%0d busy not high after start", o.name(), 8 << sew);
      if (errors == max_errors) $fatal(1, "TB STOPPED: %0d mismatches", errors);
    end
    while (done !== 1'b1) @(negedge clk);
    checks++;
    if (result !== exp_res) begin
      errors++;
      if (errors <= 10)
        $display(
            "FAIL %s sew=%0d a=%h b=%h got %h exp %h", o.name(), 8 << sew, x, y, result, exp_res
        );
      if (errors == max_errors) $fatal(1, "TB STOPPED: %0d mismatches", errors);
    end
    // done pulses one enabled cycle, result holds
    if (stall_pct == 0) begin
      @(negedge clk);
      if (done !== 1'b0 || result !== exp_res) begin
        errors++;
        $display("FAIL %s sew=%0d done not a pulse or result not held", o.name(), 8 << sew);
        if (errors == max_errors) $fatal(1, "TB STOPPED: %0d mismatches", errors);
      end
    end
  endtask


  // Named corner cases also check their one-enabled-cycle completion.
  task automatic check_timed(input string label, input vec_op_e o, input logic [2:0] sew,
                             input logic [ELEN-1:0] x, input logic [ELEN-1:0] y,
                             input int expected_cycles);
    int              cycles;
    logic [ELEN-1:0] exp_res;
    exp_res = ref_lane(o, 8 << sew, x, y);
    launch(o, sew, x, y);
    cycles = 0;
    while (done !== 1'b1) begin
      @(negedge clk);
      cycles++;
    end
    checks++;
    if (result !== exp_res || cycles != expected_cycles) begin
      errors++;
      $display("FAIL %s %s sew=%0d: result=%h exp=%h cycles=%0d exp=%0d", label, o.name(),
               8 << sew, result, exp_res, cycles, expected_cycles);
      if (errors == max_errors) $fatal(1, "TB STOPPED: %0d mismatches", errors);
    end
  endtask

  task automatic special_cases(input logic [2:0] sew);
    int              w;
    logic [ELEN-1:0] smin;
    logic [ELEN-1:0] minus_one;
    w         = 8 << sew;
    smin      = ELEN'(1) << (w - 1);
    minus_one = ELEN'(umask(w));
    $display("Checking division by zero and signed overflow at SEW=%0d", w);
    for (int k = 0; k < $size(ops); k++)
      check_timed("division by zero", ops[k], sew, junk(smin | ELEN'(13), w), junk('0, w), 1);
    check_timed("signed DIV overflow", VEC_DIV, sew, junk(smin, w), junk(minus_one, w), 1);
    check_timed("signed REM overflow", VEC_REM, sew, junk(smin, w), junk(minus_one, w), 1);
  endtask

  task automatic measure_cycles(input logic [2:0] sew);
    int cycles;

    // Use an ordinary unsigned division
    launch(VEC_DIVU, sew, 32'd13, 32'd3);

    cycles = 0;
    while (done !== 1'b1) begin
      @(negedge clk);
      cycles++;
    end

    $display("SEW=%0d: %0d cycles, result=%0d", 8 << sew, cycles, result);

    checks++;
    if (result !== 32'd4 || cycles != (8 << sew) + 1) begin
      errors++;
      $display("FAIL: expected quotient 4 and %0d cycles", (8 << sew) + 1);
      if (errors == max_errors) $fatal(1, "TB STOPPED: %0d mismatches", errors);
    end
  endtask


  // Edge values
  function automatic logic [ELEN-1:0] edge_val(input int idx, input int w);
    longint m;
    m = umask(w);
    case (idx)
      0: edge_val = ELEN'(0);
      1: edge_val = ELEN'(1);
      2: edge_val = ELEN'(2);
      3: edge_val = ELEN'(3);
      4: edge_val = ELEN'(7);
      5: edge_val = ELEN'(m);
      6: edge_val = ELEN'(m - 1);
      7: edge_val = ELEN'(m >> 1);
      8: edge_val = ELEN'((m >> 1) + 1);
      9: edge_val = ELEN'((m >> 1) + 2);
      default: edge_val = ELEN'((m >> 1) - 1);
    endcase
  endfunction

  task automatic edges(input logic [2:0] sew);
    int w;
    w = 8 << sew;
    for (int k = 0; k < $size(ops); k++)
      for (int i = 0; i < 11; i++)
        for (int j = 0; j < 11; j++)
          check(ops[k], sew, junk(edge_val(i, w), w), junk(edge_val(j, w), w));
  endtask

  task automatic random_cases(input logic [2:0] sew, input int n);
    for (int k = 0; k < $size(ops); k++)
      for (int i = 0; i < n; i++) check(ops[k], sew, ELEN'($urandom), ELEN'($urandom));
  endtask

  // A second start while busy must not disturb the first divide
  task automatic busy_start();
    logic [ELEN-1:0] exp_res;
    exp_res = ref_lane(VEC_DIV, 8, 32'h1234_56F0, 32'hABCD_EF10);
    launch(VEC_DIV, 3'd0, 32'h1234_56F0, 32'hABCD_EF10);
    repeat (5) @(negedge clk);
    op    = VEC_DIVU;
    vsew  = 3'd2;
    a     = '1;
    b     = 32'd3;
    start = 1'b1;
    @(negedge clk);
    start = 1'b0;
    while (done !== 1'b1) @(negedge clk);
    checks++;
    if (result !== exp_res) begin
      errors++;
      $display("FAIL start while busy disturbed result: got %h exp %h", result, exp_res);
      if (errors == max_errors) $fatal(1, "TB STOPPED: %0d mismatches", errors);
    end
    @(negedge clk);
  endtask

  // Reset in the middle of a divide
  task automatic reset_mid();
    launch(VEC_DIVU, 3'd2, 32'd1000, 32'd7);
    repeat (10) @(negedge clk);
    rst_n = 1'b0;
    repeat (2) @(negedge clk);
    checks++;
    if (busy !== 1'b0 || done !== 1'b0) begin
      errors++;
      $display("FAIL reset mid divide: busy=%b done=%b", busy, done);
      if (errors == max_errors) $fatal(1, "TB STOPPED: %0d mismatches", errors);
    end
    rst_n = 1'b1;
  endtask

  task automatic expect_outputs(input string label, input logic exp_busy, input logic exp_done,
                                input logic [ELEN-1:0] exp_result);
    checks++;
    if (busy !== exp_busy || done !== exp_done || result !== exp_result) begin
      errors++;
      $display("FAIL %s: busy=%b exp=%b done=%b exp=%b result=%h exp=%h", label, busy, exp_busy,
               done, exp_done, result, exp_result);
      if (errors == max_errors) $fatal(1, "TB STOPPED: %0d mismatches", errors);
    end
  endtask

  // Disabled clocks must neither advance EXEC nor clear DONE or accept start.
  task automatic protocol_stalls(input logic [2:0] sew);
    int              cycles;
    logic [ELEN-1:0] held_result;
    launch(VEC_DIVU, sew, ELEN'(13), ELEN'(3));
    // launch returns on a falling edge; let the random driver's NBA finish first.
    #1;
    manual_stalls = 1'b1;
    core_en       = 1'b0;
    held_result   = result;
    repeat (3) begin
      @(posedge clk);
      #1;
      expect_outputs("EXEC holds while disabled", 1'b1, 1'b0, held_result);
    end
    @(negedge clk);
    core_en = 1'b1;
    cycles  = 0;
    while (done !== 1'b1) begin
      @(negedge clk);
      cycles++;
    end
    expect_outputs("EXEC resumes with correct result", 1'b0, 1'b1, ELEN'(4));
    checks++;
    if (cycles != (8 << sew) + 1) begin
      errors++;
      $display("FAIL disabled clocks advanced EXEC at SEW=%0d: enabled cycles=%0d exp=%0d",
               8 << sew, cycles, (8 << sew) + 1);
      if (errors == max_errors) $fatal(1, "TB STOPPED: %0d mismatches", errors);
    end

    core_en = 1'b0;
    start   = 1'b1;
    op      = VEC_DIVU;
    vsew    = 3'd2;
    a       = ELEN'(9);
    b       = ELEN'(3);
    repeat (3) begin
      @(posedge clk);
      #1;
      expect_outputs("DONE holds while disabled", 1'b0, 1'b1, ELEN'(4));
    end
    @(negedge clk);
    core_en = 1'b1;
    @(posedge clk);
    #1;
    expect_outputs("DONE clears and ignores start on enabled edge", 1'b0, 1'b0, ELEN'(4));

    @(negedge clk);
    core_en = 1'b0;
    repeat (3) begin
      @(posedge clk);
      #1;
      expect_outputs("disabled IDLE ignores start", 1'b0, 1'b0, ELEN'(4));
    end
    @(negedge clk);
    start   = 1'b0;
    core_en = 1'b1;
    @(posedge clk);
    #1;
    expect_outputs("disabled start was not queued", 1'b0, 1'b0, ELEN'(4));
    @(negedge clk);
    manual_stalls = 1'b0;
  endtask

  // Stall the edge that would publish a normal result or handle an exception.
  task automatic stall_completion(input vec_op_e o, input logic [2:0] sew, input logic [ELEN-1:0] x,
                                  input logic [ELEN-1:0] y);
    logic [ELEN-1:0] held_result;
    logic [ELEN-1:0] exp_result;
    exp_result = ref_lane(o, 8 << sew, x, y);
    launch(o, sew, x, y);
    #1;
    manual_stalls = 1'b1;
    core_en       = 1'b1;
    repeat (expected_latency(o, 8 << sew, x, y) - 1) @(negedge clk);
    #1;
    core_en     = 1'b0;
    held_result = result;
    expect_outputs("before completion edge", 1'b1, 1'b0, held_result);
    repeat (3) begin
      @(posedge clk);
      #1;
      expect_outputs("completion holds while disabled", 1'b1, 1'b0, held_result);
    end
    @(negedge clk);
    core_en = 1'b1;
    @(posedge clk);
    #1;
    expect_outputs("completion resumes on enabled edge", 1'b0, 1'b1, exp_result);
    @(negedge clk);
    manual_stalls = 1'b0;
  endtask

  task automatic completion_stalls(input logic [2:0] sew);
    int              w;
    logic [ELEN-1:0] smin;
    w    = 8 << sew;
    smin = ELEN'(1) << (w - 1);
    for (int k = 0; k < $size(ops); k++) begin
      stall_completion(ops[k], sew, junk(ELEN'(-29), w), junk(ELEN'(3), w));
      stall_completion(ops[k], sew, junk(ELEN'(-29), w), junk('0, w));
    end
    stall_completion(VEC_DIV, sew, junk(smin, w), junk('1, w));
    stall_completion(VEC_REM, sew, junk(smin, w), junk('1, w));
  endtask

  // Reset is synchronous and takes priority over core_en, including result clearing.
  task automatic reset_stalled();
    logic [ELEN-1:0] held_result;
    check(VEC_DIVU, 3'd0, ELEN'(13), ELEN'(3));
    launch(VEC_DIVU, 3'd2, ELEN'(1000), ELEN'(7));
    repeat (3) @(negedge clk);
    #1;
    manual_stalls = 1'b1;
    core_en       = 1'b0;
    held_result   = result;
    rst_n         = 1'b0;
    #1;
    expect_outputs("reset waits for rising edge", 1'b1, 1'b0, held_result);
    @(posedge clk);
    #1;
    expect_outputs("reset overrides disabled core and clears result", 1'b0, 1'b0, '0);
    @(negedge clk);
    rst_n = 1'b1;
    @(posedge clk);
    #1;
    expect_outputs("reset state holds while disabled", 1'b0, 1'b0, '0);
    @(negedge clk);
    core_en       = 1'b1;
    manual_stalls = 1'b0;
    check(VEC_DIVU, 3'd0, ELEN'(29), ELEN'(4));
  endtask

  task automatic verdict();
    $display("Enabled-cycle latency verified for %0d completed operations", latency_checks);
    $display("vec_div_lane: %0d checks, %0d errors", checks, errors);
    if (errors != 0) $fatal(1, "vec_div_lane FAILED");
    $finish;
  endtask

  initial void'($value$plusargs("max_errors=%d", max_errors));

  initial begin
    repeat (Timeout) @(posedge clk);
    $fatal(1, "FAIL: timeout, %0d errors, %0d checks", errors, checks);
  end

  initial begin
    $dumpfile("vec_div_lane_tb.vcd");
    $dumpvars(0, vec_div_lane_tb);
  end

  initial begin
    repeat (3) @(negedge clk);
    rst_n = 1'b1;

    // Edge operands at every width
    edges(3'd0);
    edges(3'd1);
    edges(3'd2);

    // Random operands
    random_cases(3'd0, 300);
    random_cases(3'd1, 300);
    random_cases(3'd2, 300);

    // Handshake corners
    busy_start();
    reset_mid();
    protocol_stalls(3'd0);
    protocol_stalls(3'd1);
    protocol_stalls(3'd2);
    completion_stalls(3'd0);
    completion_stalls(3'd1);
    completion_stalls(3'd2);
    reset_stalled();

    // Explicit ISA corner cases at every supported width
    special_cases(3'd0);
    special_cases(3'd1);
    special_cases(3'd2);

    // Random core_en stalls
    stall_pct = 40;
    random_cases(3'd0, 50);
    random_cases(3'd1, 50);
    random_cases(3'd2, 50);
    stall_pct = 0;

    measure_cycles(3'd0);  // 8-bit
    measure_cycles(3'd1);  // 16-bit
    measure_cycles(3'd2);  // 32-bit

    verdict();
  end

endmodule

`default_nettype wire
