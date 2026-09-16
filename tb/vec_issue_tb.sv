`default_nettype none

module vec_issue_tb
  import vec_pkg::*;
();

  localparam int AWIDTH = 5;
  localparam int SbDepth = 8;

  int checks = 0;
  int errors = 0;

  logic clk = 1'b0;
  logic rst_n;
  logic core_en;

  logic instr_valid;
  logic cancel;
  vec_op_e op;
  vec_src_e src;
  logic [AWIDTH-1:0] vs1;
  logic [AWIDTH-1:0] vs2;
  logic [AWIDTH-1:0] vd;
  logic vm;
  logic reads_vd;
  logic [4:0] simm;
  logic [31:0] xdata;
  logic [31:0] xstride;
  logic [7:0] vl;
  logic [2:0] vsew;
  logic [2:0] vlmul;
  logic [1:0] vxrm;

  logic seq_busy;
  logic seq_done;
  logic seq_start;
  vec_op_e seq_op;
  vec_src_e seq_src;
  logic [AWIDTH-1:0] seq_vs1;
  logic [AWIDTH-1:0] seq_vs2;
  logic [AWIDTH-1:0] seq_vd;
  logic seq_vm;
  logic seq_reads_vd;
  logic [4:0] seq_simm;
  logic [31:0] seq_xdata;
  logic [31:0] seq_xstride;
  logic [7:0] seq_vl;
  logic [2:0] seq_vsew;
  logic [2:0] seq_vlmul;
  logic [1:0] seq_vxrm;
  logic vec_hold;
  logic vec_idle;
  logic load_pending;
  logic store_pending;

  int run_len = 3;

  always #5 clk = ~clk;

  vec_issue #(
      .AWIDTH(AWIDTH)
  ) dut (
      .clk(clk),
      .rst_n(rst_n),
      .core_en(core_en),
      .instr_valid(instr_valid),
      .cancel(cancel),
      .op(op),
      .src(src),
      .vs1(vs1),
      .vs2(vs2),
      .vd(vd),
      .vm(vm),
      .reads_vd(reads_vd),
      .simm(simm),
      .xdata(xdata),
      .xstride(xstride),
      .vl(vl),
      .vsew(vsew),
      .vlmul(vlmul),
      .vxrm(vxrm),
      .seq_busy(seq_busy),
      .seq_done(seq_done),
      .seq_start(seq_start),
      .seq_op(seq_op),
      .seq_src(seq_src),
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
      .vec_hold(vec_hold),
      .vec_idle(vec_idle),
      .load_pending(load_pending),
      .store_pending(store_pending)
  );

  // Sequencer stand in
  int seq_ticks;
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      seq_busy  <= 1'b0;
      seq_done  <= 1'b0;
      seq_ticks <= 0;
    end else begin
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

  // Snapshot scoreboard
  vec_op_e sb_op[SbDepth];
  vec_src_e sb_src[SbDepth];
  logic [AWIDTH-1:0] sb_vs1[SbDepth];
  logic [AWIDTH-1:0] sb_vs2[SbDepth];
  logic [AWIDTH-1:0] sb_vd[SbDepth];
  logic sb_vm[SbDepth];
  logic sb_reads_vd[SbDepth];
  logic [4:0] sb_simm[SbDepth];
  logic [31:0] sb_xdata[SbDepth];
  logic [31:0] sb_xstride[SbDepth];
  logic [7:0] sb_vl[SbDepth];
  logic [2:0] sb_vsew[SbDepth];
  logic [2:0] sb_vlmul[SbDepth];
  logic [1:0] sb_vxrm[SbDepth];

  int sb_head = 0;
  int sb_tail = 0;
  int accepted = 0;
  int launched = 0;

  task automatic note(input string what, input logic [31:0] got, input logic [31:0] want);
    checks = checks + 1;
    if (got !== want) begin
      errors = errors + 1;
      if (errors < 20) $display("FAIL %0s got=%h want=%h at %0t", what, got, want, $time);
    end
  endtask

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
    sb_tail              = (sb_tail + 1) % SbDepth;
    accepted             = accepted + 1;
  endtask

  task automatic sb_check();
    if (sb_head == sb_tail) begin
      errors = errors + 1;
      $display("FAIL start with empty scoreboard at %0t", $time);
    end else begin
      note("op", 32'(sb_op[sb_head]), 32'(seq_op));
      note("src", 32'(sb_src[sb_head]), 32'(seq_src));
      note("vs1", 32'(sb_vs1[sb_head]), 32'(seq_vs1));
      note("vs2", 32'(sb_vs2[sb_head]), 32'(seq_vs2));
      note("vd", 32'(sb_vd[sb_head]), 32'(seq_vd));
      note("vm", 32'(sb_vm[sb_head]), 32'(seq_vm));
      note("reads_vd", 32'(sb_reads_vd[sb_head]), 32'(seq_reads_vd));
      note("simm", 32'(sb_simm[sb_head]), 32'(seq_simm));
      note("xdata", sb_xdata[sb_head], seq_xdata);
      note("xstride", sb_xstride[sb_head], seq_xstride);
      note("vl", 32'(sb_vl[sb_head]), 32'(seq_vl));
      note("vsew", 32'(sb_vsew[sb_head]), 32'(seq_vsew));
      note("vlmul", 32'(sb_vlmul[sb_head]), 32'(seq_vlmul));
      note("vxrm", 32'(sb_vxrm[sb_head]), 32'(seq_vxrm));
      sb_head  = (sb_head + 1) % SbDepth;
      launched = launched + 1;
    end
  endtask

  // Pending work model
  int inflight[$];

  task automatic check_pending();
    logic want_load;
    logic want_store;
    want_load  = 1'b0;
    want_store = 1'b0;
    for (int i = 0; i < inflight.size(); i++) begin
      if (inflight[i] == int'(VEC_LOAD)) want_load = 1'b1;
      if (inflight[i] == int'(VEC_STORE)) want_store = 1'b1;
    end
    note("load pending", 32'(load_pending), 32'(want_load));
    note("store pending", 32'(store_pending), 32'(want_store));
  endtask

  // Invariants every cycle
  task automatic check_invariants();
    checks = checks + 1;
    if (seq_start && seq_busy) begin
      errors = errors + 1;
      $display("FAIL start while busy at %0t", $time);
    end
    checks = checks + 1;
    if (vec_idle && (seq_start || seq_busy)) begin
      errors = errors + 1;
      $display("FAIL idle while running at %0t", $time);
    end
    checks = checks + 1;
    if (vec_hold && vec_idle) begin
      errors = errors + 1;
      $display("FAIL hold while idle at %0t", $time);
    end
    checks = checks + 1;
    if (vec_hold && !instr_valid) begin
      errors = errors + 1;
      $display("FAIL hold with no instruction at %0t", $time);
    end
  endtask

  always @(posedge clk) begin
    if (rst_n && core_en) begin
      check_invariants();
      check_pending();
      if (seq_done) void'(inflight.pop_front());
      if (instr_valid && !vec_hold && !cancel) begin
        sb_push();
        inflight.push_back(int'(op));
      end
      if (seq_start) sb_check();
    end
  end

  task automatic init_signals();
    rst_n       = 1'b0;
    core_en     = 1'b1;
    instr_valid = 1'b0;
    cancel      = 1'b0;
    xstride     = '0;
    op          = VEC_ADD;
    src         = VEC_SRC_VV;
    vs1         = '0;
    vs2         = '0;
    vd          = '0;
    vm          = 1'b1;
    reads_vd    = 1'b0;
    simm        = '0;
    xdata       = '0;
    vl          = 8'd4;
    vsew        = 3'd2;
    vlmul       = 3'd0;
    vxrm        = 2'd0;
    repeat (3) @(negedge clk);
    rst_n = 1'b1;
    @(negedge clk);
  endtask

  // Scramble live config
  task automatic scramble_config();
    vl    = 8'($urandom);
    vsew  = 3'($urandom % 3);
    vlmul = 3'($urandom);
    vxrm  = 2'($urandom);
  endtask

  // The one primitive
  task automatic present(input vec_op_e o, input vec_src_e s, input logic [AWIDTH-1:0] a1,
                         input logic [AWIDTH-1:0] a2, input logic [AWIDTH-1:0] ad, input logic m,
                         input logic rvd, input logic [4:0] im, input logic [31:0] xd);
    @(negedge clk);
    op          = o;
    src         = s;
    vs1         = a1;
    vs2         = a2;
    vd          = ad;
    vm          = m;
    reads_vd    = rvd;
    simm        = im;
    xdata       = xd;
    xstride     = $urandom;
    instr_valid = 1'b1;
    #1;
    while (vec_hold) @(negedge clk);
    @(posedge clk);
    #1 instr_valid = 1'b0;
    cancel = 1'b0;
    scramble_config();
  endtask

  function automatic vec_op_e random_op();
    case ($urandom % 4)
      0: return VEC_LOAD;
      1: return VEC_STORE;
      default: return vec_op_e'($urandom % 16);
    endcase
  endfunction

  task automatic present_random();
    cancel = (($urandom % 8) == 0);
    present(random_op(), vec_src_e'($urandom % 3), AWIDTH'($urandom), AWIDTH'($urandom),
            AWIDTH'($urandom), 1'($urandom), 1'($urandom), 5'($urandom), $urandom);
  endtask

  task automatic gap(input int n);
    repeat (n) @(negedge clk);
  endtask

  // Drain the unit
  task automatic settle();
    int guard;
    begin
      guard = 0;
      while (!vec_idle && guard < 200) begin
        @(negedge clk);
        guard = guard + 1;
      end
      checks = checks + 1;
      if (!vec_idle) begin
        errors = errors + 1;
        $display("FAIL never went idle at %0t", $time);
      end
    end
  endtask

  // Empty slot accepts
  task automatic check_empty_accepts();
    settle();
    @(negedge clk);
    instr_valid = 1'b1;
    #1;
    checks = checks + 1;
    if (vec_hold) begin
      errors = errors + 1;
      $display("FAIL held on an empty slot at %0t", $time);
    end
    @(posedge clk);
    #1 instr_valid = 1'b0;
  endtask

  // Hold when full
  task automatic check_hold_when_full();
    settle();
    run_len = 12;
    present(VEC_ADD, VEC_SRC_VV, 5'd1, 5'd2, 5'd3, 1'b1, 1'b0, 5'd0, 32'd0);
    present(VEC_SUB, VEC_SRC_VV, 5'd4, 5'd5, 5'd6, 1'b1, 1'b0, 5'd0, 32'd0);
    @(negedge clk);
    instr_valid = 1'b1;
    op = VEC_XOR;
    #1;
    checks = checks + 1;
    if (!vec_hold) begin
      errors = errors + 1;
      $display("FAIL no hold on a full slot at %0t", $time);
    end
    while (vec_hold) @(negedge clk);
    @(posedge clk);
    #1 instr_valid = 1'b0;
    scramble_config();
    settle();
    run_len = 3;
  endtask

  // Core disabled freezes
  task automatic check_core_off();
    settle();
    @(negedge clk);
    core_en = 1'b0;
    instr_valid = 1'b1;
    op = VEC_OR;
    repeat (4) @(negedge clk);
    checks = checks + 1;
    if (!vec_idle) begin
      errors = errors + 1;
      $display("FAIL accepted while disabled at %0t", $time);
    end
    instr_valid = 1'b0;
    @(negedge clk);
    core_en = 1'b1;
    @(negedge clk);
  endtask

  // Trapped instruction dropped
  task automatic check_cancel();
    int taken;
    settle();
    taken  = accepted;
    cancel = 1'b1;
    present(VEC_STORE, VEC_SRC_NONE, 5'd1, 5'd2, 5'd3, 1'b1, 1'b0, 5'd0, 32'd0);
    gap(3);
    note("cancel accepted", 32'(accepted), 32'(taken));
    note("cancel idle", 32'(vec_idle), 32'd1);
    note("cancel store pending", 32'(store_pending), 32'd0);
  endtask

  // Memory flags set
  task automatic check_flags_on_entry();
    settle();
    run_len = 6;
    present(VEC_LOAD, VEC_SRC_NONE, 5'd1, 5'd2, 5'd3, 1'b1, 1'b0, 5'd0, 32'd0);
    note("load pending on entry", 32'(load_pending), 32'd1);
    present(VEC_STORE, VEC_SRC_NONE, 5'd1, 5'd2, 5'd3, 1'b1, 1'b0, 5'd0, 32'd0);
    note("store pending on entry", 32'(store_pending), 32'd1);
    settle();
    note("load cleared", 32'(load_pending), 32'd0);
    note("store cleared", 32'(store_pending), 32'd0);
    run_len = 3;
  endtask

  // Zero length completes
  task automatic check_zero_length();
    settle();
    run_len = 0;
    vl = 8'd0;
    present(VEC_ADD, VEC_SRC_VV, 5'd7, 5'd8, 5'd9, 1'b1, 1'b0, 5'd0, 32'd0);
    settle();
    run_len = 3;
    vl = 8'd4;
  endtask

  // Random traffic
  task automatic soak(input int n);
    for (int i = 0; i < n; i++) begin
      run_len = int'($urandom % 9);
      present_random();
      if (($urandom % 4) == 0) gap(int'($urandom % 6));
    end
    run_len = 3;
    settle();
  endtask

  task automatic verdict();
    checks = checks + 1;
    if (accepted != launched) begin
      errors = errors + 1;
      $display("FAIL accepted %0d launched %0d", accepted, launched);
    end
    $display("vec_issue: %0d checks, %0d errors, %0d instructions", checks, errors, launched);
    if (errors != 0) $fatal(1, "vec_issue FAILED");
    $finish;
  endtask

  initial begin
    // Quiet start
    init_signals();

    // Empty slot accepts
    check_empty_accepts();

    // Hold when full
    check_hold_when_full();

    // Core disabled freezes
    check_core_off();

    // Zero length completes
    check_zero_length();

    // Trapped instruction dropped
    check_cancel();

    // Memory flags set
    check_flags_on_entry();

    // Random traffic
    soak(400);

    verdict();
  end

endmodule

`default_nettype wire
