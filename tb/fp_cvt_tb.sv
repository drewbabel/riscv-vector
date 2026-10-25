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
  import fp_pkg::FlagNv;
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

  localparam string TfDir = "build/testfloat/";

  localparam logic [FlagW-1:0] FlagNone = '0;
  localparam logic [XLEN-1:0] UMaxHalf = XLEN'({HalfW{1'b1}});
  localparam logic [XLEN-1:0] SMaxHalf = XLEN'({(HalfW - 1) {1'b1}});
  localparam logic [XLEN-1:0] SMinHalf = XLEN'(1) << (HalfW - 1);

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

  task automatic run_file(input string path, input logic to_int, input logic is_unsigned,
                          input logic [RmW-1:0] rm);
    int fd;
    int line;
    logic [OpW-1:0] x;
    logic [OpW-1:0] r;
    logic [FlagW-1:0] f;
    logic [XLEN-1:0] res_half;
    logic [FlagW-1:0] flags_half;
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
      test_cvt(src, to_int, is_unsigned, 1'b0, rm, x, r, f);
      if (to_int) begin
        ref_f2i_half(FLEN'(x), is_unsigned, XLEN'(r), f, res_half, flags_half);
        test_cvt(src, to_int, is_unsigned, 1'b1, rm, x, OpW'(res_half), flags_half);
      end else begin
        x_half = {(OpW - HalfW)'({$urandom, $urandom}), x[HalfW-1:0]};
        test_cvt(src, to_int, is_unsigned, 1'b1, rm, x_half, OpW'(i2f_half(x[HalfW-1:0], is_unsigned
                 )), FlagNone);
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
    logic [OpW-1:0] x;
    for (int i = 0; i < 2 ** HalfW; i++) begin
      x = {(OpW - HalfW)'({$urandom, $urandom}), HalfW'(i)};
      test_cvt($sformatf("%s sweep16 %s %h", FMT, uns ? "unsigned" : "signed", HalfW'(i)), 1'b0,
               uns, 1'b1, modes[i%$size(modes)], x, OpW'(i2f_half(HalfW'(i), uns)), FlagNone);
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

    sweep_i2f_half(1'b0);
    sweep_i2f_half(1'b1);

    mark_done();
  end

  function automatic logic [XLEN-1:0] clip_half(input logic [FLEN-1:0] x, input logic uns);
    logic is_nan;
    logic neg;
    is_nan = (x[FLEN-2:FRAC_W] == '1) && (x[FRAC_W-1:0] != '0);
    neg = x[FLEN-1] && !is_nan;
    if (uns) clip_half = neg ? '0 : UMaxHalf;
    else clip_half = neg ? SMinHalf : SMaxHalf;
  endfunction

  task automatic ref_f2i_half(input logic [FLEN-1:0] x, input logic uns,
                              input logic [XLEN-1:0] res_full, input logic [FlagW-1:0] flags_full,
                              output logic [XLEN-1:0] res_half,
                              output logic [FlagW-1:0] flags_half);
    logic fits;
    if (uns) fits = (res_full <= UMaxHalf);
    else fits = (res_full == {{(XLEN - HalfW) {res_full[HalfW-1]}}, res_full[HalfW-1:0]});
    if ((flags_full & FlagNv) == '0 && fits) begin
      res_half   = XLEN'(res_full[HalfW-1:0]);
      flags_half = flags_full;
    end else begin
      res_half   = clip_half(x, uns);
      flags_half = FlagNv;
    end
  endtask  // Automatic

  function automatic logic [FLEN-1:0] i2f_half(input logic [HalfW-1:0] v, input logic uns);
    logic sign;
    logic [HalfW:0] mag;
    int lead;
    logic [EXP_W-1:0] exp_field;
    logic [FRAC_W-1:0] frac;
    sign = !uns && v[HalfW-1];
    mag  = sign ? (HalfW + 1)'(-{1'b1, v}) : {1'b0, v};
    if (mag == '0) begin
      i2f_half = '0;
    end else begin
      lead = 0;
      for (int i = 0; i < $bits(mag); i++) if (mag[i]) lead = i;
      exp_field = EXP_W'(Bias + lead);
      frac = FRAC_W'((FRAC_W + HalfW + 1)'(mag) << (FRAC_W - lead));
      i2f_half = {sign, exp_field, frac};
    end
  endfunction

endmodule

`default_nettype wire
