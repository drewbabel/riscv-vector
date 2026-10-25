`default_nettype none

module vec_div_lane_tb
  import vec_pkg::*;
();

  localparam int ELEN = arch_pkg::ELEN;
  localparam int Timeout = 2000000;
  localparam int NumEdges = 11;
  localparam int LongW = $bits(longint);
  localparam logic [2:0] Sew8 = 3'd0;
  localparam logic [2:0] SewTop = 3'($clog2(ELEN / 8));
  localparam int MinChecks = 26000;

  int checks = 0;
  int errors = 0;
  int max_errors = 0;
  int stall_pct = 0;

  logic clk = 1'b0;
  logic rst_n;
  logic core_en;
  logic start;
  vec_op_e op;
  logic [2:0] vsew;
  logic [ELEN-1:0] a;
  logic [ELEN-1:0] b;
  logic [ELEN-1:0] result;
  logic busy;
  logic done;

  vec_op_e ops[4] = '{VEC_DIVU, VEC_DIV, VEC_REMU, VEC_REM};

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
    rst_n     = 1'b0;
    stall_pct = 0;
    core_en   = 1'b1;
    start     = 1'b0;
    op        = VEC_DIVU;
    vsew      = Sew8;
    a         = '0;
    b         = '0;
    repeat (2) @(posedge clk);
    @(negedge clk);
    rst_n = 1'b1;
  endtask  // Automatic

  // Random stalls
  task automatic drive_core_en();
    core_en = ($urandom_range(99) >= stall_pct);
  endtask  // Automatic

  task automatic watchdog();
    repeat (Timeout) @(posedge clk);
    $fatal(1, "FAIL: timeout, %0d errors, %0d checks", errors, checks);
  endtask  // Automatic

  // Raise start until an enabled edge takes it
  task automatic launch(input vec_op_e o, input logic [2:0] sew, input logic [ELEN-1:0] x,
                        input logic [ELEN-1:0] y);
    logic taken;
    @(negedge clk);
    // muldiv only takes start in IDLE (same rule as datapath.sv: !busy && !done)
    while (busy || done) @(negedge clk);
    op = o;
    vsew = sew;
    a = x;
    b = y;
    start = 1'b1;
    taken = 1'b0;
    while (!taken) begin
      @(posedge clk);
      taken = core_en;
      @(negedge clk);
    end
    start = 1'b0;
    // Scramble inputs: the lane must not depend on them after start
    vsew = 3'($urandom);
    a = ELEN'($urandom);
    b = ELEN'($urandom);
  endtask  // Automatic

  // One divide
  task automatic divide(input vec_op_e o, input logic [2:0] sew, input logic [ELEN-1:0] x,
                        input logic [ELEN-1:0] y);
    logic [ELEN-1:0] exp_res;
    string name;
    name = $sformatf("%s sew=%0d a=%h b=%h", o.name(), 8 << sew, x, y);
    exp_res = ref_lane(o, 8 << sew, x, y);
    launch(o, sew, x, y);
    if (stall_pct == 0) check({name, " busy after start"}, ELEN'(busy), ELEN'(1'b1));
    while (done !== 1'b1) @(negedge clk);
    check(name, result, exp_res);
    // done pulses one enabled cycle, result holds
    if (stall_pct == 0) begin
      @(negedge clk);
      check({name, " done pulse"}, ELEN'(done), ELEN'(1'b0));
      check({name, " result held"}, result, exp_res);
    end
  endtask  // Automatic

  task automatic edges(input logic [2:0] sew);
    int w;
    w = 8 << sew;
    for (int k = 0; k < $size(ops); k++)
      for (int i = 0; i < NumEdges; i++)
        for (int j = 0; j < NumEdges; j++)
          divide(ops[k], sew, junk(edge_val(i, w), w), junk(edge_val(j, w), w));
  endtask  // Automatic

  task automatic edges_all();
    for (int s = int'(Sew8); s <= int'(SewTop); s++) edges(3'(s));
  endtask  // Automatic

  task automatic random_cases(input logic [2:0] sew, input int n);
    for (int k = 0; k < $size(ops); k++)
      for (int i = 0; i < n; i++) divide(ops[k], sew, ELEN'($urandom), ELEN'($urandom));
  endtask  // Automatic

  task automatic random_all(input int n);
    for (int s = int'(Sew8); s <= int'(SewTop); s++) random_cases(3'(s), n);
  endtask  // Automatic

  task automatic stalled_cases(input int pct, input int n);
    stall_pct = pct;
    random_cases(Sew8, n);
    random_cases(SewTop, n);
    stall_pct = 0;
  endtask  // Automatic

  // A second start while busy must not disturb the first divide
  task automatic busy_start();
    logic [ELEN-1:0] x;
    logic [ELEN-1:0] y;
    logic [ELEN-1:0] exp_res;
    x = ELEN'('h1234_56F0);
    y = ELEN'('hABCD_EF10);
    exp_res = ref_lane(VEC_DIV, 8, x, y);
    launch(VEC_DIV, Sew8, x, y);
    repeat (5) @(negedge clk);
    op = VEC_DIVU;
    vsew = SewTop;
    a = '1;
    b = ELEN'(3);
    start = 1'b1;
    @(negedge clk);
    start = 1'b0;
    while (done !== 1'b1) @(negedge clk);
    check("start while busy", result, exp_res);
    @(negedge clk);
  endtask  // Automatic

  // Reset in the middle of a divide
  task automatic reset_mid();
    launch(VEC_DIVU, SewTop, ELEN'(1000), ELEN'(7));
    repeat (10) @(negedge clk);
    do_reset();
    check("reset mid divide busy", ELEN'(busy), ELEN'(1'b0));
    check("reset mid divide done", ELEN'(done), ELEN'(1'b0));
  endtask  // Automatic

  task automatic do_verdict();
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
    u = uval(x, w);
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

  // Handshake rule
  always @(negedge clk) if (rst_n && done) check("busy with done", ELEN'(busy), ELEN'(1'b0));

endmodule

`default_nettype wire
