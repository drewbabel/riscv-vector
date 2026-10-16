`default_nettype none

module fp_cvt_tb ();

  localparam int MinChecks = 140000;

  int checks;
  int errors;
  int max_errors;

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
    if (errors != 0) $fatal(1, "FAIL: %0d mismatches, %0d checks", errors, checks);
    $display("PASS: %0d checks", checks);
    $finish;
  endtask  // Automatic

  initial begin
    $dumpfile("fp_cvt_tb.vcd");
    $dumpvars(0, f32_bench);
    wait (f32_bench.done && f64_bench.done);
    do_verdict();
  end

  initial begin
    if ($value$plusargs("max_errors=%d", max_errors) && max_errors > 0) begin
      wait (f32_bench.errors + f64_bench.errors >= max_errors);
      $fatal(1, "TB STOPPED: %0d mismatches", f32_bench.errors + f64_bench.errors);
    end
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
  localparam int Bias = (1 << (EXP_W - 1)) - 1;

  localparam string TfDir = "build/testfloat/";
  localparam int ShowErrors = 20;

  localparam logic [4:0] FlagNone = 5'b00000;

  int checks = 0;
  int errors = 0;
  logic done = 1'b0;

  logic cvt_to_int;
  logic cvt_unsigned;
  logic cvt_half;
  logic [2:0] cvt_rm;
  logic [OpW-1:0] cvt_a;
  logic [OpW-1:0] cvt_result;
  logic [4:0] cvt_fflags;

  fp_cvt #(
      .ExpW (EXP_W),
      .FracW(FRAC_W)
  ) dut (
      .to_int(cvt_to_int),
      .is_unsigned(cvt_unsigned),
      .iw(cvt_half ? 3'd1 : 3'd2),
      .rm(cvt_rm),
      .a(cvt_a),
      .result(cvt_result),
      .fflags(cvt_fflags)
  );

  logic [2:0] modes[5] = '{RmRne, RmRtz, RmRdn, RmRup, RmRmm};

  task automatic check(input string src, input logic ti, input logic uns, input logic hw,
                       input logic [2:0] mode, input logic [OpW-1:0] x,
                       input logic [OpW-1:0] exp_res, input logic [4:0] exp_flags);
    cvt_to_int = ti;
    cvt_unsigned = uns;
    cvt_half = hw;
    cvt_rm = mode;
    cvt_a = x;
    #1;
    checks++;
    if (cvt_result !== exp_res || cvt_fflags !== exp_flags) begin
      errors++;
      if (errors <= ShowErrors)
        $display(
            "FAIL %s to_int=%0d unsigned=%0d half=%0d rm=%0d a=%h exp %h/%b got %h/%b",
            src,
            ti,
            uns,
            hw,
            mode,
            x,
            exp_res,
            exp_flags,
            cvt_result,
            cvt_fflags
        );
    end
  endtask  // Automatic

  function automatic logic [XLEN-1:0] clip16(input logic [FLEN-1:0] x, input logic uns);
    logic is_nan;
    logic neg;
    is_nan = (x[FLEN-2:FRAC_W] == '1) && (x[FRAC_W-1:0] != '0);
    neg = x[FLEN-1] && !is_nan;
    if (uns) clip16 = neg ? 32'h0000_0000 : 32'h0000_ffff;
    else clip16 = neg ? 32'h0000_8000 : 32'h0000_7fff;
  endfunction

  task automatic ref_f2i16(input logic [FLEN-1:0] x, input logic uns, input logic [XLEN-1:0] res32,
                           input logic [4:0] flags32, output logic [XLEN-1:0] res16,
                           output logic [4:0] flags16);
    int   sv;
    logic fits;
    sv = int'(res32);
    if (uns) fits = (res32 <= 32'h0000_ffff);
    else fits = (sv >= -32768) && (sv <= 32767);
    if (!flags32[4] && fits) begin
      res16   = {16'h0000, res32[15:0]};
      flags16 = flags32;
    end else begin
      res16   = clip16(x, uns);
      flags16 = FlagNv;
    end
  endtask  // Automatic

  function automatic logic [FLEN-1:0] i2f16(input logic [15:0] v, input logic uns);
    logic sign;
    logic [16:0] mag;
    int lead;
    logic [EXP_W-1:0] exp_field;
    logic [FRAC_W-1:0] frac;
    sign = !uns && v[15];
    mag  = sign ? 17'(-{1'b1, v}) : {1'b0, v};
    if (mag == 17'd0) begin
      i2f16 = '0;
    end else begin
      lead = 0;
      for (int i = 0; i < 17; i++) if (mag[i]) lead = i;
      exp_field = EXP_W'(Bias + lead);
      frac = FRAC_W'((FRAC_W + 17)'(mag) << (FRAC_W - lead));
      i2f16 = {sign, exp_field, frac};
    end
  endfunction

  task automatic run_file(input string path, input logic to_int, input logic is_unsigned,
                          input logic [2:0] rm);
    int fd;
    int line;
    logic [OpW-1:0] x;
    logic [OpW-1:0] r;
    logic [4:0] f;
    logic [XLEN-1:0] res16;
    logic [4:0] flags16;
    logic [OpW-1:0] x16;
    string src;
    fd = $fopen(path, "r");
    if (fd == 0) $fatal(1, "TB MISSING FILE: %s (run make testfloat)", path);
    line = 0;
    while ($fscanf(
        fd, "%h %h %h\n", x, r, f
    ) == 3) begin
      line++;
      src = $sformatf("%s:%0d", path, line);
      check(src, to_int, is_unsigned, 1'b0, rm, x, r, f);
      if (to_int) begin
        ref_f2i16(FLEN'(x), is_unsigned, XLEN'(r), f, res16, flags16);
        check(src, to_int, is_unsigned, 1'b1, rm, x, OpW'(res16), flags16);
      end else begin
        x16 = {(OpW - 16)'({$urandom, $urandom}), x[15:0]};
        check(src, to_int, is_unsigned, 1'b1, rm, x16, OpW'(i2f16(x[15:0], is_unsigned)), FlagNone);
      end
    end
    if (!$feof(fd)) $fatal(1, "TB BAD LINE: %s:%0d", path, line + 1);
    $fclose(fd);
    if (line == 0) $fatal(1, "TB EMPTY FILE: %s", path);
    $display("%s: %0d lines", path, line);
  endtask  // Automatic

  task automatic run_op(input string op, input logic to_int, input logic is_unsigned);
    string rms[5] = '{"rne", "rtz", "rdn", "rup", "rmm"};
    for (int m = 0; m < 5; m++)
      run_file({TfDir, op, "_", rms[m], ".txt"}, to_int, is_unsigned, modes[m]);
  endtask  // Automatic

  task automatic sweep_i2f16(input logic uns);
    logic [OpW-1:0] x;
    for (int i = 0; i < 65536; i++) begin
      x = {(OpW - 16)'({$urandom, $urandom}), 16'(i)};
      check($sformatf("%s sweep16 %s %h", FMT, uns ? "unsigned" : "signed", 16'(i)), 1'b0, uns,
            1'b1, modes[i%5], x, OpW'(i2f16(16'(i), uns)), FlagNone);
    end
  endtask  // Automatic

  initial begin
    run_op({FMT, "_to_i32"}, 1'b1, 1'b0);
    run_op({FMT, "_to_ui32"}, 1'b1, 1'b1);

    run_op({"i32_to_", FMT}, 1'b0, 1'b0);
    run_op({"ui32_to_", FMT}, 1'b0, 1'b1);

    sweep_i2f16(1'b0);
    sweep_i2f16(1'b1);

    done = 1'b1;
  end

endmodule

`default_nettype wire
