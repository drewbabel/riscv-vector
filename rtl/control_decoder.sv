`default_nettype none

module control_decoder
  import csr_pkg::*;
  import opcode_pkg::*;
  import muldiv_pkg::*;
  import fp_pkg::*;
(
    input  wire                    [ OpcodeW-1:0] op,
    input  wire                    [ Funct3W-1:0] funct3,
    input  wire                    [CsrAddrW-1:0] funct12,
    output logic                                  reg_write,
    output logic                   [ ImmSrcW-1:0] imm_src,
    output logic                   [   SrcAW-1:0] alu_a_src,
    output logic                                  pc_target_src,
    output logic                                  alu_src,
    output logic                                  mem_write,
    output logic                   [ ResSrcW-1:0] result_src,
    output logic                                  branch,
    output logic                                  jump,
    output logic                   [  AluOpW-1:0] alu_op,
    output logic                                  csr_access,
    output logic                                  is_ecall,
    output logic                                  is_ebreak,
    output logic                                  is_mret,
    output logic                                  illegal,
    output logic                                  is_muldiv,
    output muldiv_pkg::muldiv_op_e                muldiv_op
);

  localparam logic [5:0] Funct6Vwxunary = 6'b010000;

  logic [$bits(Funct7MulDiv)-1:0] funct7;
  logic [$bits(Funct6Vwxunary)-1:0] funct6;
  logic [$bits(Funct5Fcmp)-1:0] funct5;

  assign funct7 = funct12[CsrAddrW-1-:$bits(funct7)];
  assign funct6 = funct12[CsrAddrW-1-:$bits(funct6)];
  assign funct5 = funct12[CsrAddrW-1-:$bits(funct5)];

  always_comb begin
    reg_write     = 1'b0;
    imm_src       = ImmI;
    alu_a_src     = SrcARs1;
    pc_target_src = 1'b0;
    alu_src       = 1'b0;
    mem_write     = 1'b0;
    result_src    = ResAlu;
    branch        = 1'b0;
    jump          = 1'b0;
    alu_op        = AluOpAdd;
    csr_access    = 1'b0;
    is_ecall      = 1'b0;
    is_ebreak     = 1'b0;
    is_mret       = 1'b0;
    illegal       = 1'b0;
    is_muldiv     = 1'b0;
    muldiv_op     = MD_MUL;

    case (op)
      OpcodeOp: begin  // R-type and RV32M
        reg_write = 1'b1;
        alu_src   = 1'b0;
        alu_op    = AluOpFunct;
        if (funct7 == Funct7MulDiv) begin  // RV32M ops
          is_muldiv = 1'b1;
          muldiv_op = muldiv_op_e'(funct3);
        end
      end

      OpcodeOpImm: begin  // addi, andi, ori, xori, slli, srli, srai, slti, sltiu
        reg_write = 1'b1;
        imm_src   = ImmI;
        alu_src   = 1'b1;
        alu_op    = AluOpFunct;
      end

      OpcodeLoad: begin  // lw
        reg_write  = 1'b1;
        imm_src    = ImmI;
        alu_src    = 1'b1;
        result_src = ResMem;
        alu_op     = AluOpAdd;
      end

      OpcodeStore: begin  // sw
        imm_src   = ImmS;
        alu_src   = 1'b1;
        mem_write = 1'b1;
        alu_op    = AluOpAdd;
      end

      OpcodeBranch: begin  // beq, bne, blt, bge, bltu, bgeu
        imm_src = ImmB;
        alu_src = 1'b0;
        branch  = 1'b1;
        alu_op  = AluOpBranch;
      end

      OpcodeJal: begin  // jal
        reg_write  = 1'b1;
        imm_src    = ImmJ;
        result_src = ResPc4;
        jump       = 1'b1;
      end

      OpcodeJalr: begin  // jalr
        reg_write     = 1'b1;
        imm_src       = ImmI;
        alu_src       = 1'b1;
        result_src    = ResPc4;
        jump          = 1'b1;
        alu_op        = AluOpAdd;  // alu computes rs1 + imm as the target
        pc_target_src = 1'b1;  // pc target comes from the alu, not pc + imm
      end

      OpcodeLui: begin  // lui
        reg_write = 1'b1;
        imm_src   = ImmU;
        alu_a_src = SrcAZero;
        alu_src   = 1'b1;
        alu_op    = AluOpAdd;
      end

      OpcodeAuipc: begin  // auipc
        reg_write = 1'b1;
        imm_src   = ImmU;
        alu_a_src = SrcAPc;
        alu_src   = 1'b1;
        alu_op    = AluOpAdd;
      end

      OpcodeSystem: begin
        if (funct3 == Funct3Priv) begin
          is_ecall  = (funct12 == Funct12Ecall);
          is_ebreak = (funct12 == Funct12Ebreak);
          is_mret   = (funct12 == Funct12Mret);
        end else if (funct3 == Funct3SysRsvd) begin
          illegal = 1'b1;
        end else begin
          reg_write  = 1'b1;
          csr_access = 1'b1;
        end
      end

      OpcodeOpV: begin
        // Scalar result forms
        if (funct3 == Funct3Opcfg) reg_write = 1'b1;
        else if ((funct3 == Funct3Opmvv) && (funct6 == Funct6Vwxunary)) reg_write = 1'b1;
      end

      OpcodeOpFp: begin
        if ((funct5 == Funct5FcvtWS) || (funct5 == Funct5FmvXW) || (funct5 == Funct5Fcmp))
          reg_write = 1'b1;
      end

      OpcodeLoadFp: begin
        if (funct3 == Funct3FpWord) begin
          imm_src    = ImmI;
          alu_src    = 1'b1;
          result_src = ResMem;
          alu_op     = AluOpAdd;
        end
      end

      OpcodeStoreFp: begin
        if (funct3 == Funct3FpWord) begin
          imm_src   = ImmS;
          alu_src   = 1'b1;
          mem_write = 1'b1;
          alu_op    = AluOpAdd;
        end
      end

      default: ;  // Illegal opcode nop
    endcase
  end

endmodule

`default_nettype wire
