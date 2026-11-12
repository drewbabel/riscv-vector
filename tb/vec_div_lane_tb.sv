`default_nettype none

module vec_div_lane_tb
  import vec_pkg::*;
();

  localparam int ELEN = arch_pkg::ELEN;
  localparam int Timeout = 2000000;
  localparam int NumEdges = 11;
  localparam int LongW = $bits(longint);
  localparam logic [VsewW-1:0] Sew8 = VsewW'(0);
  localparam logic [VsewW-1:0] SewTop = VsewW'($clog2(ELEN / 8));
  localparam int MinChecks = 26000;

  int                  checks = 0;
  int                  errors = 0;
  int                  max_errors = 0;
  int                  stall_pct = 0;
  int                  latency_checks = 0;
  int                  enabled_cycles = 0;
  int                  target_cycles = 0;
  int                  accepted_width = 0;
  vec_op_e             accepted_op = VEC_DIVU;
  bit                  latency_active = 1'b0;
  bit                  manual_stalls = 1'b0;

  logic                clk = 1'b0;
  logic                rst_n;
  logic                core_en;
  logic                start;
  vec_op_e             op;
  logic    [VsewW-1:0] vsew;
  logic    [ ELEN-1:0] a;
  logic    [ ELEN-1:0] b;
  logic    [ ELEN-1:0] result;
  logic                busy;
  logic                done;

  vec_op_e             ops                    [4] = '{VEC_DIVU, VEC_DIV, VEC_REMU, VEC_REM};

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

  task automatic check(input string name, input logic [ELEN-1:0] got, input logic [ELEN-1:0] exp);
    checks++;
    if (got !== exp) begin
      errors++;
      $display("FAIL %s: got %h, expected %h", name, got, exp);
      if (errors == max_errors) $fatal(1, "TB STOPPED: %0d mismatches", errors);
    end
  endtask  // Automatic

  task automatic do_reset();
    @(negedge clk);
    rst_n         = 1'b0;
    stall_pct     = 0;
    manual_stalls = 1'b0;
    core_en       = 1'b1;
    start         = 1'b0;
    op            = VEC_DIVU;
    vsew          = Sew8;
    a             = '0;
    b             = '0;
    repeat (2) @(posedge clk);
    @(negedge clk);
    rst_n = 1'b1;
  endtask  // Automatic

  // Random stalls
  task automatic drive_core_en();
    if (!manual_stalls) core_en = ($urandom_range(99) >= stall_pct);
  endtask  // Automatic

  task automatic watchdog();
    repeat (Timeout) @(posedge clk);
    $fatal(1, "FAIL: timeout, %0d errors, %0d checks", errors, checks);
  endtask  // Automatic

  // Enabled completion latency
  task automatic track_latency();
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
      check($sformatf("%s sew=%0d enabled cycles", accepted_op.name(), accepted_width),
            ELEN'(enabled_cycles), ELEN'(target_cycles));
      latency_checks++;
      latency_active = 1'b0;
    end
  endtask  // Automatic

  // Hold start until accepted
  task automatic launch(input vec_op_e o, input logic [VsewW-1:0] sew, input logic [ELEN-1:0] x,
                        input logic [ELEN-1:0] y);
    logic taken;
    @(negedge clk);
    while (busy || done) @(negedge clk);
    op    = o;
    vsew  = sew;
    a     = x;
    b     = y;
    start = 1'b1;
    taken = 1'b0;
    while (!taken) begin
      @(posedge clk);
      taken = core_en;
      @(negedge clk);
    end
    start = 1'b0;
    // Scramble accepted inputs
    if (o == VEC_DIVU) op = VEC_REM;
    else op = VEC_DIVU;
    vsew = VsewW'($urandom);
    a    = ELEN'($urandom);
    b    = ELEN'($urandom);
  endtask  // Automatic

  // One divide
  task automatic divide(input vec_op_e o, input logic [VsewW-1:0] sew, input logic [ELEN-1:0] x,
                        input logic [ELEN-1:0] y);
    logic  [ELEN-1:0] exp_res;
    string            name;
    name    = $sformatf("%s sew=%0d a=%h b=%h", o.name(), 8 << sew, x, y);
    exp_res = ref_lane(o, 8 << sew, x, y);
    launch(o, sew, x, y);
    if (stall_pct == 0) check({name, " busy after start"}, ELEN'(busy), ELEN'(1'b1));
    while (done !== 1'b1) @(negedge clk);
    check(name, result, exp_res);
    // Pulse and held result
    if (stall_pct == 0) begin
      @(negedge clk);
      check({name, " done pulse"}, ELEN'(done), ELEN'(1'b0));
      check({name, " result held"}, result, exp_res);
    end
  endtask  // Automatic

  task automatic edges(input logic [VsewW-1:0] sew);
    int w;
    w = 8 << sew;
    for (int k = 0; k < $size(ops); k++)
      for (int i = 0; i < NumEdges; i++)
        for (int j = 0; j < NumEdges; j++)
          divide(ops[k], sew, junk(edge_val(i, w), w), junk(edge_val(j, w), w));
  endtask  // Automatic

  task automatic edges_all();
    for (int s = int'(Sew8); s <= int'(SewTop); s++) edges(VsewW'(s));
  endtask  // Automatic

  task automatic random_cases(input logic [VsewW-1:0] sew, input int n);
    for (int k = 0; k < $size(ops); k++)
      for (int i = 0; i < n; i++) divide(ops[k], sew, ELEN'($urandom), ELEN'($urandom));
  endtask  // Automatic

  task automatic random_all(input int n);
    for (int s = int'(Sew8); s <= int'(SewTop); s++) random_cases(VsewW'(s), n);
  endtask  // Automatic

  task automatic stalled_cases(input int pct, input int n);
    stall_pct = pct;
    random_all(n);
    stall_pct = 0;
  endtask  // Automatic

  // Ignore busy start
  task automatic busy_start();
    logic [ELEN-1:0] x;
    logic [ELEN-1:0] y;
    logic [ELEN-1:0] exp_res;
    x       = ELEN'('h1234_56F0);
    y       = ELEN'('hABCD_EF10);
    exp_res = ref_lane(VEC_DIV, 8, x, y);
    launch(VEC_DIV, Sew8, x, y);
    repeat (5) @(negedge clk);
    op    = VEC_DIVU;
    vsew  = SewTop;
    a     = '1;
    b     = ELEN'(3);
    start = 1'b1;
    @(negedge clk);
    start = 1'b0;
    while (done !== 1'b1) @(negedge clk);
    check("start while busy", result, exp_res);
    @(negedge clk);
  endtask  // Automatic

  // Reset during division
  task automatic reset_mid();
    launch(VEC_DIVU, SewTop, ELEN'(1000), ELEN'(7));
    repeat (10) @(negedge clk);
    do_reset();
    check("reset mid divide busy", ELEN'(busy), ELEN'(1'b0));
    check("reset mid divide done", ELEN'(done), ELEN'(1'b0));
  endtask  // Automatic

  task automatic expect_outputs(input string name, input logic exp_busy, input logic exp_done,
                                input logic [ELEN-1:0] exp_result);
    check({name, " busy"}, ELEN'(busy), ELEN'(exp_busy));
    check({name, " done"}, ELEN'(done), ELEN'(exp_done));
    check({name, " result"}, result, exp_result);
  endtask  // Automatic

  // Stall each state
  task automatic protocol_stalls(input logic [VsewW-1:0] sew);
    int              cycles;
    logic [ELEN-1:0] held_result;
    launch(VEC_DIVU, sew, ELEN'(13), ELEN'(3));
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
    expect_outputs("EXEC resumes", 1'b0, 1'b1, ELEN'(4));
    check("EXEC resumed enabled cycles", ELEN'(cycles), ELEN'((8 << sew) + 1));

    core_en = 1'b0;
    start   = 1'b1;
    op      = VEC_DIVU;
    vsew    = SewTop;
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
    expect_outputs("DONE clears and ignores start", 1'b0, 1'b0, ELEN'(4));

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
  endtask  // Automatic

  // Stall completion edge
  task automatic stall_completion(input vec_op_e o, input logic [VsewW-1:0] sew,
                                  input logic [ELEN-1:0] x, input logic [ELEN-1:0] y);
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
    expect_outputs("completion resumes", 1'b0, 1'b1, exp_result);
    @(negedge clk);
    manual_stalls = 1'b0;
  endtask  // Automatic

  task automatic completion_stalls(input logic [VsewW-1:0] sew);
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
  endtask  // Automatic

  // Reset while stalled
  task automatic reset_stalled();
    logic [ELEN-1:0] held_result;
    divide(VEC_DIVU, Sew8, ELEN'(13), ELEN'(3));
    launch(VEC_DIVU, SewTop, ELEN'(1000), ELEN'(7));
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
    expect_outputs("reset overrides disabled core", 1'b0, 1'b0, '0);
    @(negedge clk);
    rst_n = 1'b1;
    @(posedge clk);
    #1;
    expect_outputs("reset state holds while disabled", 1'b0, 1'b0, '0);
    @(negedge clk);
    core_en       = 1'b1;
    manual_stalls = 1'b0;
    divide(VEC_DIVU, Sew8, ELEN'(29), ELEN'(4));
  endtask  // Automatic

  task automatic check_timed(input string name, input vec_op_e o, input logic [VsewW-1:0] sew,
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
    check({name, " result"}, result, exp_res);
    check({name, " cycles"}, ELEN'(cycles), ELEN'(expected_cycles));
  endtask  // Automatic

  // Arithmetic exceptions
  task automatic special_cases(input logic [VsewW-1:0] sew);
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
  endtask  // Automatic

  task automatic measure_cycles(input logic [VsewW-1:0] sew);
    int cycles;
    launch(VEC_DIVU, sew, ELEN'(13), ELEN'(3));
    cycles = 0;
    while (done !== 1'b1) begin
      @(negedge clk);
      cycles++;
    end
    $display("SEW=%0d: %0d cycles, result=%0d", 8 << sew, cycles, result);
    check("measured quotient", result, ELEN'(4));
    check("measured cycles", ELEN'(cycles), ELEN'((8 << sew) + 1));
  endtask  // Automatic

  task automatic directed_all();
    for (int s = int'(Sew8); s <= int'(SewTop); s++) begin
      protocol_stalls(VsewW'(s));
      completion_stalls(VsewW'(s));
      special_cases(VsewW'(s));
      measure_cycles(VsewW'(s));
    end
  endtask  // Automatic

  task automatic do_verdict();
    $display("Enabled-cycle latency verified for %0d completed operations", latency_checks);
    if (checks < MinChecks)
      $fatal(1, "TB UNDER-RAN: %0d checks, expected at least %0d", checks, MinChecks);
    if (errors == 0) $display("PASS: %0d checks, %0d mismatches", checks, errors);
    else $fatal(1, "FAIL: %0d mismatches, %0d checks", errors, checks);
    $finish;
  endtask  // Automatic

  initial void'($value$plusargs("max_errors=%d", max_errors));

  initial watchdog();

  initial begin
    $dumpfile("vec_div_lane_tb.vcd");
    $dumpvars(0, vec_div_lane_tb);
    do_reset();
    edges_all();
    random_all(300);
    busy_start();
    reset_mid();
    directed_all();
    reset_stalled();
    stalled_cases(40, 50);
    do_verdict();
  end

  // Width helpers
  function automatic longint umask(input int w);
    umask = (64'sd1 <<< w) - 64'sd1;
  endfunction

  function automatic longint uval(input logic [ELEN-1:0] x, input int w);
    uval = longint'({{(LongW - ELEN) {1'b0}}, x}) & umask(w);
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
      VEC_DIV: begin
        if (sy == 0) t = -1;
        else if (sx == smin && sy == -1) t = sx;
        else t = sx / sy;
      end
      default: begin
        if (sy == 0) t = sx;
        else if (sx == smin && sy == -1) t = 0;
        else t = sx % sy;
      end
    endcase
    ref_lane = ELEN'(t & umask(w));
  endfunction

  function automatic int expected_latency(input vec_op_e o, input int w, input logic [ELEN-1:0] x,
                                          input logic [ELEN-1:0] y);
    longint sx;
    longint sy;
    longint smin;
    sx               = sval(x, w);
    sy               = sval(y, w);
    smin             = -(64'sd1 <<< (w - 1));
    expected_latency = w + 1;
    if (uval(y, w) == 0) expected_latency = 1;
    else if ((o == VEC_DIV) || (o == VEC_REM)) begin
      if (sx == smin && sy == -1) expected_latency = 1;
    end
  endfunction

  // Junk above element
  function automatic logic [ELEN-1:0] junk(input logic [ELEN-1:0] x, input int w);
    logic [ELEN-1:0] keep;
    keep = ELEN'(umask(w));
    junk = (x & keep) | (ELEN'($urandom) & ~keep);
  endfunction

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

  always @(negedge clk) drive_core_en();
  always @(posedge clk) track_latency();

  // Handshake rule
  always @(negedge clk) if (rst_n && done) check("busy with done", ELEN'(busy), ELEN'(1'b0));

endmodule

`default_nettype wire
