`default_nettype none

module vec_issue_tb
  import vec_pkg::*;
();

  localparam int XLEN = arch_pkg::XLEN;
  localparam int AWIDTH = arch_pkg::RegAddrW;
  localparam int VLEN = arch_pkg::VLEN;
  localparam int VlW = $clog2(VLEN + 1);
  localparam int RmW = fp_pkg::RmW;
  localparam int SbDepth = 8;
  localparam int IdleTimeout = 200;
  localparam int ReleaseTimeout = 50;
  localparam int SoakCycles = 4000;
  localparam int MinChecks = 23000 + 5 * SoakCycles;

  int checks = 0;
  int errors = 0;
  int max_errors = 0;
  int accepted = 0;
  int launched = 0;

  logic clk = 1'b0;
  logic rst_n;
  logic core_en;

  logic instr_valid;
  logic cancel;
  logic ex_adv;
  vec_op_e op;
  vec_src_e src;
  vec_eew_e eew;
  logic writes_xreg;
  logic [AWIDTH-1:0] vs1;
  logic [AWIDTH-1:0] vs2;
  logic [AWIDTH-1:0] vd;
  logic vm;
  logic reads_vd;
  logic [4:0] simm;
  logic [XLEN-1:0] xdata;
  logic [XLEN-1:0] xstride;
  logic [VlW-1:0] vl;
  logic [2:0] vsew;
  logic [2:0] vlmul;
  logic [1:0] vxrm;
  vec_fop_e fop;
  logic [RmW-1:0] frm;

  logic seq_busy;
  logic seq_done;
  logic seq_start;
  vec_op_e seq_op;
  vec_src_e seq_src;
  vec_eew_e seq_eew;
  logic [AWIDTH-1:0] seq_vs1;
  logic [AWIDTH-1:0] seq_vs2;
  logic [AWIDTH-1:0] seq_vd;
  logic seq_vm;
  logic seq_reads_vd;
  logic [4:0] seq_simm;
  logic [XLEN-1:0] seq_xdata;
  logic [XLEN-1:0] seq_xstride;
  logic [VlW-1:0] seq_vl;
  logic [2:0] seq_vsew;
  logic [2:0] seq_vlmul;
  logic [1:0] seq_vxrm;
  vec_fop_e seq_fop;
  logic [RmW-1:0] seq_frm;
  logic vec_hold;
  logic vec_idle;
  logic load_pending;
  logic store_pending;

  int run_len;
  int seq_ticks;
  logic taken;
  logic soak_on = 1'b0;
  logic [AWIDTH:0] wr_regs;
  logic [AWIDTH-1:0] rd1;
  logic [AWIDTH:0] rd1_regs;
  logic [AWIDTH:0] rd2_regs;
  logic clear;
  logic [AWIDTH-1:0] clear_addr;
  logic pipe_busy;

  vec_op_e sb_op[SbDepth];
  vec_src_e sb_src[SbDepth];
  logic [AWIDTH-1:0] sb_vs1[SbDepth];
  logic [AWIDTH-1:0] sb_vs2[SbDepth];
  logic [AWIDTH-1:0] sb_vd[SbDepth];
  logic sb_vm[SbDepth];
  logic sb_reads_vd[SbDepth];
  logic [4:0] sb_simm[SbDepth];
  logic [XLEN-1:0] sb_xdata[SbDepth];
  logic [XLEN-1:0] sb_xstride[SbDepth];
  logic [VlW-1:0] sb_vl[SbDepth];
  logic [2:0] sb_vsew[SbDepth];
  logic [2:0] sb_vlmul[SbDepth];
  logic [1:0] sb_vxrm[SbDepth];
  vec_fop_e sb_fop[SbDepth];
  logic [RmW-1:0] sb_frm[SbDepth];
  vec_eew_e sb_eew[SbDepth];
  int sb_head = 0;
  int sb_tail = 0;
  int inflight[$];

  always #5 clk = ~clk;

  vec_issue #(
      .XLEN  (XLEN),
      .AWIDTH(AWIDTH),
      .VLEN  (VLEN)
  ) dut (
      .clk(clk),
      .rst_n(rst_n),
      .core_en(core_en),
      .instr_valid(instr_valid),
      .cancel(cancel),
      .ex_advance(ex_adv && !vec_hold),
      .op(op),
      .src(src),
      .eew(eew),
      .writes_xreg(writes_xreg),
      .vs1(vs1),
      .vs2(vs2),
      .vd(vd),
      .vm(vm),
      .reads_vd(reads_vd),
      .simm(simm),
      .xdata(xdata),
      .xstride(xstride),
      .fop(fop),
      .wr_regs(wr_regs),
      .rd1(rd1),
      .rd1_regs(rd1_regs),
      .rd2_regs(rd2_regs),
      .clear(clear),
      .clear_addr(clear_addr),
      .vl(vl),
      .vsew(vsew),
      .vlmul(vlmul),
      .vxrm(vxrm),
      .frm(frm),
      .seq_busy(seq_busy),
      .seq_done(seq_done),
      .pipe_busy(pipe_busy),
      .x_done(seq_done),
      .seq_start(seq_start),
      .seq_op(seq_op),
      .seq_src(seq_src),
      .seq_eew(seq_eew),
      .seq_vs1(seq_vs1),
      .seq_vs2(seq_vs2),
      .seq_vd(seq_vd),
      .seq_vm(seq_vm),
      .seq_reads_vd(seq_reads_vd),
      .seq_simm(seq_simm),
      .seq_xdata(seq_xdata),
      .seq_xstride(seq_xstride),
      .seq_vl(seq_vl),
      .seq_vsew(seq_vsew),
      .seq_vlmul(seq_vlmul),
      .seq_vxrm(seq_vxrm),
      .seq_fop(seq_fop),
      .seq_frm(seq_frm),
      .vec_hold(vec_hold),
      .vec_idle(vec_idle),
      .load_pending(load_pending),
      .store_pending(store_pending)
  );

  task automatic check(input string name, input logic [XLEN-1:0] got, input logic [XLEN-1:0] exp);
    checks++;
    if (got !== exp) begin
      errors++;
      $display("FAIL %s: got %h, expected %h", name, got, exp);
      if (errors == max_errors) $fatal(1, "TB STOPPED: %0d mismatches", errors);
    end
  endtask  // Automatic

  task automatic do_reset();
    rst_n       = 1'b0;
    core_en     = 1'b1;
    ex_adv      = 1'b1;
    instr_valid = 1'b0;
    cancel      = 1'b0;
    xstride     = '0;
    op          = VEC_ADD;
    src         = VEC_SRC_VV;
    eew         = VEC_EEW_SAME;
    writes_xreg = 1'b0;
    vs1         = '0;
    vs2         = '0;
    vd          = '0;
    vm          = 1'b1;
    reads_vd    = 1'b0;
    simm        = '0;
    xdata       = '0;
    vl          = VlW'(4);
    vsew        = 3'd2;
    vlmul       = 3'd0;
    vxrm        = 2'd0;
    fop         = VEC_FADD;
    frm         = fp_pkg::RmRne;
    run_len     = 3;
    taken       = 1'b0;
    wr_regs     = '0;
    rd1         = '0;
    rd1_regs    = '0;
    rd2_regs    = '0;
    clear       = 1'b0;
    clear_addr  = '0;
    pipe_busy   = 1'b0;
    repeat (3) @(negedge clk);
    rst_n = 1'b1;
    @(negedge clk);
  endtask  // Automatic

  task automatic sb_push();
    sb_op[sb_tail]       = op;
    sb_src[sb_tail]      = src;
    sb_vs1[sb_tail]      = vs1;
    sb_vs2[sb_tail]      = vs2;
    sb_vd[sb_tail]       = vd;
    sb_vm[sb_tail]       = vm;
    sb_reads_vd[sb_tail] = reads_vd;
    sb_simm[sb_tail]     = simm;
    sb_xdata[sb_tail]    = xdata;
    sb_xstride[sb_tail]  = xstride;
    sb_vl[sb_tail]       = vl;
    sb_vsew[sb_tail]     = vsew;
    sb_vlmul[sb_tail]    = vlmul;
    sb_vxrm[sb_tail]     = vxrm;
    sb_fop[sb_tail]      = fop;
    sb_frm[sb_tail]      = frm;
    sb_eew[sb_tail]      = eew;
    sb_tail              = (sb_tail + 1) % SbDepth;
    accepted++;
  endtask  // Automatic

  task automatic sb_check();
    check("start has entry", XLEN'(sb_head != sb_tail), XLEN'(1'b1));
    if (sb_head != sb_tail) begin
      check("op", XLEN'(seq_op), XLEN'(sb_op[sb_head]));
      check("src", XLEN'(seq_src), XLEN'(sb_src[sb_head]));
      check("vs1", XLEN'(seq_vs1), XLEN'(sb_vs1[sb_head]));
      check("vs2", XLEN'(seq_vs2), XLEN'(sb_vs2[sb_head]));
      check("vd", XLEN'(seq_vd), XLEN'(sb_vd[sb_head]));
      check("vm", XLEN'(seq_vm), XLEN'(sb_vm[sb_head]));
      check("reads_vd", XLEN'(seq_reads_vd), XLEN'(sb_reads_vd[sb_head]));
      check("simm", XLEN'(seq_simm), XLEN'(sb_simm[sb_head]));
      check("xdata", seq_xdata, sb_xdata[sb_head]);
      check("xstride", seq_xstride, sb_xstride[sb_head]);
      check("vl", XLEN'(seq_vl), XLEN'(sb_vl[sb_head]));
      check("vsew", XLEN'(seq_vsew), XLEN'(sb_vsew[sb_head]));
      check("vlmul", XLEN'(seq_vlmul), XLEN'(sb_vlmul[sb_head]));
      check("vxrm", XLEN'(seq_vxrm), XLEN'(sb_vxrm[sb_head]));
      check("fop", XLEN'(seq_fop), XLEN'(sb_fop[sb_head]));
      check("frm", XLEN'(seq_frm), XLEN'(sb_frm[sb_head]));
      check("eew", XLEN'(seq_eew), XLEN'(sb_eew[sb_head]));
      sb_head = (sb_head + 1) % SbDepth;
      launched++;
    end
  endtask  // Automatic

  // Pending work model
  task automatic check_pending();
    logic exp_load;
    logic exp_store;
    exp_load  = 1'b0;
    exp_store = 1'b0;
    for (int i = 0; i < inflight.size(); i++) begin
      if (inflight[i] == int'(VEC_LOAD)) exp_load = 1'b1;
      if (inflight[i] == int'(VEC_STORE)) exp_store = 1'b1;
    end
    check("load pending", XLEN'(load_pending), XLEN'(exp_load));
    check("store pending", XLEN'(store_pending), XLEN'(exp_store));
  endtask  // Automatic

  // Invariants every cycle
  task automatic check_invariants();
    check("start while busy", XLEN'(seq_start && seq_busy), '0);
    check("idle while running", XLEN'(vec_idle && (seq_start || seq_busy)), '0);
    check("hold while idle", XLEN'(vec_hold && vec_idle && !writes_xreg), '0);
    check("hold with no instruction", XLEN'(vec_hold && !instr_valid), '0);
  endtask  // Automatic

  task automatic check_launches();
    check("all accepted launched", XLEN'(launched), XLEN'(accepted));
  endtask  // Automatic

  // Scramble live config
  task automatic scramble_config();
    vl    = VlW'($urandom);
    vsew  = 3'($urandom_range(2));
    vlmul = 3'($urandom);
    vxrm  = 2'($urandom);
    frm   = RmW'($urandom);
    fop   = vec_fop_e'($urandom_range(int'(VEC_FMV)));
  endtask  // Automatic

  // The one primitive
  task automatic present(input vec_op_e o, input vec_src_e s, input logic [AWIDTH-1:0] a1,
                         input logic [AWIDTH-1:0] a2, input logic [AWIDTH-1:0] ad, input logic m,
                         input logic rvd, input logic [4:0] im, input logic [XLEN-1:0] xd,
                         input logic drop);
    op          = o;
    src         = s;
    vs1         = a1;
    vs2         = a2;
    vd          = ad;
    vm          = m;
    reads_vd    = rvd;
    simm        = im;
    xdata       = xd;
    xstride     = XLEN'($urandom);
    eew         = vec_eew_e'($urandom_range(3));
    cancel      = drop;
    instr_valid = 1'b1;
    do @(posedge clk); while (vec_hold);
    @(negedge clk);
    instr_valid = 1'b0;
    cancel      = 1'b0;
    scramble_config();
  endtask  // Automatic

  task automatic present_simple(input vec_op_e o, input vec_src_e s, input int a1, input int a2,
                                input int ad, input logic drop);
    present(o, s, AWIDTH'(a1), AWIDTH'(a2), AWIDTH'(ad), 1'b1, 1'b0, '0, '0, drop);
  endtask  // Automatic

  function automatic vec_op_e random_op();
    case ($urandom_range(
        3
    ))
      0: return VEC_LOAD;
      1: return VEC_STORE;
      default: return vec_op_e'($urandom_range(15));
    endcase
  endfunction

  task automatic present_random();
    present(random_op(), vec_src_e'($urandom_range(2)), AWIDTH'($urandom), AWIDTH'($urandom),
            AWIDTH'($urandom), 1'($urandom), 1'($urandom), 5'($urandom), XLEN'($urandom),
            $urandom_range(7) == 0);
  endtask  // Automatic

  // Scalar move
  task automatic drive_xreg(input int src2);
    op          = VEC_MV_X_S;
    src         = VEC_SRC_VV;
    eew         = VEC_EEW_SAME;
    writes_xreg = 1'b1;
    vs1         = AWIDTH'(0);
    vs2         = AWIDTH'(src2);
    vd          = AWIDTH'(1);
    vm          = 1'b1;
    reads_vd    = 1'b0;
    vl          = VlW'(4);
    instr_valid = 1'b1;
  endtask  // Automatic

  task automatic end_xreg();
    instr_valid = 1'b0;
    writes_xreg = 1'b0;
    op          = VEC_ADD;
  endtask  // Automatic

  task automatic wait_release();
    do @(negedge clk); while (vec_hold);
  endtask  // Automatic

  task automatic gap(input int n);
    repeat (n) @(negedge clk);
  endtask  // Automatic

  // Drain the unit
  task automatic settle();
    int guard;
    guard = 0;
    while (!vec_idle && guard < IdleTimeout) begin
      @(negedge clk);
      guard++;
    end
    check("went idle", XLEN'(vec_idle), XLEN'(1'b1));
  endtask  // Automatic

  // Empty slot accepts
  task automatic test_empty_accepts();
    settle();
    instr_valid = 1'b1;
    @(posedge clk);
    check("empty slot no hold", XLEN'(vec_hold), '0);
    @(negedge clk);
    instr_valid = 1'b0;
  endtask  // Automatic

  // Hold when full
  task automatic test_hold_when_full();
    settle();
    run_len = 12;
    present_simple(VEC_ADD, VEC_SRC_VV, 1, 2, 3, 1'b0);
    present_simple(VEC_SUB, VEC_SRC_VV, 4, 5, 6, 1'b0);
    instr_valid = 1'b1;
    op = VEC_XOR;
    @(posedge clk);
    check("full slot hold", XLEN'(vec_hold), XLEN'(1'b1));
    while (vec_hold) @(posedge clk);
    @(negedge clk);
    instr_valid = 1'b0;
    scramble_config();
    settle();
    run_len = 3;
  endtask  // Automatic

  // Core disabled freezes
  task automatic test_core_off();
    settle();
    core_en = 1'b0;
    instr_valid = 1'b1;
    op = VEC_OR;
    repeat (4) @(negedge clk);
    check("disabled stays idle", XLEN'(vec_idle), XLEN'(1'b1));
    instr_valid = 1'b0;
    @(negedge clk);
    core_en = 1'b1;
    @(negedge clk);
  endtask  // Automatic

  // Trapped instruction dropped
  task automatic test_cancel();
    int launch0;
    settle();
    launch0 = launched;
    present_simple(VEC_STORE, VEC_SRC_NONE, 1, 2, 3, 1'b1);
    gap(3);
    check("cancel launched", XLEN'(launched), XLEN'(launch0));
    check("cancel idle", XLEN'(vec_idle), XLEN'(1'b1));
    check("cancel store pending", XLEN'(store_pending), '0);
  endtask  // Automatic

  // Memory flags set
  task automatic test_flags_on_entry();
    settle();
    run_len = 6;
    present_simple(VEC_LOAD, VEC_SRC_NONE, 1, 2, 3, 1'b0);
    check("load pending on entry", XLEN'(load_pending), XLEN'(1'b1));
    present_simple(VEC_STORE, VEC_SRC_NONE, 1, 2, 3, 1'b0);
    check("store pending on entry", XLEN'(store_pending), XLEN'(1'b1));
    settle();
    check("load cleared", XLEN'(load_pending), '0);
    check("store cleared", XLEN'(store_pending), '0);
    run_len = 3;
  endtask  // Automatic

  // Zero length completes
  task automatic test_zero_length();
    settle();
    run_len = 0;
    vl = '0;
    present_simple(VEC_ADD, VEC_SRC_VV, 7, 8, 9, 1'b0);
    settle();
    run_len = 3;
    vl = VlW'(4);
  endtask  // Automatic

  // Scalar result waits
  task automatic test_xreg_wait();
    int guard;
    int launch0;
    settle();
    launch0 = launched;
    drive_xreg(3);
    wait_release();
    @(posedge clk);
    @(negedge clk);
    check("wait after accept", XLEN'(vec_hold), XLEN'(1'b1));
    guard = 0;
    while (vec_hold && guard < ReleaseTimeout) begin
      @(negedge clk);
      guard++;
    end
    end_xreg();
    check("wait released", XLEN'(vec_hold), '0);
    settle();
    check("one launch per wait", XLEN'(launched - launch0), XLEN'(2));
  endtask  // Automatic

  // Stalled result release
  task automatic test_xreg_stall();
    int launch0;
    settle();
    launch0 = launched;
    drive_xreg(5);
    wait_release();
    instr_valid = 1'b0;
    ex_adv = 1'b0;
    repeat (2) @(negedge clk);
    instr_valid = 1'b1;
    repeat (3) begin
      @(posedge clk);
      check("stalled result no hold", XLEN'(vec_hold), '0);
      check("stalled result no start", XLEN'(seq_start), '0);
    end
    @(negedge clk);
    ex_adv = 1'b1;
    @(negedge clk);
    end_xreg();
    settle();
    check("one launch across stall", XLEN'(launched - launch0), XLEN'(1));
  endtask  // Automatic

  // Random traffic
  task automatic soak(input int n);
    repeat (n) begin
      run_len = $urandom_range(8);
      present_random();
      if ($urandom_range(3) == 0) gap($urandom_range(5));
    end
    run_len = 3;
    settle();
  endtask  // Automatic

  function automatic logic [(1<<AWIDTH)-1:0] ref_group(input int base, input int regs);
    logic [(1<<AWIDTH)-1:0] bits;
    for (int i = 0; i < (1 << AWIDTH); i++) bits[i] = (i >= base) && (i < base + regs);
    return bits;
  endfunction

  function automatic vec_op_e soak_op();
    case ($urandom_range(
        7
    ))
      0: return VEC_LOAD;
      1: return VEC_STORE;
      2: return VEC_SLIDEUP;
      3: return VEC_SLIDEDOWN;
      4: return VEC_SLIDE1UP;
      5: return VEC_SLIDE1DOWN;
      default: return vec_op_e'($urandom_range(15));
    endcase
  endfunction

  // Every input random
  task automatic test_cycle_soak(input int cycles);
    logic [(1<<AWIDTH)-1:0] m_busy, need;
    logic mq_valid, mq_xreg, mq_vm, me_valid, me_load, me_store, mx_pend, mx_spent, m_start;
    vec_op_e mq_op, ms_op;
    vec_src_e mq_src, ms_src;
    vec_eew_e mq_eew, ms_eew;
    vec_fop_e mq_fop, ms_fop;
    logic [AWIDTH-1:0] mq_vs1, mq_vs2, mq_vd, mq_rd1, ms_vs1, ms_vs2, ms_vd;
    logic [AWIDTH:0] mq_wr, mq_r1n, mq_r2n;
    logic mq_rvd, ms_rvd, ms_vm;
    logic [4:0] mq_simm, ms_simm;
    logic [XLEN-1:0] mq_xd, mq_xs, ms_xd, ms_xs;
    logic [VlW-1:0] mq_vl, ms_vl;
    logic [2:0] mq_vsew, mq_vlmul, ms_vsew, ms_vlmul;
    logic [1:0] mq_vxrm, ms_vxrm;
    logic [RmW-1:0] mq_frm, ms_frm;
    logic ready, port, launch, xwait, accept, hold, seqb, seqd, adv, m_any;
    soak_on = 1'b1;
    do_reset();
    m_busy   = '0;
    mq_valid = 1'b0;
    me_valid = 1'b0;
    mx_pend  = 1'b0;
    mx_spent = 1'b0;
    m_start  = 1'b0;
    m_any    = 1'b0;
    for (int c = 0; c < cycles; c++) begin
      core_en     = $urandom_range(4) != 0;
      instr_valid = $urandom_range(3) != 0;
      cancel      = $urandom_range(7) == 0;
      ex_adv      = 1'($urandom);
      op          = soak_op();
      src         = vec_src_e'($urandom_range(3));
      eew         = vec_eew_e'($urandom_range(3));
      writes_xreg = $urandom_range(5) == 0;
      vs1         = AWIDTH'($urandom);
      vs2         = AWIDTH'($urandom);
      vd          = AWIDTH'($urandom);
      vm          = 1'($urandom);
      reads_vd    = 1'($urandom);
      simm        = 5'($urandom);
      xdata       = XLEN'($urandom);
      xstride     = XLEN'($urandom);
      wr_regs     = (AWIDTH + 1)'($urandom_range(8));
      rd1         = AWIDTH'($urandom);
      rd1_regs    = (AWIDTH + 1)'($urandom_range(8));
      rd2_regs    = (AWIDTH + 1)'($urandom_range(8));
      pipe_busy   = $urandom_range(2) == 0;
      clear       = 1'($urandom);
      clear_addr  = AWIDTH'($urandom);
      for (int t = 0; t < 4; t++) if (!m_busy[clear_addr]) clear_addr = AWIDTH'($urandom);
      run_len = $urandom_range(5);
      scramble_config();
      #1;
      seqb = seq_busy;
      seqd = seq_done;
      need = ref_group(int'(mq_vd), int'(mq_wr)) | ref_group(int'(mq_rd1), int'(mq_r1n)) |
          ref_group(int'(mq_vs2), int'(mq_r2n)) | (1 << AWIDTH)'(!mq_vm);
      ready = (m_busy & need) == '0;
      port   = (mq_op == VEC_LOAD) || (mq_op == VEC_SLIDEUP) || (mq_op == VEC_SLIDEDOWN) ||
          (mq_op == VEC_SLIDE1UP) || (mq_op == VEC_SLIDE1DOWN);
      launch = mq_valid && !me_valid && ready && !(port && pipe_busy);
      xwait = (mq_valid && mq_xreg) || mx_pend;
      accept = instr_valid && !cancel && !xwait && !mx_spent && (!mq_valid || launch);
      hold   = (instr_valid && (xwait || writes_xreg) && !mx_spent) ||
          (instr_valid && mq_valid && !launch);
      adv = ex_adv && !hold;
      check("soak hold", XLEN'(vec_hold), XLEN'(hold));
      check("soak idle", XLEN'(vec_idle), XLEN'(!mq_valid && !me_valid && !seqb && (m_busy == '0)));
      check("soak load pending", XLEN'(load_pending),
            XLEN'((mq_valid && mq_op == VEC_LOAD) || (me_valid && me_load)));
      check("soak store pending", XLEN'(store_pending),
            XLEN'((mq_valid && mq_op == VEC_STORE) || (me_valid && me_store)));
      check("soak start", XLEN'(seq_start), XLEN'(m_start));
      if (m_any) begin
        check("soak op", XLEN'(seq_op), XLEN'(ms_op));
        check("soak src", XLEN'(seq_src), XLEN'(ms_src));
        check("soak eew", XLEN'(seq_eew), XLEN'(ms_eew));
        check("soak vs1", XLEN'(seq_vs1), XLEN'(ms_vs1));
        check("soak vs2", XLEN'(seq_vs2), XLEN'(ms_vs2));
        check("soak vd", XLEN'(seq_vd), XLEN'(ms_vd));
        check("soak vm", XLEN'(seq_vm), XLEN'(ms_vm));
        check("soak reads_vd", XLEN'(seq_reads_vd), XLEN'(ms_rvd));
        check("soak simm", XLEN'(seq_simm), XLEN'(ms_simm));
        check("soak xdata", seq_xdata, ms_xd);
        check("soak xstride", seq_xstride, ms_xs);
        check("soak vl", XLEN'(seq_vl), XLEN'(ms_vl));
        check("soak vsew", XLEN'(seq_vsew), XLEN'(ms_vsew));
        check("soak vlmul", XLEN'(seq_vlmul), XLEN'(ms_vlmul));
        check("soak vxrm", XLEN'(seq_vxrm), XLEN'(ms_vxrm));
        check("soak fop", XLEN'(seq_fop), XLEN'(ms_fop));
        check("soak frm", XLEN'(seq_frm), XLEN'(ms_frm));
      end
      if (core_en) begin
        m_start  = 1'b0;
        mx_spent = (seqd && mx_pend) || (mx_spent && !adv);
        if (launch && mq_xreg) mx_pend = 1'b1;
        else if (seqd) mx_pend = 1'b0;
        m_busy = m_busy & ~((1 << AWIDTH)'(clear) << clear_addr);
        if (launch) begin
          m_busy   = m_busy | ref_group(int'(mq_vd), int'(mq_wr));
          m_start  = 1'b1;
          m_any    = 1'b1;
          me_valid = 1'b1;
          me_load  = mq_op == VEC_LOAD;
          me_store = mq_op == VEC_STORE;
          ms_op    = mq_op;
          ms_src   = mq_src;
          ms_eew   = mq_eew;
          ms_vs1   = mq_vs1;
          ms_vs2   = mq_vs2;
          ms_vd    = mq_vd;
          ms_vm    = mq_vm;
          ms_rvd   = mq_rvd;
          ms_simm  = mq_simm;
          ms_xd    = mq_xd;
          ms_xs    = mq_xs;
          ms_vl    = mq_vl;
          ms_vsew  = mq_vsew;
          ms_vlmul = mq_vlmul;
          ms_vxrm  = mq_vxrm;
          ms_fop   = mq_fop;
          ms_frm   = mq_frm;
          mq_valid = 1'b0;
        end
        if (accept) begin
          mq_valid = 1'b1;
          mq_op    = op;
          mq_src   = src;
          mq_eew   = eew;
          mq_xreg  = writes_xreg;
          mq_vs1   = vs1;
          mq_vs2   = vs2;
          mq_vd    = vd;
          mq_vm    = vm;
          mq_rvd   = reads_vd;
          mq_simm  = simm;
          mq_xd    = xdata;
          mq_xs    = xstride;
          mq_vl    = vl;
          mq_vsew  = vsew;
          mq_vlmul = vlmul;
          mq_vxrm  = vxrm;
          mq_fop   = fop;
          mq_frm   = frm;
          mq_wr    = wr_regs;
          mq_rd1   = rd1;
          mq_r1n   = rd1_regs;
          mq_r2n   = rd2_regs;
        end
        if (seqd) me_valid = 1'b0;
      end
      @(negedge clk);
    end
    do_reset();
    soak_on = 1'b0;
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
    do_reset();

    test_empty_accepts();
    test_hold_when_full();
    test_core_off();
    test_zero_length();
    test_cancel();
    test_flags_on_entry();
    test_xreg_wait();
    test_xreg_stall();
    soak(400);

    check_launches();
    test_cycle_soak(SoakCycles);
    do_verdict();
  end

  // Sequencer stand in
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      seq_busy  <= 1'b0;
      seq_done  <= 1'b0;
      seq_ticks <= 0;
    end else if (core_en) begin
      seq_done <= 1'b0;
      if (!seq_busy) begin
        if (seq_start) begin
          if (run_len == 0) begin
            seq_done <= 1'b1;
          end else begin
            seq_busy  <= 1'b1;
            seq_ticks <= run_len;
          end
        end
      end else if (seq_ticks <= 1) begin
        seq_busy <= 1'b0;
        seq_done <= 1'b1;
      end else begin
        seq_ticks <= seq_ticks - 1;
      end
    end
  end

  // Entry from handshake
  always @(posedge clk) begin
    if (rst_n && core_en && !soak_on) begin
      check_invariants();
      check_pending();
      if (seq_done) void'(inflight.pop_front());
      if (instr_valid && !cancel && !taken && (!vec_hold || writes_xreg)) begin
        sb_push();
        inflight.push_back(int'(op));
        taken = 1'b1;
      end
      if (ex_adv && !vec_hold) taken = 1'b0;
      if (seq_start) sb_check();
    end
  end

endmodule

`default_nettype wire
