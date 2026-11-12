`default_nettype none

module control_unit_tb
  import alu_pkg::*;
  import csr_pkg::*;
  import muldiv_pkg::*;
  import opcode_pkg::*;
();

  localparam int MinChecks = 380000;
  localparam int FieldW = 4;
  localparam int Funct12s = 16;
  localparam logic [6:0] Funct7M = 7'b0000001;
  localparam logic [2:0] Funct3Opcfg = 3'b111;
  localparam logic [2:0] Funct3Opmvv = 3'b010;
  localparam logic [5:0] Funct6Wxunary = 6'b010000;
  localparam logic [2:0] Funct3Word = 3'b010;
  localparam logic [4:0] Funct5Fcmp = 5'b10100;
  localparam logic [4:0] Funct5FcvtWS = 5'b11000;
  localparam logic [4:0] Funct5FmvXW = 5'b11100;

  int checks = 0;
  int errors = 0;
  int max_errors = 0;

  logic [OpcodeW-1:0] op;
  logic [Funct3W-1:0] funct3;
  logic [CsrAddrW-1:0] funct12;
  logic funct7b5;

  logic reg_write;
  logic [ImmSrcW-1:0] imm_src;
  logic [SrcAW-1:0] alu_a_src;
  logic pc_target_src;
  logic alu_src;
  logic mem_write;
  logic [ResSrcW-1:0] result_src;
  alu_op_e alu_ctrl;
  logic branch;
  logic jump;
  logic csr_access;
  logic is_ecall;
  logic is_ebreak;
  logic is_mret;
  logic illegal;
  logic is_muldiv;
  muldiv_op_e muldiv_op;

  logic [CsrAddrW-1:0] funct12s[Funct12s] = '{
      CsrAddrW'('h000),
      CsrAddrW'('h001),
      CsrAddrW'('h302),
      CsrAddrW'('h300),
      CsrAddrW'('h341),
      {Funct7M, 5'd3},
      {Funct7M, 5'd31},
      CsrAddrW'('h400),
      {Funct6Wxunary, 6'd5},
      {Funct6Wxunary, 6'd33},
      {Funct5Fcmp, 7'd1},
      {Funct5FcvtWS, 7'd0},
      {Funct5FmvXW, 7'd0},
      CsrAddrW'('hfff),
      CsrAddrW'('h020),
      CsrAddrW'('h7e5)
  };

  control_unit dut (
      .op           (op),
      .funct3       (funct3),
      .funct12      (funct12),
      .funct7b5     (funct7b5),
      .reg_write    (reg_write),
      .imm_src      (imm_src),
      .alu_a_src    (alu_a_src),
      .pc_target_src(pc_target_src),
      .alu_src      (alu_src),
      .mem_write    (mem_write),
      .result_src   (result_src),
      .alu_ctrl     (alu_ctrl),
      .branch       (branch),
      .jump         (jump),
      .csr_access   (csr_access),
      .is_ecall     (is_ecall),
      .is_ebreak    (is_ebreak),
      .is_mret      (is_mret),
      .illegal      (illegal),
      .is_muldiv    (is_muldiv),
      .muldiv_op    (muldiv_op)
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

  function automatic alu_op_e funct_alu();
    case (funct3)
      3'b000:  return alu_op_e'((funct7b5 && op[5]) ? ALU_SUB : ALU_ADD);
      3'b001:  return ALU_SLL;
      3'b010:  return ALU_SLT;
      3'b011:  return ALU_SLTU;
      3'b100:  return ALU_XOR;
      3'b101:  return alu_op_e'(funct7b5 ? ALU_SRA : ALU_SRL);
      3'b110:  return ALU_OR;
      default: return ALU_AND;
    endcase
  endfunction

  task automatic check_effects(input string tag, input logic rw, input logic mw, input logic br,
                               input logic jp);
    logic sys;
    logic priv;
    logic rsvd;
    logic md;
    sys  = op == OpcodeSystem;
    priv = sys && funct3 == 3'b000;
    rsvd = sys && funct3 == 3'b100;
    md   = op == OpcodeOp && funct12[11:5] == Funct7M;
    check({tag, " reg_write"}, FieldW'(reg_write), FieldW'(rw || (sys && !priv && !rsvd)));
    check({tag, " mem_write"}, FieldW'(mem_write), FieldW'(mw));
    check({tag, " branch"}, FieldW'(branch), FieldW'(br));
    check({tag, " jump"}, FieldW'(jump), FieldW'(jp));
    check({tag, " csr_access"}, FieldW'(csr_access), FieldW'(sys && !priv && !rsvd));
    check({tag, " is_ecall"}, FieldW'(is_ecall), FieldW'(priv && funct12 == 12'h000));
    check({tag, " is_ebreak"}, FieldW'(is_ebreak), FieldW'(priv && funct12 == 12'h001));
    check({tag, " is_mret"}, FieldW'(is_mret), FieldW'(priv && funct12 == 12'h302));
    check({tag, " illegal"}, FieldW'(illegal), FieldW'(rsvd));
    check({tag, " is_muldiv"}, FieldW'(is_muldiv), FieldW'(md));
    if (md) check({tag, " muldiv_op"}, FieldW'(muldiv_op), FieldW'(funct3));
  endtask  // Automatic

  task automatic check_alu(input string tag, input logic [ImmSrcW-1:0] imm,
                           input logic [SrcAW-1:0] srca, input logic b_imm,
                           input logic [ResSrcW-1:0] res, input alu_op_e ctrl, input logic tgt);
    check({tag, " imm_src"}, FieldW'(imm_src), FieldW'(imm));
    check({tag, " alu_a_src"}, FieldW'(alu_a_src), FieldW'(srca));
    check({tag, " alu_src"}, FieldW'(alu_src), FieldW'(b_imm));
    check({tag, " result_src"}, FieldW'(result_src), FieldW'(res));
    check({tag, " alu_ctrl"}, FieldW'(alu_ctrl), FieldW'(ctrl));
    check({tag, " pc_target_src"}, FieldW'(pc_target_src), FieldW'(tgt));
  endtask  // Automatic

  task automatic check_now();
    string tag;
    logic  f5_int;
    #1;
    tag = $sformatf("op %b f3 %b f12 %h f7b5 %b", op, funct3, funct12, funct7b5);
    f5_int = funct12[11:7] == Funct5FcvtWS || funct12[11:7] == Funct5FmvXW ||
        funct12[11:7] == Funct5Fcmp;
    case (op)
      OpcodeOp: begin
        check_effects(tag, 1'b1, 1'b0, 1'b0, 1'b0);
        check({tag, " alu_src"}, FieldW'(alu_src), FieldW'(1'b0));
        check({tag, " alu_ctrl"}, FieldW'(alu_ctrl), FieldW'(funct_alu()));
        check({tag, " alu_a_src"}, FieldW'(alu_a_src), FieldW'(SrcARs1));
        check({tag, " result_src"}, FieldW'(result_src), FieldW'(ResAlu));
        check({tag, " pc_target_src"}, FieldW'(pc_target_src), FieldW'(1'b0));
      end
      OpcodeOpImm: begin
        check_effects(tag, 1'b1, 1'b0, 1'b0, 1'b0);
        check_alu(tag, ImmI, SrcARs1, 1'b1, ResAlu, funct_alu(), 1'b0);
      end
      OpcodeLoad: begin
        check_effects(tag, 1'b1, 1'b0, 1'b0, 1'b0);
        check_alu(tag, ImmI, SrcARs1, 1'b1, ResMem, ALU_ADD, 1'b0);
      end
      OpcodeStore: begin
        check_effects(tag, 1'b0, 1'b1, 1'b0, 1'b0);
        check({tag, " imm_src"}, FieldW'(imm_src), FieldW'(ImmS));
        check({tag, " alu_src"}, FieldW'(alu_src), FieldW'(1'b1));
        check({tag, " alu_ctrl"}, FieldW'(alu_ctrl), FieldW'(ALU_ADD));
        check({tag, " alu_a_src"}, FieldW'(alu_a_src), FieldW'(SrcARs1));
      end
      OpcodeBranch: begin
        check_effects(tag, 1'b0, 1'b0, 1'b1, 1'b0);
        check({tag, " imm_src"}, FieldW'(imm_src), FieldW'(ImmB));
        check({tag, " alu_src"}, FieldW'(alu_src), FieldW'(1'b0));
        check({tag, " alu_ctrl"}, FieldW'(alu_ctrl), FieldW'(ALU_SUB));
        check({tag, " alu_a_src"}, FieldW'(alu_a_src), FieldW'(SrcARs1));
        check({tag, " pc_target_src"}, FieldW'(pc_target_src), FieldW'(1'b0));
      end
      OpcodeJal: begin
        check_effects(tag, 1'b1, 1'b0, 1'b0, 1'b1);
        check({tag, " imm_src"}, FieldW'(imm_src), FieldW'(ImmJ));
        check({tag, " result_src"}, FieldW'(result_src), FieldW'(ResPc4));
        check({tag, " pc_target_src"}, FieldW'(pc_target_src), FieldW'(1'b0));
      end
      OpcodeJalr: begin
        check_effects(tag, 1'b1, 1'b0, 1'b0, 1'b1);
        check_alu(tag, ImmI, SrcARs1, 1'b1, ResPc4, ALU_ADD, 1'b1);
      end
      OpcodeLui: begin
        check_effects(tag, 1'b1, 1'b0, 1'b0, 1'b0);
        check_alu(tag, ImmU, SrcAZero, 1'b1, ResAlu, ALU_ADD, 1'b0);
      end
      OpcodeAuipc: begin
        check_effects(tag, 1'b1, 1'b0, 1'b0, 1'b0);
        check_alu(tag, ImmU, SrcAPc, 1'b1, ResAlu, ALU_ADD, 1'b0);
      end
      OpcodeOpV: begin
        check_effects(
            tag, funct3 == Funct3Opcfg || (funct3 == Funct3Opmvv && funct12[11:6] == Funct6Wxunary),
            1'b0, 1'b0, 1'b0);
      end
      OpcodeOpFp: check_effects(tag, f5_int, 1'b0, 1'b0, 1'b0);
      OpcodeLoadFp: begin
        check_effects(tag, 1'b0, 1'b0, 1'b0, 1'b0);
        if (funct3 == Funct3Word) check_alu(tag, ImmI, SrcARs1, 1'b1, ResMem, ALU_ADD, 1'b0);
      end
      OpcodeStoreFp: begin
        check_effects(tag, 1'b0, funct3 == Funct3Word, 1'b0, 1'b0);
        if (funct3 == Funct3Word) begin
          check({tag, " imm_src"}, FieldW'(imm_src), FieldW'(ImmS));
          check({tag, " alu_src"}, FieldW'(alu_src), FieldW'(1'b1));
          check({tag, " alu_ctrl"}, FieldW'(alu_ctrl), FieldW'(ALU_ADD));
        end
      end
      default: check_effects(tag, 1'b0, 1'b0, 1'b0, 1'b0);
    endcase
  endtask  // Automatic

  task automatic sweep_all();
    for (int o = 0; o < 2 ** OpcodeW; o++)
      for (int f3 = 0; f3 < 2 ** Funct3W; f3++)
        for (int b5 = 0; b5 < 2; b5++)
          for (int f = 0; f < Funct12s; f++) begin
            op = OpcodeW'(o);
            funct3 = Funct3W'(f3);
            funct7b5 = 1'(b5);
            funct12 = funct12s[f];
            check_now();
          end
  endtask  // Automatic

  task automatic priv_sweep();
    for (int f = 0; f < 2 ** CsrAddrW; f++) begin
      op = OpcodeSystem;
      funct3 = 3'b000;
      funct7b5 = 1'b0;
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
    funct7b5 = 1'b0;
    #1;
  endtask  // Automatic

  initial begin
    $dumpfile("control_unit_tb.vcd");
    $dumpvars(0, control_unit_tb);
    do_reset();

    sweep_all();
    priv_sweep();

    do_verdict();
  end

endmodule

`default_nettype wire
