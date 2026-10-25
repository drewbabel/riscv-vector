`default_nettype none

module fp_add_tb ();

  localparam int MinChecks = 940000;
  localparam int MinStall  = 4000;
  localparam int MinHold   = 1000;

  int checks = 0;
  int stall_checks = 0;
  int hold_checks = 0;
  int errors = 0;

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
    $dumpfile("fp_add_tb.vcd");
    $dumpvars(0, f32_bench);
    wait (f32_bench.done && f64_bench.done && f16_bench.done);
    do_verdict();
  end

endmodule

module fp_add_bench
  import fp_pkg::RmRne, fp_pkg::RmRtz, fp_pkg::RmRdn, fp_pkg::RmRup, fp_pkg::RmRmm;
  import fp_pkg::FlagNv, fp_pkg::FpAddLatency;
#(
    parameter  int    EXP_W  = 8,
    parameter  int    FRAC_W = 23,
    parameter  string FMT    = "f32",
    localparam int    FLEN   = 1 + EXP_W + FRAC_W
) ();

  localparam int Latency = FpAddLatency;
  localparam int StallOps = 1000;
  localparam int FlagW = $bits(FlagNv);
  localparam int RmW = $bits(RmRne);
  localparam string TfDir = "build/testfloat/";
  localparam logic [FLEN-1:0] PosInf = {1'b0, {EXP_W{1'b1}}, {FRAC_W{1'b0}}};
  localparam logic [FLEN-1:0] One = {2'b00, {(EXP_W - 1) {1'b1}}, {FRAC_W{1'b0}}};
  localparam logic [FLEN-1:0] CanonNan = {1'b0, {EXP_W{1'b1}}, 1'b1, {(FRAC_W - 1) {1'b0}}};

  int checks = 0;
  int stall_checks = 0;
  int hold_checks = 0;
  int errors = 0;
  int max_errors = 0;
  logic done = 1'b0;
  logic stalling = 1'b0;

  logic clk = 1'b0;
  logic rst_n;
  logic core_en;
  logic sub;
  logic [RmW-1:0] rm;
  logic [FLEN-1:0] a;
  logic [FLEN-1:0] b;
  logic [FLEN-1:0] result;
  logic [FlagW-1:0] fflags;

  logic pend_valid[$];
  string pend_name[$];
  logic [FLEN-1:0] pend_res[$];
  logic [FlagW-1:0] pend_flags[$];

  initial void'($value$plusargs("max_errors=%d", max_errors));

  always #5 clk = ~clk;

  fp_add #(
      .ExpW (EXP_W),
      .FracW(FRAC_W)
  ) dut (
      .clk(clk),
      .rst_n(rst_n),
      .core_en(core_en),
      .sub(sub),
      .rm(rm),
      .a(a),
      .b(b),
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
    sub = 1'b0;
    rm = RmRne;
    a = '0;
    b = '0;
    repeat (2) @(posedge clk);
    @(negedge clk);
    rst_n = 1'b1;
  endtask  // Automatic

  function automatic logic [FLEN-1:0] rand_bits();
    rand_bits = FLEN'({$urandom, $urandom});
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
      sub = 1'($urandom);
      rm = RmW'($urandom);
      a = rand_bits();
      b = rand_bits();
      @(negedge clk);
      hold_checks++;
      check("hold result", result, held_res);
      check("hold flags", FLEN'(fflags), FLEN'(held_flags));
    end
    core_en = 1'b1;
  endtask  // Automatic

  task automatic issue(input logic valid, input string name, input logic op_sub,
                       input logic [RmW-1:0] op_rm, input logic [FLEN-1:0] op_a,
                       input logic [FLEN-1:0] op_b, input logic [FLEN-1:0] exp_res,
                       input logic [FlagW-1:0] exp_flags);
    @(negedge clk);
    retire();
    stall();
    sub = op_sub;
    rm  = op_rm;
    a   = op_a;
    b   = op_b;
    pend_valid.push_back(valid);
    pend_name.push_back(name);
    pend_res.push_back(exp_res);
    pend_flags.push_back(exp_flags);
  endtask  // Automatic

  task automatic send(input string path, input int line, input logic op_sub,
                      input logic [RmW-1:0] op_rm, input logic [FLEN-1:0] op_a,
                      input logic [FLEN-1:0] op_b, input logic [FLEN-1:0] exp_res,
                      input logic [FlagW-1:0] exp_flags);
    issue(1'b1, $sformatf("%s:%0d sub=%0d rm=%0d a=%h b=%h", path, line, op_sub, op_rm, op_a, op_b),
          op_sub, op_rm, op_a, op_b, exp_res, exp_flags);
  endtask  // Automatic

  task automatic drain();
    repeat (Latency) begin
      issue(1'b0, "", 1'($urandom), RmW'($urandom), rand_bits(), rand_bits(), '0, '0);
    end
  endtask  // Automatic

  task automatic run_file(input string path, input logic op_sub, input logic [RmW-1:0] op_rm);
    int fd;
    int line;
    logic [FLEN-1:0] fa;
    logic [FLEN-1:0] fb;
    logic [FLEN-1:0] exp_res;
    logic [FlagW-1:0] exp_flags;
    fd = $fopen(path, "r");
    if (fd == 0) $fatal(1, "TB MISSING FILE: %s (run make testfloat)", path);
    line = 0;
    while ($fscanf(
        fd, "%h %h %h %h\n", fa, fb, exp_res, exp_flags
    ) == 4) begin
      line++;
      send(path, line, op_sub, op_rm, fa, fb, exp_res, exp_flags);
    end
    if (!$feof(fd)) $fatal(1, "TB BAD LINE: %s:%0d", path, line + 1);
    $fclose(fd);
    if (line == 0) $fatal(1, "TB EMPTY FILE: %s", path);
    $display("%s: %0d lines", path, line);
  endtask  // Automatic

  task automatic run_stall_file(input string path, input logic op_sub, input logic [RmW-1:0] op_rm);
    int fd;
    int line;
    logic [FLEN-1:0] fa;
    logic [FLEN-1:0] fb;
    logic [FLEN-1:0] exp_res;
    logic [FlagW-1:0] exp_flags;
    fd = $fopen(path, "r");
    if (fd == 0) $fatal(1, "TB MISSING FILE: %s (run make testfloat)", path);
    for (line = 1; line <= StallOps; line++) begin
      if ($fscanf(fd, "%h %h %h %h\n", fa, fb, exp_res, exp_flags) != 4)
        $fatal(1, "TB BAD LINE: %s:%0d", path, line);
      send(path, line, op_sub, op_rm, fa, fb, exp_res, exp_flags);
    end
    $fclose(fd);
  endtask  // Automatic

  task automatic run_stalls();
    stalling = 1'b1;
    run_stall_file({TfDir, FMT, "_add_rne.txt"}, 1'b0, RmRne);
    run_stall_file({TfDir, FMT, "_add_rdn.txt"}, 1'b0, RmRdn);
    run_stall_file({TfDir, FMT, "_sub_rup.txt"}, 1'b1, RmRup);
    run_stall_file({TfDir, FMT, "_sub_rmm.txt"}, 1'b1, RmRmm);
    drain();
    stalling = 1'b0;
    $display("%s stalls: %0d checks, %0d hold checks", FMT, stall_checks, hold_checks);
  endtask  // Automatic

  task automatic run_nan_bits();
    for (int i = 0; i < FRAC_W; i++) begin
      send({FMT, " nan_bits_a"}, i, 1'b0, RmRne, PosInf | (FLEN'(1) << i), One, CanonNan,
           (i != FRAC_W - 1) ? FlagNv : '0);
      send({FMT, " nan_bits_b"}, i, 1'b0, RmRne, One, PosInf | (FLEN'(1) << i), CanonNan,
           (i != FRAC_W - 1) ? FlagNv : '0);
    end
  endtask  // Automatic

  task automatic mark_done();
    done = 1'b1;
  endtask  // Automatic

  initial begin
    do_reset();

    run_file({TfDir, FMT, "_add_rne.txt"}, 1'b0, RmRne);
    run_file({TfDir, FMT, "_add_rtz.txt"}, 1'b0, RmRtz);
    run_file({TfDir, FMT, "_add_rdn.txt"}, 1'b0, RmRdn);
    run_file({TfDir, FMT, "_add_rup.txt"}, 1'b0, RmRup);
    run_file({TfDir, FMT, "_add_rmm.txt"}, 1'b0, RmRmm);

    run_file({TfDir, FMT, "_sub_rne.txt"}, 1'b1, RmRne);
    run_file({TfDir, FMT, "_sub_rtz.txt"}, 1'b1, RmRtz);
    run_file({TfDir, FMT, "_sub_rdn.txt"}, 1'b1, RmRdn);
    run_file({TfDir, FMT, "_sub_rup.txt"}, 1'b1, RmRup);
    run_file({TfDir, FMT, "_sub_rmm.txt"}, 1'b1, RmRmm);

    run_nan_bits();
    drain();
    run_stalls();
    mark_done();
  end

endmodule

`default_nettype wire
