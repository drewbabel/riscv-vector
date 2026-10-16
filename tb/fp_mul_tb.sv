`default_nettype none

module fp_mul_tb
  import fp_pkg::*;
();

  localparam int MinChecks  = 232000;
  localparam int ShowErrors = 20;

  int checks = 0;
  int errors = 0;
  int max_errors = 0;

  logic [2:0] rm;
  logic [FLEN-1:0] a;
  logic [FLEN-1:0] b;
  logic [FLEN-1:0] result;
  logic [4:0] fflags;

  fp_mul dut (
      .rm(rm),
      .a(a),
      .b(b),
      .result(result),
      .fflags(fflags)
  );

  task automatic check(input string path, input int line, input logic [FLEN-1:0] exp_res,
                       input logic [4:0] exp_flags);
    checks++;
    if (result !== exp_res || fflags !== exp_flags) begin
      errors++;
      if (errors <= ShowErrors)
        $display(
            "FAIL %s:%0d rm=%0d a=%h b=%h exp %h/%b got %h/%b",
            path,
            line,
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
    rm = mode;
    forever begin
      code = $fscanf(fd, "%h %h %h %h\n", va, vb, vres, vflags);
      if (code != 4) break;
      lines++;
      a = va;
      b = vb;
      #1;
      check(path, lines, vres, vflags);
    end
    if (!$feof(fd)) $fatal(1, "TB BAD LINE: %s:%0d", path, lines + 1);
    $fclose(fd);
    $display("%s: %0d lines", path, lines);
  endtask

  task automatic run_nan_payloads();
    logic [FLEN-1:0] nan;
    logic [4:0] flags;
    rm = RmRne;
    for (int i = 0; i < 23; i++) begin
      nan = 32'h7F80_0000 | (32'd1 << i);
      flags = (i == 22) ? '0 : FlagNv;
      a = nan;
      b = 32'h3F80_0000;
      #1;
      check("nan payload a", i, 32'h7FC0_0000, flags);
      a = 32'h3F80_0000;
      b = nan;
      #1;
      check("nan payload b", i, 32'h7FC0_0000, flags);
    end
  endtask

  task automatic do_verdict();
    if (checks < MinChecks) $fatal(1, "TB UNDER-RAN: %0d checks, expected %0d", checks, MinChecks);
    if (errors != 0) $fatal(1, "FAIL: %0d mismatches, %0d checks", errors, checks);
    $display("PASS: %0d checks", checks);
    $finish;
  endtask

  initial void'($value$plusargs("max_errors=%d", max_errors));

  initial begin
    string dump_tag;
    if ($value$plusargs("DUMP%s", dump_tag)) begin
      $dumpfile({"fp_mul_tb", dump_tag, ".vcd"});
      $dumpvars(0, fp_mul_tb);
    end

    run_file("build/testfloat/f32_mul_rne.txt", RmRne);
    run_file("build/testfloat/f32_mul_rtz.txt", RmRtz);
    run_file("build/testfloat/f32_mul_rdn.txt", RmRdn);
    run_file("build/testfloat/f32_mul_rup.txt", RmRup);
    run_file("build/testfloat/f32_mul_rmm.txt", RmRmm);
    run_nan_payloads();

    do_verdict();
  end

endmodule

`default_nettype wire
