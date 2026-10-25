`default_nettype none

module sc_control_decoder
  import csr_pkg::*;
  import opcode_pkg::*;
(
    input  wire  [ OpcodeW-1:0] op,
    input  wire  [ Funct3W-1:0] funct3,
    input  wire  [CsrAddrW-1:0] funct12,
    output logic                reg_write,
    output logic [ ImmSrcW-1:0] imm_src,
    output logic [   SrcAW-1:0] alu_a_src,
    output logic                pc_target_src,
    output logic                alu_src,
    output logic                mem_write,
    output logic [ ResSrcW-1:0] result_src,
    output logic                branch,
    output logic                jump,
    output logic [  AluOpW-1:0] alu_op,
    output logic                csr_access,
    output logic                is_ecall,
    output logic                is_ebreak,
    output logic                is_mret
);

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

    case (op)
      OpcodeOp: begin
        reg_write = 1'b1;
        alu_src   = 1'b0;
        alu_op    = AluOpFunct;
      end

      OpcodeOpImm: begin
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

      OpcodeBranch: begin
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
        alu_op        = AluOpAdd;  // Target via alu
        pc_target_src = 1'b1;  // Target from alu
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
        end else begin
          reg_write  = 1'b1;
          csr_access = 1'b1;
        end
      end

      default: begin
        reg_write     = 1'b0;
        imm_src       = 'x;
        alu_a_src     = 'x;
        pc_target_src = 1'bx;
        alu_src       = 1'bx;
        mem_write     = 1'b0;
        result_src    = 'x;
        branch        = 1'b0;
        jump          = 1'b0;
        alu_op        = 'x;
      end
    endcase
  end

endmodule

`default_nettype wire
