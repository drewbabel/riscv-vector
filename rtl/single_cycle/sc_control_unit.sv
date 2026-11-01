`default_nettype none

module sc_control_unit
  import alu_pkg::*;
  import csr_pkg::*;
  import opcode_pkg::*;
(
    input  wire              [ OpcodeW-1:0] op,
    input  wire              [ Funct3W-1:0] funct3,
    input  wire              [CsrAddrW-1:0] funct12,
    input  wire                             funct7b5,
    input  wire                             zero,
    input  wire                             lt,
    input  wire                             ltu,
    output logic                            reg_write,
    output logic             [ ImmSrcW-1:0] imm_src,
    output logic             [   SrcAW-1:0] alu_a_src,
    output logic                            pc_target_src,
    output logic                            alu_src,
    output logic                            mem_write,
    output logic             [ ResSrcW-1:0] result_src,
    output logic                            pc_src,
    output alu_pkg::alu_op_e                alu_ctrl,
    output logic                            csr_access,
    output logic                            is_ecall,
    output logic                            is_ebreak,
    output logic                            is_mret
);

  logic [AluOpW-1:0] alu_op;
  logic branch;
  logic jump;

  sc_control_decoder u_decoder (
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

  alu_decoder u_alu_decoder (
      .alu_op  (alu_op),
      .funct3  (funct3),
      .funct7b5(funct7b5),
      .op5     (op[5]),
      .alu_ctrl(alu_ctrl)
  );

  logic branch_taken;

  always_comb begin
    case (funct3)
      Funct3Beq:  branch_taken = zero;
      Funct3Bne:  branch_taken = !zero;
      Funct3Blt:  branch_taken = lt;
      Funct3Bge:  branch_taken = !lt;
      Funct3Bltu: branch_taken = ltu;
      Funct3Bgeu: branch_taken = !ltu;
      default:    branch_taken = 1'b0;
    endcase
  end

  assign pc_src = (branch & branch_taken) | jump;

endmodule

`default_nettype wire
