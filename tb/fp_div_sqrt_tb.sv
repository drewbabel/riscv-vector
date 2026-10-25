`default_nettype none

module fp_div_sqrt_tb ();

  localparam int MinChecks = 1_300_000;

  int checks = 0;
  int errors = 0;

  fp_div_sqrt_bench #(
      .EXP_W (8),
      .FRAC_W(23),
      .FMT   ("f32"),
      .THIRD (32'h3EAA_AAAB),
      .ROOT2 (32'h3FB5_04F3)
  ) f32_bench ();

  fp_div_sqrt_bench #(
      .EXP_W (11),
      .FRAC_W(52),
      .FMT   ("f64"),
      .THIRD (64'h3FD5_5555_5555_5555),
      .ROOT2 (64'h3FF6_A09E_667F_3BCD)
  ) f64_bench ();

  fp_div_sqrt_bench #(
      .EXP_W (5),
      .FRAC_W(10),
      .FMT   ("f16"),
      .THIRD (16'h3555),
      .ROOT2 (16'h3DA8)
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
    if (errors == 0) $display("PASS: %0d checks, %0d mismatches", checks, errors);
    else $fatal(1, "FAIL: %0d mismatches, %0d checks", errors, checks);
    $finish;
  endtask  // Automatic

  initial begin
    $dumpfile("fp_div_sqrt_tb.vcd");
    $dumpvars(0, f32_bench);
    wait (f32_bench.done_all && f64_bench.done_all && f16_bench.done_all);
    do_verdict();
  end

endmodule

module fp_div_sqrt_bench
  import fp_pkg::RmRne, fp_pkg::RmRtz, fp_pkg::RmRdn, fp_pkg::RmRup, fp_pkg::RmRmm;
  import fp_pkg::FlagNx;
#(
    parameter  int               EXP_W  = 8,
    parameter  int               FRAC_W = 23,
    parameter  string            FMT    = "f32",
    localparam int               FLEN   = 1 + EXP_W + FRAC_W,
    parameter  logic  [FLEN-1:0] THIRD  = 'h3EAA_AAAB,
    parameter  logic  [FLEN-1:0] ROOT2  = 'h3FB5_04F3
) ();

  localparam int StallCycles = 7;
  localparam int Bias = (1 << (EXP_W - 1)) - 1;
  localparam int FlagW = $bits(FlagNx);
  localparam int RmW = $bits(RmRne);
  localparam string TfDir = "build/testfloat/";

  localparam logic [FLEN-1:0] One = {2'b00, {(EXP_W - 1) {1'b1}}, {FRAC_W{1'b0}}};
  localparam logic [FLEN-1:0] Two = {1'b0, EXP_W'(Bias + 1), {FRAC_W{1'b0}}};
  localparam logic [FLEN-1:0] Three = {1'b0, EXP_W'(Bias + 1), 1'b1, {(FRAC_W - 1) {1'b0}}};
  localparam logic [FLEN-1:0] Third = THIRD;
  localparam logic [FLEN-1:0] Root2 = ROOT2;

  int checks = 0;
  int errors = 0;
  int max_errors = 0;
  int timeout = 200;
  int div_latency = -1;
  int sqrt_latency = -1;
  logic done_all = 1'b0;

  logic clk = 1'b0;
  logic rst_n;
  logic core_en;
  logic start;
  logic sqrt;
  logic [RmW-1:0] rm;
  logic [FLEN-1:0] a;
  logic [FLEN-1:0] b;
  logic [FLEN-1:0] result;
  logic [FlagW-1:0] fflags;
  logic busy;
  logic done;

  initial void'($value$plusargs("max_errors=%d", max_errors));
  initial void'($value$plusargs("timeout=%d", timeout));

  always #5 clk = ~clk;

  fp_div_sqrt #(
      .ExpW (EXP_W),
      .FracW(FRAC_W)
  ) dut (
      .clk(clk),
      .rst_n(rst_n),
      .core_en(core_en),
      .start(start),
      .sqrt(sqrt),
      .rm(rm),
      .a(a),
      .b(b),
      .result(result),
      .fflags(fflags),
      .busy(busy),
      .done(done)
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
    start = 1'b0;
    sqrt = 1'b0;
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

  function automatic string op_name(input logic sq);
    op_name = sq ? "sqrt" : "div";
  endfunction

  task automatic launch(input logic sq, input logic [RmW-1:0] mode, input logic [FLEN-1:0] x,
                        input logic [FLEN-1:0] y);
    int n;
    n = 0;
    @(negedge clk);
    while ((busy === 1'b1 || done === 1'b1) && n < timeout) begin
      @(negedge clk);
      n++;
    end
    sqrt = sq;
    rm = mode;
    a = x;
    b = y;
    start = 1'b1;
    @(posedge clk);
    @(negedge clk);
    start = 1'b0;
    sqrt = 1'($urandom);
    rm = RmW'($urandom);
    a = rand_bits();
    b = rand_bits();
  endtask  // Automatic

  task automatic wait_done(output logic [FLEN-1:0] res, output logic [FlagW-1:0] flags,
                           output int lat);
    lat = 0;
    while (done !== 1'b1 && lat < timeout) begin
      @(negedge clk);
      lat++;
    end
    res   = result;
    flags = fflags;
    if (done !== 1'b1) lat = -1;
  endtask  // Automatic

  task automatic do_op(input logic sq, input logic [RmW-1:0] mode, input logic [FLEN-1:0] x,
                       input logic [FLEN-1:0] y, output logic [FLEN-1:0] res,
                       output logic [FlagW-1:0] flags, output int lat);
    launch(sq, mode, x, y);
    wait_done(res, flags, lat);
  endtask  // Automatic

  task automatic check_op(
      input string fname, input int line, input logic sq, input logic [FLEN-1:0] x,
      input logic [FLEN-1:0] y, input logic [FLEN-1:0] exp_res, input logic [FlagW-1:0] exp_flags,
      input logic [FLEN-1:0] got_res, input logic [FlagW-1:0] got_flags, input int lat);
    string name;
    name = $sformatf("%s %s:%0d %s a=%h b=%h", FMT, fname, line, op_name(sq), x, y);
    check({name, " done"}, FLEN'(lat >= 0), FLEN'(1'b1));
    check({name, " result"}, got_res, exp_res);
    check({name, " flags"}, FLEN'(got_flags), FLEN'(exp_flags));
  endtask  // Automatic

  task automatic check_state(input string name, input logic exp_busy, input logic exp_done);
    check({FMT, " ", name, " busy"}, FLEN'(busy), FLEN'(exp_busy));
    check({FMT, " ", name, " done"}, FLEN'(done), FLEN'(exp_done));
  endtask  // Automatic

  task automatic run_file(input logic sq, input string rname, input logic [RmW-1:0] mode);
    string fname;
    int fd;
    int n;
    int line;
    logic [FLEN-1:0] x;
    logic [FLEN-1:0] y;
    logic [FLEN-1:0] exp_res;
    logic [FlagW-1:0] exp_flags;
    logic [FLEN-1:0] got_res;
    logic [FlagW-1:0] got_flags;
    int lat;
    fname = {TfDir, FMT, "_", op_name(sq), "_", rname, ".txt"};
    fd = $fopen(fname, "r");
    if (fd == 0) $fatal(1, "TB MISSING FILE: %s (run make testfloat)", fname);
    line = 0;
    while (!$feof(
        fd
    )) begin
      if (sq) begin
        n = $fscanf(fd, "%h %h %h\n", x, exp_res, exp_flags);
        y = rand_bits();
      end else begin
        n = $fscanf(fd, "%h %h %h %h\n", x, y, exp_res, exp_flags);
      end
      if (n == -1) break;
      line++;
      if (n != (sq ? 3 : 4)) $fatal(1, "TB BAD LINE: %s:%0d", fname, line);
      do_op(sq, mode, x, y, got_res, got_flags, lat);
      check_op(fname, line, sq, x, y, exp_res, exp_flags, got_res, got_flags, lat);
    end
    $fclose(fd);
    if (line == 0) $fatal(1, "TB EMPTY FILE: %s", fname);
    $display("%s: %0d lines", fname, line);
  endtask  // Automatic

  task automatic run_files(input logic sq);
    run_file(sq, "rne", RmRne);
    run_file(sq, "rtz", RmRtz);
    run_file(sq, "rdn", RmRdn);
    run_file(sq, "rup", RmRup);
    run_file(sq, "rmm", RmRmm);
  endtask  // Automatic

  task automatic measure_latency();
    logic [ FLEN-1:0] res;
    logic [FlagW-1:0] flags;
    do_op(1'b0, RmRne, One, Three, res, flags, div_latency);
    check_op("divide latency", 0, 1'b0, One, Three, Third, FlagNx, res, flags, div_latency);
    do_op(1'b1, RmRne, Two, '0, res, flags, sqrt_latency);
    check_op("sqrt latency", 0, 1'b1, Two, '0, Root2, FlagNx, res, flags, sqrt_latency);
    $display("%s divide latency: %0d cycles", FMT, div_latency);
    $display("%s sqrt latency: %0d cycles", FMT, sqrt_latency);
  endtask  // Automatic

  task automatic busy_start();
    logic [FLEN-1:0] res;
    logic [FlagW-1:0] flags;
    int lat;
    launch(1'b0, RmRne, One, Three);
    @(negedge clk);
    sqrt = 1'b0;
    rm = RmRtz;
    a = Two;
    b = One;
    start = 1'b1;
    @(negedge clk);
    start = 1'b0;
    wait_done(res, flags, lat);
    check_op("start while busy", 0, 1'b0, One, Three, Third, FlagNx, res, flags, lat);
  endtask  // Automatic

  task automatic done_start();
    logic [FLEN-1:0] res;
    logic [FlagW-1:0] flags;
    int lat;
    do_op(1'b0, RmRne, One, Three, res, flags, lat);
    check_op("start in done cycle", 0, 1'b0, One, Three, Third, FlagNx, res, flags, lat);
    sqrt  = 1'b1;
    rm    = RmRne;
    a     = Two;
    b     = '0;
    start = 1'b1;
    check_state("start in done cycle before the edge", 1'b0, 1'b1);
    @(posedge clk);
    @(negedge clk);
    start = 1'b0;
    a = rand_bits();
    check_state("start in done cycle after the edge", 1'b1, 1'b0);
    wait_done(res, flags, lat);
    check_op("start in done cycle", 1, 1'b1, Two, '0, Root2, FlagNx, res, flags, lat);
    check({FMT, " start in done cycle latency"}, FLEN'(lat), FLEN'(sqrt_latency));
  endtask  // Automatic

  task automatic reset_mid();
    logic [FLEN-1:0] res;
    logic [FlagW-1:0] flags;
    int lat;
    launch(1'b0, RmRne, One, Three);
    repeat (5) @(negedge clk);
    do_reset();
    check_state("reset mid operation", 1'b0, 1'b0);
    do_op(1'b0, RmRne, One, Three, res, flags, lat);
    check_op("after reset", 0, 1'b0, One, Three, Third, FlagNx, res, flags, lat);
  endtask  // Automatic

  task automatic stall_one(input logic sq, input logic [FLEN-1:0] x, input logic [FLEN-1:0] y,
                           input logic [FLEN-1:0] exp_res, input int base_lat);
    logic [FLEN-1:0] res;
    logic [FlagW-1:0] flags;
    int lat;
    int pre;
    check({FMT, " core_en stall ", op_name(sq), " unstalled latency known"}, FLEN'(base_lat >= 2),
          FLEN'(1'b1));
    if (base_lat < 2) return;
    pre = base_lat / 2;
    launch(sq, RmRne, x, y);
    repeat (pre - 1) @(negedge clk);
    core_en = 1'b0;
    for (int i = 0; i < StallCycles; i++) begin
      @(negedge clk);
      check_state($sformatf("core_en stall %s cycle %0d", op_name(sq), i), 1'b1, 1'b0);
    end
    core_en = 1'b1;
    wait_done(res, flags, lat);
    if (lat >= 0) lat = lat + pre - 1 + StallCycles;
    check_op("core_en stall", 0, sq, x, y, exp_res, FlagNx, res, flags, lat);
    check({FMT, " core_en stall ", op_name(sq), " latency"}, FLEN'(lat),
          FLEN'(base_lat + StallCycles));
  endtask  // Automatic

  task automatic core_en_stall();
    stall_one(1'b0, One, Three, Third, div_latency);
    stall_one(1'b1, Two, '0, Root2, sqrt_latency);
  endtask  // Automatic

  task automatic done_pulse();
    logic [FLEN-1:0] res;
    logic [FlagW-1:0] flags;
    int lat;
    do_op(1'b0, RmRne, One, Three, res, flags, lat);
    check_op("done pulse", 0, 1'b0, One, Three, Third, FlagNx, res, flags, lat);
    @(negedge clk);
    check_state("done pulse a cycle later", 1'b0, 1'b0);
  endtask  // Automatic

  task automatic mark_done();
    @(posedge clk);
    done_all = 1'b1;
  endtask  // Automatic

  initial begin
    do_reset();
    run_files(1'b0);
    run_files(1'b1);
    measure_latency();
    busy_start();
    done_start();
    reset_mid();
    core_en_stall();
    done_pulse();
    mark_done();
  end

endmodule

`default_nettype wire
