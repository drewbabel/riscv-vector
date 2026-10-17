`default_nettype none

module fp_mul_tb ();

  localparam int MinChecks = 232000;
  localparam int MinStall  = 4000;
  localparam int MinHold   = 1000;

  int checks;
  int stall_checks;
  int hold_checks;
  int errors;
  int max_errors;

  fp_mul_bench #(
      .EXP_W (8),
      .FRAC_W(23),
      .FMT   ("f32")
  ) f32_bench ();

  fp_mul_bench #(
      .EXP_W (11),
      .FRAC_W(52),
      .FMT   ("f64")
  ) f64_bench ();

  fp_mul_bench #(
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
    if (errors != 0) $fatal(1, "FAIL: %0d mismatches, %0d checks", errors, checks);
    $display("PASS: %0d checks, %0d stall checks, %0d hold checks", checks, stall_checks,
             hold_checks);
    $finish;
  endtask  // Automatic

  initial begin
    $dumpfile("fp_mul_tb.vcd");
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

module fp_mul_bench
  import fp_pkg::RmRne, fp_pkg::RmRtz, fp_pkg::RmRdn, fp_pkg::RmRup, fp_pkg::RmRmm;
  import fp_pkg::FlagNv, fp_pkg::FpMulLatency;
#(
    parameter  int    EXP_W  = 8,
    parameter  int    FRAC_W = 23,
    parameter  string FMT    = "f32",
    localparam int    FLEN   = 1 + EXP_W + FRAC_W
) ();

  localparam int ShowErrors = 20;
  localparam int Latency    = FpMulLatency;
  localparam int StallOps   = 1000;
  localparam string TfDir = "build/testfloat/";
  localparam logic [FLEN-1:0] PosInf = {1'b0, {EXP_W{1'b1}}, {FRAC_W{1'b0}}};
  localparam logic [FLEN-1:0] One = {2'b00, {(EXP_W - 1) {1'b1}}, {FRAC_W{1'b0}}};
  localparam logic [FLEN-1:0] CanonNan = {1'b0, {EXP_W{1'b1}}, 1'b1, {(FRAC_W - 1) {1'b0}}};

  int checks = 0;
  int stall_checks = 0;
  int hold_checks = 0;
  int errors = 0;
  logic done = 1'b0;
  logic stalling = 1'b0;

  logic clk;
  logic rst_n = 1'b0;
  logic core_en = 1'b1;
  logic [2:0] rm = RmRne;
  logic [FLEN-1:0] a = '0;
  logic [FLEN-1:0] b = '0;
  logic [FLEN-1:0] result;
  logic [4:0] fflags;

  logic pend_valid[$];
  string pend_path[$];
  int pend_line[$];
  logic [2:0] pend_rm[$];
  logic [FLEN-1:0] pend_a[$];
  logic [FLEN-1:0] pend_b[$];
  logic [FLEN-1:0] pend_res[$];
  logic [4:0] pend_flags[$];

  initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;
  end

  fp_mul #(
      .ExpW (EXP_W),
      .FracW(FRAC_W)
  ) dut (
      .clk(clk),
      .rst_n(rst_n),
      .core_en(core_en),
      .rm(rm),
      .a(a),
      .b(b),
      .result(result),
      .fflags(fflags)
  );

  function automatic logic [FLEN-1:0] rand_bits();
    rand_bits = FLEN'({$urandom, $urandom});
  endfunction

  task automatic do_reset();
    @(negedge clk);
    rst_n = 1'b0;
    repeat (2) @(posedge clk);
    @(negedge clk);
    rst_n = 1'b1;
  endtask  // Automatic

  task automatic retire();
    string path;
    int line;
    logic valid;
    logic [2:0] op_rm;
    logic [FLEN-1:0] op_a;
    logic [FLEN-1:0] op_b;
    logic [FLEN-1:0] exp_res;
    logic [4:0] exp_flags;
    if (pend_valid.size() < Latency) return;
    valid = pend_valid.pop_front();
    path = pend_path.pop_front();
    line = pend_line.pop_front();
    op_rm = pend_rm.pop_front();
    op_a = pend_a.pop_front();
    op_b = pend_b.pop_front();
    exp_res = pend_res.pop_front();
    exp_flags = pend_flags.pop_front();
    if (!valid) return;
    if (stalling) stall_checks++;
    else checks++;
    if (result !== exp_res || fflags !== exp_flags) begin
      errors++;
      if (errors <= ShowErrors)
        $display(
            "FAIL %s:%0d rm=%0d a=%h b=%h exp %h/%b got %h/%b",
            path,
            line,
            op_rm,
            op_a,
            op_b,
            exp_res,
            exp_flags,
            result,
            fflags
        );
    end
  endtask  // Automatic

  task automatic stall();
    logic [FLEN-1:0] held_res;
    logic [4:0] held_flags;
    while (stalling && 1'($urandom)) begin
      held_res = result;
      held_flags = fflags;
      core_en = 1'b0;
      rm = 3'($urandom);
      a = rand_bits();
      b = rand_bits();
      @(negedge clk);
      hold_checks++;
      if (result !== held_res || fflags !== held_flags) begin
        errors++;
        if (errors <= ShowErrors)
          $display("FAIL hold: exp %h/%b got %h/%b", held_res, held_flags, result, fflags);
      end
    end
    core_en = 1'b1;
  endtask  // Automatic

  task automatic issue(input logic valid, input string path, input int line,
                       input logic [2:0] op_rm, input logic [FLEN-1:0] op_a,
                       input logic [FLEN-1:0] op_b, input logic [FLEN-1:0] exp_res,
                       input logic [4:0] exp_flags);
    @(negedge clk);
    retire();
    stall();
    rm = op_rm;
    a  = op_a;
    b  = op_b;
    pend_valid.push_back(valid);
    pend_path.push_back(path);
    pend_line.push_back(line);
    pend_rm.push_back(op_rm);
    pend_a.push_back(op_a);
    pend_b.push_back(op_b);
    pend_res.push_back(exp_res);
    pend_flags.push_back(exp_flags);
  endtask  // Automatic

  task automatic check(input string path, input int line, input logic [2:0] op_rm,
                       input logic [FLEN-1:0] op_a, input logic [FLEN-1:0] op_b,
                       input logic [FLEN-1:0] exp_res, input logic [4:0] exp_flags);
    issue(1'b1, path, line, op_rm, op_a, op_b, exp_res, exp_flags);
  endtask  // Automatic

  task automatic drain();
    repeat (Latency) begin
      issue(1'b0, "", 0, 3'($urandom), rand_bits(), rand_bits(), '0, '0);
    end
  endtask  // Automatic

  task automatic run_file(input string path, input logic [2:0] mode);
    int fd;
    int code;
    int lines;
    logic [FLEN-1:0] va;
    logic [FLEN-1:0] vb;
    logic [FLEN-1:0] vres;
    logic [4:0] vflags;
    fd = $fopen(path, "r");
    if (fd == 0) $fatal(1, "TB MISSING FILE: %s (run make testfloat)", path);
    lines = 0;
    forever begin
      code = $fscanf(fd, "%h %h %h %h\n", va, vb, vres, vflags);
      if (code != 4) break;
      lines++;
      check(path, lines, mode, va, vb, vres, vflags);
    end
    if (!$feof(fd)) $fatal(1, "TB BAD LINE: %s:%0d", path, lines + 1);
    $fclose(fd);
    if (lines == 0) $fatal(1, "TB EMPTY FILE: %s", path);
    $display("%s: %0d lines", path, lines);
  endtask  // Automatic

  task automatic run_stall_file(input string path, input logic [2:0] mode);
    int fd;
    int lines;
    logic [FLEN-1:0] va;
    logic [FLEN-1:0] vb;
    logic [FLEN-1:0] vres;
    logic [4:0] vflags;
    fd = $fopen(path, "r");
    if (fd == 0) $fatal(1, "TB MISSING FILE: %s (run make testfloat)", path);
    for (lines = 1; lines <= StallOps; lines++) begin
      if ($fscanf(fd, "%h %h %h %h\n", va, vb, vres, vflags) != 4)
        $fatal(1, "TB BAD LINE: %s:%0d", path, lines);
      check(path, lines, mode, va, vb, vres, vflags);
    end
    $fclose(fd);
  endtask  // Automatic

  task automatic run_stalls();
    stalling = 1'b1;
    run_stall_file({TfDir, FMT, "_mul_rne.txt"}, RmRne);
    run_stall_file({TfDir, FMT, "_mul_rtz.txt"}, RmRtz);
    run_stall_file({TfDir, FMT, "_mul_rup.txt"}, RmRup);
    run_stall_file({TfDir, FMT, "_mul_rmm.txt"}, RmRmm);
    drain();
    stalling = 1'b0;
    $display("%s stalls: %0d checks, %0d hold checks", FMT, stall_checks, hold_checks);
  endtask  // Automatic

  task automatic run_nan_payloads();
    logic [FLEN-1:0] nan;
    logic [4:0] flags;
    for (int i = 0; i < FRAC_W; i++) begin
      nan   = PosInf | (FLEN'(1) << i);
      flags = (i == FRAC_W - 1) ? '0 : FlagNv;
      check({FMT, " nan payload a"}, i, RmRne, nan, One, CanonNan, flags);
      check({FMT, " nan payload b"}, i, RmRne, One, nan, CanonNan, flags);
    end
  endtask  // Automatic

  initial begin
    do_reset();

    run_file({TfDir, FMT, "_mul_rne.txt"}, RmRne);
    run_file({TfDir, FMT, "_mul_rtz.txt"}, RmRtz);
    run_file({TfDir, FMT, "_mul_rdn.txt"}, RmRdn);
    run_file({TfDir, FMT, "_mul_rup.txt"}, RmRup);
    run_file({TfDir, FMT, "_mul_rmm.txt"}, RmRmm);
    run_nan_payloads();
    drain();
    run_stalls();

    done = 1'b1;
  end

endmodule

`default_nettype wire
