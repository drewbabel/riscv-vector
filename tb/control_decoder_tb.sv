`default_nettype none

module control_decoder_tb
  import opcode_pkg::*;
  import csr_pkg::Funct3Priv, csr_pkg::Funct3Csrrw, csr_pkg::Funct3Csrrs, csr_pkg::Funct3Csrrc;
  import csr_pkg::Funct3Csrrwi, csr_pkg::Funct3Csrrsi, csr_pkg::Funct3Csrrci;
  import csr_pkg::Funct3SysRsvd;
  import csr_pkg::Funct12Ecall, csr_pkg::Funct12Ebreak, csr_pkg::Funct12Mret;
  import csr_pkg::MstatusAddr, csr_pkg::MepcAddr, csr_pkg::FflagsAddr, csr_pkg::VlAddr;
  import muldiv_pkg::*;
  import fp_pkg::Funct5FcvtWS, fp_pkg::Funct5FmvXW, fp_pkg::Funct5Fcmp, fp_pkg::FmtS;
  import fp_pkg::RmRne, fp_pkg::RmRtz, fp_pkg::RmRdn, fp_pkg::RmDyn;
();

  localparam int OpW = OpcodeW;
  localparam int Funct12W = $bits(Funct12Ecall);
  localparam int Funct7W = $bits(Funct7MulDiv);
  localparam int Funct5W = $bits(Funct5Fcmp);
  localparam int Rs2W = arch_pkg::RegAddrW;
  localparam int ImmSrcW = 3;
  localparam int SelW = 2;
  localparam int FieldW = ImmSrcW;
  localparam int SoakOps = 20000;
  localparam int MinChecks = 180000;

  localparam logic [ImmSrcW-1:0] ImmI = ImmSrcW'(0);
  localparam logic [ImmSrcW-1:0] ImmS = ImmSrcW'(1);
  localparam logic [ImmSrcW-1:0] ImmB = ImmSrcW'(2);
  localparam logic [ImmSrcW-1:0] ImmU = ImmSrcW'(3);
  localparam logic [ImmSrcW-1:0] ImmJ = ImmSrcW'(4);

  localparam logic [SelW-1:0] SrcARs1 = SelW'(0);
  localparam logic [SelW-1:0] SrcAPc = SelW'(1);
  localparam logic [SelW-1:0] SrcAZero = SelW'(2);

  localparam logic [SelW-1:0] ResAlu = SelW'(0);
  localparam logic [SelW-1:0] ResMem = SelW'(1);
  localparam logic [SelW-1:0] ResPc4 = SelW'(2);

  localparam logic [SelW-1:0] AluAdd = SelW'(0);
  localparam logic [SelW-1:0] AluBranch = SelW'(1);
  localparam logic [SelW-1:0] AluFunct = SelW'(2);

  int checks = 0;
  int errors = 0;
  int max_errors = 0;

  logic [OpW-1:0] op;
  logic [Funct3W-1:0] funct3;
  logic [Funct12W-1:0] funct12;
  logic reg_write;
  logic [ImmSrcW-1:0] imm_src;
  logic [SelW-1:0] alu_a_src;
  logic pc_target_src;
  logic alu_src;
  logic mem_write;
  logic [SelW-1:0] result_src;
  logic branch;
  logic jump;
  logic [SelW-1:0] alu_op;
  logic csr_access;
  logic is_ecall;
  logic is_ebreak;
  logic is_mret;
  logic illegal;
  logic is_muldiv;
  muldiv_op_e muldiv_op;

  logic [Funct3W-1:0] csr_funct3s[6] = '{
      Funct3Csrrw,
      Funct3Csrrs,
      Funct3Csrrc,
      Funct3Csrrwi,
      Funct3Csrrsi,
      Funct3Csrrci
  };
  logic [Funct12W-1:0] csr_funct12s[7] = '{
      Funct12Ecall,
      Funct12Ebreak,
      Funct12Mret,
      MstatusAddr,
      MepcAddr,
      FflagsAddr,
      VlAddr
  };
  muldiv_op_e muldiv_ops[2**Funct3W] = '{
      MD_MUL,
      MD_MULH,
      MD_MULHSU,
      MD_MULHU,
      MD_DIV,
      MD_DIVU,
      MD_REM,
      MD_REMU
  };

  control_decoder dut (
      .op           (op),
      .funct3       (funct3),
      .funct12      (funct12),
      .reg_write    (reg_write),
      .imm_src      (imm_src),
      .alu_a_src    (alu_a_src),
      .pc_target_src(pc_target_src),
      .alu_src      (alu_src),
      .mem_write    (mem_write),
      .result_src   (result_src),
      .branch       (branch),
      .jump         (jump),
      .alu_op       (alu_op),
      .csr_access   (csr_access),
      .is_ecall     (is_ecall),
      .is_ebreak    (is_ebreak),
      .is_mret      (is_mret),
      .illegal      (illegal),
      .is_muldiv    (is_muldiv),
      .muldiv_op    (muldiv_op)
  );

  initial void'($value$plusargs("max_errors=%d", max_errors));

  task automatic check(input string name, input logic got, input logic exp);
    checks++;
    if (got !== exp) begin
      errors++;
      $display("FAIL %s: got %h, expected %h", name, got, exp);
      if (errors == max_errors) $fatal(1, "TB STOPPED: %0d mismatches", errors);
    end
  endtask  // Automatic

  task automatic check_field(input string name, input logic [FieldW-1:0] got,
                             input logic [FieldW-1:0] exp);
    checks++;
    if (got !== exp) begin
      errors++;
      $display("FAIL %s: got %h, expected %h", name, got, exp);
      if (errors == max_errors) $fatal(1, "TB STOPPED: %0d mismatches", errors);
    end
  endtask  // Automatic

  task automatic do_reset();
    op = '0;
    funct3 = '0;
    funct12 = '0;
    #1;
  endtask  // Automatic

  task automatic decode(input logic [OpW-1:0] o, input logic [Funct3W-1:0] f3,
                        input logic [Funct12W-1:0] f12);
    op = o;
    funct3 = f3;
    funct12 = f12;
    #1;
  endtask  // Automatic

  task automatic check_system(input string name);
    logic exp_muldiv;
    exp_muldiv = muldiv_ref(op, funct12);
    check({name, " csr_access"}, csr_access, csr_ref(op, funct3));
    check({name, " is_ecall"}, is_ecall, priv_ref(op, funct3, funct12, Funct12Ecall));
    check({name, " is_ebreak"}, is_ebreak, priv_ref(op, funct3, funct12, Funct12Ebreak));
    check({name, " is_mret"}, is_mret, priv_ref(op, funct3, funct12, Funct12Mret));
    check({name, " illegal"}, illegal, op == OpcodeSystem && funct3 == Funct3SysRsvd);
    check({name, " is_muldiv"}, is_muldiv, exp_muldiv);
    if (exp_muldiv) check_field({name, " muldiv_op"}, muldiv_op, muldiv_ops[funct3]);
  endtask  // Automatic

  task automatic chk_default(input string name);
    check({name, " reg_write"}, reg_write, 1'b0);
    check_field({name, " imm_src"}, imm_src, ImmI);
    check_field({name, " alu_a_src"}, FieldW'(alu_a_src), FieldW'(SrcARs1));
    check({name, " pc_target_src"}, pc_target_src, 1'b0);
    check({name, " alu_src"}, alu_src, 1'b0);
    check({name, " mem_write"}, mem_write, 1'b0);
    check_field({name, " result_src"}, FieldW'(result_src), FieldW'(ResAlu));
    check({name, " branch"}, branch, 1'b0);
    check({name, " jump"}, jump, 1'b0);
    check_field({name, " alu_op"}, FieldW'(alu_op), FieldW'(AluAdd));
    check_system(name);
  endtask  // Automatic

  task automatic chk_op();
    decode(OpcodeOp, '0, '0);
    check("op reg_write", reg_write, 1'b1);
    check("op alu_src", alu_src, 1'b0);
    check("op mem_write", mem_write, 1'b0);
    check_field("op result_src", FieldW'(result_src), FieldW'(ResAlu));
    check("op branch", branch, 1'b0);
    check("op jump", jump, 1'b0);
    check_field("op alu_op", FieldW'(alu_op), FieldW'(AluFunct));
    check_field("op alu_a_src", FieldW'(alu_a_src), FieldW'(SrcARs1));
    check("op pc_target_src", pc_target_src, 1'b0);
    check_system("op");
  endtask  // Automatic

  task automatic chk_opimm();
    decode(OpcodeOpImm, '0, '0);
    check("opimm reg_write", reg_write, 1'b1);
    check_field("opimm imm_src", imm_src, ImmI);
    check("opimm alu_src", alu_src, 1'b1);
    check("opimm mem_write", mem_write, 1'b0);
    check_field("opimm result_src", FieldW'(result_src), FieldW'(ResAlu));
    check("opimm branch", branch, 1'b0);
    check("opimm jump", jump, 1'b0);
    check_field("opimm alu_op", FieldW'(alu_op), FieldW'(AluFunct));
    check_field("opimm alu_a_src", FieldW'(alu_a_src), FieldW'(SrcARs1));
    check("opimm pc_target_src", pc_target_src, 1'b0);
    check_system("opimm");
  endtask  // Automatic

  task automatic chk_load();
    decode(OpcodeLoad, '0, '0);
    check("load reg_write", reg_write, 1'b1);
    check_field("load imm_src", imm_src, ImmI);
    check("load alu_src", alu_src, 1'b1);
    check("load mem_write", mem_write, 1'b0);
    check_field("load result_src", FieldW'(result_src), FieldW'(ResMem));
    check("load branch", branch, 1'b0);
    check("load jump", jump, 1'b0);
    check_field("load alu_op", FieldW'(alu_op), FieldW'(AluAdd));
    check_field("load alu_a_src", FieldW'(alu_a_src), FieldW'(SrcARs1));
    check("load pc_target_src", pc_target_src, 1'b0);
    check_system("load");
  endtask  // Automatic

  task automatic chk_store();
    decode(OpcodeStore, '0, '0);
    check("store reg_write", reg_write, 1'b0);
    check_field("store imm_src", imm_src, ImmS);
    check("store alu_src", alu_src, 1'b1);
    check("store mem_write", mem_write, 1'b1);
    check("store branch", branch, 1'b0);
    check("store jump", jump, 1'b0);
    check_field("store alu_op", FieldW'(alu_op), FieldW'(AluAdd));
    check_field("store alu_a_src", FieldW'(alu_a_src), FieldW'(SrcARs1));
    check("store pc_target_src", pc_target_src, 1'b0);
    check_system("store");
  endtask  // Automatic

  task automatic chk_branch();
    decode(OpcodeBranch, '0, '0);
    check("branch reg_write", reg_write, 1'b0);
    check_field("branch imm_src", imm_src, ImmB);
    check("branch alu_src", alu_src, 1'b0);
    check("branch mem_write", mem_write, 1'b0);
    check("branch branch", branch, 1'b1);
    check("branch jump", jump, 1'b0);
    check_field("branch alu_op", FieldW'(alu_op), FieldW'(AluBranch));
    check_field("branch alu_a_src", FieldW'(alu_a_src), FieldW'(SrcARs1));
    check("branch pc_target_src", pc_target_src, 1'b0);
    check_system("branch");
  endtask  // Automatic

  task automatic chk_jal();
    decode(OpcodeJal, '0, '0);
    check("jal reg_write", reg_write, 1'b1);
    check_field("jal imm_src", imm_src, ImmJ);
    check("jal mem_write", mem_write, 1'b0);
    check_field("jal result_src", FieldW'(result_src), FieldW'(ResPc4));
    check("jal branch", branch, 1'b0);
    check("jal jump", jump, 1'b1);
    check_field("jal alu_a_src", FieldW'(alu_a_src), FieldW'(SrcARs1));
    check("jal pc_target_src", pc_target_src, 1'b0);
    check_system("jal");
  endtask  // Automatic

  task automatic chk_jalr();
    decode(OpcodeJalr, '0, '0);
    check("jalr reg_write", reg_write, 1'b1);
    check_field("jalr imm_src", imm_src, ImmI);
    check("jalr alu_src", alu_src, 1'b1);
    check("jalr mem_write", mem_write, 1'b0);
    check_field("jalr result_src", FieldW'(result_src), FieldW'(ResPc4));
    check("jalr branch", branch, 1'b0);
    check("jalr jump", jump, 1'b1);
    check_field("jalr alu_op", FieldW'(alu_op), FieldW'(AluAdd));
    check_field("jalr alu_a_src", FieldW'(alu_a_src), FieldW'(SrcARs1));
    check("jalr pc_target_src", pc_target_src, 1'b1);
    check_system("jalr");
  endtask  // Automatic

  task automatic chk_lui();
    decode(OpcodeLui, '0, '0);
    check("lui reg_write", reg_write, 1'b1);
    check_field("lui imm_src", imm_src, ImmU);
    check("lui alu_src", alu_src, 1'b1);
    check("lui mem_write", mem_write, 1'b0);
    check_field("lui result_src", FieldW'(result_src), FieldW'(ResAlu));
    check("lui branch", branch, 1'b0);
    check("lui jump", jump, 1'b0);
    check_field("lui alu_op", FieldW'(alu_op), FieldW'(AluAdd));
    check_field("lui alu_a_src", FieldW'(alu_a_src), FieldW'(SrcAZero));
    check("lui pc_target_src", pc_target_src, 1'b0);
    check_system("lui");
  endtask  // Automatic

  task automatic chk_auipc();
    decode(OpcodeAuipc, '0, '0);
    check("auipc reg_write", reg_write, 1'b1);
    check_field("auipc imm_src", imm_src, ImmU);
    check("auipc alu_src", alu_src, 1'b1);
    check("auipc mem_write", mem_write, 1'b0);
    check_field("auipc result_src", FieldW'(result_src), FieldW'(ResAlu));
    check("auipc branch", branch, 1'b0);
    check("auipc jump", jump, 1'b0);
    check_field("auipc alu_op", FieldW'(alu_op), FieldW'(AluAdd));
    check_field("auipc alu_a_src", FieldW'(alu_a_src), FieldW'(SrcAPc));
    check("auipc pc_target_src", pc_target_src, 1'b0);
    check_system("auipc");
  endtask  // Automatic

  task automatic chk_illegal();
    decode('1, '0, '0);
    check("illegal reg_write", reg_write, 1'b0);
    check("illegal mem_write", mem_write, 1'b0);
    check_system("illegal");
  endtask  // Automatic

  task automatic chk_op_fp();
    logic [Funct3W-1:0] f3s[4] = '{RmRne, RmRtz, RmRdn, RmDyn};
    logic [Funct5W-1:0] f5;
    for (int f = 0; f < 2 ** Funct5W; f++) begin
      f5 = Funct5W'(f);
      for (int i = 0; i < $size(f3s); i++) begin
        decode(OpcodeOpFp, f3s[i], {f5, FmtS, Rs2W'(i)});
        check($sformatf("opfp %b reg_write", f5), reg_write,
              f5 == Funct5FcvtWS || f5 == Funct5FmvXW || f5 == Funct5Fcmp);
        check("opfp mem_write", mem_write, 1'b0);
        check("opfp branch", branch, 1'b0);
        check("opfp jump", jump, 1'b0);
        check_system($sformatf("opfp %b", f5));
      end
    end
  endtask  // Automatic

  task automatic chk_flw();
    decode(OpcodeLoadFp, Funct3FpWord, Funct12W'('hffc));
    check("flw reg_write", reg_write, 1'b0);
    check_field("flw imm_src", imm_src, ImmI);
    check("flw alu_src", alu_src, 1'b1);
    check("flw mem_write", mem_write, 1'b0);
    check_field("flw result_src", FieldW'(result_src), FieldW'(ResMem));
    check("flw branch", branch, 1'b0);
    check("flw jump", jump, 1'b0);
    check_field("flw alu_op", FieldW'(alu_op), FieldW'(AluAdd));
    check_field("flw alu_a_src", FieldW'(alu_a_src), FieldW'(SrcARs1));
    check("flw pc_target_src", pc_target_src, 1'b0);
    check_system("flw");
  endtask  // Automatic

  task automatic chk_fsw();
    decode(OpcodeStoreFp, Funct3FpWord, Funct12W'('h7e5));
    check("fsw reg_write", reg_write, 1'b0);
    check_field("fsw imm_src", imm_src, ImmS);
    check("fsw alu_src", alu_src, 1'b1);
    check("fsw mem_write", mem_write, 1'b1);
    check("fsw branch", branch, 1'b0);
    check("fsw jump", jump, 1'b0);
    check_field("fsw alu_op", FieldW'(alu_op), FieldW'(AluAdd));
    check_field("fsw alu_a_src", FieldW'(alu_a_src), FieldW'(SrcARs1));
    check("fsw pc_target_src", pc_target_src, 1'b0);
    check_system("fsw");
  endtask  // Automatic

  task automatic chk_fused();
    logic [OpW-1:0] ops[4] = '{OpcodeFmadd, OpcodeFmsub, OpcodeFnmsub, OpcodeFnmadd};
    for (int o = 0; o < $size(ops); o++) begin
      for (int f3 = 0; f3 < 2 ** Funct3W; f3++) begin
        decode(ops[o], Funct3W'(f3), Funct12W'(o * 1000 + f3));
        chk_default($sformatf("fused %b rm %b", ops[o], Funct3W'(f3)));
      end
    end
  endtask  // Automatic

  task automatic chk_vec_mem();
    logic [Funct3W-1:0] f3s[4] = '{
        Funct3W'('b000),
        Funct3W'('b101),
        Funct3W'('b110),
        Funct3W'('b111)
    };
    for (int i = 0; i < $size(f3s); i++) begin
      decode(OpcodeLoadFp, f3s[i], Funct12W'('h020));
      chk_default($sformatf("vload %b", f3s[i]));
      decode(OpcodeStoreFp, f3s[i], Funct12W'('h020));
      chk_default($sformatf("vstore %b", f3s[i]));
    end
  endtask  // Automatic

  task automatic chk_priv();
    for (int f = 0; f < 2 ** Funct12W; f++) begin
      decode(OpcodeSystem, Funct3Priv, Funct12W'(f));
      chk_default($sformatf("priv %h", Funct12W'(f)));
    end
  endtask  // Automatic

  task automatic chk_csr();
    string name;
    for (int i = 0; i < $size(csr_funct3s); i++) begin
      for (int j = 0; j < $size(csr_funct12s); j++) begin
        decode(OpcodeSystem, csr_funct3s[i], csr_funct12s[j]);
        name = $sformatf("csr %b %h", funct3, funct12);
        check({name, " reg_write"}, reg_write, 1'b1);
        check({name, " mem_write"}, mem_write, 1'b0);
        check({name, " branch"}, branch, 1'b0);
        check({name, " jump"}, jump, 1'b0);
        check_system(name);
      end
    end
  endtask  // Automatic

  task automatic chk_sys_rsvd();
    for (int j = 0; j < $size(csr_funct12s); j++) begin
      decode(OpcodeSystem, Funct3SysRsvd, csr_funct12s[j]);
      chk_default($sformatf("sys rsvd %h", funct12));
    end
  endtask  // Automatic

  task automatic chk_muldiv(input logic [OpW-1:0] o);
    string name;
    for (int f7 = 0; f7 < 2 ** Funct7W; f7++) begin
      for (int f3 = 0; f3 < 2 ** Funct3W; f3++) begin
        decode(o, Funct3W'(f3), {Funct7W'(f7), Rs2W'($urandom)});
        name = $sformatf("muldiv %b %b %b", o, Funct7W'(f7), Funct3W'(f3));
        check({name, " reg_write"}, reg_write, 1'b1);
        check({name, " mem_write"}, mem_write, 1'b0);
        check_field({name, " alu_op"}, FieldW'(alu_op), FieldW'(AluFunct));
        check_system(name);
      end
    end
  endtask  // Automatic

  task automatic soak(input int n);
    logic [OpW-1:0] o;
    logic [Funct3W-1:0] f3;
    repeat (n) begin
      o  = OpW'($urandom);
      f3 = Funct3W'($urandom);
      decode(o, f3, Funct12W'($urandom));
      check_system($sformatf("soak %b %b %h", op, funct3, funct12));
    end
  endtask  // Automatic

  task automatic do_verdict();
    if (checks < MinChecks)
      $fatal(1, "TB UNDER-RAN: %0d checks, expected at least %0d", checks, MinChecks);
    if (errors == 0) $display("PASS: %0d checks, %0d mismatches", checks, errors);
    else $fatal(1, "FAIL: %0d mismatches, %0d checks", errors, checks);
    $finish;
  endtask  // Automatic

  initial begin
    $dumpfile("control_decoder_tb.vcd");
    $dumpvars(0, control_decoder_tb);
    do_reset();

    // Base opcodes
    chk_op();
    chk_opimm();
    chk_load();
    chk_store();
    chk_branch();
    chk_jal();
    chk_jalr();
    chk_lui();
    chk_auipc();
    chk_illegal();

    // Float and vector
    chk_op_fp();
    chk_flw();
    chk_fsw();
    chk_fused();
    chk_vec_mem();

    // System and M
    chk_priv();
    chk_csr();
    chk_sys_rsvd();
    chk_muldiv(OpcodeOp);
    chk_muldiv(OpcodeOpImm);
    soak(SoakOps);

    do_verdict();
  end

  function automatic logic csr_ref(input logic [OpW-1:0] o, input logic [Funct3W-1:0] f3);
    csr_ref = 1'b0;
    for (int i = 0; i < $size(csr_funct3s); i++) begin
      if (o == OpcodeSystem && f3 == csr_funct3s[i]) csr_ref = 1'b1;
    end
  endfunction

  function automatic logic priv_ref(input logic [OpW-1:0] o, input logic [Funct3W-1:0] f3,
                                    input logic [Funct12W-1:0] f12,
                                    input logic [Funct12W-1:0] code);
    priv_ref = o == OpcodeSystem && f3 == Funct3Priv && f12 == code;
  endfunction

  function automatic logic muldiv_ref(input logic [OpW-1:0] o, input logic [Funct12W-1:0] f12);
    muldiv_ref = o == OpcodeOp && f12[Funct12W-1-:Funct7W] == Funct7MulDiv;
  endfunction

endmodule

`default_nettype wire
