`default_nettype none

module fp_fma_tb ();

  localparam int MinChecks  = 3_950_000;
  localparam int MaxPrinted = 20;

  int checks = 0;
  int errors = 0;
  int max_errors = 0;
  int stride = 1;
  string dump_arg;

  logic neg_prod;
  logic neg_add;
  logic [2:0] rm;
  logic [31:0] a;
  logic [31:0] b;
  logic [31:0] c;
  logic [31:0] result;
  logic [4:0] fflags;

  fp_fma dut (
      .neg_prod(neg_prod),
      .neg_add(neg_add),
      .rm(rm),
      .a(a),
      .b(b),
      .c(c),
      .result(result),
      .fflags(fflags)
  );

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

  task automatic check(input string path, input int line, input logic [31:0] exp_res,
                       input logic [4:0] exp_flags);
    checks++;
    if (result !== exp_res || fflags !== exp_flags) begin
      errors++;
      if (errors <= MaxPrinted)
        $display(
            "FAIL %s:%0d %s rm=%0d a=%h b=%h c=%h exp %h/%b got %h/%b",
            path,
            line,
            form_name(
                neg_prod, neg_add
            ),
            rm,
            a,
            b,
            c,
            exp_res,
            exp_flags,
            result,
            fflags
        );
      if (errors == max_errors) $fatal(1, "TB STOPPED: %0d mismatches", errors);
    end
  endtask

  task automatic run_form(input string path, input int line, input logic np, input logic na,
                          input logic [31:0] x, input logic [31:0] y, input logic [31:0] z,
                          input logic [31:0] exp_res, input logic [4:0] exp_flags);
    neg_prod = np;
    neg_add = na;
    a = {x[31] ^ np, x[30:0]};
    b = y;
    c = {z[31] ^ na, z[30:0]};
    #1;
    check(path, line, exp_res, exp_flags);
  endtask

  task automatic run_vec(input string path, input int line, input logic [31:0] x,
                         input logic [31:0] y, input logic [31:0] z, input logic [31:0] exp_res,
                         input logic [4:0] exp_flags);
    run_form(path, line, 1'b0, 1'b0, x, y, z, exp_res, exp_flags);
    run_form(path, line, 1'b0, 1'b1, x, y, z, exp_res, exp_flags);
    run_form(path, line, 1'b1, 1'b0, x, y, z, exp_res, exp_flags);
    run_form(path, line, 1'b1, 1'b1, x, y, z, exp_res, exp_flags);
  endtask

  task automatic run_file(input string path, input logic [2:0] mode);
    int fd;
    int line;
    logic [31:0] x;
    logic [31:0] y;
    logic [31:0] z;
    logic [31:0] exp_res;
    logic [4:0] exp_flags;
    string skip;
    fd = $fopen(path, "r");
    if (fd == 0) $fatal(1, "%s missing, run make testfloat", path);
    rm   = mode;
    line = 0;
    while ($fscanf(
        fd, "%h %h %h %h %h\n", x, y, z, exp_res, exp_flags
    ) == 5) begin
      line++;
      run_vec(path, line, x, y, z, exp_res, exp_flags);
      for (int k = 1; k < stride; k++) if ($fgets(skip, fd) != 0) line++;
    end
    if (!$feof(fd)) $fatal(1, "%s: parse stopped after line %0d", path, line);
    $fclose(fd);
    $display("%s: %0d lines read", path, line);
  endtask

  task automatic do_verdict();
    if (checks < MinChecks / stride)
      $fatal(1, "TB UNDER-RAN: %0d checks, need %0d", checks, MinChecks / stride);
    if (errors != 0) $fatal(1, "FAIL: %0d mismatches, %0d checks", errors, checks);
    $display("PASS: %0d checks", checks);
    $finish;
  endtask

  initial void'($value$plusargs("max_errors=%d", max_errors));

  initial begin
    void'($value$plusargs("stride=%d", stride));
    if ($value$plusargs("DUMP%s", dump_arg) && dump_arg == "") begin
      $dumpfile("fp_fma_tb.vcd");
      $dumpvars(0, fp_fma_tb);
    end

    run_file("build/testfloat/f32_mulAdd_rne.txt", 3'd0);
    run_file("build/testfloat/f32_mulAdd_rtz.txt", 3'd1);
    run_file("build/testfloat/f32_mulAdd_rdn.txt", 3'd2);
    run_file("build/testfloat/f32_mulAdd_rup.txt", 3'd3);
    run_file("build/testfloat/f32_mulAdd_rmm.txt", 3'd4);

    rm = 3'd3;
    run_vec("directed", 1, 32'h3F80_0000, 32'h3F80_0000, 32'h0000_0008, 32'h3F80_0001, 5'b00001);
    rm = 3'd0;
    run_vec("directed", 2, 32'h3F80_0000, 32'h3F80_0000, 32'h477F_FF00, 32'h4780_0000, 5'b00000);

    do_verdict();
  end

endmodule

`default_nettype wire
