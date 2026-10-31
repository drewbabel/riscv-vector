`default_nettype none

module sc_control_decoder_tb
  import csr_pkg::*;
  import opcode_pkg::*;
();

  localparam int MinChecks = 100000;
  localparam int FieldW = 3;
  localparam int Funct12s = 8;

  int checks = 0;
  int errors = 0;
  int max_errors = 0;

  logic [OpcodeW-1:0] op;
  logic [Funct3W-1:0] funct3;
  logic [CsrAddrW-1:0] funct12;
  logic reg_write;
  logic [ImmSrcW-1:0] imm_src;
  logic [SrcAW-1:0] alu_a_src;
  logic pc_target_src;
  logic alu_src;
  logic mem_write;
  logic [ResSrcW-1:0] result_src;
  logic branch;
  logic jump;
  logic [AluOpW-1:0] alu_op;
  logic csr_access;
  logic is_ecall;
  logic is_ebreak;
  logic is_mret;

  logic [CsrAddrW-1:0] funct12s[Funct12s] = '{
      Funct12Ecall,
      Funct12Ebreak,
      Funct12Mret,
      MstatusAddr,
      MepcAddr,
      CsrAddrW'('h003),
      CsrAddrW'('h303),
      CsrAddrW'('hfff)
  };

  sc_control_decoder dut (
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
      .is_mret      (is_mret)
  );

  initial void'($value$plusargs("max_errors=%d", max_errors));

  task automatic check(input string name, input logic [FieldW-1:0] got,
                       input logic [FieldW-1:0] exp);
    checks++;
    if (got !== exp) begin
      errors++;
      $display("FAIL %s: got %h, expected %h", name, got, exp);
      if (errors == max_errors) $fatal(1, "TB STOPPED: %0d mismatches", errors);
    end
  endtask  // Automatic

  task automatic check_flags(input string tag, input logic rw, input logic mw, input logic br,
                             input logic jp);
    logic sys;
    logic priv;
    sys  = op == OpcodeSystem;
    priv = sys && funct3 == Funct3Priv;
    check({tag, " reg_write"}, FieldW'(reg_write), FieldW'(rw || (sys && !priv)));
    check({tag, " mem_write"}, FieldW'(mem_write), FieldW'(mw));
    check({tag, " branch"}, FieldW'(branch), FieldW'(br));
    check({tag, " jump"}, FieldW'(jump), FieldW'(jp));
    check({tag, " csr_access"}, FieldW'(csr_access), FieldW'(sys && !priv));
    check({tag, " is_ecall"}, FieldW'(is_ecall), FieldW'(priv && funct12 == Funct12Ecall));
    check({tag, " is_ebreak"}, FieldW'(is_ebreak), FieldW'(priv && funct12 == Funct12Ebreak));
    check({tag, " is_mret"}, FieldW'(is_mret), FieldW'(priv && funct12 == Funct12Mret));
  endtask  // Automatic

  task automatic check_path(input string tag, input logic [ImmSrcW-1:0] imm,
                            input logic [SrcAW-1:0] srca, input logic b_imm,
                            input logic [ResSrcW-1:0] res, input logic [AluOpW-1:0] aop,
                            input logic tgt);
    check({tag, " imm_src"}, FieldW'(imm_src), FieldW'(imm));
    check({tag, " alu_a_src"}, FieldW'(alu_a_src), FieldW'(srca));
    check({tag, " alu_src"}, FieldW'(alu_src), FieldW'(b_imm));
    check({tag, " result_src"}, FieldW'(result_src), FieldW'(res));
    check({tag, " alu_op"}, FieldW'(alu_op), FieldW'(aop));
    check({tag, " pc_target_src"}, FieldW'(pc_target_src), FieldW'(tgt));
  endtask  // Automatic

  task automatic check_now();
    string tag;
    #1;
    tag = $sformatf("op %b f3 %b f12 %h", op, funct3, funct12);
    case (op)
      OpcodeOp: begin
        check_flags(tag, 1'b1, 1'b0, 1'b0, 1'b0);
        check({tag, " alu_src"}, FieldW'(alu_src), FieldW'(1'b0));
        check({tag, " alu_op"}, FieldW'(alu_op), FieldW'(AluOpFunct));
        check({tag, " alu_a_src"}, FieldW'(alu_a_src), FieldW'(SrcARs1));
        check({tag, " result_src"}, FieldW'(result_src), FieldW'(ResAlu));
        check({tag, " pc_target_src"}, FieldW'(pc_target_src), FieldW'(1'b0));
      end
      OpcodeOpImm: begin
        check_flags(tag, 1'b1, 1'b0, 1'b0, 1'b0);
        check_path(tag, ImmI, SrcARs1, 1'b1, ResAlu, AluOpFunct, 1'b0);
      end
      OpcodeLoad: begin
        check_flags(tag, 1'b1, 1'b0, 1'b0, 1'b0);
        check_path(tag, ImmI, SrcARs1, 1'b1, ResMem, AluOpAdd, 1'b0);
      end
      OpcodeStore: begin
        check_flags(tag, 1'b0, 1'b1, 1'b0, 1'b0);
        check({tag, " imm_src"}, FieldW'(imm_src), FieldW'(ImmS));
        check({tag, " alu_src"}, FieldW'(alu_src), FieldW'(1'b1));
        check({tag, " alu_op"}, FieldW'(alu_op), FieldW'(AluOpAdd));
        check({tag, " alu_a_src"}, FieldW'(alu_a_src), FieldW'(SrcARs1));
        check({tag, " pc_target_src"}, FieldW'(pc_target_src), FieldW'(1'b0));
      end
      OpcodeBranch: begin
        check_flags(tag, 1'b0, 1'b0, 1'b1, 1'b0);
        check({tag, " imm_src"}, FieldW'(imm_src), FieldW'(ImmB));
        check({tag, " alu_src"}, FieldW'(alu_src), FieldW'(1'b0));
        check({tag, " alu_op"}, FieldW'(alu_op), FieldW'(AluOpBranch));
        check({tag, " alu_a_src"}, FieldW'(alu_a_src), FieldW'(SrcARs1));
        check({tag, " pc_target_src"}, FieldW'(pc_target_src), FieldW'(1'b0));
      end
      OpcodeJal: begin
        check_flags(tag, 1'b1, 1'b0, 1'b0, 1'b1);
        check({tag, " imm_src"}, FieldW'(imm_src), FieldW'(ImmJ));
        check({tag, " result_src"}, FieldW'(result_src), FieldW'(ResPc4));
        check({tag, " pc_target_src"}, FieldW'(pc_target_src), FieldW'(1'b0));
      end
      OpcodeJalr: begin
        check_flags(tag, 1'b1, 1'b0, 1'b0, 1'b1);
        check_path(tag, ImmI, SrcARs1, 1'b1, ResPc4, AluOpAdd, 1'b1);
      end
      OpcodeLui: begin
        check_flags(tag, 1'b1, 1'b0, 1'b0, 1'b0);
        check_path(tag, ImmU, SrcAZero, 1'b1, ResAlu, AluOpAdd, 1'b0);
      end
      OpcodeAuipc: begin
        check_flags(tag, 1'b1, 1'b0, 1'b0, 1'b0);
        check_path(tag, ImmU, SrcAPc, 1'b1, ResAlu, AluOpAdd, 1'b0);
      end
      OpcodeSystem: begin
        check_flags(tag, 1'b0, 1'b0, 1'b0, 1'b0);
        check({tag, " result_src"}, FieldW'(result_src), FieldW'(ResAlu));
      end
      default: check_flags(tag, 1'b0, 1'b0, 1'b0, 1'b0);
    endcase
  endtask  // Automatic

  task automatic sweep_all();
    for (int o = 0; o < 2 ** OpcodeW; o++)
      for (int f3 = 0; f3 < 2 ** Funct3W; f3++)
        for (int f = 0; f < Funct12s; f++) begin
          op = OpcodeW'(o);
          funct3 = Funct3W'(f3);
          funct12 = funct12s[f];
          check_now();
        end
  endtask  // Automatic

  task automatic priv_sweep();
    for (int f = 0; f < 2 ** CsrAddrW; f++) begin
      op = OpcodeSystem;
      funct3 = Funct3Priv;
      funct12 = CsrAddrW'(f);
      check_now();
    end
  endtask  // Automatic

  task automatic do_verdict();
    if (checks < MinChecks)
      $fatal(1, "TB UNDER-RAN: %0d checks, expected at least %0d", checks, MinChecks);
    if (errors == 0) $display("PASS: %0d checks, %0d mismatches", checks, errors);
    else $fatal(1, "FAIL: %0d mismatches, %0d checks", errors, checks);
    $finish;
  endtask  // Automatic

  task automatic do_reset();
    op = '0;
    funct3 = '0;
    funct12 = '0;
    #1;
  endtask  // Automatic

  initial begin
    $dumpfile("sc_control_decoder_tb.vcd");
    $dumpvars(0, sc_control_decoder_tb);
    do_reset();

    sweep_all();
    priv_sweep();

    do_verdict();
  end

endmodule

`default_nettype wire
