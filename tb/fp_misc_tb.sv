`default_nettype none

module fp_misc_tb ();

  localparam int MinChecks = 239000;
  localparam int NumSpecials = 17;
  localparam int NumRandom = 100000;
  localparam int ShowErrors = 20;

  localparam logic [31:0] CanonNan = 32'h7FC0_0000;
  localparam logic [4:0] FlagNv = 5'b1_0000;

  // Opcode encodings
  localparam logic [7:0] OpFsgnj = {5'b00100, 3'b000};
  localparam logic [7:0] OpFsgnjn = {5'b00100, 3'b001};
  localparam logic [7:0] OpFsgnjx = {5'b00100, 3'b010};
  localparam logic [7:0] OpFmin = {5'b00101, 3'b000};
  localparam logic [7:0] OpFmax = {5'b00101, 3'b001};
  localparam logic [7:0] OpFeq = {5'b10100, 3'b010};
  localparam logic [7:0] OpFlt = {5'b10100, 3'b001};
  localparam logic [7:0] OpFle = {5'b10100, 3'b000};
  localparam logic [7:0] OpFclass = {5'b11100, 3'b001};

  int checks = 0;
  int errors = 0;
  int max_errors = 0;

  logic [4:0] funct5;
  logic [2:0] funct3;
  logic [31:0] a;
  logic [31:0] b;
  logic [31:0] result;
  logic [4:0] fflags;

  logic [31:0] specials[NumSpecials] = '{
      32'h0000_0000,  // Plus zero
      32'h8000_0000,  // Minus zero
      32'h7F80_0000,  // Plus infinity
      32'hFF80_0000,  // Minus infinity
      32'h7FC0_0000,  // Quiet NaN
      32'h7FA0_0000,  // Signaling NaN
      32'h7FC1_2345,  // Quiet NaN with payload
      32'h0000_0001,  // Smallest positive subnormal
      32'h8000_0001,  // Smallest negative subnormal
      32'h007F_FFFF,  // Largest positive subnormal
      32'h807F_FFFF,  // Largest negative subnormal
      32'h0080_0000,  // Smallest positive normal
      32'h8080_0000,  // Smallest negative normal
      32'h7F7F_FFFF,  // Largest positive normal
      32'hFF7F_FFFF,  // Largest negative normal
      32'h3F80_0000,  // Plus one
      32'hBF80_0000  // Minus one
  };

  fp_misc dut (
      .funct5(funct5),
      .funct3(funct3),
      .a(a),
      .b(b),
      .result(result),
      .fflags(fflags)
  );

  // Operand classes
  function automatic logic is_nan(input logic [30:0] x);
    is_nan = (x[30:23] == 8'hFF) && (x[22:0] != 23'd0);
  endfunction

  function automatic logic is_snan(input logic [30:0] x);
    is_snan = is_nan(x) && !x[22];
  endfunction

  // Minus zero orders first
  function automatic logic ord_lt(input logic [31:0] x, input logic [31:0] y);
    if (x[31] != y[31]) ord_lt = x[31];
    else if (!x[31]) ord_lt = x[30:0] < y[30:0];
    else ord_lt = x[30:0] > y[30:0];
  endfunction

  // Reference models
  function automatic logic [31:0] ref_fmin(input logic [31:0] x, input logic [31:0] y);
    if (is_nan(x[30:0]) && is_nan(y[30:0])) ref_fmin = CanonNan;
    else if (is_nan(x[30:0])) ref_fmin = y;
    else if (is_nan(y[30:0])) ref_fmin = x;
    else ref_fmin = ord_lt(y, x) ? y : x;
  endfunction

  function automatic logic [31:0] ref_fmax(input logic [31:0] x, input logic [31:0] y);
    if (is_nan(x[30:0]) && is_nan(y[30:0])) ref_fmax = CanonNan;
    else if (is_nan(x[30:0])) ref_fmax = y;
    else if (is_nan(y[30:0])) ref_fmax = x;
    else ref_fmax = ord_lt(x, y) ? y : x;
  endfunction

  function automatic logic [4:0] ref_minmax_flags(input logic [30:0] x, input logic [30:0] y);
    ref_minmax_flags = (is_snan(x) || is_snan(y)) ? FlagNv : 5'd0;
  endfunction

  function automatic logic [31:0] ref_fsgnj(input logic [2:0] f3, input logic [31:0] x,
                                            input logic y_sign);
    case (f3)
      3'b000:  ref_fsgnj = {y_sign, x[30:0]};
      3'b001:  ref_fsgnj = {~y_sign, x[30:0]};
      default: ref_fsgnj = {x[31] ^ y_sign, x[30:0]};
    endcase
  endfunction

  function automatic logic [31:0] ref_fclass(input logic [31:0] x);
    logic [9:0] m;
    m = 10'd0;
    if (x[30:23] == 8'hFF) begin
      if (x[22:0] == 23'd0) m[x[31] ? 0 : 7] = 1'b1;
      else m[x[22] ? 9 : 8] = 1'b1;
    end else if (x[30:23] == 8'h00) begin
      if (x[22:0] == 23'd0) m[x[31] ? 3 : 4] = 1'b1;
      else m[x[31] ? 2 : 5] = 1'b1;
    end else begin
      m[x[31] ? 1 : 6] = 1'b1;
    end
    ref_fclass = {22'd0, m};
  endfunction

  function automatic string op_name(input logic [4:0] f5, input logic [2:0] f3);
    case ({
      f5, f3
    })
      OpFsgnj: op_name = "FSGNJ.S";
      OpFsgnjn: op_name = "FSGNJN.S";
      OpFsgnjx: op_name = "FSGNJX.S";
      OpFmin: op_name = "FMIN.S";
      OpFmax: op_name = "FMAX.S";
      OpFeq: op_name = "FEQ.S";
      OpFlt: op_name = "FLT.S";
      OpFle: op_name = "FLE.S";
      OpFclass: op_name = "FCLASS.S";
      default: op_name = "UNDEFINED";
    endcase
  endfunction

  // Quarter special operands
  function automatic logic [31:0] rand_operand();
    if (($urandom & 32'd3) == 32'd0) rand_operand = specials[int'($urandom_range(NumSpecials-1))];
    else rand_operand = 32'($urandom);
  endfunction

  // One check
  task automatic check(input string src, input logic [7:0] op, input logic [31:0] x,
                       input logic [31:0] y, input logic [31:0] exp_res,
                       input logic [4:0] exp_flags);
    {funct5, funct3} = op;
    a = x;
    b = y;
    #1;
    checks++;
    if (result !== exp_res || fflags !== exp_flags) begin
      errors++;
      if (errors <= ShowErrors)
        $display(
            "FAIL %s %s (funct5=%b funct3=%b) a=%h b=%h exp %h/%b got %h/%b",
            src,
            op_name(
                op[7:3], op[2:0]
            ),
            op[7:3],
            op[2:0],
            x,
            y,
            exp_res,
            exp_flags,
            result,
            fflags
        );
      if (errors == max_errors) $fatal(1, "TB STOPPED: %0d mismatches", errors);
    end
  endtask

  // TestFloat compare file
  task automatic run_file(input string path, input logic [4:0] f5, input logic [2:0] f3);
    int fd;
    int lines;
    logic [31:0] fa;
    logic [31:0] fb;
    logic [3:0] fr;
    logic [4:0] ff;
    fd = $fopen(path, "r");
    if (fd == 0) $fatal(1, "TB MISSING FILE: %s (run make testfloat)", path);
    lines = 0;
    while ($fscanf(
        fd, "%h %h %h %h", fa, fb, fr, ff
    ) == 4) begin
      lines++;
      check(path, {f5, f3}, fa, fb, {28'd0, fr}, ff);
    end
    if (!$feof(fd)) $fatal(1, "TB PARSE ERROR: %s after %0d lines", path, lines);
    $fclose(fd);
    if (lines == 0) $fatal(1, "TB EMPTY FILE: %s", path);
    $display("%s: %0d lines", path, lines);
  endtask

  // Every special pair
  task automatic directed_pairs();
    for (int i = 0; i < NumSpecials; i++)
      for (int j = 0; j < NumSpecials; j++) begin
        check("directed", OpFmin, specials[i], specials[j], ref_fmin(specials[i], specials[j]),
              ref_minmax_flags(specials[i][30:0], specials[j][30:0]));
        check("directed", OpFmax, specials[i], specials[j], ref_fmax(specials[i], specials[j]),
              ref_minmax_flags(specials[i][30:0], specials[j][30:0]));
        check("directed", OpFsgnj, specials[i], specials[j], ref_fsgnj(
              3'b000, specials[i], specials[j][31]), 5'd0);
        check("directed", OpFsgnjn, specials[i], specials[j], ref_fsgnj(
              3'b001, specials[i], specials[j][31]), 5'd0);
        check("directed", OpFsgnjx, specials[i], specials[j], ref_fsgnj(
              3'b010, specials[i], specials[j][31]), 5'd0);
      end
  endtask

  // Every special value
  task automatic directed_class();
    for (int i = 0; i < NumSpecials; i++)
      check("directed", OpFclass, specials[i], 32'($urandom), ref_fclass(specials[i]), 5'd0);
  endtask

  // Zero against one bit
  task automatic directed_zero_cmp();
    logic [31:0] z;
    logic [31:0] y;
    for (int s = 0; s < 4; s++)
      for (int k = 0; k < 31; k++) begin
        z = {s[0], 31'd0};
        y = {s[1], 31'd1 << k};
        check("directed", OpFeq, z, y, 32'd0, 5'd0);
        check("directed", OpFeq, y, z, 32'd0, 5'd0);
        check("directed", OpFlt, z, y, {31'd0, ~y[31]}, 5'd0);
        check("directed", OpFlt, y, z, {31'd0, y[31]}, 5'd0);
      end
  endtask

  // Random min and max
  task automatic random_minmax(input int n);
    logic [31:0] x;
    logic [31:0] y;
    for (int i = 0; i < n; i++) begin
      x = rand_operand();
      y = rand_operand();
      check("random", OpFmin, x, y, ref_fmin(x, y), ref_minmax_flags(x[30:0], y[30:0]));
      check("random", OpFmax, x, y, ref_fmax(x, y), ref_minmax_flags(x[30:0], y[30:0]));
    end
  endtask

  // Undefined encodings
  task automatic undefined_ops();
    logic [7:0] ops[5] = '{
        {5'b00100, 3'b011},
        {5'b00101, 3'b111},
        {5'b10100, 3'b011},
        {5'b11100, 3'b010},
        {5'b11111, 3'b000}
    };
    for (int k = 0; k < $size(ops); k++)
      for (int i = 0; i < NumSpecials; i++)
        check("undefined", ops[k], specials[i], specials[(i+5)%NumSpecials], 32'd0, 5'd0);
  endtask

  task automatic read_args();
    string dump_arg;
    void'($value$plusargs("max_errors=%d", max_errors));
    if ($value$plusargs("DUMP%s", dump_arg) && dump_arg == "") begin
      $dumpfile("fp_misc_tb.vcd");
      $dumpvars(0, fp_misc_tb);
    end
  endtask

  task automatic do_verdict();
    if (checks < MinChecks) $fatal(1, "TB UNDER-RAN: %0d checks, expected %0d", checks, MinChecks);
    if (errors != 0) $fatal(1, "FAIL: %0d mismatches, %0d checks", errors, checks);
    $display("PASS: %0d checks", checks);
    $finish;
  endtask

  initial begin
    read_args();

    // TestFloat compares
    run_file("build/testfloat/f32_eq.txt", OpFeq[7:3], OpFeq[2:0]);
    run_file("build/testfloat/f32_le.txt", OpFle[7:3], OpFle[2:0]);
    run_file("build/testfloat/f32_lt.txt", OpFlt[7:3], OpFlt[2:0]);

    // Special values
    directed_pairs();
    directed_class();
    directed_zero_cmp();

    // Random min and max
    random_minmax(NumRandom);

    // Undefined encodings
    undefined_ops();

    do_verdict();
  end

endmodule

`default_nettype wire
