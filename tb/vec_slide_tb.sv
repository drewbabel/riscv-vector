`default_nettype none

module vec_slide_tb
  import vec_pkg::*;
();

  localparam int XLEN = arch_pkg::XLEN;
  localparam int AWIDTH = arch_pkg::RegAddrW;
  localparam int VLEN = arch_pkg::VLEN;
  localparam int ELEN = arch_pkg::ELEN;
  localparam int VlW = $clog2(VLEN + 1);
  localparam int Regs = arch_pkg::NumRegs;
  localparam int Timeout = 2000000;
  localparam int RandomRuns = 600;
  localparam int MinChecks = RandomRuns * (2 * Regs + 36);

  int checks = 0;
  int errors = 0;
  int max_errors = 0;

  logic clk = 1'b0;
  logic rst_n;
  logic core_en;

  logic start;
  vec_op_e op;
  logic vm;
  logic [AWIDTH-1:0] vs2;
  logic [AWIDTH-1:0] vd;
  logic [VlW-1:0] vl;
  logic [2:0] vsew;
  logic [2:0] vlmul;
  logic [XLEN-1:0] offset;
  logic [XLEN-1:0] scalar;

  logic [VLEN-1:0] rdata_lo;
  logic [VLEN-1:0] rdata_hi;
  logic [AWIDTH-1:0] raddr_lo;
  logic [AWIDTH-1:0] raddr_hi;
  logic wen;
  logic [AWIDTH-1:0] waddr;
  logic [VLEN-1:0] wstrb;
  logic [VLEN-1:0] wdata;
  logic busy;
  logic done;

  logic [VLEN-1:0] regs[Regs];
  logic [VLEN-1:0] golden_regs[Regs];

  int enable_pct = 100;
  int writes = 0;
  int dones = 0;
  logic [AWIDTH-1:0] next_waddr;

  always #5 clk = ~clk;

  vec_slide #(
      .XLEN  (XLEN),
      .AWIDTH(AWIDTH),
      .VLEN  (VLEN)
  ) dut (
      .clk(clk),
      .rst_n(rst_n),
      .core_en(core_en),
      .start(start),
      .op(op),
      .vm(vm),
      .vs2(vs2),
      .vd(vd),
      .vl(vl),
      .vsew(vsew),
      .vlmul(vlmul),
      .offset(offset),
      .scalar(scalar),
      .v0(regs[0]),
      .rdata_lo(rdata_lo),
      .rdata_hi(rdata_hi),
      .raddr_lo(raddr_lo),
      .raddr_hi(raddr_hi),
      .wen(wen),
      .waddr(waddr),
      .wstrb(wstrb),
      .wdata(wdata),
      .busy(busy),
      .done(done)
  );

  // Checks
  task automatic check(input string name, input logic [VLEN-1:0] got, input logic [VLEN-1:0] exp);
    checks++;
    if (got !== exp) begin
      errors++;
      $display("FAIL %s: got %h, expected %h", name, got, exp);
      if (errors == max_errors) $fatal(1, "TB STOPPED: %0d mismatches", errors);
    end
  endtask  // Automatic

  // Drive
  task automatic do_reset();
    rst_n   = 1'b0;
    core_en = 1'b1;
    start   = 1'b0;
    op      = VEC_SLIDEUP;
    vm      = 1'b1;
    vs2     = '0;
    vd      = '0;
    vl      = '0;
    vsew    = '0;
    vlmul   = '0;
    offset  = '0;
    scalar  = '0;
    repeat (2) @(posedge clk);
    @(negedge clk);
    rst_n = 1'b1;
  endtask  // Automatic

  task automatic fill_state();
    for (int r = 0; r < Regs; r++) begin
      for (int k = VLEN / 32 - 1; k >= 0; k--) regs[r][k*32+:32] = 32'($urandom);
      golden_regs[r] = regs[r];
    end
  endtask  // Automatic

  task automatic run_one(input vec_op_e o, input logic [2:0] sew, input logic [2:0] lmul,
                         input logic [VlW-1:0] n, input logic [XLEN-1:0] off,
                         input logic [XLEN-1:0] x, input logic m, input logic [AWIDTH-1:0] s2,
                         input logic [AWIDTH-1:0] d);
    op = o;
    vsew = sew;
    vlmul = lmul;
    vl = n;
    offset = off;
    scalar = x;
    vm = m;
    vs2 = s2;
    vd = d;
    apply_golden();
    writes = 0;
    dones = 0;
    next_waddr = d;
    @(negedge clk);
    start = 1'b1;
    @(posedge clk);
    while (!core_en) @(posedge clk);
    @(negedge clk);
    start = 1'b0;
    while (!done) @(negedge clk);
    while (done) @(negedge clk);
    check("register steps", VLEN'(writes), VLEN'((n == '0) ? 0 : group_regs(lmul)));
    check("done pulses", VLEN'(dones), VLEN'(1));
    check_state();
  endtask  // Automatic

  task automatic run_regs(input vec_op_e o, input logic [2:0] sew, input logic [2:0] lmul,
                          input int n, input logic [XLEN-1:0] off, input logic [XLEN-1:0] x,
                          input logic m, input int s2, input int d);
    run_one(o, sew, lmul, VlW'(n), off, x, m, AWIDTH'(s2), AWIDTH'(d));
  endtask  // Automatic

  function automatic logic [XLEN-1:0] pick_offset(input int vlmax);
    case ($urandom_range(
        7
    ))
      0: return XLEN'(0);
      1: return XLEN'($urandom_range(VLEN + 4, VLEN - 4));
      2: return XLEN'($urandom);
      3: return {XLEN{1'b1}} - XLEN'($urandom_range(3));
      default: return XLEN'($urandom_range(vlmax + 1));
    endcase
  endfunction

  task automatic run_random();
    vec_op_e o;
    logic [2:0] sew;
    logic [2:0] lmul;
    int vlmax;
    int g;
    logic m;
    logic [AWIDTH-1:0] s2;
    logic [AWIDTH-1:0] d;
    case ($urandom_range(
        3
    ))
      0: o = VEC_SLIDEUP;
      1: o = VEC_SLIDEDOWN;
      2: o = VEC_SLIDE1UP;
      default: o = VEC_SLIDE1DOWN;
    endcase
    sew  = 3'($urandom_range(2));
    lmul = 3'($urandom_range(7));
    if (lmul == 3'd4) lmul = 3'd0;
    vlmax = vlmax_of(sew, lmul);
    if (vlmax == 0) begin
      lmul  = 3'd0;
      vlmax = vlmax_of(sew, lmul);
    end
    g  = group_regs(lmul);
    m  = 1'($urandom);
    s2 = AWIDTH'($urandom_range(Regs / g - 1) * g);
    d  = AWIDTH'($urandom_range(Regs / g - 1, 1) * g);
    if ((o == VEC_SLIDEDOWN || o == VEC_SLIDE1DOWN) && $urandom_range(3) == 0 && s2 != '0) d = s2;
    if ((o == VEC_SLIDEUP || o == VEC_SLIDE1UP) && d == s2) s2 = d - AWIDTH'(g);
    if (m && $urandom_range(7) == 0 && s2 != '0) d = '0;
    run_one(o, sew, lmul, VlW'($urandom_range(vlmax)), pick_offset(vlmax), XLEN'($urandom), m, s2,
            d);
  endtask  // Automatic

  task automatic run_many(input int n, input int pct);
    enable_pct = pct;
    repeat (n) run_random();
  endtask  // Automatic

  // Directed forms
  task automatic test_directed();
    run_regs(VEC_SLIDEUP, 3'd0, 3'd0, vlmax_of(3'd0, 3'd0), XLEN'(3), '0, 1'b1, 1, 2);
    run_regs(VEC_SLIDEDOWN, 3'd0, 3'd0, vlmax_of(3'd0, 3'd0), XLEN'(3), '0, 1'b1, 1, 3);
    run_regs(VEC_SLIDE1UP, 3'd2, 3'd0, vlmax_of(3'd2, 3'd0), '0, XLEN'(32'hDEAD_BEEF), 1'b1, 4, 5);
    run_regs(VEC_SLIDE1DOWN, 3'd1, 3'd0, vlmax_of(3'd1, 3'd0), '0, XLEN'(32'h0000_1234), 1'b1, 6,
             7);
  endtask  // Automatic

  // Group spans
  task automatic test_groups();
    run_regs(VEC_SLIDEUP, 3'd1, 3'd2, vlmax_of(3'd1, 3'd2), XLEN'(11), '0, 1'b1, 8, 16);
    run_regs(VEC_SLIDEDOWN, 3'd2, 3'd3, vlmax_of(3'd2, 3'd3), XLEN'(9), '0, 1'b1, 16, 8);
    run_regs(VEC_SLIDE1UP, 3'd0, 3'd1, vlmax_of(3'd0, 3'd1) - 3, '0, XLEN'(32'h0000_00A5), 1'b0, 10,
             12);
    run_regs(VEC_SLIDE1DOWN, 3'd0, 3'd1, vlmax_of(3'd0, 3'd1) - 3, '0, XLEN'(32'h0000_005A), 1'b0,
             12, 14);
  endtask  // Automatic

  // Overlap walks upward
  task automatic test_overlap();
    run_regs(VEC_SLIDEDOWN, 3'd0, 3'd3, VLEN, XLEN'(21), '0, 1'b1, 24, 24);
    run_regs(VEC_SLIDE1DOWN, 3'd2, 3'd2, vlmax_of(3'd2, 3'd2), '0, XLEN'(32'h7777_0000), 1'b0, 20,
             20);
  endtask  // Automatic

  // Large offsets
  task automatic test_large_offsets();
    run_regs(VEC_SLIDEUP, 3'd0, 3'd0, vlmax_of(3'd0, 3'd0), '1, '0, 1'b1, 1, 2);
    run_regs(VEC_SLIDEDOWN, 3'd0, 3'd0, vlmax_of(3'd0, 3'd0), '1, '0, 1'b1, 1, 3);
    run_regs(VEC_SLIDEDOWN, 3'd2, 3'd3, vlmax_of(3'd2, 3'd3), XLEN'(VLEN), '0, 1'b1, 8, 16);
    run_regs(VEC_SLIDEUP, 3'd2, 3'd3, vlmax_of(3'd2, 3'd3), XLEN'(vlmax_of(3'd2, 3'd3) - 1), '0,
             1'b1, 8, 16);
  endtask  // Automatic

  // Fractional groups
  task automatic test_fractional();
    run_regs(VEC_SLIDEDOWN, 3'd0, 3'd7, vlmax_of(3'd0, 3'd7), XLEN'(5), '0, 1'b1, 9, 11);
    run_regs(VEC_SLIDE1DOWN, 3'd0, 3'd6, vlmax_of(3'd0, 3'd6) - 1, '0, XLEN'(32'h0000_0011), 1'b1,
             9, 11);
  endtask  // Automatic

  // Zero length
  task automatic test_zero_length();
    run_regs(VEC_SLIDEUP, 3'd0, 3'd0, 0, XLEN'(1), '0, 1'b1, 1, 2);
    run_regs(VEC_SLIDE1DOWN, 3'd2, 3'd1, 0, '0, XLEN'(5), 1'b0, 4, 6);
  endtask  // Automatic

  task automatic check_state();
    for (int r = 0; r < Regs; r++) check("register", regs[r], golden_regs[r]);
  endtask  // Automatic

  task automatic do_verdict();
    if (checks < MinChecks)
      $fatal(1, "TB UNDER-RAN: %0d checks, expected at least %0d", checks, MinChecks);
    if (errors == 0) $display("PASS: %0d checks, %0d mismatches", checks, errors);
    else $fatal(1, "FAIL: %0d mismatches, %0d checks", errors, checks);
    $finish;
  endtask  // Automatic

  task automatic watchdog();
    repeat (Timeout) @(posedge clk);
    $fatal(1, "FAIL: timeout, %0d mismatches, %0d checks", errors, checks);
  endtask  // Automatic

  initial void'($value$plusargs("max_errors=%d", max_errors));

  initial watchdog();

  initial begin
    $dumpfile("vec_slide_tb.vcd");
    $dumpvars(0, vec_slide_tb);
    fill_state();
    do_reset();

    test_directed();
    test_groups();
    test_overlap();
    test_large_offsets();
    test_fractional();
    test_zero_length();
    run_many(RandomRuns, 100);
    run_many(RandomRuns, 60);

    do_verdict();
  end

  // Group geometry
  function automatic int group_regs(input logic [2:0] lmul);
    return lmul[2] ? 1 : (1 << lmul[1:0]);
  endfunction

  function automatic int vlmax_of(input logic [2:0] sew, input logic [2:0] lmul);
    int epr;
    epr = VLEN >> (3 + sew);
    return lmul[2] ? (epr >> (3'd0 - lmul)) : (epr << lmul);
  endfunction

  // Reference semantics
  task automatic apply_golden();
    logic [VLEN-1:0] src[Regs];
    int bits;
    int epr;
    int vlmax;
    logic [XLEN-1:0] amt;
    int from;
    logic [ELEN-1:0] val;
    logic up;
    logic one;
    bits = 8 << vsew;
    epr = VLEN / bits;
    vlmax = vlmax_of(vsew, vlmul);
    up = (op == VEC_SLIDEUP) || (op == VEC_SLIDE1UP);
    one = (op == VEC_SLIDE1UP) || (op == VEC_SLIDE1DOWN);
    amt = one ? XLEN'(1) : offset;
    for (int r = 0; r < Regs; r++) src[r] = golden_regs[r];
    for (int i = 0; i < int'(vl); i++) begin
      if (!(vm || src[0][i])) continue;
      if (up) begin
        if (one && i == 0) val = ELEN'(scalar);
        else if (XLEN'(i) < amt) continue;
        else begin
          from = i - int'(amt);
          val  = ELEN'(src[(int'(vs2)+from/epr)%Regs] >> ((from % epr) * bits));
        end
      end else begin
        if (one && i == int'(vl) - 1) val = ELEN'(scalar);
        else if (amt >= XLEN'(vlmax - i)) val = '0;
        else begin
          from = i + int'(amt);
          val  = ELEN'(src[(int'(vs2)+from/epr)%Regs] >> ((from % epr) * bits));
        end
      end
      for (int k = 0; k < bits; k++) golden_regs[(int'(vd)+i/epr)%Regs][(i%epr)*bits+k] = val[k];
    end
  endtask  // Automatic

  // Pace and models
  always @(negedge clk) core_en = ($urandom_range(99) < enable_pct);

  assign rdata_lo = regs[raddr_lo];
  assign rdata_hi = regs[raddr_hi];

  always @(posedge clk) begin
    if (rst_n && core_en) begin
      if (wen) regs[waddr] <= (regs[waddr] & ~wstrb) | (wdata & wstrb);
      if (busy) begin
        writes++;
        next_waddr <= next_waddr + AWIDTH'(1);
      end
      if (done) dones++;
    end
  end

  // Comparison
  always @(negedge clk) begin
    if (rst_n) begin
      check("write while idle", VLEN'(wen && !busy), VLEN'(0));
      check("write needs a strobe", VLEN'(busy && (wen != (wstrb != '0))), VLEN'(0));
      if (busy) check("write order", VLEN'(waddr), VLEN'(next_waddr));
    end
  end

endmodule

`default_nettype wire
