`default_nettype none

module vec_fp_div_lane_tb
  import vec_pkg::*;
  import fp_pkg::RmRne, fp_pkg::RmRtz, fp_pkg::RmRdn, fp_pkg::RmRup, fp_pkg::RmRmm;
  import fp_pkg::FlagNx;
();

  localparam int MinChecks = 5 * (46464 + 46464);
  localparam int OpTimeout = 400;
  localparam int StallPct = 25;
  localparam string TfDir = "build/testfloat/";

  localparam logic [31:0] One = 32'h3F80_0000;
  localparam logic [31:0] Two = 32'h4000_0000;
  localparam logic [31:0] Three = 32'h4040_0000;
  localparam logic [31:0] Third = 32'h3EAA_AAAB;
  localparam logic [31:0] Root2 = 32'h3FB5_04F3;
  localparam logic [31:0] OneHalf = 32'h3F00_0000;

  int checks = 0;
  int errors = 0;
  int max_errors = 0;
  int stall_pct = 0;
  int div_rev = 0;

  logic clk = 1'b0;
  logic rst_n = 1'b0;
  logic core_en = 1'b1;
  logic start = 1'b0;
  vec_fop_e op = VEC_FDIV;
  logic [2:0] rm = RmRne;
  logic [31:0] a = '0;
  logic [31:0] b = '0;
  logic [31:0] result;
  logic [4:0] fflags;
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

  // Handshake rule
  always @(posedge clk)
    if (rst_n && busy && done) begin
      errors++;
      $display("FAIL busy and done both high at %0t", $time);
      if (errors == max_errors) $fatal(1, "TB STOPPED: %0d mismatches", errors);
    end

  task automatic fail(input string msg);
    errors++;
    if (errors <= 20) $display("FAIL %s", msg);
    if (errors == max_errors) $fatal(1, "TB STOPPED: %0d mismatches", errors);
  endtask

  // Raise start
  task automatic launch(input vec_fop_e o, input logic [2:0] mode, input logic [31:0] x,
                        input logic [31:0] y);
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
    op = vec_fop_e'($urandom_range(2) + 32'(VEC_FDIV));
    rm = 3'($urandom);
    a = $urandom;
    b = $urandom;
  endtask

  task automatic wait_done(output int lat);
    lat = 0;
    while (done !== 1'b1 && lat < OpTimeout) begin
      @(negedge clk);
      lat++;
    end
    if (done !== 1'b1) lat = -1;
  endtask

  task automatic check(input string where, input vec_fop_e o, input logic [2:0] mode,
                       input logic [31:0] x, input logic [31:0] y, input logic [31:0] exp_res,
                       input logic [4:0] exp_flags);
    int lat;
    launch(o, mode, x, y);
    wait_done(lat);
    checks++;
    if (lat < 0) fail($sformatf("%s %s a=%h b=%h timeout", where, o.name(), x, y));
    else if (result !== exp_res || fflags !== exp_flags)
      fail($sformatf(
           "%s %s rm=%0d a=%h b=%h got %h/%b exp %h/%b",
           where,
           o.name(),
           mode,
           x,
           y,
           result,
           fflags,
           exp_res,
           exp_flags
           ));
  endtask

  // One TestFloat file
  task automatic run_file(input logic sq, input string rname, input logic [2:0] mode);
    string fname;
    int fd;
    int n;
    int line;
    logic [31:0] x;
    logic [31:0] y;
    logic [31:0] exp_res;
    logic [4:0] exp_flags;
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
        check($sformatf("%s:%0d", fname, line), VEC_FSQRT, mode, x, $urandom, exp_res, exp_flags);
      else if ($urandom_range(1) != 0) begin
        div_rev++;
        check($sformatf("%s:%0d", fname, line), VEC_FRDIV, mode, y, x, exp_res, exp_flags);
      end else check($sformatf("%s:%0d", fname, line), VEC_FDIV, mode, x, y, exp_res, exp_flags);
    end
    $fclose(fd);
    if (line == 0) $fatal(1, "TB EMPTY FILE: %s", fname);
    $display("%s: %0d lines", fname, line);
  endtask

  task automatic run_files(input logic sq);
    run_file(sq, "rne", RmRne);
    run_file(sq, "rtz", RmRtz);
    run_file(sq, "rdn", RmRdn);
    run_file(sq, "rup", RmRup);
    run_file(sq, "rmm", RmRmm);
  endtask

  // Reverse operand order
  task automatic reverse_order();
    check("reverse", VEC_FRDIV, RmRne, Three, One, Third, FlagNx);
    check("reverse", VEC_FDIV, RmRne, Two, One, Two, 5'd0);
    check("reverse", VEC_FRDIV, RmRne, Two, One, OneHalf, 5'd0);
  endtask

  // Start while busy
  task automatic busy_start();
    int lat;
    launch(VEC_FDIV, RmRne, One, Three);
    repeat (3) @(negedge clk);
    op = VEC_FSQRT;
    a = Two;
    b = One;
    start = 1'b1;
    @(negedge clk);
    start = 1'b0;
    wait_done(lat);
    checks++;
    if (lat < 0 || result !== Third || fflags !== FlagNx)
      fail($sformatf("start while busy: got %h/%b", result, fflags));
  endtask

  // Done cycle start
  task automatic done_start();
    int lat;
    launch(VEC_FDIV, RmRne, One, Three);
    wait_done(lat);
    checks++;
    if (lat < 0 || result !== Third) fail($sformatf("done start first: got %h", result));
    op = VEC_FSQRT;
    a = Two;
    start = 1'b1;
    @(posedge clk);
    @(negedge clk);
    start = 1'b0;
    checks++;
    if (busy !== 1'b0 || done !== 1'b0)
      fail($sformatf("start in done cycle taken: busy=%b done=%b", busy, done));
    checks++;
    if (result !== Third) fail($sformatf("result not held after done: got %h", result));
    check("after done start", VEC_FSQRT, RmRne, Two, '0, Root2, FlagNx);
  endtask

  // Reset mid operation
  task automatic reset_mid();
    launch(VEC_FDIV, RmRne, One, Three);
    repeat (5) @(negedge clk);
    rst_n = 1'b0;
    repeat (2) @(negedge clk);
    checks++;
    if (busy !== 1'b0 || done !== 1'b0)
      fail($sformatf("reset mid operation: busy=%b done=%b", busy, done));
    rst_n = 1'b1;
    check("after reset", VEC_FDIV, RmRne, One, Three, Third, FlagNx);
  endtask

  task automatic verdict();
    if (checks < MinChecks)
      $fatal(1, "TB UNDER-RAN: %0d checks, expected at least %0d", checks, MinChecks);
    if (div_rev == 0) $fatal(1, "TB UNDER-RAN: no reverse divides");
    $display("vec_fp_div_lane: %0d checks, %0d reverse, %0d errors", checks, div_rev, errors);
    if (errors != 0) $fatal(1, "vec_fp_div_lane FAILED");
    $finish;
  endtask

  initial void'($value$plusargs("max_errors=%d", max_errors));

  initial begin
    $dumpfile("vec_fp_div_lane_tb.vcd");
    $dumpvars(0, vec_fp_div_lane_tb);
  end

  initial begin
    repeat (3) @(negedge clk);
    rst_n = 1'b1;

    reverse_order();
    busy_start();
    done_start();
    reset_mid();

    $dumpoff;
    stall_pct = StallPct;
    run_files(1'b0);
    run_files(1'b1);
    reverse_order();
    stall_pct = 0;

    verdict();
  end

endmodule

`default_nettype wire
