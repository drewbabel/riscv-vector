`default_nettype none

module vec_fp_div_lane_tb
  import vec_pkg::*;
  import fp_pkg::RmRne, fp_pkg::RmRtz, fp_pkg::RmRdn, fp_pkg::RmRup, fp_pkg::RmRmm;
  import fp_pkg::FlagNx;
();

  localparam int FLEN = fp_pkg::FLEN;
  localparam int FlagW = $bits(fp_pkg::FlagNx);
  localparam int RmW = $bits(fp_pkg::RmRne);
  localparam int MinChecks = 2_000_000;
  localparam int OpTimeout = 400;
  localparam int StallPct = 25;
  localparam string TfDir = "build/testfloat/";

  localparam logic [FLEN-1:0] One = 'h3F80_0000;
  localparam logic [FLEN-1:0] Two = 'h4000_0000;
  localparam logic [FLEN-1:0] Three = 'h4040_0000;
  localparam logic [FLEN-1:0] Third = 'h3EAA_AAAB;
  localparam logic [FLEN-1:0] Root2 = 'h3FB5_04F3;
  localparam logic [FLEN-1:0] OneHalf = 'h3F00_0000;

  int checks = 0;
  int errors = 0;
  int max_errors = 0;
  int stall_pct = 0;
  int div_rev = 0;

  logic clk = 1'b0;
  logic rst_n = 1'b0;
  logic core_en = 1'b1;
  logic start;
  vec_fop_e op;
  logic [RmW-1:0] rm;
  logic [FLEN-1:0] a;
  logic [FLEN-1:0] b;
  logic [FLEN-1:0] result;
  logic [FlagW-1:0] fflags;
  logic busy;
  logic done;

  always #5 clk = ~clk;

  vec_fp_div_lane dut (
      .clk(clk),
      .rst_n(rst_n),
      .core_en(core_en),
      .start(start),
      .op(op),
      .rm(rm),
      .a(a),
      .b(b),
      .result(result),
      .fflags(fflags),
      .busy(busy),
      .done(done)
  );

  // Random stalls
  always @(negedge clk) core_en <= ($urandom_range(99) >= stall_pct);

  task automatic check(input string name, input logic [FLEN-1:0] got, input logic [FLEN-1:0] exp);
    checks++;
    if (got !== exp) begin
      errors++;
      $display("FAIL %s: got %h, expected %h", name, got, exp);
      if (errors == max_errors) $fatal(1, "TB STOPPED: %0d mismatches", errors);
    end
  endtask  // Automatic

  task automatic do_reset();
    @(negedge clk);
    rst_n = 1'b0;
    start = 1'b0;
    op = VEC_FDIV;
    rm = RmRne;
    a = '0;
    b = '0;
    repeat (2) @(posedge clk);
    @(negedge clk);
    rst_n = 1'b1;
  endtask  // Automatic

  // Raise start
  task automatic launch(input vec_fop_e o, input logic [RmW-1:0] mode, input logic [FLEN-1:0] x,
                        input logic [FLEN-1:0] y);
    logic taken;
    @(negedge clk);
    while (busy || done) @(negedge clk);
    op = o;
    rm = mode;
    a = x;
    b = y;
    start = 1'b1;
    taken = 1'b0;
    while (!taken) begin
      @(posedge clk);
      taken = core_en;
      @(negedge clk);
    end
    start = 1'b0;
    op = vec_fop_e'($urandom_range(2) + int'(VEC_FDIV));
    rm = RmW'($urandom);
    a = FLEN'($urandom);
    b = FLEN'($urandom);
  endtask  // Automatic

  task automatic wait_done();
    int lat;
    lat = 0;
    while (done !== 1'b1 && lat < OpTimeout) begin
      @(negedge clk);
      lat++;
    end
  endtask  // Automatic

  task automatic expect_result(input string name, input logic [FLEN-1:0] exp_res,
                               input logic [FlagW-1:0] exp_flags);
    check({name, " done"}, FLEN'(done), FLEN'(1'b1));
    check({name, " result"}, result, exp_res);
    check({name, " fflags"}, FLEN'(fflags), FLEN'(exp_flags));
  endtask  // Automatic

  task automatic expect_idle(input string name);
    check({name, " busy"}, FLEN'(busy), '0);
    check({name, " done"}, FLEN'(done), '0);
  endtask  // Automatic

  task automatic run_op(input string where, input vec_fop_e o, input logic [RmW-1:0] mode,
                        input logic [FLEN-1:0] x, input logic [FLEN-1:0] y,
                        input logic [FLEN-1:0] exp_res, input logic [FlagW-1:0] exp_flags);
    launch(o, mode, x, y);
    wait_done();
    expect_result({where, " ", o.name()}, exp_res, exp_flags);
  endtask  // Automatic

  // One TestFloat file
  task automatic run_file(input logic sq, input string rname, input logic [RmW-1:0] mode);
    string fname;
    int fd;
    int n;
    int line;
    logic [FLEN-1:0] x;
    logic [FLEN-1:0] y;
    logic [FLEN-1:0] exp_res;
    logic [FlagW-1:0] exp_flags;
    fname = {TfDir, "f32_", sq ? "sqrt" : "div", "_", rname, ".txt"};
    fd = $fopen(fname, "r");
    if (fd == 0) $fatal(1, "TB MISSING FILE: %s (run make testfloat)", fname);
    line = 0;
    while (!$feof(
        fd
    )) begin
      if (sq) n = $fscanf(fd, "%h %h %h\n", x, exp_res, exp_flags);
      else n = $fscanf(fd, "%h %h %h %h\n", x, y, exp_res, exp_flags);
      if (n == -1) break;
      line++;
      if (n != (sq ? 3 : 4)) $fatal(1, "TB BAD LINE: %s:%0d", fname, line);
      if (sq)
        run_op($sformatf("%s:%0d", fname, line), VEC_FSQRT, mode, x, FLEN'($urandom), exp_res,
               exp_flags);
      else if (1'($urandom)) begin
        div_rev++;
        run_op($sformatf("%s:%0d", fname, line), VEC_FRDIV, mode, y, x, exp_res, exp_flags);
      end else run_op($sformatf("%s:%0d", fname, line), VEC_FDIV, mode, x, y, exp_res, exp_flags);
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

  // Reverse operand order
  task automatic reverse_order();
    run_op("reverse", VEC_FRDIV, RmRne, Three, One, Third, FlagNx);
    run_op("reverse", VEC_FDIV, RmRne, Two, One, Two, '0);
    run_op("reverse", VEC_FRDIV, RmRne, Two, One, OneHalf, '0);
  endtask  // Automatic

  // Start while busy
  task automatic busy_start();
    launch(VEC_FDIV, RmRne, One, Three);
    repeat (3) @(negedge clk);
    op = VEC_FSQRT;
    a = Two;
    b = One;
    start = 1'b1;
    @(negedge clk);
    start = 1'b0;
    wait_done();
    expect_result("start while busy", Third, FlagNx);
  endtask  // Automatic

  // Done cycle start
  task automatic done_start();
    launch(VEC_FDIV, RmRne, One, Three);
    wait_done();
    expect_result("done start first", Third, FlagNx);
    op = VEC_FSQRT;
    a = Two;
    start = 1'b1;
    @(posedge clk);
    @(negedge clk);
    start = 1'b0;
    expect_idle("start in done cycle");
    check("result held after done", result, Third);
    run_op("after done start", VEC_FSQRT, RmRne, Two, '0, Root2, FlagNx);
  endtask  // Automatic

  // Reset mid operation
  task automatic reset_mid();
    launch(VEC_FDIV, RmRne, One, Three);
    repeat (5) @(negedge clk);
    do_reset();
    expect_idle("reset mid operation");
    run_op("after reset", VEC_FDIV, RmRne, One, Three, Third, FlagNx);
  endtask  // Automatic

  task automatic stalled_files();
    $dumpoff;
    stall_pct = StallPct;
    run_files(1'b0);
    run_files(1'b1);
    reverse_order();
    stall_pct = 0;
  endtask  // Automatic

  task automatic do_verdict();
    if (checks < MinChecks)
      $fatal(1, "TB UNDER-RAN: %0d checks, expected at least %0d", checks, MinChecks);
    if (div_rev == 0) $fatal(1, "TB UNDER-RAN: no reverse divides");
    if (errors == 0) $display("PASS: %0d checks, %0d mismatches", checks, errors);
    else $fatal(1, "FAIL: %0d mismatches, %0d checks", errors, checks);
    $finish;
  endtask  // Automatic

  initial void'($value$plusargs("max_errors=%d", max_errors));

  initial begin
    $dumpfile("vec_fp_div_lane_tb.vcd");
    $dumpvars(0, vec_fp_div_lane_tb);
    do_reset();

    reverse_order();
    busy_start();
    done_start();
    reset_mid();
    stalled_files();

    do_verdict();
  end

  // Handshake rule
  always @(negedge clk) if (rst_n && done) check("busy with done", FLEN'(busy), '0);

endmodule

`default_nettype wire
