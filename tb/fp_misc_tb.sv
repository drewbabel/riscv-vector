`default_nettype none

module fp_misc_tb ();

  localparam int MinChecks = 239000;

  int checks;
  int errors;
  int max_errors;

  fp_misc_bench #(
      .EXP_W (8),
      .FRAC_W(23),
      .FMT   ("f32")
  ) f32_bench ();

  fp_misc_bench #(
      .EXP_W (11),
      .FRAC_W(52),
      .FMT   ("f64")
  ) f64_bench ();

  fp_misc_bench #(
      .EXP_W (5),
      .FRAC_W(10),
      .FMT   ("f16")
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
    $dumpfile("fp_misc_tb.vcd");
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

module fp_misc_bench
  import fp_pkg::Funct5Fsgnj, fp_pkg::Funct5Fminmax, fp_pkg::Funct5Fcmp, fp_pkg::Funct5FmvXW;
  import fp_pkg::Funct3Fsgnj, fp_pkg::Funct3Fsgnjn, fp_pkg::Funct3Fsgnjx;
  import fp_pkg::Funct3Fmin, fp_pkg::Funct3Fmax;
  import fp_pkg::Funct3Fle, fp_pkg::Funct3Flt, fp_pkg::Funct3Feq, fp_pkg::Funct3Fclass;
  import fp_pkg::FlagNv;
#(
    parameter  int    EXP_W  = 8,
    parameter  int    FRAC_W = 23,
    parameter  string FMT    = "f32",
    localparam int    FLEN   = 1 + EXP_W + FRAC_W
) ();

  localparam int NumSpecials = 17;
  localparam int NumRandom = 100000;
  localparam int ShowErrors = 20;
  localparam string TfDir = "build/testfloat/";

  localparam int OpW = $bits(Funct5Fsgnj) + $bits(Funct3Fsgnj);

  localparam logic [FLEN-1:0] CanonNan = {1'b0, {EXP_W{1'b1}}, 1'b1, {(FRAC_W - 1) {1'b0}}};
  localparam logic [FLEN-1:0] PosInf = {1'b0, {EXP_W{1'b1}}, {FRAC_W{1'b0}}};
  localparam logic [FLEN-1:0] One = {2'b00, {(EXP_W - 1) {1'b1}}, {FRAC_W{1'b0}}};
  localparam logic [FLEN-1:0] SignBit = {1'b1, {(FLEN - 1) {1'b0}}};
  localparam logic [FLEN-1:0] MaxSub = {1'b0, {EXP_W{1'b0}}, {FRAC_W{1'b1}}};
  localparam logic [FLEN-1:0] MinNorm = {1'b0, EXP_W'(1), {FRAC_W{1'b0}}};
  localparam logic [FLEN-1:0] MaxNorm = {2'b01, {(EXP_W - 2) {1'b1}}, 1'b0, {FRAC_W{1'b1}}};
  localparam logic [FLEN-1:0] SigNan = {1'b0, {EXP_W{1'b1}}, 2'b01, {(FRAC_W - 2) {1'b0}}};
  localparam logic [FLEN-1:0] PayloadNan = CanonNan | FLEN'((FRAC_W - 1)'(20'h12345));

  localparam logic [OpW-1:0] OpFsgnj = {Funct5Fsgnj, Funct3Fsgnj};
  localparam logic [OpW-1:0] OpFsgnjn = {Funct5Fsgnj, Funct3Fsgnjn};
  localparam logic [OpW-1:0] OpFsgnjx = {Funct5Fsgnj, Funct3Fsgnjx};
  localparam logic [OpW-1:0] OpFmin = {Funct5Fminmax, Funct3Fmin};
  localparam logic [OpW-1:0] OpFmax = {Funct5Fminmax, Funct3Fmax};
  localparam logic [OpW-1:0] OpFeq = {Funct5Fcmp, Funct3Feq};
  localparam logic [OpW-1:0] OpFlt = {Funct5Fcmp, Funct3Flt};
  localparam logic [OpW-1:0] OpFle = {Funct5Fcmp, Funct3Fle};
  localparam logic [OpW-1:0] OpFclass = {Funct5FmvXW, Funct3Fclass};

  int checks = 0;
  int errors = 0;
  logic done = 1'b0;

  logic [4:0] funct5;
  logic [2:0] funct3;
  logic [FLEN-1:0] a;
  logic [FLEN-1:0] b;
  logic [FLEN-1:0] result;
  logic [4:0] fflags;

  logic [FLEN-1:0] specials[NumSpecials] = '{
      '0,
      SignBit,
      PosInf,
      SignBit | PosInf,
      CanonNan,
      SigNan,
      PayloadNan,
      FLEN'(1),
      SignBit | FLEN'(1),
      MaxSub,
      SignBit | MaxSub,
      MinNorm,
      SignBit | MinNorm,
      MaxNorm,
      SignBit | MaxNorm,
      One,
      SignBit | One
  };

  fp_misc #(
      .ExpW (EXP_W),
      .FracW(FRAC_W)
  ) dut (
      .funct5(funct5),
      .funct3(funct3),
      .a(a),
      .b(b),
      .result(result),
      .fflags(fflags)
  );

  function automatic logic is_nan(input logic [FLEN-2:0] x);
    is_nan = (x[FLEN-2:FRAC_W] == '1) && (x[FRAC_W-1:0] != '0);
  endfunction

  function automatic logic is_snan(input logic [FLEN-2:0] x);
    is_snan = is_nan(x) && !x[FRAC_W-1];
  endfunction

  function automatic logic ord_lt(input logic [FLEN-1:0] x, input logic [FLEN-1:0] y);
    if (x[FLEN-1] != y[FLEN-1]) ord_lt = x[FLEN-1];
    else if (!x[FLEN-1]) ord_lt = x[FLEN-2:0] < y[FLEN-2:0];
    else ord_lt = x[FLEN-2:0] > y[FLEN-2:0];
  endfunction

  function automatic logic [FLEN-1:0] ref_fmin(input logic [FLEN-1:0] x, input logic [FLEN-1:0] y);
    if (is_nan(x[FLEN-2:0]) && is_nan(y[FLEN-2:0])) ref_fmin = CanonNan;
    else if (is_nan(x[FLEN-2:0])) ref_fmin = y;
    else if (is_nan(y[FLEN-2:0])) ref_fmin = x;
    else ref_fmin = ord_lt(y, x) ? y : x;
  endfunction

  function automatic logic [FLEN-1:0] ref_fmax(input logic [FLEN-1:0] x, input logic [FLEN-1:0] y);
    if (is_nan(x[FLEN-2:0]) && is_nan(y[FLEN-2:0])) ref_fmax = CanonNan;
    else if (is_nan(x[FLEN-2:0])) ref_fmax = y;
    else if (is_nan(y[FLEN-2:0])) ref_fmax = x;
    else ref_fmax = ord_lt(x, y) ? y : x;
  endfunction

  function automatic logic [4:0] ref_minmax_flags(input logic [FLEN-2:0] x,
                                                  input logic [FLEN-2:0] y);
    ref_minmax_flags = (is_snan(x) || is_snan(y)) ? FlagNv : 5'd0;
  endfunction

  function automatic logic [FLEN-1:0] ref_fsgnj(input logic [2:0] f3, input logic [FLEN-1:0] x,
                                                input logic y_sign);
    case (f3)
      Funct3Fsgnj:  ref_fsgnj = {y_sign, x[FLEN-2:0]};
      Funct3Fsgnjn: ref_fsgnj = {~y_sign, x[FLEN-2:0]};
      default:      ref_fsgnj = {x[FLEN-1] ^ y_sign, x[FLEN-2:0]};
    endcase
  endfunction

  function automatic logic [FLEN-1:0] ref_fclass(input logic [FLEN-1:0] x);
    logic [9:0] m;
    m = 10'd0;
    if (x[FLEN-2:FRAC_W] == '1) begin
      if (x[FRAC_W-1:0] == '0) m[x[FLEN-1] ? 0 : 7] = 1'b1;
      else m[x[FRAC_W-1] ? 9 : 8] = 1'b1;
    end else if (x[FLEN-2:FRAC_W] == '0) begin
      if (x[FRAC_W-1:0] == '0) m[x[FLEN-1] ? 3 : 4] = 1'b1;
      else m[x[FLEN-1] ? 2 : 5] = 1'b1;
    end else begin
      m[x[FLEN-1] ? 1 : 6] = 1'b1;
    end
    ref_fclass = FLEN'(m);
  endfunction

  function automatic string op_name(input logic [4:0] f5, input logic [2:0] f3);
    case ({
      f5, f3
    })
      OpFsgnj: op_name = "FSGNJ";
      OpFsgnjn: op_name = "FSGNJN";
      OpFsgnjx: op_name = "FSGNJX";
      OpFmin: op_name = "FMIN";
      OpFmax: op_name = "FMAX";
      OpFeq: op_name = "FEQ";
      OpFlt: op_name = "FLT";
      OpFle: op_name = "FLE";
      OpFclass: op_name = "FCLASS";
      default: op_name = "UNDEFINED";
    endcase
  endfunction

  function automatic logic [FLEN-1:0] rand_bits();
    rand_bits = FLEN'({$urandom, $urandom});
  endfunction

  function automatic logic [FLEN-1:0] rand_operand();
    if (($urandom & 32'd3) == 32'd0) rand_operand = specials[int'($urandom_range(NumSpecials-1))];
    else rand_operand = rand_bits();
  endfunction

  task automatic check(input string src, input logic [OpW-1:0] op, input logic [FLEN-1:0] x,
                       input logic [FLEN-1:0] y, input logic [FLEN-1:0] exp_res,
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
            "FAIL %s %s %s (funct5=%b funct3=%b) a=%h b=%h exp %h/%b got %h/%b",
            FMT,
            src,
            op_name(
                funct5, funct3
            ),
            funct5,
            funct3,
            x,
            y,
            exp_res,
            exp_flags,
            result,
            fflags
        );
    end
  endtask  // Automatic

  task automatic run_file(input string op, input logic [4:0] f5, input logic [2:0] f3);
    string path;
    int fd;
    int lines;
    logic [FLEN-1:0] fa;
    logic [FLEN-1:0] fb;
    logic [3:0] fr;
    logic [4:0] ff;
    path = {TfDir, FMT, "_", op, ".txt"};
    fd   = $fopen(path, "r");
    if (fd == 0) $fatal(1, "TB MISSING FILE: %s (run make testfloat)", path);
    lines = 0;
    while ($fscanf(
        fd, "%h %h %h %h", fa, fb, fr, ff
    ) == 4) begin
      lines++;
      check(path, {f5, f3}, fa, fb, FLEN'(fr), ff);
    end
    if (!$feof(fd)) $fatal(1, "TB BAD LINE: %s:%0d", path, lines + 1);
    $fclose(fd);
    if (lines == 0) $fatal(1, "TB EMPTY FILE: %s", path);
    $display("%s: %0d lines", path, lines);
  endtask  // Automatic

  task automatic directed_pairs();
    for (int i = 0; i < NumSpecials; i++)
      for (int j = 0; j < NumSpecials; j++) begin
        check("directed", OpFmin, specials[i], specials[j], ref_fmin(specials[i], specials[j]),
              ref_minmax_flags(specials[i][FLEN-2:0], specials[j][FLEN-2:0]));
        check("directed", OpFmax, specials[i], specials[j], ref_fmax(specials[i], specials[j]),
              ref_minmax_flags(specials[i][FLEN-2:0], specials[j][FLEN-2:0]));
        check("directed", OpFsgnj, specials[i], specials[j], ref_fsgnj(
              Funct3Fsgnj, specials[i], specials[j][FLEN-1]), 5'd0);
        check("directed", OpFsgnjn, specials[i], specials[j], ref_fsgnj(
              Funct3Fsgnjn, specials[i], specials[j][FLEN-1]), 5'd0);
        check("directed", OpFsgnjx, specials[i], specials[j], ref_fsgnj(
              Funct3Fsgnjx, specials[i], specials[j][FLEN-1]), 5'd0);
      end
  endtask  // Automatic

  task automatic directed_class();
    for (int i = 0; i < NumSpecials; i++)
      check("directed", OpFclass, specials[i], rand_bits(), ref_fclass(specials[i]), 5'd0);
  endtask  // Automatic

  task automatic directed_zero_cmp();
    logic [FLEN-1:0] z;
    logic [FLEN-1:0] y;
    for (int s = 0; s < 4; s++)
      for (int k = 0; k < FLEN - 1; k++) begin
        z = {s[0], (FLEN - 1)'(0)};
        y = {s[1], (FLEN - 1)'(1) << k};
        check("directed", OpFeq, z, y, '0, 5'd0);
        check("directed", OpFeq, y, z, '0, 5'd0);
        check("directed", OpFlt, z, y, {(FLEN - 1)'(0), ~y[FLEN-1]}, 5'd0);
        check("directed", OpFlt, y, z, {(FLEN - 1)'(0), y[FLEN-1]}, 5'd0);
      end
  endtask  // Automatic

  task automatic random_minmax(input int n);
    logic [FLEN-1:0] x;
    logic [FLEN-1:0] y;
    for (int i = 0; i < n; i++) begin
      x = rand_operand();
      y = rand_operand();
      check("random", OpFmin, x, y, ref_fmin(x, y), ref_minmax_flags(x[FLEN-2:0], y[FLEN-2:0]));
      check("random", OpFmax, x, y, ref_fmax(x, y), ref_minmax_flags(x[FLEN-2:0], y[FLEN-2:0]));
    end
  endtask  // Automatic

  task automatic undefined_ops();
    logic [OpW-1:0] ops[5] = '{
        {Funct5Fsgnj, 3'b011},
        {Funct5Fminmax, 3'b111},
        {Funct5Fcmp, 3'b011},
        {Funct5FmvXW, 3'b010},
        {5'b11111, 3'b000}
    };
    for (int k = 0; k < $size(ops); k++)
      for (int i = 0; i < NumSpecials; i++)
        check("undefined", ops[k], specials[i], specials[(i+5)%NumSpecials], '0, 5'd0);
  endtask  // Automatic

  initial begin
    run_file("eq", Funct5Fcmp, Funct3Feq);
    run_file("le", Funct5Fcmp, Funct3Fle);
    run_file("lt", Funct5Fcmp, Funct3Flt);

    directed_pairs();
    directed_class();
    directed_zero_cmp();

    random_minmax(NumRandom);

    undefined_ops();

    done = 1'b1;
  end

endmodule

`default_nettype wire
