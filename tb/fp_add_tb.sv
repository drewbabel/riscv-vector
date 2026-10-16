`default_nettype none

module fp_add_tb ();

  localparam int MinChecks = 464000;

  int checks;
  int errors;
  int max_errors;

  fp_add_bench #(
      .EXP_W (8),
      .FRAC_W(23),
      .FMT   ("f32")
  ) f32_bench ();

  fp_add_bench #(
      .EXP_W (11),
      .FRAC_W(52),
      .FMT   ("f64")
  ) f64_bench ();

  fp_add_bench #(
      .EXP_W (5),
      .FRAC_W(10),
      .FMT   ("f16")
  ) f16_bench ();

  task automatic do_verdict();
    checks = f32_bench.checks + f64_bench.checks + f16_bench.checks;
    errors = f32_bench.errors + f64_bench.errors + f16_bench.errors;
    if (f32_bench.checks < MinChecks || f64_bench.checks < MinChecks ||
        f16_bench.checks < MinChecks)
      $fatal(
          1,
          "TB UNDER-RAN: %0d, %0d and %0d checks, expected at least %0d each",
          f32_bench.checks,
          f64_bench.checks,
          f16_bench.checks,
          MinChecks
      );
    if (errors != 0) $fatal(1, "FAIL: %0d mismatches, %0d checks", errors, checks);
    $display("PASS: %0d checks", checks);
    $finish;
  endtask  // Automatic

  initial begin
    $dumpfile("fp_add_tb.vcd");
    $dumpvars(0, f32_bench);
    wait (f32_bench.done && f64_bench.done && f16_bench.done);
    do_verdict();
  end

  initial begin
    if ($value$plusargs("max_errors=%d", max_errors) && max_errors > 0) begin
      wait (f32_bench.errors + f64_bench.errors + f16_bench.errors >= max_errors);
      $fatal(1, "TB STOPPED: %0d mismatches",
             f32_bench.errors + f64_bench.errors + f16_bench.errors);
    end
  end

endmodule

module fp_add_bench
  import fp_pkg::RmRne, fp_pkg::RmRtz, fp_pkg::RmRdn, fp_pkg::RmRup, fp_pkg::RmRmm;
  import fp_pkg::FlagNv;
#(
    parameter  int    EXP_W  = 8,
    parameter  int    FRAC_W = 23,
    parameter  string FMT    = "f32",
    localparam int    FLEN   = 1 + EXP_W + FRAC_W
) ();

  localparam int ShowErrors = 20;
  localparam string TfDir = "build/testfloat/";

  localparam logic [FLEN-1:0] PosInf = {1'b0, {EXP_W{1'b1}}, {FRAC_W{1'b0}}};
  localparam logic [FLEN-1:0] One = {2'b00, {(EXP_W - 1) {1'b1}}, {FRAC_W{1'b0}}};
  localparam logic [FLEN-1:0] CanonNan = {1'b0, {EXP_W{1'b1}}, 1'b1, {(FRAC_W - 1) {1'b0}}};

  int checks = 0;
  int errors = 0;
  logic done = 1'b0;

  logic sub;
  logic [2:0] rm;
  logic [FLEN-1:0] a;
  logic [FLEN-1:0] b;
  logic [FLEN-1:0] result;
  logic [4:0] fflags;

  fp_add #(
      .ExpW (EXP_W),
      .FracW(FRAC_W)
  ) dut (
      .sub(sub),
      .rm(rm),
      .a(a),
      .b(b),
      .result(result),
      .fflags(fflags)
  );

  task automatic check(input string path, input int line, input logic [FLEN-1:0] exp_res,
                       input logic [4:0] exp_flags);
    checks++;
    if (result !== exp_res || fflags !== exp_flags) begin
      errors++;
      if (errors <= ShowErrors)
        $display(
            "FAIL %s:%0d sub=%0d rm=%0d a=%h b=%h exp %h/%b got %h/%b",
            path,
            line,
            sub,
            rm,
            a,
            b,
            exp_res,
            exp_flags,
            result,
            fflags
        );
    end
  endtask  // Automatic

  task automatic run_file(input string op, input logic op_sub, input string rname,
                          input logic [2:0] op_rm);
    string path;
    int fd;
    int line;
    logic [FLEN-1:0] fa;
    logic [FLEN-1:0] fb;
    logic [FLEN-1:0] exp_res;
    logic [4:0] exp_flags;
    path = {TfDir, FMT, "_", op, "_", rname, ".txt"};
    fd   = $fopen(path, "r");
    if (fd == 0) $fatal(1, "TB MISSING FILE: %s (run make testfloat)", path);
    line = 0;
    while ($fscanf(
        fd, "%h %h %h %h\n", fa, fb, exp_res, exp_flags
    ) == 4) begin
      line++;
      sub = op_sub;
      rm  = op_rm;
      a   = fa;
      b   = fb;
      #1;
      check(path, line, exp_res, exp_flags);
    end
    if (!$feof(fd)) $fatal(1, "TB BAD LINE: %s:%0d", path, line + 1);
    $fclose(fd);
    if (line == 0) $fatal(1, "TB EMPTY FILE: %s", path);
    $display("%s: %0d lines", path, line);
  endtask  // Automatic

  task automatic run_op(input string op, input logic op_sub);
    run_file(op, op_sub, "rne", RmRne);
    run_file(op, op_sub, "rtz", RmRtz);
    run_file(op, op_sub, "rdn", RmRdn);
    run_file(op, op_sub, "rup", RmRup);
    run_file(op, op_sub, "rmm", RmRmm);
  endtask  // Automatic

  task automatic run_nan_bits();
    for (int i = 0; i < FRAC_W; i++) begin
      sub = 1'b0;
      rm  = RmRne;
      a   = PosInf | (FLEN'(1) << i);
      b   = One;
      #1;
      check({FMT, " nan_bits_a"}, i, CanonNan, (i != FRAC_W - 1) ? FlagNv : '0);
      a = One;
      b = PosInf | (FLEN'(1) << i);
      #1;
      check({FMT, " nan_bits_b"}, i, CanonNan, (i != FRAC_W - 1) ? FlagNv : '0);
    end
  endtask  // Automatic

  initial begin
    run_op("add", 1'b0);
    run_op("sub", 1'b1);
    run_nan_bits();
    done = 1'b1;
  end

endmodule

`default_nettype wire
