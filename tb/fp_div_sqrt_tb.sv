`default_nettype none

module fp_div_sqrt_tb
  import fp_pkg::*;
();

  localparam int StallCycles = 7;
  localparam int ShowErrors  = 20;
  localparam int MinChecks   = 5 * (46464 + 46464);

  int checks = 0;
  int errors = 0;
  int max_errors = 0;
  int timeout = 200;
  int div_latency = -1;
  int sqrt_latency = -1;

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

  fp_div_sqrt dut (
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

  task automatic do_reset();
    @(negedge clk);
    rst_n = 1'b0;
    repeat (2) @(posedge clk);
    @(negedge clk);
    rst_n = 1'b1;
  endtask

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
    a = FLEN'($urandom);
    b = FLEN'($urandom);
  endtask

  task automatic wait_done(output logic [FLEN-1:0] res, output logic [4:0] flags, output int lat);
    lat = 0;
    while (done !== 1'b1 && lat < timeout) begin
      @(negedge clk);
      lat++;
    end
    res   = result;
    flags = fflags;
    if (done !== 1'b1) lat = -1;
  endtask

  task automatic do_op(input logic sq, input logic [2:0] mode, input logic [FLEN-1:0] x,
                       input logic [FLEN-1:0] y, output logic [FLEN-1:0] res,
                       output logic [4:0] flags, output int lat);
    launch(sq, mode, x, y);
    wait_done(res, flags, lat);
  endtask

  task automatic fail(input string msg);
    errors++;
    $display("FAIL %s", msg);
    if (errors == max_errors) $fatal(1, "TB STOPPED: %0d mismatches", errors);
  endtask

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
              "FAIL %s:%0d %s a=%h b=%h exp %h/%b got TIMEOUT after %0d cycles",
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
              "FAIL %s:%0d %s a=%h b=%h exp %h/%b got %h/%b",
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
      if (errors == max_errors) $fatal(1, "TB STOPPED: %0d mismatches", errors);
    end
  endtask

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
    fname = {"build/testfloat/f32_", sq ? "sqrt" : "div", "_", rname, ".txt"};
    fd = $fopen(fname, "r");
    if (fd == 0) $fatal(1, "missing %s: run make testfloat first", fname);
    line = 0;
    while (!$feof(
        fd
    )) begin
      if (sq) begin
        n = $fscanf(fd, "%h %h %h\n", x, exp_res, exp_flags);
        y = FLEN'($urandom);
      end else begin
        n = $fscanf(fd, "%h %h %h %h\n", x, y, exp_res, exp_flags);
      end
      if (n == -1) break;
      line++;
      if (n != (sq ? 3 : 4)) $fatal(1, "%s:%0d malformed line (%0d fields)", fname, line, n);
      do_op(sq, mode, x, y, got_res, got_flags, lat);
      check(fname, line, sq, x, y, exp_res, exp_flags, got_res, got_flags, lat);
    end
    $fclose(fd);
    $display("%s: %0d lines", fname, line);
  endtask

  task automatic run_files(input logic sq);
    run_file(sq, "rne", RmRne);
    run_file(sq, "rtz", RmRtz);
    run_file(sq, "rdn", RmRdn);
    run_file(sq, "rup", RmRup);
    run_file(sq, "rmm", RmRmm);
  endtask

  task automatic measure_latency();
    logic [FLEN-1:0] res;
    logic [4:0] flags;
    do_op(1'b0, RmRne, 32'h3F80_0000, 32'h4040_0000, res, flags, div_latency);
    check("divide latency", 0, 1'b0, 32'h3F80_0000, 32'h4040_0000, 32'h3EAA_AAAB, FlagNx, res,
          flags, div_latency);
    do_op(1'b1, RmRne, 32'h4000_0000, '0, res, flags, sqrt_latency);
    check("sqrt latency", 0, 1'b1, 32'h4000_0000, '0, 32'h3FB5_04F3, FlagNx, res, flags,
          sqrt_latency);
    $display("divide latency: %0d cycles", div_latency);
    $display("sqrt latency: %0d cycles", sqrt_latency);
  endtask

  task automatic busy_start();
    logic [FLEN-1:0] res;
    logic [4:0] flags;
    int lat;
    launch(1'b0, RmRne, 32'h3F80_0000, 32'h4040_0000);
    @(negedge clk);
    sqrt = 1'b0;
    rm = RmRtz;
    a = 32'h4000_0000;
    b = 32'h3F80_0000;
    start = 1'b1;
    @(negedge clk);
    start = 1'b0;
    wait_done(res, flags, lat);
    check("start while busy", 0, 1'b0, 32'h3F80_0000, 32'h4040_0000, 32'h3EAA_AAAB, FlagNx, res,
          flags, lat);
  endtask

  task automatic reset_mid();
    logic [FLEN-1:0] res;
    logic [4:0] flags;
    int lat;
    launch(1'b0, RmRne, 32'h3F80_0000, 32'h4040_0000);
    repeat (5) @(negedge clk);
    rst_n = 1'b0;
    repeat (2) @(negedge clk);
    checks++;
    if (busy !== 1'b0 || done !== 1'b0)
      fail($sformatf("reset mid operation: busy=%b done=%b", busy, done));
    rst_n = 1'b1;
    do_op(1'b0, RmRne, 32'h3F80_0000, 32'h4040_0000, res, flags, lat);
    check("after reset", 0, 1'b0, 32'h3F80_0000, 32'h4040_0000, 32'h3EAA_AAAB, FlagNx, res, flags,
          lat);
  endtask

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
  endtask

  task automatic core_en_stall();
    stall_one(1'b0, 32'h3F80_0000, 32'h4040_0000, 32'h3EAA_AAAB, div_latency);
    stall_one(1'b1, 32'h4000_0000, '0, 32'h3FB5_04F3, sqrt_latency);
  endtask

  task automatic done_pulse();
    logic [FLEN-1:0] res;
    logic [4:0] flags;
    int lat;
    do_op(1'b0, RmRne, 32'h3F80_0000, 32'h4040_0000, res, flags, lat);
    check("done pulse", 0, 1'b0, 32'h3F80_0000, 32'h4040_0000, 32'h3EAA_AAAB, FlagNx, res, flags,
          lat);
    @(negedge clk);
    checks++;
    if (busy !== 1'b0 || done !== 1'b0)
      fail($sformatf("done pulse: busy=%b done=%b a cycle later", busy, done));
  endtask

  task automatic do_verdict();
    @(posedge clk);
    if (checks < MinChecks) $fatal(1, "TB UNDER-RAN: %0d checks, expected %0d", checks, MinChecks);
    if (errors != 0) $fatal(1, "FAIL: %0d mismatches, %0d checks", errors, checks);
    $display("PASS: %0d checks", checks);
    $finish;
  endtask

  initial void'($value$plusargs("max_errors=%d", max_errors));
  initial void'($value$plusargs("timeout=%d", timeout));

  initial begin
    string dump;
    if ($value$plusargs("DUMP%s", dump)) begin
      $dumpfile({"fp_div_sqrt_tb", dump, ".vcd"});
      $dumpvars(0, fp_div_sqrt_tb);
    end
  end

  initial begin
    do_reset();
    run_files(1'b0);
    run_files(1'b1);
    measure_latency();
    busy_start();
    reset_mid();
    core_en_stall();
    done_pulse();
    do_verdict();
  end

endmodule

`default_nettype wire
