`default_nettype none

module vec_fp_cvt_lane_tb
  import vec_pkg::*;
  import fp_pkg::RmRne, fp_pkg::RmRtz, fp_pkg::RmRdn, fp_pkg::RmRup, fp_pkg::RmRmm;
  import fp_pkg::FlagNv, fp_pkg::FlagNx;
  import fp_pkg::ExpW, fp_pkg::FracW, fp_pkg::SigW, fp_pkg::Bias;
();

  localparam int ELEN = arch_pkg::ELEN;
  localparam int HalfW = ELEN / 2;
  localparam int FlagW = $bits(fp_pkg::FlagNv);
  localparam int RmW = $bits(fp_pkg::RmRne);
  localparam int Latency = VecFpLatency;
  localparam int MinChecks = 520_000;
  localparam int SweepStallPct = 25;
  localparam int FileStallPct = 10;
  localparam string TfDir = "build/testfloat/";
  localparam logic [2:0] VsewSame = 3'($clog2(ELEN / 8));
  localparam logic [2:0] VsewHalf = 3'($clog2(HalfW / 8));

  typedef struct packed {
    vec_fop_e op;
    vec_eew_e eew;
    logic [2:0] vsew;
    logic [RmW-1:0] rm;
    logic [ELEN-1:0] a;
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
  logic [ELEN-1:0] a;
  logic [ELEN-1:0] result;
  logic [FlagW-1:0] fflags;
  logic result_valid;

  logic [ELEN-1:0] q_res[$];
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

  task automatic check(input string name, input logic [ELEN-1:0] got, input logic [ELEN-1:0] exp);
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
    vsew = VsewSame;
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
    logic [ELEN-1:0] prev_res;
    logic [FlagW-1:0] prev_flags;
    logic prev_vld;
    was_en = core_en;
    prev_res = result;
    prev_flags = fflags;
    prev_vld = result_valid;
    @(posedge clk);
    @(negedge clk);
    if (!rst_n) begin
      check("result_valid in reset", ELEN'(result_valid), '0);
    end else if (!was_en) begin
      check("result held with core_en low", result, prev_res);
      check("fflags held with core_en low", ELEN'(fflags), ELEN'(prev_flags));
      check("result_valid held with core_en low", ELEN'(result_valid), ELEN'(prev_vld));
    end else begin
      en_cycle++;
      check_retire();
    end
  endtask  // Automatic

  task automatic check_retire();
    logic exp_valid;
    logic [ELEN-1:0] er;
    logic [FlagW-1:0] ef;
    op_info_t info;
    vec_fop_e fo;
    vec_eew_e fe;
    string name;
    exp_valid = q_issue.size() != 0 && (en_cycle - q_issue[0]) >= Latency;
    check($sformatf("result_valid at %0t", $time), ELEN'(result_valid), ELEN'(exp_valid));
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
        check({name, " fflags"}, ELEN'(fflags), ELEN'(ef));
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
        a = ELEN'($urandom);
      end
      tick();
    end
  endtask  // Automatic

  task automatic send(input string src, input vec_fop_e o, input vec_eew_e e,
                      input logic [RmW-1:0] mode, input logic [ELEN-1:0] x,
                      input logic [ELEN-1:0] er, input logic [FlagW-1:0] ef);
    op_info_t info;
    stalls();
    core_en = 1'b1;
    valid = 1'b1;
    op = o;
    eew = e;
    vsew = (e == VEC_EEW_SAME) ? VsewSame : VsewHalf;
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
    check("results never arrived", ELEN'(q_res.size()), '0);
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
    logic [ELEN-1:0] x;
    logic [ELEN-1:0] r;
    logic [FlagW-1:0] f;
    logic [ELEN-1:0] r16;
    logic [FlagW-1:0] f16;
    logic [RmW-1:0] mode;
    string path;
    string src;
    path = {TfDir, uns ? "f32_to_ui32_" : "f32_to_i32_", rms[m], ".txt"};
    fd   = $fopen(path, "r");
    if (fd == 0) $fatal(1, "TB MISSING FILE: %s (run make testfloat)", path);
    line = 0;
    while ($fscanf(
        fd, "%h %h %h\n", x, r, f
    ) == 3) begin
      line++;
      src = $sformatf("%s:%0d", path, line);
      ref_f2i16(x, uns, r, f, r16, f16);
      if (modes[m] == RmRtz) begin
        mode = modes[$urandom_range($size(modes)-1)];
        send(src, to_int_op(uns, 1'b1), VEC_EEW_SAME, mode, x, r, f);
        send(src, to_int_op(uns, 1'b1), VEC_EEW_NARROW, mode, x, r16, f16);
      end
      send(src, to_int_op(uns, 1'b0), VEC_EEW_SAME, modes[m], x, r, f);
      send(src, to_int_op(uns, 1'b0), VEC_EEW_NARROW, modes[m], x, r16, f16);
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
    logic [ELEN-1:0] x;
    logic [ELEN-1:0] r;
    logic [FlagW-1:0] f;
    logic [ELEN-1:0] x16;
    vec_fop_e o;
    string path;
    string src;
    path = {TfDir, uns ? "ui32_to_f32_" : "i32_to_f32_", rms[m], ".txt"};
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
      x16 = {HalfW'($urandom), x[HalfW-1:0]};
      send(src, o, VEC_EEW_WIDEN, modes[m], x16, i2f16(x[HalfW-1:0], uns), '0);
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
    logic [ELEN-1:0] x;
    for (int i = 0; i < (1 << HalfW); i++) begin
      x = {HalfW'($urandom), HalfW'(i)};
      send("widen sweep", VEC_FCVT_F_X, VEC_EEW_WIDEN, modes[i%$size(modes)], x, i2f16(
           HalfW'(i), 1'b0), '0);
      send("widen sweep", VEC_FCVT_F_XU, VEC_EEW_WIDEN, modes[i%$size(modes)], x, i2f16(
           HalfW'(i), 1'b1), '0);
    end
  endtask  // Automatic

  // Sixteen bit edges
  task automatic run_directed();
    send("i16 max tie", VEC_FCVT_X_F, VEC_EEW_NARROW, RmRne, 'h46FF_FF00, 'h7FFF, FlagNv);
    send("i16 max rtz", VEC_FCVT_X_F, VEC_EEW_NARROW, RmRtz, 'h46FF_FF00, 'h7FFF, FlagNx);
    send("i16 rtz form", VEC_FCVT_RTZ_X_F, VEC_EEW_NARROW, RmRup, 'h46FF_FF00, 'h7FFF, FlagNx);
    send("i16 min tie", VEC_FCVT_X_F, VEC_EEW_NARROW, RmRne, 'hC700_0080, 'h8000, FlagNx);
    send("i16 min rdn", VEC_FCVT_X_F, VEC_EEW_NARROW, RmRdn, 'hC700_0080, 'h8000, FlagNv);
    send("i16 min exact", VEC_FCVT_X_F, VEC_EEW_NARROW, RmRne, 'hC700_0000, 'h8000, '0);
    send("u16 max tie", VEC_FCVT_XU_F, VEC_EEW_NARROW, RmRne, 'h477F_FF80, 'hFFFF, FlagNv);
    send("u16 max rtz", VEC_FCVT_RTZ_XU_F, VEC_EEW_NARROW, RmRne, 'h477F_FF80, 'hFFFF, FlagNx);
    send("u16 neg half", VEC_FCVT_XU_F, VEC_EEW_NARROW, RmRne, 'hBF00_0000, 'h0000, FlagNx);
    send("u16 neg one", VEC_FCVT_XU_F, VEC_EEW_NARROW, RmRne, 'hBF80_0000, 'h0000, FlagNv);
    send("i16 qnan", VEC_FCVT_X_F, VEC_EEW_NARROW, RmRne, 'h7FC0_0000, 'h7FFF, FlagNv);
    send("i16 neg nan", VEC_FCVT_X_F, VEC_EEW_NARROW, RmRne, 'hFFC0_0000, 'h7FFF, FlagNv);
    send("u16 snan", VEC_FCVT_XU_F, VEC_EEW_NARROW, RmRne, 'h7F80_0001, 'hFFFF, FlagNv);
    send("i16 +inf", VEC_FCVT_X_F, VEC_EEW_NARROW, RmRne, 'h7F80_0000, 'h7FFF, FlagNv);
    send("i16 -inf", VEC_FCVT_X_F, VEC_EEW_NARROW, RmRne, 'hFF80_0000, 'h8000, FlagNv);
    send("u16 -inf", VEC_FCVT_XU_F, VEC_EEW_NARROW, RmRne, 'hFF80_0000, 'h0000, FlagNv);
    send("i16 big", VEC_FCVT_X_F, VEC_EEW_NARROW, RmRne, 'h4F80_0000, 'h7FFF, FlagNv);
    send("i16 neg zero", VEC_FCVT_X_F, VEC_EEW_NARROW, RmRne, 'h8000_0000, 'h0000, '0);
    send("i16 tiny up", VEC_FCVT_X_F, VEC_EEW_NARROW, RmRup, 'h0000_0001, 'h0001, FlagNx);
    send("i16 tiny dn", VEC_FCVT_X_F, VEC_EEW_NARROW, RmRdn, 'h8000_0001, 'hFFFF, FlagNx);
    send("widen i16 min", VEC_FCVT_F_X, VEC_EEW_WIDEN, RmRne, 'hABCD_8000, 'hC700_0000, '0);
    send("widen u16 max", VEC_FCVT_F_XU, VEC_EEW_WIDEN, RmRne, 'h1234_FFFF, 'h477F_FF00, '0);
    send("widen i16 -1", VEC_FCVT_F_X, VEC_EEW_WIDEN, RmRdn, 'h0000_FFFF, 'hBF80_0000, '0);
    send("widen zero", VEC_FCVT_F_X, VEC_EEW_WIDEN, RmRdn, 'hFFFF_0000, 'h0000_0000, '0);
    send("i32 rtz form", VEC_FCVT_RTZ_X_F, VEC_EEW_SAME, RmRup, 'hBFC0_0000, 'hFFFF_FFFF, FlagNx);
    send("u32 rtz form", VEC_FCVT_RTZ_XU_F, VEC_EEW_SAME, RmRup, 'h3FC0_0000, 'h0000_0001, FlagNx);
    send("f32 from u32", VEC_FCVT_F_XU, VEC_EEW_SAME, RmRne, 'hFFFF_FFFF, 'h4F80_0000, FlagNx);
    send("f32 from i32", VEC_FCVT_F_X, VEC_EEW_SAME, RmRne, 'hFFFF_FFFF, 'hBF80_0000, '0);
  endtask  // Automatic

  task automatic run_stalled(input int pct);
    stall_pct = pct;
    run_directed();
    sweep_widen();
  endtask  // Automatic

  task automatic run_reset_flight();
    send("reset flight", VEC_FCVT_F_X, VEC_EEW_SAME, RmRne, 'h0000_0001, 'h3F80_0000, '0);
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
    drain();
    run_stalled(SweepStallPct);
    run_testfloat(FileStallPct);
    run_reset_flight();

    drain();
    do_verdict();
  end

  function automatic logic [ELEN-1:0] clip16(input logic [ELEN-1:0] x, input logic uns);
    logic is_nan;
    logic neg;
    is_nan = (x[FracW+:ExpW] == '1) && (x[FracW-1:0] != '0);
    neg = x[ELEN-1] && !is_nan;
    if (uns) clip16 = neg ? '0 : ELEN'({HalfW{1'b1}});
    else clip16 = neg ? ELEN'({1'b1, {(HalfW - 1) {1'b0}}}) : ELEN'({1'b0, {(HalfW - 1) {1'b1}}});
  endfunction

  task automatic ref_f2i16(input logic [ELEN-1:0] x, input logic uns, input logic [ELEN-1:0] res32,
                           input logic [FlagW-1:0] flags32, output logic [ELEN-1:0] res16,
                           output logic [FlagW-1:0] flags16);
    int   sv;
    logic fits;
    sv = int'(res32);
    if (uns) fits = (res32 < (ELEN'(1) << HalfW));
    else fits = (sv >= -(1 << (HalfW - 1))) && (sv < (1 << (HalfW - 1)));
    if ((flags32 & FlagNv) == '0 && fits) begin
      res16   = ELEN'(res32[HalfW-1:0]);
      flags16 = flags32;
    end else begin
      res16   = clip16(x, uns);
      flags16 = FlagNv;
    end
  endtask  // Automatic

  function automatic logic [ELEN-1:0] i2f16(input logic [HalfW-1:0] v, input logic uns);
    logic sign;
    logic [HalfW:0] mag;
    int lead;
    sign = !uns && v[HalfW-1];
    mag  = sign ? -{1'b1, v} : {1'b0, v};
    if (mag == '0) begin
      i2f16 = '0;
    end else begin
      lead = 0;
      for (int i = 0; i < $bits(mag); i++) if (mag[i]) lead = i;
      i2f16 = ELEN'({sign, ExpW'(Bias + lead), FracW'(SigW'(mag) << (FracW - lead))});
    end
  endfunction

endmodule

`default_nettype wire
