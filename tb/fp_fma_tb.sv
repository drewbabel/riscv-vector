`default_nettype none

module fp_fma_tb ();

  localparam int MinChecks = 3_950_000;

  int checks;
  int errors;
  int max_errors;

  fp_fma_bench #(
      .EXP_W (8),
      .FRAC_W(23),
      .FMT   ("f32")
  ) f32_bench ();

  fp_fma_bench #(
      .EXP_W (11),
      .FRAC_W(52),
      .FMT   ("f64")
  ) f64_bench ();

  fp_fma_bench #(
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
    $dumpfile("fp_fma_tb.vcd");
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

module fp_fma_bench
  import fp_pkg::RmRne, fp_pkg::RmRtz, fp_pkg::RmRdn, fp_pkg::RmRup, fp_pkg::RmRmm;
  import fp_pkg::FlagNx;
#(
    parameter  int    EXP_W  = 8,
    parameter  int    FRAC_W = 23,
    parameter  string FMT    = "f32",
    localparam int    FLEN   = 1 + EXP_W + FRAC_W
) ();

  localparam int ShowErrors = 20;
  localparam string TfDir = "build/testfloat/";
  localparam int Bias = (1 << (EXP_W - 1)) - 1;
  localparam int CarryW = (FRAC_W < 15) ? FRAC_W : 15;

  localparam logic [FLEN-1:0] One = {2'b00, {(EXP_W - 1) {1'b1}}, {FRAC_W{1'b0}}};
  localparam logic [FLEN-1:0] OnesBelow = {
    1'b0, EXP_W'(Bias + CarryW), {CarryW{1'b1}}, {(FRAC_W - CarryW) {1'b0}}
  };
  localparam logic [FLEN-1:0] CarryOut = {1'b0, EXP_W'(Bias + CarryW + 1), {FRAC_W{1'b0}}};

  int checks = 0;
  int errors = 0;
  logic done = 1'b0;

  logic neg_prod;
  logic neg_add;
  logic [2:0] rm;
  logic [FLEN-1:0] a;
  logic [FLEN-1:0] b;
  logic [FLEN-1:0] c;
  logic [FLEN-1:0] result;
  logic [4:0] fflags;

  fp_fma #(
      .ExpW (EXP_W),
      .FracW(FRAC_W)
  ) dut (
      .neg_prod(neg_prod),
      .neg_add(neg_add),
      .rm(rm),
      .a(a),
      .b(b),
      .c(c),
      .result(result),
      .fflags(fflags)
  );

  function automatic string form_name(input logic np, input logic na);
    case ({
      np, na
    })
      2'b00:   form_name = "FMADD";
      2'b01:   form_name = "FMSUB";
      2'b10:   form_name = "FNMSUB";
      default: form_name = "FNMADD";
    endcase
  endfunction

  task automatic check(input string path, input int line, input logic [FLEN-1:0] exp_res,
                       input logic [4:0] exp_flags);
    checks++;
    if (result !== exp_res || fflags !== exp_flags) begin
      errors++;
      if (errors <= ShowErrors)
        $display(
            "FAIL %s:%0d %s rm=%0d a=%h b=%h c=%h exp %h/%b got %h/%b",
            path,
            line,
            form_name(
                neg_prod, neg_add
            ),
            rm,
            a,
            b,
            c,
            exp_res,
            exp_flags,
            result,
            fflags
        );
    end
  endtask  // Automatic

  task automatic run_form(input string path, input int line, input logic np, input logic na,
                          input logic [FLEN-1:0] x, input logic [FLEN-1:0] y,
                          input logic [FLEN-1:0] z, input logic [FLEN-1:0] exp_res,
                          input logic [4:0] exp_flags);
    neg_prod = np;
    neg_add = na;
    a = {x[FLEN-1] ^ np, x[FLEN-2:0]};
    b = y;
    c = {z[FLEN-1] ^ na, z[FLEN-2:0]};
    #1;
    check(path, line, exp_res, exp_flags);
  endtask  // Automatic

  task automatic run_vec(input string path, input int line, input logic [FLEN-1:0] x,
                         input logic [FLEN-1:0] y, input logic [FLEN-1:0] z,
                         input logic [FLEN-1:0] exp_res, input logic [4:0] exp_flags);
    run_form(path, line, 1'b0, 1'b0, x, y, z, exp_res, exp_flags);
    run_form(path, line, 1'b0, 1'b1, x, y, z, exp_res, exp_flags);
    run_form(path, line, 1'b1, 1'b0, x, y, z, exp_res, exp_flags);
    run_form(path, line, 1'b1, 1'b1, x, y, z, exp_res, exp_flags);
  endtask  // Automatic

  task automatic run_file(input string rname, input logic [2:0] mode);
    string path;
    int fd;
    int line;
    logic [FLEN-1:0] x;
    logic [FLEN-1:0] y;
    logic [FLEN-1:0] z;
    logic [FLEN-1:0] exp_res;
    logic [4:0] exp_flags;
    path = {TfDir, FMT, "_mulAdd_", rname, ".txt"};
    fd   = $fopen(path, "r");
    if (fd == 0) $fatal(1, "TB MISSING FILE: %s (run make testfloat)", path);
    rm   = mode;
    line = 0;
    while ($fscanf(
        fd, "%h %h %h %h %h\n", x, y, z, exp_res, exp_flags
    ) == 5) begin
      line++;
      run_vec(path, line, x, y, z, exp_res, exp_flags);
    end
    if (!$feof(fd)) $fatal(1, "TB BAD LINE: %s:%0d", path, line + 1);
    $fclose(fd);
    if (line == 0) $fatal(1, "TB EMPTY FILE: %s", path);
    $display("%s: %0d lines", path, line);
  endtask  // Automatic

  initial begin
    run_file("rne", RmRne);
    run_file("rtz", RmRtz);
    run_file("rdn", RmRdn);
    run_file("rup", RmRup);
    run_file("rmm", RmRmm);

    rm = RmRup;
    run_vec({FMT, " directed"}, 1, One, One, FLEN'(8), One | FLEN'(1), FlagNx);
    rm = RmRne;
    run_vec({FMT, " directed"}, 2, One, One, OnesBelow, CarryOut, '0);
    done = 1'b1;
  end

endmodule

`default_nettype wire
