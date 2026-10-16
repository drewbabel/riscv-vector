`default_nettype none

module fp_add_tb ();

  localparam int MinChecks = 464000;
  localparam int MaxPrint  = 20;

  int checks = 0;
  int errors = 0;
  int max_errors = 0;
  int stride = 1;

  logic sub;
  logic [2:0] rm;
  logic [31:0] a;
  logic [31:0] b;
  logic [31:0] result;
  logic [4:0] fflags;

  fp_add dut (
      .sub(sub),
      .rm(rm),
      .a(a),
      .b(b),
      .result(result),
      .fflags(fflags)
  );

  task automatic dump_if_asked();
    string dump_arg;
    if ($value$plusargs("DUMP%s", dump_arg)) begin
      $display("DUMP%s: writing fp_add_tb.vcd", dump_arg);
      $dumpfile("fp_add_tb.vcd");
      $dumpvars(0, fp_add_tb);
    end
  endtask

  task automatic check(input string path, input int line, input logic [31:0] exp_res,
                       input logic [4:0] exp_flags);
    checks++;
    if (result !== exp_res || fflags !== exp_flags) begin
      errors++;
      if (errors <= MaxPrint)
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
      if (errors == max_errors) $fatal(1, "TB STOPPED: %0d mismatches", errors);
    end
  endtask

  task automatic run_file(input string path, input logic op_sub, input logic [2:0] op_rm);
    int fd;
    int line;
    logic [31:0] fa;
    logic [31:0] fb;
    logic [31:0] exp_res;
    logic [4:0] exp_flags;
    fd = $fopen(path, "r");
    if (fd == 0) $fatal(1, "TB MISSING FILE: %s (run make testfloat)", path);
    line = 0;
    while ($fscanf(
        fd, "%h %h %h %h\n", fa, fb, exp_res, exp_flags
    ) == 4) begin
      line++;
      if ((line - 1) % stride == 0) begin
        sub = op_sub;
        rm  = op_rm;
        a   = fa;
        b   = fb;
        #1;
        check(path, line, exp_res, exp_flags);
      end
    end
    if ($feof(fd) == 0) $fatal(1, "TB PARSE STOPPED: %s after line %0d", path, line);
    $fclose(fd);
    $display("%s: %0d lines", path, line);
  endtask

  task automatic run_nan_bits();
    for (int i = 0; i < 23; i++) begin
      sub = 1'b0;
      rm  = 3'd0;
      a   = 32'h7F80_0000 | (32'd1 << i);
      b   = 32'h3F80_0000;
      #1;
      check("nan_bits_a", i, 32'h7FC0_0000, {i != 22, 4'b0000});
      a = 32'h3F80_0000;
      b = 32'h7F80_0000 | (32'd1 << i);
      #1;
      check("nan_bits_b", i, 32'h7FC0_0000, {i != 22, 4'b0000});
    end
  endtask

  task automatic do_verdict();
    if (checks < MinChecks / stride)
      $fatal(1, "TB UNDER-RAN: %0d checks, expected %0d", checks, MinChecks / stride);
    if (errors != 0) $fatal(1, "FAIL: %0d mismatches, %0d checks", errors, checks);
    $display("PASS: %0d checks", checks);
    $finish;
  endtask

  initial void'($value$plusargs("max_errors=%d", max_errors));

  initial begin
    void'($value$plusargs("stride=%d", stride));
    if (stride < 1) $fatal(1, "TB BAD STRIDE: %0d", stride);
    dump_if_asked();

    run_file("build/testfloat/f32_add_rne.txt", 1'b0, 3'd0);
    run_file("build/testfloat/f32_add_rtz.txt", 1'b0, 3'd1);
    run_file("build/testfloat/f32_add_rdn.txt", 1'b0, 3'd2);
    run_file("build/testfloat/f32_add_rup.txt", 1'b0, 3'd3);
    run_file("build/testfloat/f32_add_rmm.txt", 1'b0, 3'd4);

    run_file("build/testfloat/f32_sub_rne.txt", 1'b1, 3'd0);
    run_file("build/testfloat/f32_sub_rtz.txt", 1'b1, 3'd1);
    run_file("build/testfloat/f32_sub_rdn.txt", 1'b1, 3'd2);
    run_file("build/testfloat/f32_sub_rup.txt", 1'b1, 3'd3);
    run_file("build/testfloat/f32_sub_rmm.txt", 1'b1, 3'd4);

    run_nan_bits();
    do_verdict();
  end

endmodule

`default_nettype wire
