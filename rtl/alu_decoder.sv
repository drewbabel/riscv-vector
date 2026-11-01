`default_nettype none

module alu_decoder
  import alu_pkg::*;
  import opcode_pkg::*;
(
    input  wire              [ AluOpW-1:0] alu_op,
    input  wire              [Funct3W-1:0] funct3,
    input  wire                            funct7b5,
    input  wire                            op5,
    output alu_pkg::alu_op_e               alu_ctrl
);

  logic sub_variant;
  assign sub_variant = funct7b5 & op5;

  always_comb begin
    case (alu_op)
      AluOpAdd:    alu_ctrl = ALU_ADD;
      AluOpBranch: alu_ctrl = ALU_SUB;

      AluOpFunct: begin
        case (funct3)
          Funct3AddSub: alu_ctrl = alu_pkg::alu_op_e'(sub_variant ? ALU_SUB : ALU_ADD);
          Funct3Sll:    alu_ctrl = ALU_SLL;
          Funct3Slt:    alu_ctrl = ALU_SLT;
          Funct3Sltu:   alu_ctrl = ALU_SLTU;
          Funct3Xor:    alu_ctrl = ALU_XOR;
          Funct3Sr:     alu_ctrl = alu_pkg::alu_op_e'(funct7b5 ? ALU_SRA : ALU_SRL);
          Funct3Or:     alu_ctrl = ALU_OR;
          Funct3And:    alu_ctrl = ALU_AND;
          default:      alu_ctrl = alu_pkg::alu_op_e'('x);
        endcase
      end

      default: alu_ctrl = alu_pkg::alu_op_e'('x);
    endcase
  end

endmodule

`default_nettype wire
