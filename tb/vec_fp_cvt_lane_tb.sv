`default_nettype none

module vec_fp_cvt_lane_tb
  import vec_pkg::*;
  import fp_pkg::RmRne, fp_pkg::RmRtz, fp_pkg::RmRdn, fp_pkg::RmRup, fp_pkg::RmRmm;
  import fp_pkg::FlagNv, fp_pkg::FlagNx;
  import fp_pkg::FLEN, fp_pkg::ExpW, fp_pkg::FracW, fp_pkg::SigW, fp_pkg::Bias;
();

  localparam int HalfW = FLEN / 2;
  localparam int FlagW = fp_pkg::FlagW;
  localparam int RmW = fp_pkg::RmW;
  localparam int Latency = VecFpLatency;
  localparam int MinChecks = 520_000;
  localparam int SweepStallPct = 25;
  localparam int FileStallPct = 10;
  localparam int SweepW = 16;
  localparam int BuiltOps = 4096;
  localparam int RefW = FracW + FLEN + 3;
  localparam string TfDir = "build/testfloat/";

  localparam real NarrowMag = real'(longint'(1) << (HalfW - 1));
  localparam real UnsMag = real'(longint'(1) << HalfW);
  localparam logic [FLEN-1:0] Inf = FLEN'(fp_pkg::fp_inf_mag(ExpW, FracW));
  localparam logic [FLEN-1:0] QNan = Inf | (FLEN'(1) << (FracW - 1));
  localparam logic [FLEN-1:0] SNan = Inf | FLEN'(1);
  localparam logic [FLEN-1:0] Sign = FLEN'(1) << (FLEN - 1);
  localparam logic [FLEN-1:0] One = FLEN'(Bias) << FracW;
  localparam logic [FLEN-1:0] NarrowMax = (FLEN'(1) << (HalfW - 1)) - 1;
  localparam logic [FLEN-1:0] NarrowMin = FLEN'(1) << (HalfW - 1);
  localparam logic [FLEN-1:0] NarrowUMax = (FLEN'(1) << HalfW) - 1;
  localparam logic [FLEN-1:0] Junk = {(FLEN / 8) {8'hA5}} << HalfW;

  typedef struct packed {
    vec_fop_e op;
    vec_eew_e eew;
    logic [2:0] vsew;
    logic [RmW-1:0] rm;
    logic [FLEN-1:0] a;
  } op_info_t;

  int checks = 0;
  int errors = 0;
  int max_errors = 0;
  int stall_pct = 0;
  int en_cycle = 0;
  int seed = 11;

  logic clk = 1'b0;
  logic rst_n = 1'b0;
  logic core_en;
  logic valid;
  vec_fop_e op;
  vec_eew_e eew;
  logic [2:0] vsew;
  logic [RmW-1:0] rm;
  logic [FLEN-1:0] a;
  logic [FLEN-1:0] result;
  logic [FlagW-1:0] fflags;
  logic result_valid;

  logic [FLEN-1:0] q_res[$];
  logic [FlagW-1:0] q_flags[$];
  int q_issue[$];
  logic [$bits(op_info_t)-1:0] q_info[$];
  string q_src[$];

  logic [RmW-1:0] modes[5] = '{RmRne, RmRtz, RmRdn, RmRup, RmRmm};
  string rms[5] = '{"rne", "rtz", "rdn", "rup", "rmm"};

  always #5 clk = ~clk;

  vec_fp_cvt_lane dut (
      .clk(clk),
      .rst_n(rst_n),
      .core_en(core_en),
      .valid(valid),
      .op(op),
      .eew(eew),
      .vsew(vsew),
      .rm(rm),
      .a(a),
      .result(result),
      .fflags(fflags),
      .result_valid(result_valid)
  );

  task automatic check(input string name, input logic [FLEN-1:0] got, input logic [FLEN-1:0] exp);
    checks++;
    if (got !== exp) begin
      errors++;
      $display("FAIL %s: got %h, expected %h", name, got, exp);
      if (errors == max_errors) $fatal(1, "TB STOPPED: %0d mismatches", errors);
    end
  endtask  // Automatic

  task automatic do_reset(input int cycles);
    rst_n = 1'b0;
    core_en = 1'b1;
    valid = 1'b0;
    op = VEC_FCVT_X_F;
    eew = VEC_EEW_SAME;
    vsew = FpSew;
    rm = RmRne;
    a = '0;
    q_res.delete();
    q_flags.delete();
    q_issue.delete();
    q_info.delete();
    q_src.delete();
    repeat (cycles) tick();
    rst_n = 1'b1;
    tick();
  endtask  // Automatic

  task automatic seed_random();
    void'($urandom(seed));
  endtask  // Automatic

  task automatic tick();
    logic was_en;
    logic [FLEN-1:0] prev_res;
    logic [FlagW-1:0] prev_flags;
    logic prev_vld;
    was_en = core_en;
    prev_res = result;
    prev_flags = fflags;
    prev_vld = result_valid;
    @(posedge clk);
    @(negedge clk);
    if (!rst_n) begin
      check("result_valid in reset", FLEN'(result_valid), '0);
    end else if (!was_en) begin
      check("result held with core_en low", result, prev_res);
      check("fflags held with core_en low", FLEN'(fflags), FLEN'(prev_flags));
      check("result_valid held with core_en low", FLEN'(result_valid), FLEN'(prev_vld));
    end else begin
      en_cycle++;
      check_retire();
    end
  endtask  // Automatic

  task automatic check_retire();
    logic exp_valid;
    logic [FLEN-1:0] er;
    logic [FlagW-1:0] ef;
    op_info_t info;
    vec_fop_e fo;
    vec_eew_e fe;
    string name;
    exp_valid = q_issue.size() != 0 && (en_cycle - q_issue[0]) >= Latency;
    check($sformatf("result_valid at %0t", $time), FLEN'(result_valid), FLEN'(exp_valid));
    if (exp_valid) begin
      er = q_res.pop_front();
      ef = q_flags.pop_front();
      void'(q_issue.pop_front());
      info = op_info_t'(q_info.pop_front());
      fo = info.op;
      fe = info.eew;
      name = $sformatf(
          "%s %s %s sew=%0d rm=%0d a=%h",
          q_src.pop_front(),
          fo.name(),
          fe.name(),
          8 << info.vsew,
          info.rm,
          info.a
      );
      if (result_valid === 1'b1) begin
        check({name, " result"}, result, er);
        check({name, " fflags"}, FLEN'(fflags), FLEN'(ef));
      end
    end
  endtask  // Automatic

  task automatic stalls();
    while ($urandom_range(
        99
    ) < stall_pct) begin
      core_en = $urandom_range(3) != 0;
      valid   = 1'b0;
      if (!core_en) begin
        valid = 1'($urandom);
        op = vec_fop_e'(int'(VEC_FCVT_XU_F) + $urandom_range(5));
        eew = vec_eew_e'(($bits(vec_eew_e))'($urandom));
        a = rand_bits();
      end
      tick();
    end
  endtask  // Automatic

  task automatic send(input string src, input vec_fop_e o, input vec_eew_e e,
                      input logic [RmW-1:0] mode, input logic [FLEN-1:0] x,
                      input logic [FLEN-1:0] er, input logic [FlagW-1:0] ef);
    op_info_t info;
    logic [FLEN-1:0] mr;
    logic [FlagW-1:0] mf;
    stalls();
    ref_cvt(o, e, mode, x, mr, mf);
    check({src, " model result"}, mr, er);
    check({src, " model flags"}, FLEN'(mf), FLEN'(ef));
    core_en = 1'b1;
    valid = 1'b1;
    op = o;
    eew = e;
    vsew = (e == VEC_EEW_SAME) ? FpSew : FpHalfSew;
    rm = mode;
    a = x;
    q_res.push_back(er);
    q_flags.push_back(ef);
    q_issue.push_back(en_cycle);
    info.op = o;
    info.eew = e;
    info.vsew = vsew;
    info.rm = mode;
    info.a = x;
    q_info.push_back(info);
    q_src.push_back(src);
    tick();
    valid = 1'b0;
  endtask  // Automatic

  task automatic drain();
    core_en = 1'b1;
    valid   = 1'b0;
    repeat (Latency + 2) tick();
    check("results never arrived", FLEN'(q_res.size()), '0);
  endtask  // Automatic

  function automatic vec_fop_e to_int_op(input logic uns, input logic rtz);
    if (rtz && uns) to_int_op = VEC_FCVT_RTZ_XU_F;
    else if (rtz) to_int_op = VEC_FCVT_RTZ_X_F;
    else if (uns) to_int_op = VEC_FCVT_XU_F;
    else to_int_op = VEC_FCVT_X_F;
  endfunction

  // Float to integer
  task automatic run_to_int(input logic uns, input int m);
    int fd;
    int line;
    logic [FLEN-1:0] x;
    logic [FLEN-1:0] r;
    logic [FlagW-1:0] f;
    logic [FLEN-1:0] rn;
    logic [FlagW-1:0] fn;
    logic [RmW-1:0] mode;
    string path;
    string src;
    path = {TfDir, tf_fmt(), uns ? "_to_ui" : "_to_i", tf_int(), "_", rms[m], ".txt"};
    fd   = $fopen(path, "r");
    if (fd == 0) $fatal(1, "TB MISSING FILE: %s (run make testfloat)", path);
    line = 0;
    while ($fscanf(
        fd, "%h %h %h\n", x, r, f
    ) == 3) begin
      line++;
      src = $sformatf("%s:%0d", path, line);
      ref_narrow(x, uns, r, f, rn, fn);
      if (modes[m] == RmRtz) begin
        mode = modes[$urandom_range($size(modes)-1)];
        send(src, to_int_op(uns, 1'b1), VEC_EEW_SAME, mode, x, r, f);
        send(src, to_int_op(uns, 1'b1), VEC_EEW_NARROW, mode, x, rn, fn);
      end
      send(src, to_int_op(uns, 1'b0), VEC_EEW_SAME, modes[m], x, r, f);
      send(src, to_int_op(uns, 1'b0), VEC_EEW_NARROW, modes[m], x, rn, fn);
    end
    if (!$feof(fd)) $fatal(1, "TB BAD LINE: %s:%0d", path, line + 1);
    $fclose(fd);
    if (line == 0) $fatal(1, "TB EMPTY FILE: %s", path);
    $display("%s: %0d lines", path, line);
  endtask  // Automatic

  // Integer to float
  task automatic run_to_float(input logic uns, input int m);
    int fd;
    int line;
    logic [FLEN-1:0] x;
    logic [FLEN-1:0] r;
    logic [FlagW-1:0] f;
    logic [FLEN-1:0] xw;
    vec_fop_e o;
    string path;
    string src;
    path = {TfDir, uns ? "ui" : "i", tf_int(), "_to_", tf_fmt(), "_", rms[m], ".txt"};
    if (uns) o = VEC_FCVT_F_XU;
    else o = VEC_FCVT_F_X;
    fd = $fopen(path, "r");
    if (fd == 0) $fatal(1, "TB MISSING FILE: %s (run make testfloat)", path);
    line = 0;
    while ($fscanf(
        fd, "%h %h %h\n", x, r, f
    ) == 3) begin
      line++;
      src = $sformatf("%s:%0d", path, line);
      send(src, o, VEC_EEW_SAME, modes[m], x, r, f);
      xw = (rand_bits() << HalfW) | FLEN'(x[HalfW-1:0]);
      send(src, o, VEC_EEW_WIDEN, modes[m], xw, i2f_exact(x[HalfW-1:0], uns), '0);
    end
    if (!$feof(fd)) $fatal(1, "TB BAD LINE: %s:%0d", path, line + 1);
    $fclose(fd);
    if (line == 0) $fatal(1, "TB EMPTY FILE: %s", path);
    $display("%s: %0d lines", path, line);
  endtask  // Automatic

  task automatic run_testfloat(input int pct);
    stall_pct = pct;
    for (int m = 0; m < $size(modes); m++) begin
      run_to_int(1'b0, m);
      run_to_int(1'b1, m);
      run_to_float(1'b0, m);
      run_to_float(1'b1, m);
    end
  endtask  // Automatic

  // Every short integer
  task automatic sweep_widen();
    logic [FLEN-1:0] x;
    for (int i = 0; i < (1 << SweepW); i++) begin
      x = (rand_bits() << HalfW) | FLEN'(i);
      send("widen sweep", VEC_FCVT_F_X, VEC_EEW_WIDEN, modes[i%$size(modes)], x, i2f_exact(
           HalfW'(i), 1'b0), '0);
      send("widen sweep", VEC_FCVT_F_XU, VEC_EEW_WIDEN, modes[i%$size(modes)], x, i2f_exact(
           HalfW'(i), 1'b1), '0);
    end
  endtask  // Automatic

  // Floats from known integers
  task automatic run_built_to_int();
    logic uns;
    logic neg;
    logic [RmW-1:0] mode;
    logic [SigW-1:0] sig;
    logic [RefW-1:0] iv;
    logic [RefW-1:0] q;
    logic [RefW-1:0] half;
    logic [FLEN-1:0] x;
    logic [FLEN-1:0] er;
    logic [FlagW-1:0] ef;
    int lead;
    int sh;
    repeat (BuiltOps) begin
      uns  = 1'($urandom);
      neg  = 1'($urandom);
      mode = modes[$urandom_range($size(modes)-1)];
      sig  = SigW'(rand_bits()) | (SigW'(1) << FracW);
      if ($urandom_range(7) == 0) sig = '1;
      if (1'($urandom)) begin
        lead = $urandom_range(FracW - 1);
        sh   = FracW - lead;
        iv   = RefW'(sig >> sh);
        half = RefW'(1) << (sh - 1);
        case ($urandom_range(
            3
        ))
          0: q = '0;
          1: q = half;
          default: q = RefW'(rand_bits()) & ((RefW'(1) << sh) - 1);
        endcase
        x = {neg, ExpW'(Bias + lead), FracW'((iv << sh) | q)};
      end else begin
        sh = $urandom_range(FLEN - FracW + 1, 1);
        iv = RefW'(sig) << sh;
        half = RefW'(1);
        q = '0;
        x = {neg, ExpW'(Bias + FracW + sh), sig[FracW-1:0]};
      end
      iv = iv + RefW'(round_up(mode, neg, iv[0], q, half));
      built_int(iv, neg, uns, FLEN, q != '0, er, ef);
      send("built to int", to_int_op(uns, 1'b0), VEC_EEW_SAME, mode, x, er, ef);
      built_int(iv, neg, uns, HalfW, q != '0, er, ef);
      send("built to int", to_int_op(uns, 1'b0), VEC_EEW_NARROW, mode, x, er, ef);
    end
  endtask  // Automatic

  // Integers from known floats
  task automatic run_built_to_float();
    logic uns;
    logic neg;
    logic [RmW-1:0] mode;
    logic [SigW-1:0] sig;
    logic [FLEN-1:0] d;
    logic [FLEN-1:0] half;
    logic [FLEN-1:0] mag;
    logic [FLEN-1:0] er;
    logic [FlagW-1:0] ef;
    vec_fop_e o;
    int sh;
    repeat (BuiltOps) begin
      uns = 1'($urandom);
      neg = !uns && 1'($urandom);
      if (uns) o = VEC_FCVT_F_XU;
      else o = VEC_FCVT_F_X;
      mode = modes[$urandom_range($size(modes)-1)];
      sig  = SigW'(rand_bits()) | (SigW'(1) << FracW);
      if ($urandom_range(7) == 0) sig = '1;
      sh   = $urandom_range(FLEN - SigW - (uns ? 0 : 1), 1);
      half = FLEN'(1) << (sh - 1);
      case ($urandom_range(
          3
      ))
        0: d = '0;
        1: d = half;
        default: d = rand_bits() & ((FLEN'(1) << sh) - 1);
      endcase
      mag = (FLEN'(sig) << sh) | d;
      er  = {1'b0, ExpW'(Bias + FracW + sh), sig[FracW-1:0]};
      er  = er + FLEN'(round_up(mode, neg, sig[0], RefW'(d), RefW'(half)));
      if (neg) er = er | Sign;
      ef = (d != '0) ? FlagNx : '0;
      send("built to float", o, VEC_EEW_SAME, mode, neg ? -mag : mag, er, ef);
    end
  endtask  // Automatic

  task automatic run_built(input int pct);
    stall_pct = pct;
    run_built_to_int();
    run_built_to_float();
  endtask  // Automatic

  // Narrow int edges
  task automatic run_directed();
    logic [FLEN-1:0] max_tie;
    logic [FLEN-1:0] min_tie;
    logic [FLEN-1:0] min_int;
    logic [FLEN-1:0] umax_tie;
    logic [FLEN-1:0] umax_f;
    max_tie  = fp_bits(NarrowMag - 0.5);
    min_tie  = fp_bits(-(NarrowMag + 0.5));
    min_int  = fp_bits(-NarrowMag);
    umax_tie = fp_bits(UnsMag - 0.5);
    umax_f   = pow2(HalfW) - (FLEN'(1) << (FracW - HalfW + 1));
    send("narrow max tie", VEC_FCVT_X_F, VEC_EEW_NARROW, RmRne, max_tie, NarrowMax, FlagNv);
    send("narrow max rtz", VEC_FCVT_X_F, VEC_EEW_NARROW, RmRtz, max_tie, NarrowMax, FlagNx);
    send("narrow rtz form", VEC_FCVT_RTZ_X_F, VEC_EEW_NARROW, RmRup, max_tie, NarrowMax, FlagNx);
    send("narrow min tie", VEC_FCVT_X_F, VEC_EEW_NARROW, RmRne, min_tie, NarrowMin, FlagNx);
    send("narrow min rdn", VEC_FCVT_X_F, VEC_EEW_NARROW, RmRdn, min_tie, NarrowMin, FlagNv);
    send("narrow min exact", VEC_FCVT_X_F, VEC_EEW_NARROW, RmRne, min_int, NarrowMin, '0);
    send("unsigned max tie", VEC_FCVT_XU_F, VEC_EEW_NARROW, RmRne, umax_tie, NarrowUMax, FlagNv);
    send("unsigned max rtz", VEC_FCVT_RTZ_XU_F, VEC_EEW_NARROW, RmRne, umax_tie, NarrowUMax,
         FlagNx);
    send("unsigned neg half", VEC_FCVT_XU_F, VEC_EEW_NARROW, RmRne, fp_bits(-0.5), '0, FlagNx);
    send("unsigned neg one", VEC_FCVT_XU_F, VEC_EEW_NARROW, RmRne, Sign | One, '0, FlagNv);
    send("signed qnan", VEC_FCVT_X_F, VEC_EEW_NARROW, RmRne, QNan, NarrowMax, FlagNv);
    send("signed neg nan", VEC_FCVT_X_F, VEC_EEW_NARROW, RmRne, Sign | QNan, NarrowMax, FlagNv);
    send("unsigned snan", VEC_FCVT_XU_F, VEC_EEW_NARROW, RmRne, SNan, NarrowUMax, FlagNv);
    send("signed +inf", VEC_FCVT_X_F, VEC_EEW_NARROW, RmRne, Inf, NarrowMax, FlagNv);
    send("signed -inf", VEC_FCVT_X_F, VEC_EEW_NARROW, RmRne, Sign | Inf, NarrowMin, FlagNv);
    send("unsigned -inf", VEC_FCVT_XU_F, VEC_EEW_NARROW, RmRne, Sign | Inf, '0, FlagNv);
    send("signed big", VEC_FCVT_X_F, VEC_EEW_NARROW, RmRne, pow2(FLEN), NarrowMax, FlagNv);
    send("signed neg zero", VEC_FCVT_X_F, VEC_EEW_NARROW, RmRne, Sign, '0, '0);
    send("signed tiny up", VEC_FCVT_X_F, VEC_EEW_NARROW, RmRup, FLEN'(1), FLEN'(1), FlagNx);
    send("signed tiny dn", VEC_FCVT_X_F, VEC_EEW_NARROW, RmRdn, Sign | FLEN'(1), NarrowUMax,
         FlagNx);
    send("widen narrow min", VEC_FCVT_F_X, VEC_EEW_WIDEN, RmRne, Junk | NarrowMin, Sign | pow2(
         HalfW - 1), '0);
    send("widen unsigned max", VEC_FCVT_F_XU, VEC_EEW_WIDEN, RmRne, Junk | NarrowUMax, umax_f, '0);
    send("widen narrow -1", VEC_FCVT_F_X, VEC_EEW_WIDEN, RmRdn, NarrowUMax, Sign | One, '0);
    send("widen zero", VEC_FCVT_F_X, VEC_EEW_WIDEN, RmRdn, Junk, '0, '0);
    send("same rtz form", VEC_FCVT_RTZ_X_F, VEC_EEW_SAME, RmRup, fp_bits(-1.5), '1, FlagNx);
    send("same u rtz form", VEC_FCVT_RTZ_XU_F, VEC_EEW_SAME, RmRup, fp_bits(1.5), FLEN'(1), FlagNx);
    send("f from unsigned max", VEC_FCVT_F_XU, VEC_EEW_SAME, RmRne, '1, pow2(FLEN), FlagNx);
    send("f from signed -1", VEC_FCVT_F_X, VEC_EEW_SAME, RmRne, '1, Sign | One, '0);
  endtask  // Automatic

  // Half width power
  task automatic run_half_pow();
    logic [FLEN-1:0] half_pow;
    logic [FLEN-1:0] below;
    half_pow = pow2(HalfW - 1);
    below = fp_bits(NarrowMag - 1.0);
    send("half pow signed", VEC_FCVT_X_F, VEC_EEW_NARROW, RmRne, half_pow, NarrowMax, FlagNv);
    send("half pow rtz", VEC_FCVT_RTZ_X_F, VEC_EEW_NARROW, RmRdn, half_pow, NarrowMax, FlagNv);
    send("half pow neg", VEC_FCVT_X_F, VEC_EEW_NARROW, RmRne, Sign | half_pow, NarrowMin, '0);
    send("half pow below", VEC_FCVT_X_F, VEC_EEW_NARROW, RmRne, below, NarrowMax, '0);
    send("half pow unsigned", VEC_FCVT_XU_F, VEC_EEW_NARROW, RmRne, half_pow, NarrowMin, '0);
    send("half pow widen", VEC_FCVT_F_XU, VEC_EEW_WIDEN, RmRne, Junk | NarrowMin, half_pow, '0);
    send("half pow widen signed", VEC_FCVT_F_X, VEC_EEW_WIDEN, RmRne, Junk | NarrowMin,
         Sign | half_pow, '0);
    send("half pow same", VEC_FCVT_X_F, VEC_EEW_SAME, RmRne, half_pow, NarrowMin, '0);
    send("half pow from int", VEC_FCVT_F_X, VEC_EEW_SAME, RmRne, NarrowMin, half_pow, '0);
  endtask  // Automatic

  task automatic run_stalled(input int pct);
    stall_pct = pct;
    run_directed();
    run_half_pow();
    sweep_widen();
  endtask  // Automatic

  task automatic run_reset_flight();
    send("reset flight", VEC_FCVT_F_X, VEC_EEW_SAME, RmRne, FLEN'(1), One, '0);
    do_reset(Latency + 1);
    drain();
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
    $dumpfile("vec_fp_cvt_lane_tb.vcd");
    $dumpvars(0, vec_fp_cvt_lane_tb);
    seed_random();
    do_reset(2);

    run_directed();
    run_half_pow();
    drain();
    run_stalled(SweepStallPct);
    run_testfloat(FileStallPct);
    run_built(FileStallPct);
    run_reset_flight();

    drain();
    do_verdict();
  end

  function automatic logic [FLEN-1:0] rand_bits();
    logic [FLEN-1:0] w;
    w = '0;
    for (int i = 0; i < FLEN; i += 32) w = (w << 32) | FLEN'($urandom);
    return w;
  endfunction

  function automatic string tf_fmt();
    if (FLEN == 64) return "f64";
    return "f32";
  endfunction  // Automatic

  function automatic string tf_int();
    if (FLEN == 64) return "64";
    return "32";
  endfunction  // Automatic

  // Encode real value
  function automatic logic [FLEN-1:0] fp_bits(input real v);
    logic [63:0] d;
    int e;
    d = $realtobits(v);
    e = int'(d[62:52]) - 1023 + Bias;
    fp_bits = {d[63], ExpW'(e), FracW'(d[51:0] >> (52 - FracW))};
  endfunction

  function automatic logic [FLEN-1:0] pow2(input int p);
    return FLEN'(Bias + p) << FracW;
  endfunction

  function automatic logic round_up(input logic [RmW-1:0] mode, input logic neg, input logic odd,
                                    input logic [RefW-1:0] q, input logic [RefW-1:0] half);
    case (mode)
      RmRne:   return (q > half) || ((q == half) && odd);
      RmRmm:   return q >= half;
      RmRdn:   return neg && (q != '0);
      RmRup:   return !neg && (q != '0);
      default: return 1'b0;
    endcase
  endfunction

  task automatic built_int(input logic [RefW-1:0] m, input logic neg, input logic uns, input int w,
                           input logic inexact, output logic [FLEN-1:0] res,
                           output logic [FlagW-1:0] fl);
    logic [RefW-1:0] lim;
    if (uns) lim = neg ? '0 : (RefW'(1) << w) - 1;
    else lim = (RefW'(1) << (w - 1)) - RefW'(!neg);
    if (m > lim) begin
      res = FLEN'(lim);
      fl  = FlagNv;
    end else begin
      res = FLEN'((neg ? -m : m) & ((RefW'(1) << w) - 1));
      fl  = inexact ? FlagNx : '0;
    end
  endtask  // Automatic

  function automatic logic [FLEN-1:0] clip_narrow(input logic [FLEN-1:0] x, input logic uns);
    logic is_nan;
    logic neg;
    is_nan = (x[FracW+:ExpW] == '1) && (x[FracW-1:0] != '0);
    neg = x[FLEN-1] && !is_nan;
    if (uns) clip_narrow = neg ? '0 : NarrowUMax;
    else clip_narrow = neg ? NarrowMin : NarrowMax;
  endfunction

  task automatic ref_narrow(input logic [FLEN-1:0] x, input logic uns, input logic [FLEN-1:0] r,
                            input logic [FlagW-1:0] f, output logic [FLEN-1:0] rn,
                            output logic [FlagW-1:0] fn);
    longint sv;
    logic   fits;
    sv = longint'($signed(r));
    if (uns) fits = r <= NarrowUMax;
    else fits = (sv >= -longint'(NarrowMin)) && (sv <= longint'(NarrowMax));
    if ((f & FlagNv) == '0 && fits) begin
      rn = r & NarrowUMax;
      fn = f;
    end else begin
      rn = clip_narrow(x, uns);
      fn = FlagNv;
    end
  endtask  // Automatic

  function automatic logic [FLEN-1:0] i2f_exact(input logic [HalfW-1:0] v, input logic uns);
    logic sign;
    logic [HalfW:0] mag;
    int lead;
    sign = !uns && v[HalfW-1];
    mag  = sign ? -{1'b1, v} : {1'b0, v};
    if (mag == '0) begin
      i2f_exact = '0;
    end else begin
      lead = 0;
      for (int i = 0; i < $bits(mag); i++) if (mag[i]) lead = i;
      i2f_exact = {sign, ExpW'(Bias + lead), FracW'(SigW'(mag) << (FracW - lead))};
    end
  endfunction

  function automatic logic round_inc(input logic [RmW-1:0] rm, input logic neg, input logic lsb,
                                     input logic above, input logic tie, input logic inexact);
    case (rm)
      RmRne:   return above || (tie && lsb);
      RmRdn:   return neg && inexact;
      RmRup:   return !neg && inexact;
      RmRmm:   return above || tie;
      default: return 1'b0;
    endcase
  endfunction

  // Reference model
  task automatic ref_f2i(input logic [FLEN-1:0] x, input logic uns, input logic [RmW-1:0] rm,
                         input int w, output logic [FLEN-1:0] res, output logic [FlagW-1:0] fl);
    logic neg;
    logic [ExpW-1:0] e;
    logic [RefW-1:0] sig;
    logic [RefW-1:0] mag;
    logic [RefW-1:0] rem;
    logic [RefW-1:0] half;
    logic [RefW-1:0] lim;
    logic inexact;
    int sh;
    neg = x[FLEN-1];
    e   = x[FLEN-2:FracW];
    sig = RefW'(x[FracW-1:0]) | (RefW'(e != '0) << FracW);
    sh  = ((e == '0) ? 1 : int'(e)) - Bias - FracW;
    if (e == '1) begin
      mag = '1;
      inexact = 1'b0;
      if (x[FracW-1:0] != '0) neg = 1'b0;
    end else if (sh > w) begin
      mag = '1;
      inexact = 1'b0;
    end else if (sh >= 0) begin
      mag = sig << sh;
      inexact = 1'b0;
    end else if (-sh > FracW + 2) begin
      inexact = (sig != '0);
      mag = RefW'(round_inc(rm, neg, 1'b0, 1'b0, 1'b0, inexact));
    end else begin
      mag = sig >> -sh;
      rem = sig & ((RefW'(1) << -sh) - 1);
      half = RefW'(1) << (-sh - 1);
      inexact = (rem != '0);
      mag = mag + RefW'(round_inc(rm, neg, mag[0], rem > half, rem == half, inexact));
    end
    if (uns) lim = neg ? '0 : (RefW'(1) << w) - 1;
    else lim = neg ? RefW'(1) << (w - 1) : (RefW'(1) << (w - 1)) - 1;
    if (mag > lim) begin
      mag = lim;
      fl  = FlagNv;
    end else begin
      fl = inexact ? FlagNx : '0;
    end
    if (neg) mag = -mag;
    res = FLEN'(mag & ((RefW'(1) << w) - 1));
  endtask  // Automatic

  task automatic ref_i2f(input logic [FLEN-1:0] v, input logic uns, input logic [RmW-1:0] rm,
                         input int w, output logic [FLEN-1:0] res, output logic [FlagW-1:0] fl);
    logic neg;
    logic [RefW-1:0] mag;
    logic [RefW-1:0] rem;
    logic [RefW-1:0] half;
    logic inexact;
    int lead;
    int sh;
    mag = RefW'(v) & ((RefW'(1) << w) - 1);
    neg = !uns && mag[w-1];
    if (neg) mag = (RefW'(1) << w) - mag;
    fl = '0;
    if (mag == '0) begin
      res = '0;
      return;
    end
    lead = 0;
    for (int i = 0; i < RefW; i++) if (mag[i]) lead = i;
    if (lead <= FracW) begin
      mag = mag << (FracW - lead);
    end else begin
      sh = lead - FracW;
      rem = mag & ((RefW'(1) << sh) - 1);
      half = RefW'(1) << (sh - 1);
      mag = mag >> sh;
      inexact = (rem != '0);
      mag = mag + RefW'(round_inc(rm, neg, mag[0], rem > half, rem == half, inexact));
      if (mag[FracW+1]) begin
        mag  = mag >> 1;
        lead = lead + 1;
      end
      fl = inexact ? FlagNx : '0;
    end
    res = FLEN'({neg, ExpW'(Bias + lead), mag[FracW-1:0]});
  endtask  // Automatic

  task automatic ref_cvt(input vec_fop_e o, input vec_eew_e e, input logic [RmW-1:0] mode,
                         input logic [FLEN-1:0] x, output logic [FLEN-1:0] er,
                         output logic [FlagW-1:0] ef);
    logic uns;
    logic [RmW-1:0] rm;
    int w;
    uns = (o == VEC_FCVT_XU_F) || (o == VEC_FCVT_RTZ_XU_F) || (o == VEC_FCVT_F_XU);
    rm  = (o == VEC_FCVT_RTZ_X_F || o == VEC_FCVT_RTZ_XU_F) ? RmRtz : mode;
    w   = (e == VEC_EEW_SAME) ? FLEN : HalfW;
    if (o == VEC_FCVT_F_X || o == VEC_FCVT_F_XU) ref_i2f(x, uns, rm, w, er, ef);
    else ref_f2i(x, uns, rm, w, er, ef);
  endtask  // Automatic

endmodule

`default_nettype wire
