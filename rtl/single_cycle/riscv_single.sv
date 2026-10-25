`default_nettype none

module riscv_single
  import alu_pkg::*;
  import csr_pkg::*;
  import opcode_pkg::*;
#(
    parameter  int XLEN     = arch_pkg::XLEN,
    localparam int StrbW    = XLEN / 8,
    localparam int ByteOffW = $clog2(StrbW),
    localparam int InstrLsb = arch_pkg::InstrLsb,
    localparam int ILEN     = arch_pkg::ILEN
) (
    input  wire              clk,
    input  wire              core_en,
    input  wire              cycle_en,
    input  wire              rst_n,
    input  wire  [ ILEN-1:0] instr,
    input  wire  [ XLEN-1:0] read_data,
    input  wire              timer_irq,
    output logic [ XLEN-1:0] pc,
    output logic             mem_write,
    output logic [ XLEN-1:0] alu_result,
    output logic [ XLEN-1:0] write_data,
    output logic [StrbW-1:0] store_wstrb,
    output logic [ XLEN-1:0] store_data
);

  if (XLEN != 32) begin : g_xlen
    $error("riscv_single implements RV32 only");
  end

  logic [Funct3W-1:0] funct3;
  assign funct3 = instr[14:12];
  logic [CsrAddrW-1:0] funct12;
  assign funct12 = instr[31:20];
  logic [OpcodeW-1:0] opcode;
  assign opcode = instr[6:0];

  logic mem_write_raw;
  logic reg_write;
  logic reg_write_gated;
  logic [ImmSrcW-1:0] imm_src;
  logic [SrcAW-1:0] alu_a_src;
  logic alu_src;
  logic [ResSrcW-1:0] result_src;
  alu_pkg::alu_op_e alu_ctrl;
  logic pc_src;
  logic pc_target_src;
  logic zero;
  logic lt;
  logic ltu;
  logic [XLEN-1:0] load_data;
  logic [XLEN-1:0] rs1_data;
  logic [XLEN-1:0] imm_ext;
  logic [XLEN-1:0] csr_rdata;
  logic csr_access;
  logic is_ecall;
  logic is_ebreak;
  logic is_mret;
  logic exc_illegal;
  logic exc_instr_misaligned;
  logic exc_load_misaligned;
  logic exc_store_misaligned;
  logic [XLEN-1:0] pc_target;
  logic trap_taken;
  logic [XLEN-1:0] trap_vector;
  logic mret_taken;
  logic [XLEN-1:0] mepc_out;
  logic [7:0] ld_byte;
  logic [15:0] ld_half;
  logic opcode_known;
  logic is_ctrl;
  logic load_misaligned;
  logic store_misaligned;

  always_comb begin
    case (opcode)
      OpcodeOp, OpcodeOpImm, OpcodeLoad, OpcodeStore, OpcodeBranch, OpcodeJal, OpcodeJalr,
          OpcodeLui, OpcodeAuipc, OpcodeMiscMem, OpcodeSystem:
      opcode_known = 1'b1;
      default: opcode_known = 1'b0;
    endcase
  end

  always_comb begin
    case (funct3)
      Funct3Lh, Funct3Lhu: load_misaligned = alu_result[0];
      Funct3Lw:            load_misaligned = |alu_result[1:0];
      default:             load_misaligned = 1'b0;
    endcase
  end

  always_comb begin
    case (funct3)
      Funct3Sh: store_misaligned = alu_result[0];
      Funct3Sw: store_misaligned = |alu_result[1:0];
      default:  store_misaligned = 1'b0;
    endcase
  end

  assign exc_illegal = !opcode_known;
  assign is_ctrl = (opcode == OpcodeBranch) || (opcode == OpcodeJal) || (opcode == OpcodeJalr);
  assign exc_instr_misaligned = is_ctrl &&
      ((pc_src ? pc_target[InstrLsb-1:0] : pc[InstrLsb-1:0]) != '0);
  assign exc_load_misaligned = (opcode == OpcodeLoad) && load_misaligned;
  assign exc_store_misaligned = (opcode == OpcodeStore) && store_misaligned;

  sc_control_unit control_unit_inst (
      .op           (opcode),
      .funct3       (funct3),
      .funct12      (funct12),
      .funct7b5     (instr[30]),
      .zero         (zero),
      .lt           (lt),
      .ltu          (ltu),
      .reg_write    (reg_write),
      .imm_src      (imm_src),
      .alu_a_src    (alu_a_src),
      .pc_target_src(pc_target_src),
      .alu_src      (alu_src),
      .mem_write    (mem_write_raw),
      .result_src   (result_src),
      .pc_src       (pc_src),
      .alu_ctrl     (alu_ctrl),
      .csr_access   (csr_access),
      .is_ecall     (is_ecall),
      .is_ebreak    (is_ebreak),
      .is_mret      (is_mret)
  );

  extend #(
      .XLEN(XLEN)
  ) extend_inst (
      .imm_src(imm_src),
      .instr  (instr),
      .imm_ext(imm_ext)
  );

  sc_csr #(
      .XLEN(XLEN)
  ) csr_inst (
      .clk                 (clk),
      .core_en             (core_en),
      .cycle_en            (cycle_en),
      .rst_n               (rst_n),
      .csr_access          (csr_access),
      .csr_addr            (funct12),
      .funct3              (funct3),
      .rs1_data            (rs1_data),
      .zimm                (instr[19:15]),
      .pc                  (pc),
      .bad_addr            (exc_instr_misaligned ? pc_target : alu_result),
      .exc_illegal         (exc_illegal),
      .exc_ecall           (is_ecall),
      .exc_ebreak          (is_ebreak),
      .exc_instr_misaligned(exc_instr_misaligned),
      .exc_load_misaligned (exc_load_misaligned),
      .exc_store_misaligned(exc_store_misaligned),
      .is_mret             (is_mret),
      .timer_irq           (timer_irq),
      .csr_rdata           (csr_rdata),
      .trap_taken          (trap_taken),
      .trap_vector         (trap_vector),
      .mret_taken          (mret_taken),
      .mepc_out            (mepc_out)
  );

  sc_datapath #(
      .XLEN(XLEN)
  ) datapath_inst (
      .clk          (clk),
      .core_en      (core_en),
      .rst_n        (rst_n),
      .reg_write    (reg_write_gated),
      .imm_src      (imm_src),
      .alu_a_src    (alu_a_src),
      .alu_src      (alu_src),
      .result_src   (result_src),
      .csr_access   (csr_access),
      .csr_rdata    (csr_rdata),
      .alu_ctrl     (alu_ctrl),
      .pc_src       (pc_src),
      .pc_target_src(pc_target_src),
      .trap_taken   (trap_taken),
      .trap_vector  (trap_vector),
      .mret_taken   (mret_taken),
      .mepc_out     (mepc_out),
      .instr        (instr),
      .read_data    (load_data),
      .pc           (pc),
      .alu_result   (alu_result),
      .write_data   (write_data),
      .rs1_data     (rs1_data),
      .zero         (zero),
      .lt           (lt),
      .ltu          (ltu)
  );

  assign reg_write_gated = reg_write && !trap_taken;
  assign mem_write = mem_write_raw && !trap_taken;

  always_comb begin
    ld_byte = read_data[{alu_result[ByteOffW-1:0], 3'b000}+:8];
    ld_half = read_data[{alu_result[ByteOffW-1:1], 4'b0000}+:16];
    case (funct3)
      Funct3Lb:  load_data = XLEN'($signed(ld_byte));
      Funct3Lbu: load_data = XLEN'(ld_byte);
      Funct3Lh:  load_data = XLEN'($signed(ld_half));
      Funct3Lhu: load_data = XLEN'(ld_half);
      default:   load_data = read_data;  // lw
    endcase
  end

  always_comb begin
    store_data  = write_data;
    store_wstrb = '0;
    if (mem_write) begin
      case (funct3)
        Funct3Sb: begin  // sb
          store_data  = {StrbW{write_data[7:0]}};
          store_wstrb = StrbW'(1) << alu_result[ByteOffW-1:0];
        end
        Funct3Sh: begin  // sh
          store_data  = {(StrbW / 2) {write_data[15:0]}};
          store_wstrb = StrbW'(3) << alu_result[ByteOffW-1:0];
        end
        Funct3Sw: begin  // sw
          store_data  = write_data;
          store_wstrb = '1;
        end
        default: ;
      endcase
    end
  end

  assign pc_target = pc_target_src ? {alu_result[XLEN-1:1], 1'b0} : (pc + imm_ext);



endmodule

`default_nettype wire
