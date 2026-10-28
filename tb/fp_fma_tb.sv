`default_nettype none

module fp_fma_tb ();

  localparam int MinChecks = 7_900_000;
  localparam int MinStall  = 4000;
  localparam int MinHold   = 1000;

  int checks = 0;
  int stall_checks = 0;
  int hold_checks = 0;
  int errors = 0;

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

  task automatic under(input string fmt, input int n, input int stalled, input int held);
    if (n < MinChecks || stalled < MinStall || held < MinHold)
      $fatal(
          1, "TB UNDER-RAN: %s %0d checks, %0d stall checks, %0d hold checks", fmt, n, stalled, held
      );
  endtask  // Automatic

  task automatic do_verdict();
    under("f32", f32_bench.checks, f32_bench.stall_checks, f32_bench.hold_checks);
    under("f64", f64_bench.checks, f64_bench.stall_checks, f64_bench.hold_checks);
    under("f16", f16_bench.checks, f16_bench.stall_checks, f16_bench.hold_checks);
    checks = f32_bench.checks + f64_bench.checks + f16_bench.checks;
    stall_checks = f32_bench.stall_checks + f64_bench.stall_checks + f16_bench.stall_checks;
    hold_checks = f32_bench.hold_checks + f64_bench.hold_checks + f16_bench.hold_checks;
    errors = f32_bench.errors + f64_bench.errors + f16_bench.errors;
    if (errors == 0) $display("PASS: %0d checks, %0d mismatches", checks, errors);
    else $fatal(1, "FAIL: %0d mismatches, %0d checks", errors, checks);
    $finish;
  endtask  // Automatic

  initial begin
    $dumpfile("fp_fma_tb.vcd");
    $dumpvars(0, f32_bench);
    wait (f32_bench.done && f64_bench.done && f16_bench.done);
    do_verdict();
  end

endmodule

module fp_fma_bench
  import fp_pkg::RmRne, fp_pkg::RmRtz, fp_pkg::RmRdn, fp_pkg::RmRup, fp_pkg::RmRmm;
  import fp_pkg::FlagNx, fp_pkg::FpFmaLatency;
#(
    parameter  int    EXP_W  = 8,
    parameter  int    FRAC_W = 23,
    parameter  string FMT    = "f32",
    localparam int    FLEN   = 1 + EXP_W + FRAC_W
) ();

  localparam int Latency = FpFmaLatency;
  localparam int StallOps = 1000;
  localparam int FlagW = fp_pkg::FlagW;
  localparam int RmW = fp_pkg::RmW;
  localparam string TfDir = "build/testfloat/";
  localparam int Bias = (1 << (EXP_W - 1)) - 1;
  localparam int CarryW = (FRAC_W < 15) ? FRAC_W : 15;
  localparam logic [FLEN-1:0] One = {2'b00, {(EXP_W - 1) {1'b1}}, {FRAC_W{1'b0}}};
  localparam logic [FLEN-1:0] OnesBelow = {
    1'b0, EXP_W'(Bias + CarryW), {CarryW{1'b1}}, {(FRAC_W - CarryW) {1'b0}}
  };
  localparam logic [FLEN-1:0] CarryOut = {1'b0, EXP_W'(Bias + CarryW + 1), {FRAC_W{1'b0}}};

  int checks = 0;
  int stall_checks = 0;
  int hold_checks = 0;
  int errors = 0;
  int max_errors = 0;
  logic done = 1'b0;
  logic stalling = 1'b0;
  logic [RmW-1:0] file_rm = RmRne;

  logic clk = 1'b0;
  logic rst_n;
  logic core_en;
  logic neg_prod;
  logic neg_add;
  logic [RmW-1:0] rm;
  logic [FLEN-1:0] a;
  logic [FLEN-1:0] b;
  logic [FLEN-1:0] c;
  logic [FLEN-1:0] result;
  logic [FlagW-1:0] fflags;

  logic pend_valid[$];
  string pend_name[$];
  logic [FLEN-1:0] pend_res[$];
  logic [FlagW-1:0] pend_flags[$];

  initial void'($value$plusargs("max_errors=%d", max_errors));

  always #5 clk = ~clk;

  fp_fma #(
      .ExpW (EXP_W),
      .FracW(FRAC_W)
  ) dut (
      .clk(clk),
      .rst_n(rst_n),
      .core_en(core_en),
      .neg_prod(neg_prod),
      .neg_add(neg_add),
      .rm(rm),
      .a(a),
      .b(b),
      .c(c),
      .result(result),
      .fflags(fflags)
  );

  task automatic check(input string name, input logic [FLEN-1:0] got, input logic [FLEN-1:0] exp);
    checks++;
    if (got !== exp) begin
      errors++;
      $display("FAIL %s: got %h, expected %h", name, got, exp);
      if (errors == max_errors) $fatal(1, "TB STOPPED: %0d mismatches", errors);
    end
  endtask  // Automatic

  task automatic do_reset();
    rst_n = 1'b0;
    core_en = 1'b1;
    neg_prod = 1'b0;
    neg_add = 1'b0;
    rm = RmRne;
    a = '0;
    b = '0;
    c = '0;
    repeat (2) @(posedge clk);
    @(negedge clk);
    rst_n = 1'b1;
  endtask  // Automatic

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

  function automatic logic [FLEN-1:0] rand_bits();
    rand_bits = FLEN'({32'($urandom), 32'($urandom)});
  endfunction

  task automatic retire();
    logic valid;
    string name;
    logic [FLEN-1:0] exp_res;
    logic [FlagW-1:0] exp_flags;
    if (pend_valid.size() < Latency) return;
    valid = pend_valid.pop_front();
    name = pend_name.pop_front();
    exp_res = pend_res.pop_front();
    exp_flags = pend_flags.pop_front();
    if (!valid) return;
    if (stalling) stall_checks++;
    check({name, " result"}, result, exp_res);
    check({name, " flags"}, FLEN'(fflags), FLEN'(exp_flags));
  endtask  // Automatic

  task automatic stall();
    logic [ FLEN-1:0] held_res;
    logic [FlagW-1:0] held_flags;
    while (stalling && 1'($urandom)) begin
      held_res = result;
      held_flags = fflags;
      core_en = 1'b0;
      neg_prod = 1'($urandom);
      neg_add = 1'($urandom);
      rm = RmW'($urandom);
      a = rand_bits();
      b = rand_bits();
      c = rand_bits();
      @(negedge clk);
      hold_checks++;
      check("hold result", result, held_res);
      check("hold flags", FLEN'(fflags), FLEN'(held_flags));
    end
    core_en = 1'b1;
  endtask  // Automatic

  task automatic issue(input logic valid, input string name, input logic np, input logic na,
                       input logic [RmW-1:0] op_rm, input logic [FLEN-1:0] op_a,
                       input logic [FLEN-1:0] op_b, input logic [FLEN-1:0] op_c,
                       input logic [FLEN-1:0] exp_res, input logic [FlagW-1:0] exp_flags);
    @(negedge clk);
    retire();
    stall();
    neg_prod = np;
    neg_add = na;
    rm = op_rm;
    a = op_a;
    b = op_b;
    c = op_c;
    pend_valid.push_back(valid);
    pend_name.push_back(name);
    pend_res.push_back(exp_res);
    pend_flags.push_back(exp_flags);
  endtask  // Automatic

  task automatic drain();
    repeat (Latency) begin
      issue(1'b0, "", 1'($urandom), 1'($urandom), RmW'($urandom), rand_bits(), rand_bits(),
            rand_bits(), '0, '0);
    end
  endtask  // Automatic

  task automatic run_form(input string path, input int line, input logic np, input logic na,
                          input logic [FLEN-1:0] x, input logic [FLEN-1:0] y,
                          input logic [FLEN-1:0] z, input logic [FLEN-1:0] exp_res,
                          input logic [FlagW-1:0] exp_flags);
    logic [FLEN-1:0] op_a;
    logic [FLEN-1:0] op_c;
    op_a = {x[FLEN-1] ^ np, x[FLEN-2:0]};
    op_c = {z[FLEN-1] ^ na, z[FLEN-2:0]};
    issue(1'b1, $sformatf(
          "%s:%0d %s rm=%0d a=%h b=%h c=%h", path, line, form_name(np, na), file_rm, op_a, y, op_c),
          np, na, file_rm, op_a, y, op_c, exp_res, exp_flags);
  endtask  // Automatic

  task automatic run_vec(input string path, input int line, input logic [FLEN-1:0] x,
                         input logic [FLEN-1:0] y, input logic [FLEN-1:0] z,
                         input logic [FLEN-1:0] exp_res, input logic [FlagW-1:0] exp_flags);
    run_form(path, line, 1'b0, 1'b0, x, y, z, exp_res, exp_flags);
    run_form(path, line, 1'b0, 1'b1, x, y, z, exp_res, exp_flags);
    run_form(path, line, 1'b1, 1'b0, x, y, z, exp_res, exp_flags);
    run_form(path, line, 1'b1, 1'b1, x, y, z, exp_res, exp_flags);
  endtask  // Automatic

  task automatic run_file(input string path, input logic [RmW-1:0] mode);
    int fd;
    int line;
    logic [FLEN-1:0] x;
    logic [FLEN-1:0] y;
    logic [FLEN-1:0] z;
    logic [FLEN-1:0] exp_res;
    logic [FlagW-1:0] exp_flags;
    fd = $fopen(path, "r");
    if (fd == 0) $fatal(1, "TB MISSING FILE: %s (run make testfloat)", path);
    file_rm = mode;
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

  task automatic run_stalls();
    int fd;
    int line;
    logic [FLEN-1:0] x;
    logic [FLEN-1:0] y;
    logic [FLEN-1:0] z;
    logic [FLEN-1:0] exp_res;
    logic [FlagW-1:0] exp_flags;
    string path;
    path = {TfDir, FMT, "_mulAdd_rdn.txt"};
    fd   = $fopen(path, "r");
    if (fd == 0) $fatal(1, "TB MISSING FILE: %s (run make testfloat)", path);
    stalling = 1'b1;
    file_rm  = RmRdn;
    for (line = 1; line <= StallOps; line++) begin
      if ($fscanf(fd, "%h %h %h %h %h\n", x, y, z, exp_res, exp_flags) != 5)
        $fatal(1, "TB BAD LINE: %s:%0d", path, line);
      run_vec(path, line, x, y, z, exp_res, exp_flags);
    end
    $fclose(fd);
    drain();
    stalling = 1'b0;
    $display("%s stalls: %0d checks, %0d hold checks", FMT, stall_checks, hold_checks);
  endtask  // Automatic

  task automatic run_directed();
    file_rm = RmRup;
    run_vec({FMT, " directed"}, 1, One, One, FLEN'(8), One | FLEN'(1), FlagNx);
    file_rm = RmRne;
    run_vec({FMT, " directed"}, 2, One, One, OnesBelow, CarryOut, '0);
  endtask  // Automatic

  task automatic mark_done();
    done = 1'b1;
  endtask  // Automatic

  initial begin
    do_reset();

    run_file({TfDir, FMT, "_mulAdd_rne.txt"}, RmRne);
    run_file({TfDir, FMT, "_mulAdd_rtz.txt"}, RmRtz);
    run_file({TfDir, FMT, "_mulAdd_rdn.txt"}, RmRdn);
    run_file({TfDir, FMT, "_mulAdd_rup.txt"}, RmRup);
    run_file({TfDir, FMT, "_mulAdd_rmm.txt"}, RmRmm);

    run_directed();
    drain();
    run_stalls();

    mark_done();
  end

endmodule

`default_nettype wire
