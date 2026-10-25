`default_nettype none

module fp_cvt_tb ();

  localparam int MinChecks = 300000;

  int checks = 0;
  int errors = 0;

  fp_cvt_bench #(
      .EXP_W (8),
      .FRAC_W(23),
      .FMT   ("f32")
  ) f32_bench ();

  fp_cvt_bench #(
      .EXP_W (11),
      .FRAC_W(52),
      .FMT   ("f64")
  ) f64_bench ();

  task automatic do_verdict();
    checks = f32_bench.checks + f64_bench.checks;
    errors = f32_bench.errors + f64_bench.errors;
    if (f32_bench.checks < MinChecks || f64_bench.checks < MinChecks)
      $fatal(
          1,
          "TB UNDER-RAN: %0d and %0d checks, expected at least %0d each",
          f32_bench.checks,
          f64_bench.checks,
          MinChecks
      );
    if (errors == 0) $display("PASS: %0d checks, %0d mismatches", checks, errors);
    else $fatal(1, "FAIL: %0d mismatches, %0d checks", errors, checks);
    $finish;
  endtask  // Automatic

  initial begin
    $dumpfile("fp_cvt_tb.vcd");
    $dumpvars(0, f32_bench);
    wait (f32_bench.done && f64_bench.done);
    do_verdict();
  end

endmodule

module fp_cvt_bench
  import fp_pkg::RmRne, fp_pkg::RmRtz, fp_pkg::RmRdn, fp_pkg::RmRup, fp_pkg::RmRmm;
  import fp_pkg::FlagNv, fp_pkg::FlagNx;
#(
    parameter  int    EXP_W  = 8,
    parameter  int    FRAC_W = 23,
    parameter  string FMT    = "f32",
    localparam int    FLEN   = 1 + EXP_W + FRAC_W
) ();

  localparam int XLEN = arch_pkg::XLEN;
  localparam int OpW = (FLEN > XLEN) ? FLEN : XLEN;
  localparam int HalfW = XLEN / 2;
  localparam int Bias = (1 << (EXP_W - 1)) - 1;
  localparam int FlagW = fp_pkg::FlagW;
  localparam int RmW = fp_pkg::RmW;
  localparam int TfIntW = 32;
  localparam int SweepW = 16;
  localparam int RefW = FRAC_W + XLEN + 3;
  localparam int RandOps = 32768;

  localparam string TfDir = "build/testfloat/";

  localparam logic [FlagW-1:0] FlagNone = '0;

  int checks = 0;
  int errors = 0;
  int max_errors = 0;
  logic done = 1'b0;

  logic cvt_to_int;
  logic cvt_unsigned;
  logic cvt_half;
  logic [RmW-1:0] cvt_rm;
  logic [OpW-1:0] cvt_a;
  logic [OpW-1:0] cvt_result;
  logic [FlagW-1:0] cvt_fflags;

  logic [RmW-1:0] modes[5] = '{RmRne, RmRtz, RmRdn, RmRup, RmRmm};

  initial void'($value$plusargs("max_errors=%d", max_errors));

  fp_cvt #(
      .ExpW (EXP_W),
      .FracW(FRAC_W)
  ) dut (
      .to_int(cvt_to_int),
      .is_unsigned(cvt_unsigned),
      .half(cvt_half),
      .rm(cvt_rm),
      .a(cvt_a),
      .result(cvt_result),
      .fflags(cvt_fflags)
  );

  task automatic check(input string name, input logic [OpW-1:0] got, input logic [OpW-1:0] exp);
    checks++;
    if (got !== exp) begin
      errors++;
      $display("FAIL %s: got %h, expected %h", name, got, exp);
      if (errors == max_errors) $fatal(1, "TB STOPPED: %0d mismatches", errors);
    end
  endtask  // Automatic

  task automatic test_cvt(input string src, input logic ti, input logic uns, input logic hw,
                          input logic [RmW-1:0] mode, input logic [OpW-1:0] x,
                          input logic [OpW-1:0] exp_res, input logic [FlagW-1:0] exp_flags);
    string name;
    cvt_to_int = ti;
    cvt_unsigned = uns;
    cvt_half = hw;
    cvt_rm = mode;
    cvt_a = x;
    #1;
    name = $sformatf("%s to_int=%0d unsigned=%0d half=%0d rm=%0d a=%h", src, ti, uns, hw, mode, x);
    check({name, " result"}, cvt_result, exp_res);
    check({name, " flags"}, OpW'(cvt_fflags), OpW'(exp_flags));
  endtask  // Automatic

  task automatic check_model(input string src, input logic [OpW-1:0] got_res,
                             input logic [FlagW-1:0] got_flags, input logic [OpW-1:0] tf_res,
                             input logic [FlagW-1:0] tf_flags);
    check({src, " model result"}, got_res, tf_res);
    check({src, " model flags"}, OpW'(got_flags), OpW'(tf_flags));
  endtask  // Automatic

  function automatic logic [OpW-1:0] rand_bits();
    logic [OpW-1:0] w;
    w = '0;
    for (int i = 0; i < OpW; i += 32) w = (w << 32) | OpW'($urandom);
    return w;
  endfunction

  function automatic logic [XLEN-1:0] widen(input logic [TfIntW-1:0] v, input logic uns);
    if (uns) return XLEN'(v);
    return XLEN'($signed(v));
  endfunction

  task automatic run_file(input string path, input logic to_int, input logic is_unsigned,
                          input logic [RmW-1:0] rm);
    int fd;
    int line;
    logic [OpW-1:0] x;
    logic [OpW-1:0] r;
    logic [FlagW-1:0] f;
    logic [OpW-1:0] mr;
    logic [FlagW-1:0] mf;
    logic [OpW-1:0] er;
    logic [FlagW-1:0] ef;
    logic [OpW-1:0] x_half;
    string src;
    fd = $fopen(path, "r");
    if (fd == 0) $fatal(1, "TB MISSING FILE: %s (run make testfloat)", path);
    line = 0;
    while ($fscanf(
        fd, "%h %h %h\n", x, r, f
    ) == 3) begin
      line++;
      src = $sformatf("%s:%0d", path, line);
      if (to_int) begin
        ref_f2i(FLEN'(x), is_unsigned, rm, TfIntW, mr, mf);
        check_model(src, mr, mf, r, f);
        ref_f2i(FLEN'(x), is_unsigned, rm, XLEN, er, ef);
        test_cvt(src, 1'b1, is_unsigned, 1'b0, rm, x, er, ef);
        ref_f2i(FLEN'(x), is_unsigned, rm, HalfW, er, ef);
        test_cvt(src, 1'b1, is_unsigned, 1'b1, rm, x, er, ef);
      end else begin
        ref_i2f(XLEN'(x), is_unsigned, rm, TfIntW, mr, mf);
        check_model(src, mr, mf, r, f);
        test_cvt(src, 1'b0, is_unsigned, 1'b0, rm, OpW'(widen(TfIntW'(x), is_unsigned)), r, f);
        x_half = rand_bits();
        x_half[HalfW-1:0] = x[HalfW-1:0];
        ref_i2f(XLEN'(x), is_unsigned, rm, HalfW, er, ef);
        test_cvt(src, 1'b0, is_unsigned, 1'b1, rm, x_half, er, ef);
      end
    end
    if (!$feof(fd)) $fatal(1, "TB BAD LINE: %s:%0d", path, line + 1);
    $fclose(fd);
    if (line == 0) $fatal(1, "TB EMPTY FILE: %s", path);
    $display("%s: %0d lines", path, line);
  endtask  // Automatic

  task automatic run_op(input string op, input logic to_int, input logic is_unsigned);
    string rms[$size(modes)] = '{"rne", "rtz", "rdn", "rup", "rmm"};
    for (int m = 0; m < $size(modes); m++)
      run_file({TfDir, op, "_", rms[m], ".txt"}, to_int, is_unsigned, modes[m]);
  endtask  // Automatic

  task automatic sweep_i2f_half(input logic uns);
    logic [  OpW-1:0] x;
    logic [  OpW-1:0] er;
    logic [FlagW-1:0] ef;
    for (int i = 0; i < 2 ** HalfW; i++) begin
      x = rand_bits();
      x[HalfW-1:0] = HalfW'(i);
      ref_i2f(XLEN'(i), uns, modes[i%$size(modes)], HalfW, er, ef);
      test_cvt($sformatf("%s sweep%0d %s %h", FMT, HalfW, uns ? "unsigned" : "signed", HalfW'(i)),
               1'b0, uns, 1'b1, modes[i%$size(modes)], x, er, ef);
    end
  endtask  // Automatic

  function automatic logic [FLEN-1:0] rand_float();
    logic [ FLEN-1:0] x;
    logic [EXP_W-1:0] e;
    x = FLEN'(rand_bits());
    if ($urandom_range(15) == 0) return x;
    e = EXP_W'(Bias - 3 + $urandom_range(XLEN + 6));
    x[FLEN-2:FRAC_W] = e;
    case ($urandom_range(
        3
    ))
      0: x[FRAC_W-1:0] = '1;
      1: x[FRAC_W-1:0] = FRAC_W'(x[FRAC_W-1:0] & {FRAC_W{1'b1}} << $urandom_range(FRAC_W));
      default: ;
    endcase
    return x;
  endfunction

  task automatic random_f2i(input int n);
    logic [FLEN-1:0] x;
    logic [RmW-1:0] rm;
    logic uns;
    logic [OpW-1:0] er;
    logic [FlagW-1:0] ef;
    repeat (n) begin
      x   = rand_float();
      rm  = modes[$urandom_range($size(modes)-1)];
      uns = 1'($urandom);
      ref_f2i(x, uns, rm, XLEN, er, ef);
      test_cvt({FMT, " random"}, 1'b1, uns, 1'b0, rm, OpW'(x), er, ef);
      ref_f2i(x, uns, rm, HalfW, er, ef);
      test_cvt({FMT, " random"}, 1'b1, uns, 1'b1, rm, OpW'(x), er, ef);
    end
  endtask  // Automatic

  task automatic random_i2f(input int n);
    logic [OpW-1:0] v;
    logic [RmW-1:0] rm;
    logic uns;
    logic [OpW-1:0] er;
    logic [FlagW-1:0] ef;
    repeat (n) begin
      v   = rand_bits();
      v   = OpW'(XLEN'(v) >> $urandom_range(XLEN - 1));
      rm  = modes[$urandom_range($size(modes)-1)];
      uns = 1'($urandom);
      if (1'($urandom)) v = OpW'(-XLEN'(v));
      ref_i2f(XLEN'(v), uns, rm, XLEN, er, ef);
      test_cvt({FMT, " random"}, 1'b0, uns, 1'b0, rm, v, er, ef);
      ref_i2f(XLEN'(v), uns, rm, HalfW, er, ef);
      test_cvt({FMT, " random"}, 1'b0, uns, 1'b1, rm, v, er, ef);
    end
  endtask  // Automatic

  task automatic mark_done();
    done = 1'b1;
  endtask  // Automatic

  task automatic do_reset();
    cvt_to_int = '0;
    cvt_unsigned = '0;
    cvt_half = '0;
    cvt_rm = '0;
    cvt_a = '0;
    #1;
  endtask  // Automatic

  initial begin
    do_reset();
    run_op({FMT, "_to_i32"}, 1'b1, 1'b0);
    run_op({FMT, "_to_ui32"}, 1'b1, 1'b1);

    run_op({"i32_to_", FMT}, 1'b0, 1'b0);
    run_op({"ui32_to_", FMT}, 1'b0, 1'b1);

    if (HalfW <= SweepW) begin
      sweep_i2f_half(1'b0);
      sweep_i2f_half(1'b1);
    end

    random_f2i(RandOps);
    random_i2f(RandOps);

    mark_done();
  end

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

  task automatic ref_f2i(input logic [FLEN-1:0] x, input logic uns, input logic [RmW-1:0] rm,
                         input int w, output logic [OpW-1:0] res, output logic [FlagW-1:0] fl);
    logic neg;
    logic [EXP_W-1:0] e;
    logic [RefW-1:0] sig;
    logic [RefW-1:0] mag;
    logic [RefW-1:0] rem;
    logic [RefW-1:0] half;
    logic [RefW-1:0] lim;
    logic inexact;
    int sh;
    neg = x[FLEN-1];
    e   = x[FLEN-2:FRAC_W];
    sig = RefW'(x[FRAC_W-1:0]) | (RefW'(e != '0) << FRAC_W);
    sh  = ((e == '0) ? 1 : int'(e)) - Bias - FRAC_W;
    if (e == '1) begin
      mag = '1;
      inexact = 1'b0;
      if (x[FRAC_W-1:0] != '0) neg = 1'b0;
    end else if (sh > w) begin
      mag = '1;
      inexact = 1'b0;
    end else if (sh >= 0) begin
      mag = sig << sh;
      inexact = 1'b0;
    end else if (-sh > FRAC_W + 2) begin
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
      fl = inexact ? FlagNx : FlagNone;
    end
    if (neg) mag = -mag;
    res = OpW'(mag & ((RefW'(1) << w) - 1));
  endtask  // Automatic

  task automatic ref_i2f(input logic [XLEN-1:0] v, input logic uns, input logic [RmW-1:0] rm,
                         input int w, output logic [OpW-1:0] res, output logic [FlagW-1:0] fl);
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
    fl = FlagNone;
    if (mag == '0) begin
      res = '0;
      return;
    end
    lead = 0;
    for (int i = 0; i < RefW; i++) if (mag[i]) lead = i;
    if (lead <= FRAC_W) begin
      mag = mag << (FRAC_W - lead);
    end else begin
      sh = lead - FRAC_W;
      rem = mag & ((RefW'(1) << sh) - 1);
      half = RefW'(1) << (sh - 1);
      mag = mag >> sh;
      inexact = (rem != '0);
      mag = mag + RefW'(round_inc(rm, neg, mag[0], rem > half, rem == half, inexact));
      if (mag[FRAC_W+1]) begin
        mag  = mag >> 1;
        lead = lead + 1;
      end
      fl = inexact ? FlagNx : FlagNone;
    end
    res = OpW'({neg, EXP_W'(Bias + lead), mag[FRAC_W-1:0]});
  endtask  // Automatic

endmodule

`default_nettype wire
