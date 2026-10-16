`default_nettype none

module fp_div_sqrt_tb ();

  localparam int MinChecks = 5 * (46464 + 46464);

  int checks;
  int errors;
  int max_errors;

  fp_div_sqrt_bench #(
      .EXP_W (8),
      .FRAC_W(23),
      .FMT   ("f32"),
      .THIRD (64'h3EAA_AAAB),
      .ROOT2 (64'h3FB5_04F3)
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
      .THIRD (64'h3555),
      .ROOT2 (64'h3DA8)
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
    $dumpfile("fp_div_sqrt_tb.vcd");
    $dumpvars(0, f32_bench);
    wait (f32_bench.done_all && f64_bench.done_all && f16_bench.done_all);
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

module fp_div_sqrt_bench
  import fp_pkg::RmRne, fp_pkg::RmRtz, fp_pkg::RmRdn, fp_pkg::RmRup, fp_pkg::RmRmm;
  import fp_pkg::FlagNx;
#(
    parameter  int           EXP_W  = 8,
    parameter  int           FRAC_W = 23,
    parameter  string        FMT    = "f32",
    parameter  logic  [63:0] THIRD  = 64'h3EAA_AAAB,
    parameter  logic  [63:0] ROOT2  = 64'h3FB5_04F3,
    localparam int           FLEN   = 1 + EXP_W + FRAC_W
) ();

  localparam int StallCycles = 7;
  localparam int ShowErrors = 20;
  localparam int Bias = (1 << (EXP_W - 1)) - 1;
  localparam string TfDir = "build/testfloat/";

  localparam logic [FLEN-1:0] One = {2'b00, {(EXP_W - 1) {1'b1}}, {FRAC_W{1'b0}}};
  localparam logic [FLEN-1:0] Two = {1'b0, EXP_W'(Bias + 1), {FRAC_W{1'b0}}};
  localparam logic [FLEN-1:0] Three = {1'b0, EXP_W'(Bias + 1), 1'b1, {(FRAC_W - 1) {1'b0}}};
  localparam logic [FLEN-1:0] Third = FLEN'(THIRD);
  localparam logic [FLEN-1:0] Root2 = FLEN'(ROOT2);

  int checks = 0;
  int errors = 0;
  int timeout = 200;
  int div_latency = -1;
  int sqrt_latency = -1;
  logic done_all = 1'b0;

  logic clk;
  logic rst_n = 1'b0;
  logic core_en = 1'b1;
  logic start = 1'b0;
  logic sqrt = 1'b0;
  logic [2:0] rm = RmRne;
  logic [FLEN-1:0] a = '0;
  logic [FLEN-1:0] b = '0;
  logic [FLEN-1:0] result;
  logic [4:0] fflags;
  logic busy;
  logic done;

  initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;
  end

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

  task automatic launch(input logic sq, input logic [2:0] mode, input logic [FLEN-1:0] x,
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
    rm = 3'($urandom);
    a = rand_bits();
    b = rand_bits();
  endtask  // Automatic

  task automatic wait_done(output logic [FLEN-1:0] res, output logic [4:0] flags, output int lat);
    lat = 0;
    while (done !== 1'b1 && lat < timeout) begin
      @(negedge clk);
      lat++;
    end
    res   = result;
    flags = fflags;
    if (done !== 1'b1) lat = -1;
  endtask  // Automatic

  task automatic do_op(input logic sq, input logic [2:0] mode, input logic [FLEN-1:0] x,
                       input logic [FLEN-1:0] y, output logic [FLEN-1:0] res,
                       output logic [4:0] flags, output int lat);
    launch(sq, mode, x, y);
    wait_done(res, flags, lat);
  endtask  // Automatic

  task automatic fail(input string msg);
    errors++;
    $display("FAIL %s %s", FMT, msg);
  endtask  // Automatic

  task automatic check(input string fname, input int line, input logic sq, input logic [FLEN-1:0] x,
                       input logic [FLEN-1:0] y, input logic [FLEN-1:0] exp_res,
                       input logic [4:0] exp_flags, input logic [FLEN-1:0] got_res,
                       input logic [4:0] got_flags, input int lat);
    checks++;
    if (lat < 0 || got_res !== exp_res || got_flags !== exp_flags) begin
      errors++;
      if (errors <= ShowErrors) begin
        if (lat < 0)
          $display(
              "FAIL %s %s:%0d %s a=%h b=%h exp %h/%b got TIMEOUT after %0d cycles",
              FMT,
              fname,
              line,
              sq ? "sqrt" : "div",
              x,
              y,
              exp_res,
              exp_flags,
              timeout
          );
        else
          $display(
              "FAIL %s %s:%0d %s a=%h b=%h exp %h/%b got %h/%b",
              FMT,
              fname,
              line,
              sq ? "sqrt" : "div",
              x,
              y,
              exp_res,
              exp_flags,
              got_res,
              got_flags
          );
      end
    end
  endtask  // Automatic

  task automatic run_file(input logic sq, input string rname, input logic [2:0] mode);
    string fname;
    int fd;
    int n;
    int line;
    logic [FLEN-1:0] x;
    logic [FLEN-1:0] y;
    logic [FLEN-1:0] exp_res;
    logic [4:0] exp_flags;
    logic [FLEN-1:0] got_res;
    logic [4:0] got_flags;
    int lat;
    fname = {TfDir, FMT, "_", sq ? "sqrt" : "div", "_", rname, ".txt"};
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
      check(fname, line, sq, x, y, exp_res, exp_flags, got_res, got_flags, lat);
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
    logic [FLEN-1:0] res;
    logic [4:0] flags;
    do_op(1'b0, RmRne, One, Three, res, flags, div_latency);
    check("divide latency", 0, 1'b0, One, Three, Third, FlagNx, res, flags, div_latency);
    do_op(1'b1, RmRne, Two, '0, res, flags, sqrt_latency);
    check("sqrt latency", 0, 1'b1, Two, '0, Root2, FlagNx, res, flags, sqrt_latency);
    $display("%s divide latency: %0d cycles", FMT, div_latency);
    $display("%s sqrt latency: %0d cycles", FMT, sqrt_latency);
  endtask  // Automatic

  task automatic busy_start();
    logic [FLEN-1:0] res;
    logic [4:0] flags;
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
    check("start while busy", 0, 1'b0, One, Three, Third, FlagNx, res, flags, lat);
  endtask  // Automatic

  task automatic reset_mid();
    logic [FLEN-1:0] res;
    logic [4:0] flags;
    int lat;
    launch(1'b0, RmRne, One, Three);
    repeat (5) @(negedge clk);
    rst_n = 1'b0;
    repeat (2) @(negedge clk);
    checks++;
    if (busy !== 1'b0 || done !== 1'b0)
      fail($sformatf("reset mid operation: busy=%b done=%b", busy, done));
    rst_n = 1'b1;
    do_op(1'b0, RmRne, One, Three, res, flags, lat);
    check("after reset", 0, 1'b0, One, Three, Third, FlagNx, res, flags, lat);
  endtask  // Automatic

  task automatic stall_one(input logic sq, input logic [FLEN-1:0] x, input logic [FLEN-1:0] y,
                           input logic [FLEN-1:0] exp_res, input int base_lat);
    logic [FLEN-1:0] res;
    logic [4:0] flags;
    int lat;
    int pre;
    if (base_lat < 2) begin
      checks++;
      fail($sformatf("core_en stall %s: no unstalled latency to compare", sq ? "sqrt" : "div"));
      return;
    end
    pre = base_lat / 2;
    launch(sq, RmRne, x, y);
    repeat (pre - 1) @(negedge clk);
    core_en = 1'b0;
    for (int i = 0; i < StallCycles; i++) begin
      @(negedge clk);
      checks++;
      if (busy !== 1'b1 || done !== 1'b0)
        fail($sformatf(
             "core_en stall %s cycle %0d: busy=%b done=%b", sq ? "sqrt" : "div", i, busy, done));
    end
    core_en = 1'b1;
    wait_done(res, flags, lat);
    if (lat >= 0) lat = lat + pre - 1 + StallCycles;
    check("core_en stall", 0, sq, x, y, exp_res, FlagNx, res, flags, lat);
    checks++;
    if (lat != base_lat + StallCycles)
      fail($sformatf(
           "core_en stall %s: latency %0d, expected %0d",
           sq ? "sqrt" : "div",
           lat,
           base_lat + StallCycles
           ));
  endtask  // Automatic

  task automatic core_en_stall();
    stall_one(1'b0, One, Three, Third, div_latency);
    stall_one(1'b1, Two, '0, Root2, sqrt_latency);
  endtask  // Automatic

  task automatic done_pulse();
    logic [FLEN-1:0] res;
    logic [4:0] flags;
    int lat;
    do_op(1'b0, RmRne, One, Three, res, flags, lat);
    check("done pulse", 0, 1'b0, One, Three, Third, FlagNx, res, flags, lat);
    @(negedge clk);
    checks++;
    if (busy !== 1'b0 || done !== 1'b0)
      fail($sformatf("done pulse: busy=%b done=%b a cycle later", busy, done));
  endtask  // Automatic

  initial void'($value$plusargs("timeout=%d", timeout));

  initial begin
    do_reset();
    run_files(1'b0);
    run_files(1'b1);
    measure_latency();
    busy_start();
    reset_mid();
    core_en_stall();
    done_pulse();
    @(posedge clk);
    done_all = 1'b1;
  end

endmodule

`default_nettype wire
