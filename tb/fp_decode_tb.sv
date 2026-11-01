`default_nettype none

module fp_decode_tb
  import fp_pkg::*;
  import opcode_pkg::*;
();

  localparam int MinChecks = 170000;
  localparam int AWIDTH = arch_pkg::RegAddrW;
  localparam int RmW = fp_pkg::RmW;
  localparam int F5W = $bits(Funct5Fadd);
  localparam int F3W = $bits(Funct3Fsgnj);
  localparam int FmtW = $bits(FmtS);
  localparam int F7W = F5W + FmtW;

  int                 checks = 0;
  int                 errors = 0;
  int                 max_errors = 0;

  logic     [   31:0] instr;
  logic     [RmW-1:0] frm;
  logic               is_fp;
  logic               illegal;
  fp_unit_e           unit;
  logic               frs1_read;
  logic               frs2_read;
  logic               frs3_read;
  logic               frd_write;
  logic               xrd_write;
  logic               xrs1_read;
  logic     [RmW-1:0] rm;
  logic               sub;
  logic               neg_prod;
  logic               neg_add;
  logic               to_int;
  logic               is_unsigned;
  logic               sqrt;
  logic     [F5W-1:0] funct5;
  logic     [F3W-1:0] funct3;

  fp_decode dut (
      .instr      (instr),
      .frm        (frm),
      .is_fp      (is_fp),
      .illegal    (illegal),
      .unit       (unit),
      .frs1_read  (frs1_read),
      .frs2_read  (frs2_read),
      .frs3_read  (frs3_read),
      .frd_write  (frd_write),
      .xrd_write  (xrd_write),
      .xrs1_read  (xrs1_read),
      .rm         (rm),
      .sub        (sub),
      .neg_prod   (neg_prod),
      .neg_add    (neg_add),
      .to_int     (to_int),
      .is_unsigned(is_unsigned),
      .sqrt       (sqrt),
      .funct5     (funct5),
      .funct3     (funct3)
  );

  task automatic check(input string name, input logic [F5W-1:0] got, input logic [F5W-1:0] exp);
    checks++;
    if (got !== exp) begin
      errors++;
      $display("FAIL %s: got %h, expected %h", name, got, exp);
      if (errors == max_errors) $fatal(1, "TB STOPPED: %0d mismatches", errors);
    end
  endtask  // Automatic

  function automatic string label(input string name, input logic [31:0] word);
    label = $sformatf("%s word=%h frm=%b", name, word, frm);
  endfunction

  task automatic drive(input logic [31:0] word, input logic [RmW-1:0] frm_in);
    instr = word;
    frm   = frm_in;
    #1;
    check({label("pass", word), " funct5"}, funct5, F5W'(word[31:27]));
    check({label("pass", word), " funct3"}, F5W'(funct3), F5W'(word[14:12]));
  endtask  // Automatic

  task automatic chk_fp(input string name, input logic [31:0] word, input logic [RmW-1:0] frm_in,
                        input fp_unit_e exp_unit, input logic [5:0] exp_regs,
                        input logic [RmW-1:0] exp_rm, input logic [5:0] exp_ops);
    string n;
    drive(word, frm_in);
    n = label(name, word);
    check({n, " is_fp"}, F5W'(is_fp), F5W'(1'b1));
    check({n, " illegal"}, F5W'(illegal), F5W'(1'b0));
    check({n, " unit"}, F5W'(unit), F5W'(exp_unit));
    check({n, " frs1_read"}, F5W'(frs1_read), F5W'(exp_regs[5]));
    check({n, " frs2_read"}, F5W'(frs2_read), F5W'(exp_regs[4]));
    check({n, " frs3_read"}, F5W'(frs3_read), F5W'(exp_regs[3]));
    check({n, " frd_write"}, F5W'(frd_write), F5W'(exp_regs[2]));
    check({n, " xrd_write"}, F5W'(xrd_write), F5W'(exp_regs[1]));
    check({n, " xrs1_read"}, F5W'(xrs1_read), F5W'(exp_regs[0]));
    check({n, " rm"}, F5W'(rm), F5W'(exp_rm));
    check({n, " sub"}, F5W'(sub), F5W'(exp_ops[5]));
    check({n, " neg_prod"}, F5W'(neg_prod), F5W'(exp_ops[4]));
    check({n, " neg_add"}, F5W'(neg_add), F5W'(exp_ops[3]));
    check({n, " to_int"}, F5W'(to_int), F5W'(exp_ops[2]));
    check({n, " is_unsigned"}, F5W'(is_unsigned), F5W'(exp_ops[1]));
    check({n, " sqrt"}, F5W'(sqrt), F5W'(exp_ops[0]));
  endtask  // Automatic

  task automatic chk_illegal(input string name, input logic [31:0] word,
                             input logic [RmW-1:0] frm_in);
    string n;
    drive(word, frm_in);
    n = label(name, word);
    check({n, " is_fp"}, F5W'(is_fp), F5W'(1'b1));
    check({n, " illegal"}, F5W'(illegal), F5W'(1'b1));
    check({n, " unit"}, F5W'(unit), F5W'(FP_NONE));
  endtask  // Automatic

  task automatic chk_not_fp(input string name, input logic [31:0] word);
    string n;
    drive(word, RmRne);
    n = label(name, word);
    check({n, " is_fp"}, F5W'(is_fp), F5W'(1'b0));
    check({n, " illegal"}, F5W'(illegal), F5W'(1'b0));
    check({n, " unit"}, F5W'(unit), F5W'(FP_NONE));
  endtask  // Automatic

  task automatic legal_table();
    chk_fp("fmadd.s f20, f9, f25, f3, rne", 32'h19948a43, RmW'(6), FP_FMA, 6'b111100, RmRne,
           6'b000000);
    chk_fp("fmadd.s f3, f7, f14, f3, rtz", 32'h18e391c3, RmW'(3), FP_FMA, 6'b111100, RmRtz,
           6'b000000);
    chk_fp("fmadd.s f23, f6, f4, f3, rdn", 32'h18432bc3, RmW'(4), FP_FMA, 6'b111100, RmRdn,
           6'b000000);
    chk_fp("fmadd.s f31, f21, f28, f18, rup", 32'h91cabfc3, RmW'(5), FP_FMA, 6'b111100, RmRup,
           6'b000000);
    chk_fp("fmadd.s f31, f29, f4, f5, rmm", 32'h284ecfc3, RmW'(2), FP_FMA, 6'b111100, RmRmm,
           6'b000000);
    chk_fp("fmadd.s f7, f31, f3, f13, dyn", 32'h683ff3c3, RmW'(0), FP_FMA, 6'b111100, RmRne,
           6'b000000);
    chk_fp("fmadd.s f27, f17, f26, f22, dyn", 32'hb1a8fdc3, RmW'(1), FP_FMA, 6'b111100, RmRtz,
           6'b000000);
    chk_fp("fmadd.s f18, f0, f9, f26, dyn", 32'hd0907943, RmW'(2), FP_FMA, 6'b111100, RmRdn,
           6'b000000);
    chk_fp("fmadd.s f3, f12, f4, f13, dyn", 32'h684671c3, RmW'(3), FP_FMA, 6'b111100, RmRup,
           6'b000000);
    chk_fp("fmadd.s f13, f24, f9, f16, dyn", 32'h809c76c3, RmW'(4), FP_FMA, 6'b111100, RmRmm,
           6'b000000);
    chk_fp("fmsub.s f6, f21, f16, f30, rne", 32'hf10a8347, RmW'(3), FP_FMA, 6'b111100, RmRne,
           6'b001000);
    chk_fp("fmsub.s f21, f14, f12, f15, rtz", 32'h78c71ac7, RmW'(7), FP_FMA, 6'b111100, RmRtz,
           6'b001000);
    chk_fp("fmsub.s f22, f23, f5, f14, rdn", 32'h705bab47, RmW'(6), FP_FMA, 6'b111100, RmRdn,
           6'b001000);
    chk_fp("fmsub.s f12, f30, f11, f27, rup", 32'hd8bf3647, RmW'(2), FP_FMA, 6'b111100, RmRup,
           6'b001000);
    chk_fp("fmsub.s f30, f22, f9, f8, rmm", 32'h409b4f47, RmW'(5), FP_FMA, 6'b111100, RmRmm,
           6'b001000);
    chk_fp("fmsub.s f16, f26, f8, f3, dyn", 32'h188d7847, RmW'(0), FP_FMA, 6'b111100, RmRne,
           6'b001000);
    chk_fp("fmsub.s f30, f7, f3, f20, dyn", 32'ha033ff47, RmW'(1), FP_FMA, 6'b111100, RmRtz,
           6'b001000);
    chk_fp("fmsub.s f20, f12, f17, f28, dyn", 32'he1167a47, RmW'(2), FP_FMA, 6'b111100, RmRdn,
           6'b001000);
    chk_fp("fmsub.s f15, f27, f4, f13, dyn", 32'h684df7c7, RmW'(3), FP_FMA, 6'b111100, RmRup,
           6'b001000);
    chk_fp("fmsub.s f10, f14, f10, f27, dyn", 32'hd8a77547, RmW'(4), FP_FMA, 6'b111100, RmRmm,
           6'b001000);
    chk_fp("fnmsub.s f1, f24, f21, f18, rne", 32'h915c00cb, RmW'(4), FP_FMA, 6'b111100, RmRne,
           6'b010000);
    chk_fp("fnmsub.s f25, f9, f31, f20, rtz", 32'ha1f49ccb, RmW'(1), FP_FMA, 6'b111100, RmRtz,
           6'b010000);
    chk_fp("fnmsub.s f16, f7, f29, f0, rdn", 32'h01d3a84b, RmW'(4), FP_FMA, 6'b111100, RmRdn,
           6'b010000);
    chk_fp("fnmsub.s f19, f13, f18, f28, rup", 32'he126b9cb, RmW'(1), FP_FMA, 6'b111100, RmRup,
           6'b010000);
    chk_fp("fnmsub.s f27, f31, f25, f19, rmm", 32'h999fcdcb, RmW'(6), FP_FMA, 6'b111100, RmRmm,
           6'b010000);
    chk_fp("fnmsub.s f10, f3, f5, f24, dyn", 32'hc051f54b, RmW'(0), FP_FMA, 6'b111100, RmRne,
           6'b010000);
    chk_fp("fnmsub.s f21, f20, f15, f2, dyn", 32'h10fa7acb, RmW'(1), FP_FMA, 6'b111100, RmRtz,
           6'b010000);
    chk_fp("fnmsub.s f0, f5, f16, f5, dyn", 32'h2902f04b, RmW'(2), FP_FMA, 6'b111100, RmRdn,
           6'b010000);
    chk_fp("fnmsub.s f31, f9, f18, f9, dyn", 32'h4924ffcb, RmW'(3), FP_FMA, 6'b111100, RmRup,
           6'b010000);
    chk_fp("fnmsub.s f28, f3, f1, f15, dyn", 32'h7811fe4b, RmW'(4), FP_FMA, 6'b111100, RmRmm,
           6'b010000);
    chk_fp("fnmadd.s f13, f14, f29, f31, rne", 32'hf9d706cf, RmW'(0), FP_FMA, 6'b111100, RmRne,
           6'b011000);
    chk_fp("fnmadd.s f30, f3, f31, f17, rtz", 32'h89f19f4f, RmW'(7), FP_FMA, 6'b111100, RmRtz,
           6'b011000);
    chk_fp("fnmadd.s f1, f18, f29, f4, rdn", 32'h21d920cf, RmW'(1), FP_FMA, 6'b111100, RmRdn,
           6'b011000);
    chk_fp("fnmadd.s f23, f14, f31, f31, rup", 32'hf9f73bcf, RmW'(5), FP_FMA, 6'b111100, RmRup,
           6'b011000);
    chk_fp("fnmadd.s f7, f21, f0, f20, rmm", 32'ha00ac3cf, RmW'(5), FP_FMA, 6'b111100, RmRmm,
           6'b011000);
    chk_fp("fnmadd.s f27, f17, f3, f17, dyn", 32'h8838fdcf, RmW'(0), FP_FMA, 6'b111100, RmRne,
           6'b011000);
    chk_fp("fnmadd.s f25, f13, f5, f3, dyn", 32'h1856fccf, RmW'(1), FP_FMA, 6'b111100, RmRtz,
           6'b011000);
    chk_fp("fnmadd.s f19, f16, f16, f25, dyn", 32'hc90879cf, RmW'(2), FP_FMA, 6'b111100, RmRdn,
           6'b011000);
    chk_fp("fnmadd.s f21, f28, f27, f8, dyn", 32'h41be7acf, RmW'(3), FP_FMA, 6'b111100, RmRup,
           6'b011000);
    chk_fp("fnmadd.s f26, f24, f26, f13, dyn", 32'h69ac7d4f, RmW'(4), FP_FMA, 6'b111100, RmRmm,
           6'b011000);
    chk_fp("fadd.s f19, f1, f8, rne", 32'h008089d3, RmW'(3), FP_ADD, 6'b110100, RmRne, 6'b000000);
    chk_fp("fadd.s f6, f29, f5, rtz", 32'h005e9353, RmW'(1), FP_ADD, 6'b110100, RmRtz, 6'b000000);
    chk_fp("fadd.s f24, f16, f14, rdn", 32'h00e82c53, RmW'(3), FP_ADD, 6'b110100, RmRdn, 6'b000000);
    chk_fp("fadd.s f1, f12, f31, rup", 32'h01f630d3, RmW'(5), FP_ADD, 6'b110100, RmRup, 6'b000000);
    chk_fp("fadd.s f0, f18, f4, rmm", 32'h00494053, RmW'(4), FP_ADD, 6'b110100, RmRmm, 6'b000000);
    chk_fp("fadd.s f31, f26, f3, dyn", 32'h003d7fd3, RmW'(0), FP_ADD, 6'b110100, RmRne, 6'b000000);
    chk_fp("fadd.s f7, f5, f10, dyn", 32'h00a2f3d3, RmW'(1), FP_ADD, 6'b110100, RmRtz, 6'b000000);
    chk_fp("fadd.s f5, f17, f5, dyn", 32'h0058f2d3, RmW'(2), FP_ADD, 6'b110100, RmRdn, 6'b000000);
    chk_fp("fadd.s f28, f12, f20, dyn", 32'h01467e53, RmW'(3), FP_ADD, 6'b110100, RmRup, 6'b000000);
    chk_fp("fadd.s f12, f4, f21, dyn", 32'h01527653, RmW'(4), FP_ADD, 6'b110100, RmRmm, 6'b000000);
    chk_fp("fsub.s f30, f29, f24, rne", 32'h098e8f53, RmW'(3), FP_ADD, 6'b110100, RmRne, 6'b100000);
    chk_fp("fsub.s f5, f12, f25, rtz", 32'h099612d3, RmW'(1), FP_ADD, 6'b110100, RmRtz, 6'b100000);
    chk_fp("fsub.s f6, f26, f31, rdn", 32'h09fd2353, RmW'(4), FP_ADD, 6'b110100, RmRdn, 6'b100000);
    chk_fp("fsub.s f16, f12, f28, rup", 32'h09c63853, RmW'(6), FP_ADD, 6'b110100, RmRup, 6'b100000);
    chk_fp("fsub.s f29, f2, f6, rmm", 32'h08614ed3, RmW'(0), FP_ADD, 6'b110100, RmRmm, 6'b100000);
    chk_fp("fsub.s f11, f28, f16, dyn", 32'h090e75d3, RmW'(0), FP_ADD, 6'b110100, RmRne, 6'b100000);
    chk_fp("fsub.s f0, f20, f26, dyn", 32'h09aa7053, RmW'(1), FP_ADD, 6'b110100, RmRtz, 6'b100000);
    chk_fp("fsub.s f5, f10, f25, dyn", 32'h099572d3, RmW'(2), FP_ADD, 6'b110100, RmRdn, 6'b100000);
    chk_fp("fsub.s f25, f25, f13, dyn", 32'h08dcfcd3, RmW'(3), FP_ADD, 6'b110100, RmRup, 6'b100000);
    chk_fp("fsub.s f9, f25, f5, dyn", 32'h085cf4d3, RmW'(4), FP_ADD, 6'b110100, RmRmm, 6'b100000);
    chk_fp("fmul.s f8, f2, f30, rne", 32'h11e10453, RmW'(2), FP_MUL, 6'b110100, RmRne, 6'b000000);
    chk_fp("fmul.s f24, f22, f7, rtz", 32'h107b1c53, RmW'(4), FP_MUL, 6'b110100, RmRtz, 6'b000000);
    chk_fp("fmul.s f24, f23, f28, rdn", 32'h11cbac53, RmW'(2), FP_MUL, 6'b110100, RmRdn, 6'b000000);
    chk_fp("fmul.s f8, f22, f27, rup", 32'h11bb3453, RmW'(0), FP_MUL, 6'b110100, RmRup, 6'b000000);
    chk_fp("fmul.s f7, f12, f8, rmm", 32'h108643d3, RmW'(4), FP_MUL, 6'b110100, RmRmm, 6'b000000);
    chk_fp("fmul.s f13, f16, f15, dyn", 32'h10f876d3, RmW'(0), FP_MUL, 6'b110100, RmRne, 6'b000000);
    chk_fp("fmul.s f3, f23, f28, dyn", 32'h11cbf1d3, RmW'(1), FP_MUL, 6'b110100, RmRtz, 6'b000000);
    chk_fp("fmul.s f11, f3, f18, dyn", 32'h1121f5d3, RmW'(2), FP_MUL, 6'b110100, RmRdn, 6'b000000);
    chk_fp("fmul.s f31, f14, f2, dyn", 32'h10277fd3, RmW'(3), FP_MUL, 6'b110100, RmRup, 6'b000000);
    chk_fp("fmul.s f30, f10, f8, dyn", 32'h10857f53, RmW'(4), FP_MUL, 6'b110100, RmRmm, 6'b000000);
    chk_fp("fdiv.s f28, f31, f15, rne", 32'h18ff8e53, RmW'(0), FP_DIV_SQRT, 6'b110100, RmRne,
           6'b000000);
    chk_fp("fdiv.s f26, f12, f26, rtz", 32'h19a61d53, RmW'(7), FP_DIV_SQRT, 6'b110100, RmRtz,
           6'b000000);
    chk_fp("fdiv.s f6, f16, f14, rdn", 32'h18e82353, RmW'(3), FP_DIV_SQRT, 6'b110100, RmRdn,
           6'b000000);
    chk_fp("fdiv.s f15, f12, f10, rup", 32'h18a637d3, RmW'(0), FP_DIV_SQRT, 6'b110100, RmRup,
           6'b000000);
    chk_fp("fdiv.s f25, f4, f10, rmm", 32'h18a24cd3, RmW'(0), FP_DIV_SQRT, 6'b110100, RmRmm,
           6'b000000);
    chk_fp("fdiv.s f2, f4, f23, dyn", 32'h19727153, RmW'(0), FP_DIV_SQRT, 6'b110100, RmRne,
           6'b000000);
    chk_fp("fdiv.s f6, f8, f6, dyn", 32'h18647353, RmW'(1), FP_DIV_SQRT, 6'b110100, RmRtz,
           6'b000000);
    chk_fp("fdiv.s f30, f18, f1, dyn", 32'h18197f53, RmW'(2), FP_DIV_SQRT, 6'b110100, RmRdn,
           6'b000000);
    chk_fp("fdiv.s f12, f18, f3, dyn", 32'h18397653, RmW'(3), FP_DIV_SQRT, 6'b110100, RmRup,
           6'b000000);
    chk_fp("fdiv.s f31, f10, f7, dyn", 32'h18757fd3, RmW'(4), FP_DIV_SQRT, 6'b110100, RmRmm,
           6'b000000);
    chk_fp("fsqrt.s f10, f24, rne", 32'h580c0553, RmW'(7), FP_DIV_SQRT, 6'b100100, RmRne,
           6'b000001);
    chk_fp("fsqrt.s f21, f29, rtz", 32'h580e9ad3, RmW'(5), FP_DIV_SQRT, 6'b100100, RmRtz,
           6'b000001);
    chk_fp("fsqrt.s f10, f6, rdn", 32'h58032553, RmW'(4), FP_DIV_SQRT, 6'b100100, RmRdn, 6'b000001);
    chk_fp("fsqrt.s f2, f0, rup", 32'h58003153, RmW'(4), FP_DIV_SQRT, 6'b100100, RmRup, 6'b000001);
    chk_fp("fsqrt.s f11, f7, rmm", 32'h5803c5d3, RmW'(6), FP_DIV_SQRT, 6'b100100, RmRmm, 6'b000001);
    chk_fp("fsqrt.s f11, f20, dyn", 32'h580a75d3, RmW'(0), FP_DIV_SQRT, 6'b100100, RmRne,
           6'b000001);
    chk_fp("fsqrt.s f1, f23, dyn", 32'h580bf0d3, RmW'(1), FP_DIV_SQRT, 6'b100100, RmRtz, 6'b000001);
    chk_fp("fsqrt.s f0, f4, dyn", 32'h58027053, RmW'(2), FP_DIV_SQRT, 6'b100100, RmRdn, 6'b000001);
    chk_fp("fsqrt.s f4, f12, dyn", 32'h58067253, RmW'(3), FP_DIV_SQRT, 6'b100100, RmRup, 6'b000001);
    chk_fp("fsqrt.s f27, f11, dyn", 32'h5805fdd3, RmW'(4), FP_DIV_SQRT, 6'b100100, RmRmm,
           6'b000001);
    chk_fp("fsgnj.s f9, f19, f24", 32'h218984d3, RmW'(0), FP_MISC, 6'b110100, RmRne, 6'b000000);
    chk_fp("fsgnj.s f14, f11, f28", 32'h21c58753, RmW'(5), FP_MISC, 6'b110100, RmRne, 6'b000000);
    chk_fp("fsgnj.s f7, f16, f26", 32'h21a803d3, RmW'(7), FP_MISC, 6'b110100, RmRne, 6'b000000);
    chk_fp("fsgnj.s f10, f20, f29", 32'h21da0553, RmW'(7), FP_MISC, 6'b110100, RmRne, 6'b000000);
    chk_fp("fsgnjn.s f30, f31, f9", 32'h209f9f53, RmW'(0), FP_MISC, 6'b110100, RmRne, 6'b000000);
    chk_fp("fsgnjn.s f27, f16, f3", 32'h20381dd3, RmW'(5), FP_MISC, 6'b110100, RmRne, 6'b000000);
    chk_fp("fsgnjn.s f20, f19, f8", 32'h20899a53, RmW'(7), FP_MISC, 6'b110100, RmRne, 6'b000000);
    chk_fp("fsgnjn.s f24, f9, f5", 32'h20549c53, RmW'(0), FP_MISC, 6'b110100, RmRne, 6'b000000);
    chk_fp("fsgnjx.s f19, f11, f26", 32'h21a5a9d3, RmW'(0), FP_MISC, 6'b110100, RmRne, 6'b000000);
    chk_fp("fsgnjx.s f24, f9, f30", 32'h21e4ac53, RmW'(5), FP_MISC, 6'b110100, RmRne, 6'b000000);
    chk_fp("fsgnjx.s f7, f8, f30", 32'h21e423d3, RmW'(7), FP_MISC, 6'b110100, RmRne, 6'b000000);
    chk_fp("fsgnjx.s f3, f2, f0", 32'h200121d3, RmW'(0), FP_MISC, 6'b110100, RmRne, 6'b000000);
    chk_fp("fmin.s f9, f7, f23", 32'h297384d3, RmW'(0), FP_MISC, 6'b110100, RmRne, 6'b000000);
    chk_fp("fmin.s f19, f27, f15", 32'h28fd89d3, RmW'(5), FP_MISC, 6'b110100, RmRne, 6'b000000);
    chk_fp("fmin.s f18, f9, f9", 32'h28948953, RmW'(7), FP_MISC, 6'b110100, RmRne, 6'b000000);
    chk_fp("fmin.s f16, f0, f24", 32'h29800853, RmW'(5), FP_MISC, 6'b110100, RmRne, 6'b000000);
    chk_fp("fmax.s f11, f18, f23", 32'h297915d3, RmW'(0), FP_MISC, 6'b110100, RmRne, 6'b000000);
    chk_fp("fmax.s f1, f22, f17", 32'h291b10d3, RmW'(5), FP_MISC, 6'b110100, RmRne, 6'b000000);
    chk_fp("fmax.s f2, f21, f12", 32'h28ca9153, RmW'(7), FP_MISC, 6'b110100, RmRne, 6'b000000);
    chk_fp("fmax.s f16, f20, f14", 32'h28ea1853, RmW'(3), FP_MISC, 6'b110100, RmRne, 6'b000000);
    chk_fp("fcvt.w.s x6, f9, rne", 32'hc0048353, RmW'(1), FP_CVT, 6'b100010, RmRne, 6'b000100);
    chk_fp("fcvt.w.s x10, f28, rtz", 32'hc00e1553, RmW'(0), FP_CVT, 6'b100010, RmRtz, 6'b000100);
    chk_fp("fcvt.w.s x4, f28, rdn", 32'hc00e2253, RmW'(5), FP_CVT, 6'b100010, RmRdn, 6'b000100);
    chk_fp("fcvt.w.s x17, f26, rup", 32'hc00d38d3, RmW'(4), FP_CVT, 6'b100010, RmRup, 6'b000100);
    chk_fp("fcvt.w.s x9, f3, rmm", 32'hc001c4d3, RmW'(3), FP_CVT, 6'b100010, RmRmm, 6'b000100);
    chk_fp("fcvt.w.s x10, f3, dyn", 32'hc001f553, RmW'(0), FP_CVT, 6'b100010, RmRne, 6'b000100);
    chk_fp("fcvt.w.s x13, f17, dyn", 32'hc008f6d3, RmW'(1), FP_CVT, 6'b100010, RmRtz, 6'b000100);
    chk_fp("fcvt.w.s x19, f12, dyn", 32'hc00679d3, RmW'(2), FP_CVT, 6'b100010, RmRdn, 6'b000100);
    chk_fp("fcvt.w.s x15, f11, dyn", 32'hc005f7d3, RmW'(3), FP_CVT, 6'b100010, RmRup, 6'b000100);
    chk_fp("fcvt.w.s x18, f6, dyn", 32'hc0037953, RmW'(4), FP_CVT, 6'b100010, RmRmm, 6'b000100);
    chk_fp("fcvt.wu.s x1, f6, rne", 32'hc01300d3, RmW'(7), FP_CVT, 6'b100010, RmRne, 6'b000110);
    chk_fp("fcvt.wu.s x17, f7, rtz", 32'hc01398d3, RmW'(3), FP_CVT, 6'b100010, RmRtz, 6'b000110);
    chk_fp("fcvt.wu.s x3, f23, rdn", 32'hc01ba1d3, RmW'(5), FP_CVT, 6'b100010, RmRdn, 6'b000110);
    chk_fp("fcvt.wu.s x6, f11, rup", 32'hc015b353, RmW'(3), FP_CVT, 6'b100010, RmRup, 6'b000110);
    chk_fp("fcvt.wu.s x2, f6, rmm", 32'hc0134153, RmW'(0), FP_CVT, 6'b100010, RmRmm, 6'b000110);
    chk_fp("fcvt.wu.s x29, f9, dyn", 32'hc014fed3, RmW'(0), FP_CVT, 6'b100010, RmRne, 6'b000110);
    chk_fp("fcvt.wu.s x23, f29, dyn", 32'hc01efbd3, RmW'(1), FP_CVT, 6'b100010, RmRtz, 6'b000110);
    chk_fp("fcvt.wu.s x15, f20, dyn", 32'hc01a77d3, RmW'(2), FP_CVT, 6'b100010, RmRdn, 6'b000110);
    chk_fp("fcvt.wu.s x28, f22, dyn", 32'hc01b7e53, RmW'(3), FP_CVT, 6'b100010, RmRup, 6'b000110);
    chk_fp("fcvt.wu.s x6, f0, dyn", 32'hc0107353, RmW'(4), FP_CVT, 6'b100010, RmRmm, 6'b000110);
    chk_fp("fmv.x.w x25, f24", 32'he00c0cd3, RmW'(0), FP_MV_X_W, 6'b100010, RmRne, 6'b000000);
    chk_fp("fmv.x.w x20, f15", 32'he0078a53, RmW'(5), FP_MV_X_W, 6'b100010, RmRne, 6'b000000);
    chk_fp("fmv.x.w x22, f2", 32'he0010b53, RmW'(7), FP_MV_X_W, 6'b100010, RmRne, 6'b000000);
    chk_fp("fmv.x.w x28, f21", 32'he00a8e53, RmW'(6), FP_MV_X_W, 6'b100010, RmRne, 6'b000000);
    chk_fp("feq.s x11, f3, f6", 32'ha061a5d3, RmW'(0), FP_MISC, 6'b110010, RmRne, 6'b000000);
    chk_fp("feq.s x11, f31, f17", 32'ha11fa5d3, RmW'(5), FP_MISC, 6'b110010, RmRne, 6'b000000);
    chk_fp("feq.s x27, f3, f0", 32'ha001add3, RmW'(7), FP_MISC, 6'b110010, RmRne, 6'b000000);
    chk_fp("feq.s x24, f1, f3", 32'ha030ac53, RmW'(1), FP_MISC, 6'b110010, RmRne, 6'b000000);
    chk_fp("flt.s x19, f26, f16", 32'ha10d19d3, RmW'(0), FP_MISC, 6'b110010, RmRne, 6'b000000);
    chk_fp("flt.s x10, f22, f24", 32'ha18b1553, RmW'(5), FP_MISC, 6'b110010, RmRne, 6'b000000);
    chk_fp("flt.s x22, f15, f24", 32'ha1879b53, RmW'(7), FP_MISC, 6'b110010, RmRne, 6'b000000);
    chk_fp("flt.s x5, f12, f17", 32'ha11612d3, RmW'(0), FP_MISC, 6'b110010, RmRne, 6'b000000);
    chk_fp("fle.s x14, f28, f8", 32'ha08e0753, RmW'(0), FP_MISC, 6'b110010, RmRne, 6'b000000);
    chk_fp("fle.s x19, f0, f24", 32'ha18009d3, RmW'(5), FP_MISC, 6'b110010, RmRne, 6'b000000);
    chk_fp("fle.s x14, f18, f8", 32'ha0890753, RmW'(7), FP_MISC, 6'b110010, RmRne, 6'b000000);
    chk_fp("fle.s x29, f15, f25", 32'ha1978ed3, RmW'(7), FP_MISC, 6'b110010, RmRne, 6'b000000);
    chk_fp("fclass.s x12, f19", 32'he0099653, RmW'(0), FP_MISC, 6'b100010, RmRne, 6'b000000);
    chk_fp("fclass.s x3, f15", 32'he00791d3, RmW'(5), FP_MISC, 6'b100010, RmRne, 6'b000000);
    chk_fp("fclass.s x21, f28", 32'he00e1ad3, RmW'(7), FP_MISC, 6'b100010, RmRne, 6'b000000);
    chk_fp("fclass.s x10, f22", 32'he00b1553, RmW'(2), FP_MISC, 6'b100010, RmRne, 6'b000000);
    chk_fp("fcvt.s.w f21, x7, rne", 32'hd0038ad3, RmW'(6), FP_CVT, 6'b000101, RmRne, 6'b000000);
    chk_fp("fcvt.s.w f19, x12, rtz", 32'hd00619d3, RmW'(1), FP_CVT, 6'b000101, RmRtz, 6'b000000);
    chk_fp("fcvt.s.w f31, x5, rdn", 32'hd002afd3, RmW'(5), FP_CVT, 6'b000101, RmRdn, 6'b000000);
    chk_fp("fcvt.s.w f8, x1, rup", 32'hd000b453, RmW'(0), FP_CVT, 6'b000101, RmRup, 6'b000000);
    chk_fp("fcvt.s.w f23, x8, rmm", 32'hd0044bd3, RmW'(5), FP_CVT, 6'b000101, RmRmm, 6'b000000);
    chk_fp("fcvt.s.w f9, x14, dyn", 32'hd00774d3, RmW'(0), FP_CVT, 6'b000101, RmRne, 6'b000000);
    chk_fp("fcvt.s.w f9, x18, dyn", 32'hd00974d3, RmW'(1), FP_CVT, 6'b000101, RmRtz, 6'b000000);
    chk_fp("fcvt.s.w f12, x30, dyn", 32'hd00f7653, RmW'(2), FP_CVT, 6'b000101, RmRdn, 6'b000000);
    chk_fp("fcvt.s.w f19, x21, dyn", 32'hd00af9d3, RmW'(3), FP_CVT, 6'b000101, RmRup, 6'b000000);
    chk_fp("fcvt.s.w f14, x11, dyn", 32'hd005f753, RmW'(4), FP_CVT, 6'b000101, RmRmm, 6'b000000);
    chk_fp("fcvt.s.wu f4, x28, rne", 32'hd01e0253, RmW'(2), FP_CVT, 6'b000101, RmRne, 6'b000010);
    chk_fp("fcvt.s.wu f23, x2, rtz", 32'hd0111bd3, RmW'(0), FP_CVT, 6'b000101, RmRtz, 6'b000010);
    chk_fp("fcvt.s.wu f16, x7, rdn", 32'hd013a853, RmW'(3), FP_CVT, 6'b000101, RmRdn, 6'b000010);
    chk_fp("fcvt.s.wu f28, x1, rup", 32'hd010be53, RmW'(7), FP_CVT, 6'b000101, RmRup, 6'b000010);
    chk_fp("fcvt.s.wu f0, x1, rmm", 32'hd010c053, RmW'(5), FP_CVT, 6'b000101, RmRmm, 6'b000010);
    chk_fp("fcvt.s.wu f23, x21, dyn", 32'hd01afbd3, RmW'(0), FP_CVT, 6'b000101, RmRne, 6'b000010);
    chk_fp("fcvt.s.wu f21, x30, dyn", 32'hd01f7ad3, RmW'(1), FP_CVT, 6'b000101, RmRtz, 6'b000010);
    chk_fp("fcvt.s.wu f8, x2, dyn", 32'hd0117453, RmW'(2), FP_CVT, 6'b000101, RmRdn, 6'b000010);
    chk_fp("fcvt.s.wu f25, x21, dyn", 32'hd01afcd3, RmW'(3), FP_CVT, 6'b000101, RmRup, 6'b000010);
    chk_fp("fcvt.s.wu f28, x25, dyn", 32'hd01cfe53, RmW'(4), FP_CVT, 6'b000101, RmRmm, 6'b000010);
    chk_fp("fmv.w.x f22, x27", 32'hf00d8b53, RmW'(0), FP_MV_W_X, 6'b000101, RmRne, 6'b000000);
    chk_fp("fmv.w.x f28, x12", 32'hf0060e53, RmW'(5), FP_MV_W_X, 6'b000101, RmRne, 6'b000000);
    chk_fp("fmv.w.x f0, x20", 32'hf00a0053, RmW'(7), FP_MV_W_X, 6'b000101, RmRne, 6'b000000);
    chk_fp("fmv.w.x f31, x25", 32'hf00c8fd3, RmW'(4), FP_MV_W_X, 6'b000101, RmRne, 6'b000000);
    chk_fp("flw f16, 0(x29)", 32'h000ea807, RmW'(0), FP_LOAD, 6'b000101, RmRne, 6'b000000);
    chk_fp("flw f1, 12(x20)", 32'h00ca2087, RmW'(5), FP_LOAD, 6'b000101, RmRne, 6'b000000);
    chk_fp("flw f3, -4(x26)", 32'hffcd2187, RmW'(5), FP_LOAD, 6'b000101, RmRne, 6'b000000);
    chk_fp("flw f10, 2047(x5)", 32'h7ff2a507, RmW'(0), FP_LOAD, 6'b000101, RmRne, 6'b000000);
    chk_fp("flw f9, -2048(x13)", 32'h8006a487, RmW'(2), FP_LOAD, 6'b000101, RmRne, 6'b000000);
    chk_fp("fsw f5, 0(x22)", 32'h005b2027, RmW'(5), FP_STORE, 6'b010001, RmRne, 6'b000000);
    chk_fp("fsw f27, 12(x22)", 32'h01bb2627, RmW'(2), FP_STORE, 6'b010001, RmRne, 6'b000000);
    chk_fp("fsw f21, -4(x14)", 32'hff572e27, RmW'(4), FP_STORE, 6'b010001, RmRne, 6'b000000);
    chk_fp("fsw f30, 2047(x2)", 32'h7fe12fa7, RmW'(4), FP_STORE, 6'b010001, RmRne, 6'b000000);
    chk_fp("fsw f29, -2048(x17)", 32'h81d8a027, RmW'(5), FP_STORE, 6'b010001, RmRne, 6'b000000);
  endtask  // Automatic

  task automatic illegal_table();
    chk_illegal("fmadd.s fmt 01", 32'h1b948a43, RmW'(0));
    chk_illegal("fmadd.s fmt 10", 32'h1d948a43, RmW'(0));
    chk_illegal("fmadd.s fmt 11", 32'h1f948a43, RmW'(0));
    chk_illegal("fmsub.s fmt 01", 32'hf30a8347, RmW'(0));
    chk_illegal("fmsub.s fmt 10", 32'hf50a8347, RmW'(0));
    chk_illegal("fmsub.s fmt 11", 32'hf70a8347, RmW'(0));
    chk_illegal("fnmsub.s fmt 01", 32'h935c00cb, RmW'(0));
    chk_illegal("fnmsub.s fmt 10", 32'h955c00cb, RmW'(0));
    chk_illegal("fnmsub.s fmt 11", 32'h975c00cb, RmW'(0));
    chk_illegal("fnmadd.s fmt 01", 32'hfbd706cf, RmW'(0));
    chk_illegal("fnmadd.s fmt 10", 32'hfdd706cf, RmW'(0));
    chk_illegal("fnmadd.s fmt 11", 32'hffd706cf, RmW'(0));
    chk_illegal("fadd.s fmt 01", 32'h028089d3, RmW'(0));
    chk_illegal("fadd.s fmt 10", 32'h048089d3, RmW'(0));
    chk_illegal("fadd.s fmt 11", 32'h068089d3, RmW'(0));
    chk_illegal("fsub.s fmt 01", 32'h0b8e8f53, RmW'(0));
    chk_illegal("fsub.s fmt 10", 32'h0d8e8f53, RmW'(0));
    chk_illegal("fsub.s fmt 11", 32'h0f8e8f53, RmW'(0));
    chk_illegal("fmul.s fmt 01", 32'h13e10453, RmW'(0));
    chk_illegal("fmul.s fmt 10", 32'h15e10453, RmW'(0));
    chk_illegal("fmul.s fmt 11", 32'h17e10453, RmW'(0));
    chk_illegal("fdiv.s fmt 01", 32'h1aff8e53, RmW'(0));
    chk_illegal("fdiv.s fmt 10", 32'h1cff8e53, RmW'(0));
    chk_illegal("fdiv.s fmt 11", 32'h1eff8e53, RmW'(0));
    chk_illegal("fsqrt.s fmt 01", 32'h5a0c0553, RmW'(0));
    chk_illegal("fsqrt.s fmt 10", 32'h5c0c0553, RmW'(0));
    chk_illegal("fsqrt.s fmt 11", 32'h5e0c0553, RmW'(0));
    chk_illegal("fsgnj.s fmt 01", 32'h238984d3, RmW'(0));
    chk_illegal("fsgnj.s fmt 10", 32'h258984d3, RmW'(0));
    chk_illegal("fsgnj.s fmt 11", 32'h278984d3, RmW'(0));
    chk_illegal("fsgnjn.s fmt 01", 32'h229f9f53, RmW'(0));
    chk_illegal("fsgnjn.s fmt 10", 32'h249f9f53, RmW'(0));
    chk_illegal("fsgnjn.s fmt 11", 32'h269f9f53, RmW'(0));
    chk_illegal("fsgnjx.s fmt 01", 32'h23a5a9d3, RmW'(0));
    chk_illegal("fsgnjx.s fmt 10", 32'h25a5a9d3, RmW'(0));
    chk_illegal("fsgnjx.s fmt 11", 32'h27a5a9d3, RmW'(0));
    chk_illegal("fmin.s fmt 01", 32'h2b7384d3, RmW'(0));
    chk_illegal("fmin.s fmt 10", 32'h2d7384d3, RmW'(0));
    chk_illegal("fmin.s fmt 11", 32'h2f7384d3, RmW'(0));
    chk_illegal("fmax.s fmt 01", 32'h2b7915d3, RmW'(0));
    chk_illegal("fmax.s fmt 10", 32'h2d7915d3, RmW'(0));
    chk_illegal("fmax.s fmt 11", 32'h2f7915d3, RmW'(0));
    chk_illegal("fcvt.w.s fmt 01", 32'hc2048353, RmW'(0));
    chk_illegal("fcvt.w.s fmt 10", 32'hc4048353, RmW'(0));
    chk_illegal("fcvt.w.s fmt 11", 32'hc6048353, RmW'(0));
    chk_illegal("fcvt.wu.s fmt 01", 32'hc21300d3, RmW'(0));
    chk_illegal("fcvt.wu.s fmt 10", 32'hc41300d3, RmW'(0));
    chk_illegal("fcvt.wu.s fmt 11", 32'hc61300d3, RmW'(0));
    chk_illegal("fmv.x.w fmt 01", 32'he20c0cd3, RmW'(0));
    chk_illegal("fmv.x.w fmt 10", 32'he40c0cd3, RmW'(0));
    chk_illegal("fmv.x.w fmt 11", 32'he60c0cd3, RmW'(0));
    chk_illegal("feq.s fmt 01", 32'ha261a5d3, RmW'(0));
    chk_illegal("feq.s fmt 10", 32'ha461a5d3, RmW'(0));
    chk_illegal("feq.s fmt 11", 32'ha661a5d3, RmW'(0));
    chk_illegal("flt.s fmt 01", 32'ha30d19d3, RmW'(0));
    chk_illegal("flt.s fmt 10", 32'ha50d19d3, RmW'(0));
    chk_illegal("flt.s fmt 11", 32'ha70d19d3, RmW'(0));
    chk_illegal("fle.s fmt 01", 32'ha28e0753, RmW'(0));
    chk_illegal("fle.s fmt 10", 32'ha48e0753, RmW'(0));
    chk_illegal("fle.s fmt 11", 32'ha68e0753, RmW'(0));
    chk_illegal("fclass.s fmt 01", 32'he2099653, RmW'(0));
    chk_illegal("fclass.s fmt 10", 32'he4099653, RmW'(0));
    chk_illegal("fclass.s fmt 11", 32'he6099653, RmW'(0));
    chk_illegal("fcvt.s.w fmt 01", 32'hd2038ad3, RmW'(0));
    chk_illegal("fcvt.s.w fmt 10", 32'hd4038ad3, RmW'(0));
    chk_illegal("fcvt.s.w fmt 11", 32'hd6038ad3, RmW'(0));
    chk_illegal("fcvt.s.wu fmt 01", 32'hd21e0253, RmW'(0));
    chk_illegal("fcvt.s.wu fmt 10", 32'hd41e0253, RmW'(0));
    chk_illegal("fcvt.s.wu fmt 11", 32'hd61e0253, RmW'(0));
    chk_illegal("fmv.w.x fmt 01", 32'hf20d8b53, RmW'(0));
    chk_illegal("fmv.w.x fmt 10", 32'hf40d8b53, RmW'(0));
    chk_illegal("fmv.w.x fmt 11", 32'hf60d8b53, RmW'(0));
    chk_illegal("fcvt.w.s rs2 00010", 32'hc0248353, RmW'(0));
    chk_illegal("fcvt.w.s rs2 00011", 32'hc0348353, RmW'(0));
    chk_illegal("fcvt.wu.s rs2 00010", 32'hc02300d3, RmW'(0));
    chk_illegal("fcvt.s.w rs2 00010", 32'hd0238ad3, RmW'(0));
    chk_illegal("fcvt.s.wu rs2 00011", 32'hd03e0253, RmW'(0));
    chk_illegal("fsqrt.s rs2 00001", 32'h581c0553, RmW'(0));
    chk_illegal("fsqrt.s rs2 10000", 32'h590c0553, RmW'(0));
    chk_illegal("fmv.x.w rs2 00001", 32'he01c0cd3, RmW'(0));
    chk_illegal("fclass.s rs2 00001", 32'he0199653, RmW'(0));
    chk_illegal("fmv.w.x rs2 00001", 32'hf01d8b53, RmW'(0));
    chk_illegal("fmadd.s rm 101", 32'h1994da43, RmW'(0));
    chk_illegal("fmadd.s rm 110", 32'h1994ea43, RmW'(0));
    chk_illegal("fmadd.s rm 111 frm 101", 32'h1994fa43, RmW'(5));
    chk_illegal("fmadd.s rm 111 frm 110", 32'h1994fa43, RmW'(6));
    chk_illegal("fmadd.s rm 111 frm 111", 32'h1994fa43, RmW'(7));
    chk_illegal("fmsub.s rm 101", 32'hf10ad347, RmW'(0));
    chk_illegal("fmsub.s rm 110", 32'hf10ae347, RmW'(0));
    chk_illegal("fmsub.s rm 111 frm 101", 32'hf10af347, RmW'(5));
    chk_illegal("fmsub.s rm 111 frm 110", 32'hf10af347, RmW'(6));
    chk_illegal("fmsub.s rm 111 frm 111", 32'hf10af347, RmW'(7));
    chk_illegal("fnmsub.s rm 101", 32'h915c50cb, RmW'(0));
    chk_illegal("fnmsub.s rm 110", 32'h915c60cb, RmW'(0));
    chk_illegal("fnmsub.s rm 111 frm 101", 32'h915c70cb, RmW'(5));
    chk_illegal("fnmsub.s rm 111 frm 110", 32'h915c70cb, RmW'(6));
    chk_illegal("fnmsub.s rm 111 frm 111", 32'h915c70cb, RmW'(7));
    chk_illegal("fnmadd.s rm 101", 32'hf9d756cf, RmW'(0));
    chk_illegal("fnmadd.s rm 110", 32'hf9d766cf, RmW'(0));
    chk_illegal("fnmadd.s rm 111 frm 101", 32'hf9d776cf, RmW'(5));
    chk_illegal("fnmadd.s rm 111 frm 110", 32'hf9d776cf, RmW'(6));
    chk_illegal("fnmadd.s rm 111 frm 111", 32'hf9d776cf, RmW'(7));
    chk_illegal("fadd.s rm 101", 32'h0080d9d3, RmW'(0));
    chk_illegal("fadd.s rm 110", 32'h0080e9d3, RmW'(0));
    chk_illegal("fadd.s rm 111 frm 101", 32'h0080f9d3, RmW'(5));
    chk_illegal("fadd.s rm 111 frm 110", 32'h0080f9d3, RmW'(6));
    chk_illegal("fadd.s rm 111 frm 111", 32'h0080f9d3, RmW'(7));
    chk_illegal("fsub.s rm 101", 32'h098edf53, RmW'(0));
    chk_illegal("fsub.s rm 110", 32'h098eef53, RmW'(0));
    chk_illegal("fsub.s rm 111 frm 101", 32'h098eff53, RmW'(5));
    chk_illegal("fsub.s rm 111 frm 110", 32'h098eff53, RmW'(6));
    chk_illegal("fsub.s rm 111 frm 111", 32'h098eff53, RmW'(7));
    chk_illegal("fmul.s rm 101", 32'h11e15453, RmW'(0));
    chk_illegal("fmul.s rm 110", 32'h11e16453, RmW'(0));
    chk_illegal("fmul.s rm 111 frm 101", 32'h11e17453, RmW'(5));
    chk_illegal("fmul.s rm 111 frm 110", 32'h11e17453, RmW'(6));
    chk_illegal("fmul.s rm 111 frm 111", 32'h11e17453, RmW'(7));
    chk_illegal("fdiv.s rm 101", 32'h18ffde53, RmW'(0));
    chk_illegal("fdiv.s rm 110", 32'h18ffee53, RmW'(0));
    chk_illegal("fdiv.s rm 111 frm 101", 32'h18fffe53, RmW'(5));
    chk_illegal("fdiv.s rm 111 frm 110", 32'h18fffe53, RmW'(6));
    chk_illegal("fdiv.s rm 111 frm 111", 32'h18fffe53, RmW'(7));
    chk_illegal("fsqrt.s rm 101", 32'h580c5553, RmW'(0));
    chk_illegal("fsqrt.s rm 110", 32'h580c6553, RmW'(0));
    chk_illegal("fsqrt.s rm 111 frm 101", 32'h580c7553, RmW'(5));
    chk_illegal("fsqrt.s rm 111 frm 110", 32'h580c7553, RmW'(6));
    chk_illegal("fsqrt.s rm 111 frm 111", 32'h580c7553, RmW'(7));
    chk_illegal("fcvt.w.s rm 101", 32'hc004d353, RmW'(0));
    chk_illegal("fcvt.w.s rm 110", 32'hc004e353, RmW'(0));
    chk_illegal("fcvt.w.s rm 111 frm 101", 32'hc004f353, RmW'(5));
    chk_illegal("fcvt.w.s rm 111 frm 110", 32'hc004f353, RmW'(6));
    chk_illegal("fcvt.w.s rm 111 frm 111", 32'hc004f353, RmW'(7));
    chk_illegal("fcvt.wu.s rm 101", 32'hc01350d3, RmW'(0));
    chk_illegal("fcvt.wu.s rm 110", 32'hc01360d3, RmW'(0));
    chk_illegal("fcvt.wu.s rm 111 frm 101", 32'hc01370d3, RmW'(5));
    chk_illegal("fcvt.wu.s rm 111 frm 110", 32'hc01370d3, RmW'(6));
    chk_illegal("fcvt.wu.s rm 111 frm 111", 32'hc01370d3, RmW'(7));
    chk_illegal("fcvt.s.w rm 101", 32'hd003dad3, RmW'(0));
    chk_illegal("fcvt.s.w rm 110", 32'hd003ead3, RmW'(0));
    chk_illegal("fcvt.s.w rm 111 frm 101", 32'hd003fad3, RmW'(5));
    chk_illegal("fcvt.s.w rm 111 frm 110", 32'hd003fad3, RmW'(6));
    chk_illegal("fcvt.s.w rm 111 frm 111", 32'hd003fad3, RmW'(7));
    chk_illegal("fcvt.s.wu rm 101", 32'hd01e5253, RmW'(0));
    chk_illegal("fcvt.s.wu rm 110", 32'hd01e6253, RmW'(0));
    chk_illegal("fcvt.s.wu rm 111 frm 101", 32'hd01e7253, RmW'(5));
    chk_illegal("fcvt.s.wu rm 111 frm 110", 32'hd01e7253, RmW'(6));
    chk_illegal("fcvt.s.wu rm 111 frm 111", 32'hd01e7253, RmW'(7));
    chk_illegal("funct5 00110", 32'h308089d3, RmW'(0));
    chk_illegal("funct5 01000", 32'h408089d3, RmW'(0));
    chk_illegal("funct5 11111", 32'hf88089d3, RmW'(0));
    chk_illegal("funct5 00111", 32'h388089d3, RmW'(0));
    chk_illegal("funct5 10000", 32'h808089d3, RmW'(0));
    chk_illegal("fsgnj.s funct3 011", 32'h2189b4d3, RmW'(0));
    chk_illegal("fsgnj.s funct3 111", 32'h2189f4d3, RmW'(0));
    chk_illegal("fmin.s funct3 010", 32'h2973a4d3, RmW'(0));
    chk_illegal("fmin.s funct3 111", 32'h2973f4d3, RmW'(0));
    chk_illegal("feq.s funct3 011", 32'ha061b5d3, RmW'(0));
    chk_illegal("feq.s funct3 111", 32'ha061f5d3, RmW'(0));
    chk_illegal("fmv.x.w funct3 010", 32'he00c2cd3, RmW'(0));
    chk_illegal("fmv.x.w funct3 111", 32'he00c7cd3, RmW'(0));
    chk_illegal("fmv.w.x funct3 001", 32'hf00d9b53, RmW'(0));
    chk_illegal("fmv.w.x funct3 111", 32'hf00dfb53, RmW'(0));
  endtask  // Automatic

  task automatic not_fp_table();
    chk_not_fp("vle32.v v1, (x2)", 32'h02016087);
    chk_not_fp("vle8.v v3, (x4)", 32'h02020187);
    chk_not_fp("vle16.v v5, (x6), v0.t", 32'h00035287);
    chk_not_fp("vse32.v v7, (x8)", 32'h020463a7);
    chk_not_fp("vse8.v v9, (x10)", 32'h020504a7);
    chk_not_fp("vlse32.v v1, (x2), x3", 32'h0a316087);
    chk_not_fp("vfadd.vv v1, v2, v3", 32'h022190d7);
    chk_not_fp("add x1, x2, x3", 32'h003100b3);
    chk_not_fp("csrrw x1, mstatus, x2", 32'h300110f3);
    chk_not_fp("csrrs x5, fcsr, x0", 32'h003022f3);
    chk_not_fp("csrrwi x0, frm, 3", 32'h0021d073);
    chk_not_fp("lw x1, 8(x2)", 32'h00812083);
  endtask  // Automatic

  task automatic sweep_op_fp();
    logic [AWIDTH-1:0] rs2s[4];
    logic exp_ill;
    logic [RmW-1:0] exp_rm;
    fp_unit_e exp_unit;
    logic [31:0] word;
    string n;
    rs2s[0] = Rs2Zero;
    rs2s[1] = Rs2CvtWu;
    rs2s[2] = AWIDTH'(2);
    rs2s[3] = '1;
    for (int f7 = 0; f7 < 2 ** F7W; f7++) begin
      for (int f3 = 0; f3 < 2 ** F3W; f3++) begin
        for (int r = 0; r < $size(rs2s); r++) begin
          for (int m = 0; m < 2 ** RmW; m++) begin
            word = {
              F7W'(f7),
              rs2s[r],
              AWIDTH'(f7 + m),
              F3W'(f3),
              AWIDTH'(f7 ^ (2 ** AWIDTH - 1)),
              OpcodeOpFp
            };
            ref_op_fp(F7W'(f7), rs2s[r], F3W'(f3), RmW'(m), exp_ill, exp_rm, exp_unit);
            drive(word, RmW'(m));
            n = label("sweep", word);
            check({n, " is_fp"}, F5W'(is_fp), F5W'(1'b1));
            check({n, " illegal"}, F5W'(illegal), F5W'(exp_ill));
            check({n, " unit"}, F5W'(unit), F5W'(exp_unit));
            if (!exp_ill) check({n, " rm"}, F5W'(rm), F5W'(exp_rm));
          end
        end
      end
    end
  endtask  // Automatic

  task automatic sweep_fused();
    logic [$bits(OpcodeFmadd)-1:0] ops[4];
    logic [31:0] word;
    logic exp_ill;
    string n;
    ops[0] = OpcodeFmadd;
    ops[1] = OpcodeFmsub;
    ops[2] = OpcodeFnmsub;
    ops[3] = OpcodeFnmadd;
    for (int o = 0; o < $size(ops); o++) begin
      for (int fmt = 0; fmt < 2 ** FmtW; fmt++) begin
        for (int f3 = 0; f3 < 2 ** F3W; f3++) begin
          for (int m = 0; m < 2 ** RmW; m++) begin
            word = {
              AWIDTH'(m * 3),
              FmtW'(fmt),
              AWIDTH'(f3 + 7),
              AWIDTH'(o * 9),
              F3W'(f3),
              AWIDTH'(m),
              ops[o]
            };
            exp_ill = (FmtW'(fmt) != FmtS) || rm_reserved(RmW'(f3)) ||
                (RmW'(f3) == RmDyn && RmW'(m) > RmRmm);
            drive(word, RmW'(m));
            n = label("fused", word);
            check({n, " is_fp"}, F5W'(is_fp), F5W'(1'b1));
            check({n, " illegal"}, F5W'(illegal), F5W'(exp_ill));
            check({n, " unit"}, F5W'(unit), exp_ill ? F5W'(FP_NONE) : F5W'(FP_FMA));
            if (!exp_ill) begin
              check({n, " rm"}, F5W'(rm), (RmW'(f3) == RmDyn) ? F5W'(m) : F5W'(f3));
              check({n, " neg_prod"}, F5W'(neg_prod), F5W'(o >= 2));
              check({n, " neg_add"}, F5W'(neg_add), F5W'(o == 1 || o == 3));
            end
          end
        end
      end
    end
  endtask  // Automatic

  task automatic sweep_mem();
    logic [31:0] word;
    string n;
    for (int s = 0; s < 2; s++) begin
      for (int f3 = 0; f3 < 2 ** F3W; f3++) begin
        for (int k = 0; k < 4; k++) begin
          word = 32'($urandom) & 32'hffff_8f80;
          word = word | {17'b0, F3W'(f3), AWIDTH'(0), (s == 1) ? OpcodeStoreFp : OpcodeLoadFp};
          drive(word, RmW'(k));
          n = label("mem", word);
          check({n, " is_fp"}, F5W'(is_fp), F5W'(F3W'(f3) == Funct3FpWord));
          check({n, " illegal"}, F5W'(illegal), F5W'(1'b0));
          if (F3W'(f3) != Funct3FpWord) check({n, " unit"}, F5W'(unit), F5W'(FP_NONE));
          else check({n, " unit"}, F5W'(unit), (s == 1) ? F5W'(FP_STORE) : F5W'(FP_LOAD));
        end
      end
    end
  endtask  // Automatic

  task automatic do_verdict();
    if (checks < MinChecks)
      $fatal(1, "TB UNDER-RAN: %0d checks, expected at least %0d", checks, MinChecks);
    if (errors == 0) $display("PASS: %0d checks, %0d mismatches", checks, errors);
    else $fatal(1, "FAIL: %0d mismatches, %0d checks", errors, checks);
    $finish;
  endtask  // Automatic

  initial void'($value$plusargs("max_errors=%d", max_errors));

  task automatic do_reset();
    instr = '0;
    frm   = '0;
    #1;
  endtask  // Automatic

  initial begin
    $dumpfile("fp_decode_tb.vcd");
    $dumpvars(0, fp_decode_tb);
    do_reset();
    legal_table();
    illegal_table();
    not_fp_table();
    sweep_op_fp();
    sweep_fused();
    sweep_mem();
    do_verdict();
  end

  task automatic ref_op_fp(input logic [F7W-1:0] funct7, input logic [AWIDTH-1:0] rs2,
                           input logic [F3W-1:0] f3, input logic [RmW-1:0] frm_in,
                           output logic exp_ill, output logic [RmW-1:0] exp_rm,
                           output fp_unit_e exp_unit);
    logic defined, uses_rm, f3_ok, rs2_ok, rm_bad;
    defined  = 1'b1;
    uses_rm  = 1'b0;
    f3_ok    = 1'b1;
    rs2_ok   = 1'b1;
    exp_unit = FP_NONE;
    case (funct7[F7W-1:FmtW])
      Funct5Fadd, Funct5Fsub: begin
        exp_unit = FP_ADD;
        uses_rm  = 1'b1;
      end
      Funct5Fmul: begin
        exp_unit = FP_MUL;
        uses_rm  = 1'b1;
      end
      Funct5Fdiv: begin
        exp_unit = FP_DIV_SQRT;
        uses_rm  = 1'b1;
      end
      Funct5Fsqrt: begin
        exp_unit = FP_DIV_SQRT;
        uses_rm  = 1'b1;
        rs2_ok   = (rs2 == Rs2Zero);
      end
      Funct5Fsgnj, Funct5Fcmp: begin
        exp_unit = FP_MISC;
        f3_ok    = (f3 <= Funct3Fsgnjx);
      end
      Funct5Fminmax: begin
        exp_unit = FP_MISC;
        f3_ok    = (f3 <= Funct3Fmax);
      end
      Funct5FcvtWS, Funct5FcvtSW: begin
        exp_unit = FP_CVT;
        uses_rm  = 1'b1;
        rs2_ok   = (rs2 <= Rs2CvtWu);
      end
      Funct5FmvXW: begin
        exp_unit = FP_MISC;
        if (f3 == Funct3Fmv) exp_unit = FP_MV_X_W;
        f3_ok  = (f3 <= Funct3Fclass);
        rs2_ok = (rs2 == Rs2Zero);
      end
      Funct5FmvWX: begin
        exp_unit = FP_MV_W_X;
        f3_ok    = (f3 == Funct3Fmv);
        rs2_ok   = (rs2 == Rs2Zero);
      end
      default: defined = 1'b0;
    endcase
    rm_bad  = uses_rm && (rm_reserved(f3) || (f3 == RmDyn && frm_in > RmRmm));
    exp_ill = !defined || (funct7[FmtW-1:0] != FmtS) || !rs2_ok || rm_bad || (!uses_rm && !f3_ok);
    exp_rm  = '0;
    if (uses_rm) exp_rm = (f3 == RmDyn) ? frm_in : f3;
    if (exp_ill) exp_unit = FP_NONE;
  endtask  // Automatic

  function automatic logic rm_reserved(input logic [RmW-1:0] r);
    rm_reserved = (r > RmRmm) && (r != RmDyn);
  endfunction

endmodule

`default_nettype wire
