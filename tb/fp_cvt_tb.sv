`default_nettype none

module fp_cvt_tb
  import fp_pkg::*;
();

  localparam int XLEN = arch_pkg::XLEN;
  localparam int OpW = (FLEN > XLEN) ? FLEN : XLEN;

  localparam string TfDir = "build/testfloat/";
  localparam int MinChecks = 140000;
  localparam int ShowErrors = 20;

  int checks = 0;
  int errors = 0;
  int max_errors = 0;

  logic cvt_to_int;
  logic cvt_unsigned;
  logic [2:0] cvt_iw;
  logic [2:0] cvt_rm;
  logic [OpW-1:0] cvt_a;
  logic [OpW-1:0] cvt_result;
  logic [4:0] cvt_fflags;

  fp_cvt dut (
      .to_int(cvt_to_int),
      .is_unsigned(cvt_unsigned),
      .iw(cvt_iw),
      .rm(cvt_rm),
      .a(cvt_a),
      .result(cvt_result),
      .fflags(cvt_fflags)
  );

  localparam logic [4:0] FlagNone = 5'b00000;

  localparam logic [2:0] Iw16 = 3'd1;
  localparam logic [2:0] Iw32 = 3'd2;

  logic [2:0] modes[5] = '{RmRne, RmRtz, RmRdn, RmRup, RmRmm};

  task automatic check(input string src, input logic ti, input logic uns, input logic [2:0] w,
                       input logic [2:0] mode, input logic [OpW-1:0] x,
                       input logic [OpW-1:0] exp_res, input logic [4:0] exp_flags);
    cvt_to_int = ti;
    cvt_unsigned = uns;
    cvt_iw = w;
    cvt_rm = mode;
    cvt_a = x;
    #1;
    checks++;
    if (cvt_result !== exp_res || cvt_fflags !== exp_flags) begin
      errors++;
      if (errors <= ShowErrors)
        $display(
            "FAIL %s to_int=%0d unsigned=%0d iw=%0d rm=%0d a=%h exp %h/%b got %h/%b",
            src,
            ti,
            uns,
            w,
            mode,
            x,
            exp_res,
            exp_flags,
            cvt_result,
            cvt_fflags
        );
      if (errors == max_errors) $fatal(1, "TB STOPPED: %0d mismatches", errors);
    end
  endtask

  function automatic logic [XLEN-1:0] clip16(input logic [FLEN-1:0] x, input logic uns);
    logic is_nan;
    logic neg;
    is_nan = (x[30:23] == 8'hff) && (x[22:0] != 23'd0);
    neg = x[31] && !is_nan;
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
  endtask

  function automatic logic [FLEN-1:0] i2f16(input logic [15:0] v, input logic uns);
    logic sign;
    logic [16:0] mag;
    int lead;
    logic [7:0] exp_field;
    logic [22:0] frac;
    sign = !uns && v[15];
    mag  = sign ? 17'(-{1'b1, v}) : {1'b0, v};
    if (mag == 17'd0) begin
      i2f16 = 32'h0000_0000;
    end else begin
      lead = 0;
      for (int i = 0; i < 17; i++) if (mag[i]) lead = i;
      exp_field = 8'(127 + lead);
      frac = 23'({6'd0, mag} << (23 - lead));
      i2f16 = {sign, exp_field, frac};
    end
  endfunction

  task automatic start_dump();
    string dump_arg;
    if ($value$plusargs("DUMP%s", dump_arg)) begin
      $display("DUMP%s: writing fp_cvt_tb.vcd", dump_arg);
      $dumpfile("fp_cvt_tb.vcd");
      $dumpvars(0, fp_cvt_tb);
    end
  endtask

  task automatic run_file(input string path, input logic to_int, input logic is_unsigned,
                          input logic [2:0] rm);
    int fd;
    int line;
    logic [OpW-1:0] x;
    logic [OpW-1:0] r;
    logic [4:0] f;
    logic [XLEN-1:0] res16;
    logic [4:0] flags16;
    logic [XLEN-1:0] x16;
    string src;
    fd = $fopen(path, "r");
    if (fd == 0) $fatal(1, "TB MISSING FILE: %s (run make testfloat)", path);
    line = 0;
    while ($fscanf(
        fd, "%h %h %h\n", x, r, f
    ) == 3) begin
      line++;
      src = $sformatf("%s:%0d", path, line);
      check(src, to_int, is_unsigned, Iw32, rm, x, r, f);
      if (to_int) begin
        ref_f2i16(x, is_unsigned, r, f, res16, flags16);
        check(src, to_int, is_unsigned, Iw16, rm, x, res16, flags16);
      end else begin
        x16 = {16'($urandom), x[15:0]};
        check(src, to_int, is_unsigned, Iw16, rm, x16, i2f16(x[15:0], is_unsigned), FlagNone);
      end
    end
    if (!$feof(fd)) $fatal(1, "TB BAD LINE: %s:%0d", path, line + 1);
    $fclose(fd);
    if (line == 0) $fatal(1, "TB EMPTY FILE: %s", path);
    $display("%s: %0d lines", path, line);
  endtask

  task automatic run_op(input string op, input logic to_int, input logic is_unsigned);
    string rms[5] = '{"rne", "rtz", "rdn", "rup", "rmm"};
    for (int m = 0; m < 5; m++)
      run_file({TfDir, op, "_", rms[m], ".txt"}, to_int, is_unsigned, modes[m]);
  endtask

  task automatic sweep_i2f16(input logic uns);
    logic [XLEN-1:0] x;
    for (int i = 0; i < 65536; i++) begin
      x = {16'($urandom), 16'(i)};
      check($sformatf("sweep16 %s %h", uns ? "unsigned" : "signed", 16'(i)), 1'b0, uns, Iw16,
            modes[i%5], x, i2f16(16'(i), uns), FlagNone);
    end
  endtask

  task automatic do_verdict();
    if (checks < MinChecks)
      $fatal(1, "TB UNDER-RAN: %0d checks, expected at least %0d", checks, MinChecks);
    if (errors != 0) $fatal(1, "FAIL: %0d mismatches, %0d checks", errors, checks);
    $display("PASS: %0d checks", checks);
    $finish;
  endtask

  initial void'($value$plusargs("max_errors=%d", max_errors));

  initial begin
    start_dump();

    run_op("f32_to_i32", 1'b1, 1'b0);
    run_op("f32_to_ui32", 1'b1, 1'b1);

    run_op("i32_to_f32", 1'b0, 1'b0);
    run_op("ui32_to_f32", 1'b0, 1'b1);

    sweep_i2f16(1'b0);
    sweep_i2f16(1'b1);

    do_verdict();
  end

endmodule

`default_nettype wire
