`default_nettype none

module datapath
  import alu_pkg::*;
  import cache_pkg::*;
  import opcode_pkg::*;
  import muldiv_pkg::*;
  import bp_pkg::*;
  import csr_pkg::VxsatAddr;
  import csr_pkg::VcsrAddr;
  import csr_pkg::FflagsAddr;
  import csr_pkg::FrmAddr;
  import csr_pkg::FcsrAddr;
  import csr_pkg::MstatusAddr;
  import fp_pkg::*;
#(
    parameter  int XLEN      = arch_pkg::XLEN,
    parameter  int VLEN      = arch_pkg::VLEN,
    parameter  bit GSHARE_EN = 1'b1,
    localparam int VlW       = $clog2(VLEN + 1),
    localparam int VstartW   = $clog2(VLEN),
    localparam int StrbW     = XLEN / 8,
    localparam int ByteOffW  = $clog2(StrbW)
) (
`ifdef RISCV_FORMAL
    output logic                         dbg_valid,
    output logic [             XLEN-1:0] dbg_insn,
    output logic [             XLEN-1:0] dbg_pc_rdata,
    output logic [             XLEN-1:0] dbg_pc_wdata,
    output logic [             XLEN-1:0] dbg_rs1_rdata,
    output logic [             XLEN-1:0] dbg_rs2_rdata,
    output logic [             XLEN-1:0] dbg_rd_wdata,
    output logic                         dbg_reg_write,
    output logic [             XLEN-1:0] dbg_mem_addr,
    output logic [            StrbW-1:0] dbg_mem_wmask,
    output logic [             XLEN-1:0] dbg_mem_wdata,
    output logic [             XLEN-1:0] dbg_mem_rdata,
    output logic                         dbg_trap,
    output logic [             XLEN-1:0] dbg_csr_wdata,
    output logic [             XLEN-1:0] dbg_mscratch,
    output logic [             XLEN-1:0] dbg_mstatus,
    output logic [             XLEN-1:0] dbg_mtvec,
    output logic [             XLEN-1:0] dbg_mepc,
    output logic [             XLEN-1:0] dbg_mcause,
    output logic [             XLEN-1:0] dbg_mtval,
    output logic [             XLEN-1:0] dbg_mie,
    output logic [             XLEN-1:0] dbg_mip,
    output logic [             XLEN-1:0] dbg_mcycle,
    output logic [             XLEN-1:0] dbg_minstret,
    output logic [             XLEN-1:0] dbg_mcycleh,
    output logic [             XLEN-1:0] dbg_minstreth,
    output logic [                  4:0] dbg_fflags,
    output logic [              VlW-1:0] dbg_vl,
    output logic [                  7:0] dbg_vtype_bits,
    output logic                         dbg_vtype_ill,
    output logic [          VstartW-1:0] dbg_vstart,
    output logic [                  7:0] dbg_vec_tag,
    output logic                         dbg_vec_retire,
    output logic [arch_pkg::NumRegs-1:0] dbg_vec_wregs,
    output logic                         dbg_vec_idle,
    output logic                         dbg_ex_commit,
    output logic [             XLEN-1:0] dbg_ex_insn,
`endif
    input  wire                          clk,
    input  wire                          core_en,
    input  wire                          rst_n,
    input  wire  [             XLEN-1:0] instr,
    input  wire  [         LineBits-1:0] read_line,
    input  wire                          timer_irq,
    input  wire                          ext_irq,
    input  wire                          imem_ready,
    input  wire                          dmem_ready,
    output logic                         dmem_req,
    output logic [             XLEN-1:0] pc,
    output logic                         mem_write,
    output logic [             XLEN-1:0] alu_result,
    output logic [             XLEN-1:0] write_data,
    output logic [            StrbW-1:0] store_wstrb,
    output logic [             XLEN-1:0] store_data,
    output logic [             XLEN-1:0] mem_addr,
    input  wire                          vmem_ready,
    output logic                         vmem_req,
    output logic [             XLEN-1:0] vmem_addr,
    output logic [         LineBits-1:0] vmem_wdata,
    output logic [        LineBytes-1:0] vmem_wstrb
);

  // Vector port is line
  if (VLEN != LineBits) begin : g_vlen_line
    $error("VLEN must equal LineBits");
  end

  logic                   [    XLEN-1:0] pc_next;
  logic                   [    XLEN-1:0] pc_plus4;
  logic                   [    XLEN-1:0] rs1_data;
  logic                   [    XLEN-1:0] rs2_data;
  logic                   [    XLEN-1:0] imm_ext;
  logic                   [    XLEN-1:0] src_a;
  logic                   [    XLEN-1:0] src_b;
  logic                   [    XLEN-1:0] forwarded_rs1;
  logic                   [    XLEN-1:0] forwarded_rs2;
  logic                   [    XLEN-1:0] result;
  logic                   [    XLEN-1:0] result_ex;
  logic                   [    XLEN-1:0] load_data;
  logic                   [    XLEN-1:0] read_data;
  logic                   [         7:0] ld_byte;
  logic                   [        15:0] ld_half;

  logic                                  reg_write;
  logic                                  mem_write_dec;
  logic                   [         2:0] imm_src;
  logic                   [         1:0] alu_a_src;
  logic                                  alu_src;
  logic                   [         1:0] result_src;
  logic                                  pc_target_src;
  alu_pkg::alu_op_e                      alu_ctrl;
  logic                                  zero;
  logic                                  lt;
  logic                                  ltu;
  logic                                  branch;
  logic                                  jump;
  logic                                  is_muldiv;
  muldiv_pkg::muldiv_op_e                muldiv_op;

  // Pipeline registers

  logic                   [    XLEN-1:0] instr_id;
  logic                   [    XLEN-1:0] pc_id;
  logic                   [    XLEN-1:0] pc_plus4_id;

  logic                   [    XLEN-1:0] pc_ex;
  logic                   [    XLEN-1:0] pc_plus4_ex;
  logic                   [         2:0] funct3_ex;
  logic                   [    XLEN-1:0] imm_ext_ex;
  logic                   [         1:0] alu_a_src_ex;
  logic                                  pc_target_src_ex;
  logic                                  alu_src_ex;
  logic                                  mem_write_ex;
  logic                   [         1:0] result_src_ex;
  alu_pkg::alu_op_e                      alu_ctrl_ex;
  logic                   [    XLEN-1:0] rs1_data_ex;
  logic                   [    XLEN-1:0] rs2_data_ex;
  logic                   [         4:0] rs1_ex;
  logic                   [         4:0] rs2_ex;
  logic                   [         4:0] rd_ex;
  logic                                  reg_write_ex;
  logic                                  branch_ex;
  logic                                  jump_ex;
  logic                                  is_muldiv_ex;
  muldiv_pkg::muldiv_op_e                muldiv_op_ex;

  logic                   [    XLEN-1:0] alu_result_mem;
  logic                   [    XLEN-1:0] pc_plus4_mem;
  logic                   [         1:0] result_src_mem;
  logic                   [    XLEN-1:0] write_data_mem;
  logic                                  mem_write_mem;
  logic                   [         2:0] funct3_mem;
  logic                   [         4:0] rd_mem;
  logic                                  reg_write_mem;

  logic                   [         1:0] result_src_wb;
  logic                   [    XLEN-1:0] pc_plus4_wb;
  logic                   [    XLEN-1:0] alu_result_wb;
  logic                   [         4:0] rd_wb;
  logic                   [    XLEN-1:0] load_data_wb;
  logic                                  reg_write_wb;

  // Hazard detection
  logic                                  stall;
  logic                                  hazard_stall;
  logic                                  flush;
  logic                                  ifid_en;
  logic                                  idex_en;
  logic                                  exmem_en;
  logic                                  memwb_en;
  logic                                  ifid_bubble;
  logic                                  idex_bubble;
  logic                                  exmem_bubble;
  logic                                  memwb_bubble;
  logic                                  if_hold;
  logic                                  redirect_pending;
  logic                   [    XLEN-1:0] redirect_target;
  logic                   [    XLEN-1:0] flush_target;
  logic                                  id_hold;
  logic                                  ex_hold;
  logic                                  mem_hold;
  logic                                  pc_en;
  logic                   [         1:0] forward_a;
  logic                   [         1:0] forward_b;
  logic                   [         1:0] fwd_a;
  logic                   [         1:0] fwd_b;
  logic                                  fwd_hold;
  logic                                  mem_pc4;

  // Branch resolution
  logic                                  branch_taken_ex;
  logic                                  pc_src_ex;
  logic                   [    XLEN-1:0] pc_target_ex;

  // CSR trap
  logic                                  csr_access;
  logic                                  is_ecall;
  logic                                  is_ebreak;
  logic                                  is_mret;
  logic                                  exc_illegal;
  logic                   [    XLEN-1:0] instr_ex;
  logic                                  csr_access_ex;
  logic                                  is_ecall_ex;
  logic                                  is_ebreak_ex;
  logic                                  is_mret_ex;
  logic                                  exc_illegal_ex;
  logic                                  valid_id;
  logic                                  valid_ex;
  logic                                  valid_mem;
  logic                                  valid_wb;
  logic                                  commit_valid;
  logic                                  exc_instr_misaligned;
  logic                                  exc_load_misaligned;
  logic                                  exc_store_misaligned;
  logic                                  mem_misaligned;
  logic                   [    XLEN-1:0] csr_rdata;
  logic                                  trap_taken;
  logic                   [    XLEN-1:0] trap_vector;
  logic                                  mret_taken;
  logic                   [    XLEN-1:0] mepc_out;
  logic                   [    XLEN-1:0] bad_addr;

  logic                   [    XLEN-1:0] muldiv_result;
  logic                                  muldiv_busy;
  logic                                  muldiv_done;
  logic                                  muldiv_start;
  logic                                  muldiv_hold;
  logic                                  commit_ready;
  logic                                  vec_is_vector;
  logic                   [         1:0] vec_vxrm;
  logic                                  vec_vxsat;
  logic                                  vec_csr_we;
  logic                   [        11:0] vec_csr_waddr;
  logic                   [    XLEN-1:0] vec_csr_wdata;
  logic                                  vec_csr_wait;
  logic                                  vec_hold;
  logic                                  vec_vstart_set;
  logic                   [         4:0] vec_fflags;
  logic                                  vec_fp_id;
  logic                                  vec_fp_ex;
  logic                                  vec_issue_ok;
  logic                                  vec_idle;
  logic                                  vec_load_pending;
  logic                                  vec_store_pending;
  logic                                  vec_misaligned;
  logic                                  vec_xreg_valid;
  logic                   [    XLEN-1:0] vec_xreg_result;
  logic                                  vmem_hold;
  logic                                  is_fence_ex;
  logic                   [    XLEN-1:0] vec_bad_addr;

  logic                                  bp_taken;
  logic                   [GhistLen-1:0] bp_index;
  logic                                  btb_hit;
  logic                   [    XLEN-1:0] btb_target;
  logic                                  btb_is_cond;
  logic                                  predict_taken;
  logic                   [    XLEN-1:0] predict_target;
  logic predict_taken_id, predict_taken_ex;
  logic [XLEN-1:0] predict_target_id, predict_target_ex;
  logic [GhistLen-1:0] bp_index_id, bp_index_ex;
  logic                             mispredict;
  logic     [             XLEN-1:0] correct_pc;

  logic                             fp_is_d;
  logic                             fp_illegal_d;
  fp_unit_e                         fp_unit_d;
  logic                             frs1_read_d;
  logic                             frs2_read_d;
  logic                             frs3_read_d;
  logic                             frd_write_d;
  logic                             fxrd_write_d;
  logic                             fxrs1_read_d;
  logic     [                  2:0] fp_rm_d;
  logic                             fp_sub_d;
  logic                             fp_neg_prod_d;
  logic                             fp_neg_add_d;
  logic                             fp_to_int_d;
  logic                             fp_unsigned_d;
  logic                             fp_sqrt_d;
  logic     [                  4:0] fp_funct5_d;
  logic     [                  2:0] fp_funct3_d;
  logic                             fp_op_d;
  logic                             fp_load_d;
  logic                             fp_store_d;
  logic     [             FLEN-1:0] fp_rdata1;
  logic     [             FLEN-1:0] fp_rdata2;
  logic     [             FLEN-1:0] fp_rdata3;

  logic                             fp_op_ex;
  logic                             fp_load_ex;
  logic                             fp_store_ex;
  logic                             fp_load_mem;
  logic                             fp_load_wb;
  fp_unit_e                         fp_unit_ex;
  logic                             frd_write_ex;
  logic                             fxrd_write_ex;
  logic                             fp_sub_ex;
  logic                             fp_neg_prod_ex;
  logic                             fp_neg_add_ex;
  logic                             fp_to_int_ex;
  logic                             fp_unsigned_ex;
  logic                             fp_sqrt_ex;
  logic     [                  4:0] fp_funct5_ex;
  logic     [                  2:0] fp_funct3_ex;
  logic     [             FLEN-1:0] fp_a_ex;
  logic     [             FLEN-1:0] fp_b_ex;
  logic     [             FLEN-1:0] fp_c_ex;
  logic     [                  2:0] fp_rm_ex;
  logic     [                  2:0] frm_q;

  logic                             fp_fop_ex;
  logic                             fp_xop_ex;
  logic                             fp_start;
  logic                             fp_xstart;
  logic                             fp_xack;
  logic                             fp_ready;
  logic                             fp_idle;
  logic     [arch_pkg::NumRegs-1:0] fp_busy;
  logic                             fp_wb_valid;
  logic     [                  4:0] fp_wb_rd;
  logic     [             FLEN-1:0] fp_wb_data;
  logic     [                  4:0] fp_wb_flags;
  logic                             fp_xvalid;
  logic     [             XLEN-1:0] fp_xresult;
  logic     [                  4:0] fp_xflags;
  logic                             fp_hold;
  logic                             fp_csr_ex;
  logic                             frm_write_ex;

  pc #(
      .XLEN(XLEN),
      .RESET_ADDR('h0000_0000)
  ) pc_inst (
      .clk(clk),
      .core_en(core_en && pc_en),
      .rst_n(rst_n),
      .pc_next(pc_next),
      .pc_q(pc)
  );

  // IF/ID
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      instr_id          <= '0;
      pc_id             <= '0;
      pc_plus4_id       <= '0;
      predict_taken_id  <= 1'b0;
      predict_target_id <= '0;
      bp_index_id       <= '0;
    end else if (core_en && (flush || (ifid_en && ifid_bubble))) begin
      instr_id          <= 32'h0000_0013;  // NOP
      pc_id             <= '0;
      pc_plus4_id       <= '0;
      predict_taken_id  <= 1'b0;
      predict_target_id <= '0;
      bp_index_id       <= '0;
    end else if (core_en && ifid_en) begin
      instr_id          <= instr;
      pc_id             <= pc;
      pc_plus4_id       <= pc_plus4;
      predict_taken_id  <= predict_taken;
      predict_target_id <= predict_target;
      bp_index_id       <= bp_index;
    end
  end

  logic vec_dec_id_valid;
  vec_pkg::vec_op_e vec_dec_id_op;
  vec_pkg::vec_src_e vec_dec_id_src;
  vec_pkg::vec_eew_e vec_dec_id_eew;
  logic vec_dec_id_vm;
  logic [4:0] vec_dec_id_vs1;
  logic [4:0] vec_dec_id_vs2;
  logic [4:0] vec_dec_id_vd;
  logic [4:0] vec_dec_id_simm;
  logic vec_dec_id_reads_vd;
  logic vec_dec_id_reads_xreg;
  logic vec_dec_id_writes_xreg;
  logic vec_dec_id_writes_mask;
  vec_pkg::vec_fop_e vec_dec_id_fop;
  logic vec_dec_id_reads_freg;
  logic vec_dec_id_writes_freg;
  logic [1:0] vec_dec_id_mem_width;
  logic vec_dec_id_mem_whole;
  logic [2:0] vec_dec_id_mem_nf;
  logic vec_dec_id_mem_mask;
  logic vec_dec_id_mem_strided;
  vec_pkg::vec_dec_t vec_dec_id;

  vec_decode vec_decode_inst (
      .instr(instr_id),
      .valid(vec_dec_id_valid),
      .op(vec_dec_id_op),
      .src(vec_dec_id_src),
      .eew(vec_dec_id_eew),
      .vm(vec_dec_id_vm),
      .vs1(vec_dec_id_vs1),
      .vs2(vec_dec_id_vs2),
      .vd(vec_dec_id_vd),
      .simm(vec_dec_id_simm),
      .reads_vd(vec_dec_id_reads_vd),
      .reads_xreg(vec_dec_id_reads_xreg),
      .writes_xreg(vec_dec_id_writes_xreg),
      .writes_mask(vec_dec_id_writes_mask),
      .fop(vec_dec_id_fop),
      .reads_freg(vec_dec_id_reads_freg),
      .writes_freg(vec_dec_id_writes_freg),
      .mem_width(vec_dec_id_mem_width),
      .mem_whole(vec_dec_id_mem_whole),
      .mem_nf(vec_dec_id_mem_nf),
      .mem_mask(vec_dec_id_mem_mask),
      .mem_strided(vec_dec_id_mem_strided)
  );

  always_comb begin
    vec_dec_id.valid = vec_dec_id_valid;
    vec_dec_id.op = vec_dec_id_op;
    vec_dec_id.src = vec_dec_id_src;
    vec_dec_id.eew = vec_dec_id_eew;
    vec_dec_id.vm = vec_dec_id_vm;
    vec_dec_id.vs1 = vec_dec_id_vs1;
    vec_dec_id.vs2 = vec_dec_id_vs2;
    vec_dec_id.vd = vec_dec_id_vd;
    vec_dec_id.simm = vec_dec_id_simm;
    vec_dec_id.reads_vd = vec_dec_id_reads_vd;
    vec_dec_id.reads_xreg = vec_dec_id_reads_xreg;
    vec_dec_id.writes_xreg = vec_dec_id_writes_xreg;
    vec_dec_id.writes_mask = vec_dec_id_writes_mask;
    vec_dec_id.fop = vec_dec_id_fop;
    vec_dec_id.reads_freg = vec_dec_id_reads_freg;
    vec_dec_id.writes_freg = vec_dec_id_writes_freg;
    vec_dec_id.mem_width = vec_dec_id_mem_width;
    vec_dec_id.mem_whole = vec_dec_id_mem_whole;
    vec_dec_id.mem_nf = vec_dec_id_mem_nf;
    vec_dec_id.mem_mask = vec_dec_id_mem_mask;
    vec_dec_id.mem_strided = vec_dec_id_mem_strided;
  end

  vec_pkg::vec_dec_t vec_dec_ex;

  control_unit control_unit_inst (
      .op           (instr_id[6:0]),
      .funct3       (instr_id[14:12]),
      .funct12      (instr_id[31:20]),
      .funct7b5     (instr_id[30]),
      .reg_write    (reg_write),
      .imm_src      (imm_src),
      .alu_a_src    (alu_a_src),
      .pc_target_src(pc_target_src),
      .alu_src      (alu_src),
      .mem_write    (mem_write_dec),
      .result_src   (result_src),
      .alu_ctrl     (alu_ctrl),
      .branch       (branch),
      .jump         (jump),
      .csr_access   (csr_access),
      .is_ecall     (is_ecall),
      .is_ebreak    (is_ebreak),
      .is_mret      (is_mret),
      .is_muldiv    (is_muldiv),
      .muldiv_op    (muldiv_op)
  );

  assign exc_illegal = !((instr_id[6:0] == OpcodeOp) || (instr_id[6:0] == OpcodeOpImm) ||
      (instr_id[6:0] == OpcodeLoad) || (instr_id[6:0] == OpcodeStore) ||
      (instr_id[6:0] == OpcodeBranch) || (instr_id[6:0] == OpcodeJal) ||
      (instr_id[6:0] == OpcodeJalr) || (instr_id[6:0] == OpcodeLui) ||
      (instr_id[6:0] == OpcodeAuipc) || (instr_id[6:0] == OpcodeMiscMem) ||
      (instr_id[6:0] == OpcodeSystem) || (instr_id[6:0] == OpcodeOpV) ||
      (instr_id[6:0] == OpcodeLoadFp) || (instr_id[6:0] == OpcodeStoreFp) ||
      (instr_id[6:0] == OpcodeOpFp) || (instr_id[6:0] == OpcodeFmadd) ||
      (instr_id[6:0] == OpcodeFmsub) || (instr_id[6:0] == OpcodeFnmsub) ||
      (instr_id[6:0] == OpcodeFnmadd)) || fp_illegal_d;

  fp_decode u_fp_decode (
      .instr      (instr_id),
      .frm        (frm_q),
      .is_fp      (fp_is_d),
      .illegal    (fp_illegal_d),
      .unit       (fp_unit_d),
      .frs1_read  (frs1_read_d),
      .frs2_read  (frs2_read_d),
      .frs3_read  (frs3_read_d),
      .frd_write  (frd_write_d),
      .xrd_write  (fxrd_write_d),
      .xrs1_read  (fxrs1_read_d),
      .rm         (fp_rm_d),
      .sub        (fp_sub_d),
      .neg_prod   (fp_neg_prod_d),
      .neg_add    (fp_neg_add_d),
      .to_int     (fp_to_int_d),
      .is_unsigned(fp_unsigned_d),
      .sqrt       (fp_sqrt_d),
      .funct5     (fp_funct5_d),
      .funct3     (fp_funct3_d)
  );

  assign fp_op_d = fp_is_d && !fp_illegal_d && (fp_unit_d != FP_LOAD) && (fp_unit_d != FP_STORE);
  assign fp_load_d = fp_is_d && !fp_illegal_d && (fp_unit_d == FP_LOAD);
  assign fp_store_d = fp_is_d && !fp_illegal_d && (fp_unit_d == FP_STORE);

  fp_regfile fp_regfile_inst (
      .clk    (clk),
      .core_en(core_en),
      .rst_n  (rst_n),
      .we     (fp_wb_valid),
      .waddr  (fp_wb_rd),
      .wdata  (fp_wb_data),
      .we2    (fp_load_wb),
      .waddr2 (rd_wb),
      .wdata2 (load_data_wb),
      .raddr1 (instr_id[19:15]),
      .raddr2 (instr_id[24:20]),
      .raddr3 (instr_id[31:27]),
      .rdata1 (fp_rdata1),
      .rdata2 (fp_rdata2),
      .rdata3 (fp_rdata3)
  );

  regfile #(
      .XLEN(XLEN)
  ) regfile_inst (
      .clk(clk),
      .core_en(core_en),
      .rst_n(rst_n),
      .we(reg_write_wb),
      .waddr(rd_wb),
      .wdata(result),
      .raddr1(instr_id[19:15]),
      .raddr2(instr_id[24:20]),
      .rdata1(rs1_data),
      .rdata2(rs2_data)
  );

  extend #(
      .XLEN(XLEN)
  ) extend_inst (
      .imm_src(imm_src),
      .instr  (instr_id),
      .imm_ext(imm_ext)
  );

  // ID/EX
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      reg_write_ex     <= 1'b0;
      mem_write_ex     <= 1'b0;
      is_muldiv_ex     <= 1'b0;
      predict_taken_ex <= 1'b0;
      fp_op_ex         <= 1'b0;
      fp_load_ex       <= 1'b0;
      fp_store_ex      <= 1'b0;
      frd_write_ex     <= 1'b0;
      fxrd_write_ex    <= 1'b0;
    end else if (core_en) begin
      if (!idex_en) begin  // Latch operands
        rs1_data_ex <= forwarded_rs1;
        rs2_data_ex <= forwarded_rs2;
      end else begin
        predict_taken_ex  <= (predict_taken_id && !idex_bubble);
        predict_target_ex <= predict_target_id;
        bp_index_ex       <= bp_index_id;
        pc_ex             <= pc_id;
        pc_plus4_ex       <= pc_plus4_id;
        funct3_ex         <= instr_id[14:12];
        imm_ext_ex        <= imm_ext;
        alu_a_src_ex      <= alu_a_src;
        pc_target_src_ex  <= pc_target_src;
        alu_src_ex        <= alu_src;
        result_src_ex     <= idex_bubble ? 2'd0 : result_src;
        alu_ctrl_ex       <= alu_ctrl;
        rs1_data_ex       <= rs1_data;
        rs2_data_ex       <= rs2_data;
        reg_write_ex      <= (reg_write && !idex_bubble);
        mem_write_ex      <= (mem_write_dec && !idex_bubble);
        rd_ex             <= idex_bubble ? 5'd0 : instr_id[11:7];
        rs1_ex            <= instr_id[19:15];
        rs2_ex            <= instr_id[24:20];
        branch_ex         <= (branch && !idex_bubble);
        jump_ex           <= (jump && !idex_bubble);
        instr_ex          <= instr_id;
        vec_dec_ex        <= vec_dec_id;
        csr_access_ex     <= (csr_access && !idex_bubble);
        is_ecall_ex       <= (is_ecall && !idex_bubble);
        is_ebreak_ex      <= (is_ebreak && !idex_bubble);
        is_mret_ex        <= (is_mret && !idex_bubble);
        exc_illegal_ex    <= (exc_illegal && !idex_bubble);
        is_muldiv_ex      <= (is_muldiv && !idex_bubble);
        muldiv_op_ex      <= muldiv_op;
        fp_op_ex          <= (fp_op_d && !idex_bubble);
        fp_load_ex        <= (fp_load_d && !idex_bubble);
        fp_store_ex       <= (fp_store_d && !idex_bubble);
        fp_unit_ex        <= fp_unit_e'(vec_dec_id.writes_freg ? FP_MV_W_X : fp_unit_d);
        frd_write_ex      <= (((fp_op_d && frd_write_d) || vec_dec_id.writes_freg) && !idex_bubble);
        fxrd_write_ex     <= (fp_op_d && fxrd_write_d && !idex_bubble);
        fp_sub_ex         <= fp_sub_d;
        fp_neg_prod_ex    <= fp_neg_prod_d;
        fp_neg_add_ex     <= fp_neg_add_d;
        fp_to_int_ex      <= fp_to_int_d;
        fp_unsigned_ex    <= fp_unsigned_d;
        fp_sqrt_ex        <= fp_sqrt_d;
        fp_funct5_ex      <= fp_funct5_d;
        fp_funct3_ex      <= fp_funct3_d;
        fp_a_ex           <= fp_rdata1;
        fp_b_ex           <= fp_rdata2;
        fp_c_ex           <= fp_rdata3;
      end
    end
  end

  // Commit valid
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      valid_id  <= 1'b0;
      valid_ex  <= 1'b0;
      valid_mem <= 1'b0;
      valid_wb  <= 1'b0;
    end else if (core_en) begin
      // Flush beats stalls
      if (flush) valid_id <= 1'b0;
      else if (ifid_en) valid_id <= !ifid_bubble;

      if (memwb_bubble) begin
        valid_wb <= 1'b0;
      end else if (exmem_bubble) begin
        valid_mem <= 1'b0;
        valid_wb  <= valid_mem;
      end else begin
        valid_ex  <= valid_id && !idex_bubble;
        valid_mem <= valid_ex;
        valid_wb  <= valid_mem;
      end
    end
  end

  // Ready before holding
  assign commit_ready = valid_ex && !muldiv_hold && !vmem_hold && !mem_hold && !fp_hold;
  assign commit_valid = commit_ready && !vec_hold;

  hazard_unit #(
      .XLEN(XLEN)
  ) hazard_unit_inst (
      .clk(clk),
      .core_en(core_en),
      .rst_n(rst_n),
      .rs1_id(instr_id[19:15]),
      .rs2_id(instr_id[24:20]),
      .rs1_ex(rs1_ex),
      .rs2_ex(rs2_ex),
      .rd_id(instr_id[11:7]),
      .rd_ex(rd_ex),
      .rd_mem(rd_mem),
      .rd_wb(rd_wb),
      .reg_write_ex(reg_write_ex),
      .reg_write_mem(reg_write_mem),
      .reg_write_wb(reg_write_wb),
      .mem_write_ex(mem_write_ex),
      .result_src_ex(result_src_ex),
      .result_src_mem(result_src_mem),
      .result_src_wb(result_src_wb),
      .fp_op_id((fp_is_d || vec_fp_id) && valid_id),
      .frs1_read_id(frs1_read_d || vec_dec_id.reads_freg),
      .frs2_read_id(frs2_read_d),
      .frs3_read_id(frs3_read_d),
      .frd_write_id(frd_write_d || vec_dec_id.writes_freg),
      .rs3_id(instr_id[31:27]),
      .fp_busy(fp_busy),
      .frd_write_ex((frd_write_ex || fp_load_ex) && valid_ex),
      .frd_write_mem(fp_load_mem),
      .frm_write_ex(frm_write_ex),
      .stall(hazard_stall),
      .forward_a(forward_a),
      .forward_b(forward_b)
  );

  assign muldiv_hold = is_muldiv_ex && !muldiv_done;
  assign stall = hazard_stall || muldiv_hold || vec_hold || vmem_hold || fp_hold;

  assign if_hold = !imem_ready;
  assign id_hold = hazard_stall;
  assign ex_hold = muldiv_hold || vec_hold || vmem_hold || fp_hold;
  assign dmem_req = valid_mem && ((result_src_mem == 2'd1) || mem_write_mem);
  assign mem_hold = dmem_req && !dmem_ready;

  assign ifid_en = !id_hold && !ex_hold && !mem_hold;
  assign idex_en = !ex_hold && !mem_hold;
  assign exmem_en = !mem_hold;
  assign memwb_en = 1'b1;
  assign pc_en = (ifid_en && !if_hold) || (flush && !mem_hold && !if_hold);
  assign ifid_bubble = if_hold || redirect_pending;
  assign idex_bubble = id_hold || flush;
  assign exmem_bubble = ex_hold && !mem_hold;
  assign memwb_bubble = mem_hold;

  // Hold sampled operands
  assign fwd_hold = muldiv_hold && !muldiv_start;

  // Vector memory ordering
  assign is_fence_ex = (instr_ex[6:0] == OpcodeMiscMem) && (funct3_ex == 3'b000);
  assign vmem_hold = valid_ex && (((result_src_ex == 2'd1) && vec_store_pending) ||
      (mem_write_ex && (vec_load_pending || vec_store_pending)) || (is_fence_ex && !vec_idle));

  assign mem_pc4 = (result_src_mem == 2'd2);

  always_comb begin
    if (fwd_hold) fwd_a = 2'b00;
    else if (forward_a == 2'b01) fwd_a = mem_pc4 ? 2'b10 : 2'b01;
    else if (forward_a == 2'b10) fwd_a = 2'b11;
    else fwd_a = 2'b00;

    if (fwd_hold) fwd_b = 2'b00;
    else if (forward_b == 2'b01) fwd_b = mem_pc4 ? 2'b10 : 2'b01;
    else if (forward_b == 2'b10) fwd_b = 2'b11;
    else fwd_b = 2'b00;

    case (fwd_a)
      2'b01:   forwarded_rs1 = alu_result_mem;
      2'b10:   forwarded_rs1 = pc_plus4_mem;
      2'b11:   forwarded_rs1 = result;
      default: forwarded_rs1 = rs1_data_ex;
    endcase

    case (fwd_b)
      2'b01:   forwarded_rs2 = alu_result_mem;
      2'b10:   forwarded_rs2 = pc_plus4_mem;
      2'b11:   forwarded_rs2 = result;
      default: forwarded_rs2 = rs2_data_ex;
    endcase

    case (alu_a_src_ex)
      2'd0:    src_a = forwarded_rs1;
      2'd1:    src_a = pc_ex;
      2'd2:    src_a = '0;
      default: src_a = '0;
    endcase

    src_b = alu_src_ex ? imm_ext_ex : forwarded_rs2;
  end

  alu #(
      .XLEN(XLEN)
  ) alu_inst (
      .a(src_a),
      .b(src_b),
      .alu_op(alu_ctrl_ex),
      .result(alu_result),
      .zero(zero),
      .lt(lt),
      .ltu(ltu)
  );

  muldiv #(
      .XLEN(XLEN)
  ) muldiv_inst (
      .clk    (clk),
      .core_en(core_en),
      .rst_n  (rst_n),
      .start  (muldiv_start),
      .op     (muldiv_op_ex),
      .a      (forwarded_rs1),
      .b      (forwarded_rs2),
      .result (muldiv_result),
      .busy   (muldiv_busy),
      .done   (muldiv_done)
  );

  assign muldiv_start = is_muldiv_ex && !muldiv_busy && !muldiv_done;

  assign fp_fop_ex = valid_ex && frd_write_ex;
  assign fp_xop_ex = valid_ex && fxrd_write_ex;
  assign fp_rm_ex = (instr_ex[14:12] == RmDyn) ? frm_q : instr_ex[14:12];
  assign fp_csr_ex = valid_ex && csr_access_ex && ((instr_ex[31:20] == FflagsAddr) ||
      (instr_ex[31:20] == FrmAddr) || (instr_ex[31:20] == FcsrAddr));
  assign frm_write_ex = fp_csr_ex && (instr_ex[31:20] != FflagsAddr) &&
      (!funct3_ex[1] || (instr_ex[19:15] != 5'd0));
  assign fp_hold = (fp_fop_ex && !fp_ready) || (fp_xop_ex && !fp_xvalid) || (fp_csr_ex && !fp_idle);
  assign fp_start = fp_fop_ex && commit_valid && !trap_taken;
  assign fp_xstart = fp_xop_ex && !fp_xvalid;
  assign fp_xack = fp_xvalid && !ex_hold && !mem_hold;

  fp_unit #(
      .XLEN(XLEN)
  ) fp_unit_inst (
      .clk        (clk),
      .rst_n      (rst_n),
      .core_en    (core_en),
      .start      (fp_start),
      .xstart     (fp_xstart),
      .xack       (fp_xack),
      .unit       (fp_unit_ex),
      .sub        (fp_sub_ex),
      .neg_prod   (fp_neg_prod_ex),
      .neg_add    (fp_neg_add_ex),
      .to_int     (fp_to_int_ex),
      .is_unsigned(fp_unsigned_ex),
      .sqrt       (fp_sqrt_ex),
      .funct5     (fp_funct5_ex),
      .funct3     (fp_funct3_ex),
      .rm         (fp_rm_ex),
      .rd         (instr_ex[11:7]),
      .a          (fp_a_ex),
      .b          (fp_b_ex),
      .c          (fp_c_ex),
      .xa         (vec_dec_ex.writes_freg ? vec_xreg_result : forwarded_rs1),
      .ready      (fp_ready),
      .idle       (fp_idle),
      .reg_busy   (fp_busy),
      .wb_valid   (fp_wb_valid),
      .wb_rd      (fp_wb_rd),
      .wb_data    (fp_wb_data),
      .wb_flags   (fp_wb_flags),
      .xvalid     (fp_xvalid),
      .xresult    (fp_xresult),
      .xflags     (fp_xflags)
  );

  // Branch prediction
  if (GSHARE_EN) begin : g_bp
    gshare #(
        .XLEN(XLEN)
    ) gshare_inst (
        .clk          (clk),
        .core_en      (core_en),
        .rst_n        (rst_n),
        .predict_pc   (pc),
        .predict_taken(bp_taken),
        .predict_index(bp_index),
        .update_valid (branch_ex && valid_ex && !mem_hold),  // Resolved branches
        .update_taken (branch_taken_ex),
        .update_index (bp_index_ex)
    );

    btb #(
        .XLEN(XLEN)
    ) btb_inst (
        .clk           (clk),
        .core_en       (core_en),
        .rst_n         (rst_n),
        .lookup_pc     (pc),
        .hit           (btb_hit),
        .target        (btb_target),
        .is_cond       (btb_is_cond),
        .update_valid  (pc_src_ex && !mem_hold),  // Taken transfers
        .update_pc     (pc_ex),
        .update_target (pc_target_ex),
        .update_is_cond(branch_ex)
    );
  end else begin : g_no_bp
    // Always not taken
    assign bp_taken    = 1'b0;
    assign bp_index    = '0;
    assign btb_hit     = 1'b0;
    assign btb_target  = '0;
    assign btb_is_cond = 1'b0;
  end

`ifdef RISCV_FORMAL_ABSTRACT_BP
  (* anyseq *) logic abs_predict_taken;
  (* anyseq *) logic [XLEN-1:0] abs_predict_target;
  assign predict_taken  = abs_predict_taken;
  assign predict_target = {abs_predict_target[XLEN-1:1], 1'b0};
`else
  assign predict_taken  = btb_hit && (bp_taken || !btb_is_cond);
  assign predict_target = btb_target;
`endif
  // Operands not ready
  assign mispredict = commit_valid && ((predict_taken_ex != pc_src_ex) ||
      (pc_src_ex && predict_taken_ex && predict_target_ex != pc_target_ex));
  assign correct_pc = mispredict ? (pc_src_ex ? pc_target_ex : pc_plus4_ex) : '0;

  // Branch resolution
  always_comb begin
    case (funct3_ex)
      3'b000:  branch_taken_ex = zero;  // beq
      3'b001:  branch_taken_ex = !zero;  // bne
      3'b100:  branch_taken_ex = lt;  // blt
      3'b101:  branch_taken_ex = !lt;  // bge
      3'b110:  branch_taken_ex = ltu;  // bltu
      3'b111:  branch_taken_ex = !ltu;  // bgeu
      default: branch_taken_ex = 1'b0;
    endcase
  end

  assign pc_src_ex = valid_ex && ((branch_ex & branch_taken_ex) || jump_ex);
  assign pc_target_ex = pc_target_src_ex ? {alu_result[XLEN-1:1], 1'b0} : (pc_ex + imm_ext_ex);

  // EX exceptions
  assign exc_instr_misaligned = commit_valid && (branch_ex || jump_ex) && pc_src_ex &&
      (pc_target_ex[1:0] != 2'b00);

  // Alignment by width
  always_comb begin
    case (funct3_ex)
      3'b001, 3'b101: mem_misaligned = alu_result[0];  // halfword
      3'b010:         mem_misaligned = |alu_result[1:0];  // word
      default:        mem_misaligned = 1'b0;
    endcase
  end

  assign exc_load_misaligned = commit_valid && (((result_src_ex == 2'd1) && mem_misaligned) ||
      ((instr_ex[6:0] == OpcodeLoadFp) && vec_misaligned));
  assign exc_store_misaligned = commit_valid && ((mem_write_ex && mem_misaligned) ||
      ((instr_ex[6:0] == OpcodeStoreFp) && vec_misaligned));
  always_comb begin
    if (exc_instr_misaligned) bad_addr = pc_target_ex;
    else if (vec_misaligned) bad_addr = vec_bad_addr;
    else bad_addr = alu_result;
  end

  logic            is_vset;
  logic [ VlW-1:0] vl_d;
  logic [XLEN-1:0] vtype_d;
  logic [ VlW-1:0] vl_q;
  logic [XLEN-1:0] vtype_q;
  logic            exc_vec_encoding;

  assign vec_csr_wait = csr_access_ex && ((instr_ex[31:20] == VxsatAddr)
      || (instr_ex[31:20] == VcsrAddr) || (instr_ex[31:20] == FflagsAddr)
      || (instr_ex[31:20] == FcsrAddr) || (instr_ex[31:20] == MstatusAddr));

  // Vector float forms
  assign vec_fp_id = (vec_dec_id.op == vec_pkg::VEC_FARITH) ||
      (vec_dec_id.op == vec_pkg::VEC_FCMP) || (vec_dec_id.op == vec_pkg::VEC_FRED) ||
      vec_dec_id.reads_freg || vec_dec_id.writes_freg;
  assign vec_fp_ex = valid_ex && ((vec_dec_ex.op == vec_pkg::VEC_FARITH) ||
      (vec_dec_ex.op == vec_pkg::VEC_FCMP) || (vec_dec_ex.op == vec_pkg::VEC_FRED) ||
      vec_dec_ex.reads_freg || vec_dec_ex.writes_freg);

  assign exc_vec_encoding = (((instr_ex[6:0] == OpcodeOpV) && !is_vset) ||
      (instr_ex[6:0] == OpcodeLoadFp) || (instr_ex[6:0] == OpcodeStoreFp)) && !vec_is_vector &&
      !fp_load_ex && !fp_store_ex;

  vec_config #(
      .XLEN(XLEN),
      .VLEN(VLEN)
  ) vec_config_inst (
      .instr   (instr_ex),
      .rs1_data(forwarded_rs1),
      .rs2_data(forwarded_rs2),
      .vl_q    (vl_q),
      .vtype_q (vtype_q),
      .is_vset (is_vset),
      .vl_d    (vl_d),
      .vtype_d (vtype_d)
  );

  assign vec_issue_ok = commit_ready;

  /* verilator lint_off PINCONNECTEMPTY */
  vec_unit #(
      .XLEN(XLEN),
      .VLEN(VLEN)
  ) vec_unit_inst (
`ifdef RISCV_FORMAL
      .dbg_vec_tag   (dbg_vec_tag),
      .dbg_vec_retire(dbg_vec_retire),
      .dbg_vec_wregs (dbg_vec_wregs),
      .dbg_vec_idle  (dbg_vec_idle),
`endif
      .clk           (clk),
      .rst_n         (rst_n),
      .core_en       (core_en),
      .dec           (vec_dec_ex),
      .instr_valid   (vec_issue_ok),
      .cancel        (trap_taken),
      .ex_advance    (idex_en),
      .xdata         (forwarded_rs1),
      .xstride       (forwarded_rs2),
      .fdata         (fp_a_ex),
      .vill          (vtype_q[XLEN-1]),
      .vl            (vl_q),
      .vsew          (vtype_q[5:3]),
      .vlmul         (vtype_q[2:0]),
      .csr_we        (vec_csr_we),
      .csr_waddr     (vec_csr_waddr),
      .csr_wdata     (vec_csr_wdata),
      .csr_wait      (vec_csr_wait),
      .vxrm          (vec_vxrm),
      .vxsat         (vec_vxsat),
      .frm           (frm_q),
      .fflags        (vec_fflags),
      .vstart_set    (vec_vstart_set),
      .mem_rdata     (read_line),
      .mem_ready     (vmem_ready),
      .mem_req       (vmem_req),
      .mem_addr      (vmem_addr),
      .mem_wdata     (vmem_wdata),
      .mem_wstrb     (vmem_wstrb),
      .mem_misaligned(vec_misaligned),
      .mem_bad_addr  (vec_bad_addr),
      .xreg_valid    (vec_xreg_valid),
      .xreg_result   (vec_xreg_result),
      .is_vector     (vec_is_vector),
      .vec_hold      (vec_hold),
      .vec_idle      (vec_idle),
      .load_pending  (vec_load_pending),
      .store_pending (vec_store_pending)
  );
  /* verilator lint_on PINCONNECTEMPTY */

`ifdef RISCV_FORMAL
  logic [        7:0] csr_vtype_bits;
  logic               csr_vtype_ill;
  logic [VstartW-1:0] csr_vstart;
`endif

  csr #(
      .XLEN(XLEN),
      .VLEN(VLEN)
  ) csr_inst (
`ifdef RISCV_FORMAL
      .dbg_vtype_bits(csr_vtype_bits),
      .dbg_vtype_ill(csr_vtype_ill),
      .dbg_vstart(csr_vstart),
      .dbg_csr_wdata(dbg_csr_wdata),
      .dbg_mscratch(dbg_mscratch),
      .dbg_mstatus(dbg_mstatus),
      .dbg_mtvec(dbg_mtvec),
      .dbg_mepc(dbg_mepc),
      .dbg_mcause(dbg_mcause),
      .dbg_mtval(dbg_mtval),
      .dbg_mie(dbg_mie),
      .dbg_mip(dbg_mip),
      .dbg_mcycle(dbg_mcycle),
      .dbg_minstret(dbg_minstret),
      .dbg_mcycleh(dbg_mcycleh),
      .dbg_minstreth(dbg_minstreth),
      .dbg_fflags(dbg_fflags),
`endif
      .clk(clk),
      .core_en(core_en && commit_valid),
      .cycle_en(core_en),
      .rst_n(rst_n),
      .csr_access(csr_access_ex && commit_valid),
      .csr_addr(instr_ex[31:20]),
      .funct3(funct3_ex),
      .rs1_data(forwarded_rs1),
      .zimm(instr_ex[19:15]),
      .pc(pc_ex),
      .bad_addr(bad_addr),
      .exc_illegal((exc_illegal_ex || exc_vec_encoding) && commit_valid),
      .exc_ecall(is_ecall_ex && commit_valid),
      .exc_ebreak(is_ebreak_ex && commit_valid),
      .exc_instr_misaligned(exc_instr_misaligned),
      .exc_load_misaligned(exc_load_misaligned),
      .exc_store_misaligned(exc_store_misaligned),
      .is_mret(is_mret_ex && commit_valid),
      .timer_irq(timer_irq && commit_valid),
      .ext_irq(ext_irq && commit_valid),
      .csr_rdata(csr_rdata),
      .trap_taken(trap_taken),
      .trap_vector(trap_vector),
      .mret_taken(mret_taken),
      .mepc_out(mepc_out),
      .is_vset(is_vset && commit_valid),
      .vl_d(vl_d),
      .vtype_d(vtype_d),
      .is_vec_instr((is_vset || vec_is_vector) && commit_valid),
      .vl_q(vl_q),
      .vtype_q(vtype_q),
      .vec_vxrm(vec_vxrm),
      .vec_vxsat(vec_vxsat),
      .vec_csr_we(vec_csr_we),
      .vec_csr_waddr(vec_csr_waddr),
      .vec_csr_wdata(vec_csr_wdata),
      .is_fp_instr         ((((fp_op_ex || fp_load_ex || fp_store_ex) && valid_ex) || vec_fp_ex) &&
                            commit_valid),
      .fp_state_we(frd_write_ex || fp_load_ex),
      .fp_flags_we(fxrd_write_ex && fp_xvalid),
      .fp_flags(fp_xflags),
      .fp_wb_flags_we(fp_wb_valid),
      .fp_wb_flags(fp_wb_flags),
      .vec_fflags(vec_fflags),
      .frm_q(frm_q),
      .vstart_set(vec_vstart_set)
  );

  always_comb begin
    if (is_muldiv_ex) result_ex = muldiv_result;
    else if (fxrd_write_ex) result_ex = fp_xresult;
    else if (vec_xreg_valid) result_ex = vec_xreg_result;
    else if (is_vset) result_ex = {{XLEN - VlW{1'b0}}, vl_d};
    else if (csr_access_ex) result_ex = csr_rdata;
    else result_ex = alu_result;
  end

  assign flush = mispredict | trap_taken | mret_taken;

  always_comb begin
    if (trap_taken) flush_target = trap_vector;
    else if (mret_taken) flush_target = mepc_out;
    else flush_target = correct_pc;
  end

  // Deferred redirect
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      redirect_pending <= 1'b0;
      redirect_target  <= '0;
    end else if (core_en) begin
      if (flush && !pc_en) begin
        redirect_pending <= 1'b1;
        redirect_target  <= flush_target;
      end else if (pc_en) begin
        redirect_pending <= 1'b0;
      end
    end
  end

  // EX/MEM
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      reg_write_mem <= 1'b0;
      mem_write_mem <= 1'b0;
      fp_load_mem   <= 1'b0;
    end else if (core_en) begin
      if (exmem_bubble) begin  // Inject NOP
        reg_write_mem <= 1'b0;
        mem_write_mem <= 1'b0;
        fp_load_mem   <= 1'b0;
      end else if (exmem_en) begin
        alu_result_mem <= result_ex;
        pc_plus4_mem   <= pc_plus4_ex;
        write_data_mem <= fp_store_ex ? fp_b_ex : forwarded_rs2;
        mem_write_mem  <= mem_write_ex && !trap_taken;
        fp_load_mem    <= fp_load_ex && valid_ex && !trap_taken;
        funct3_mem     <= funct3_ex;
        reg_write_mem  <= reg_write_ex && !trap_taken;
        result_src_mem <= result_src_ex;
        rd_mem         <= rd_ex;
      end
    end
  end

  assign write_data = write_data_mem;
  assign mem_write  = mem_write_mem;
  assign mem_addr   = alu_result_mem;

  // Addressed word of line
  assign read_data  = read_line[alu_result_mem[WordLsb+:BlkOffLen]*XLEN+:XLEN];

  // Memory access
  always_comb begin
    // Load data
    ld_byte = read_data[{alu_result_mem[ByteOffW-1:0], 3'b000}+:8];
    ld_half = read_data[{alu_result_mem[ByteOffW-1:1], 4'b0000}+:16];
    case (funct3_mem)
      3'b000:  load_data = XLEN'($signed(ld_byte));  // lb
      3'b100:  load_data = XLEN'(ld_byte);  // lbu
      3'b001:  load_data = XLEN'($signed(ld_half));  // lh
      3'b101:  load_data = XLEN'(ld_half);  // lhu
      default: load_data = read_data;  // lw
    endcase

    // Store data
    store_data  = write_data_mem;
    store_wstrb = '0;
    if (mem_write_mem) begin
      case (funct3_mem)
        3'b000: begin  // sb
          store_data  = {StrbW{write_data_mem[7:0]}};
          store_wstrb = StrbW'(1) << alu_result_mem[ByteOffW-1:0];
        end
        3'b001: begin  // sh
          store_data  = {(StrbW / 2) {write_data_mem[15:0]}};
          store_wstrb = StrbW'(3) << alu_result_mem[ByteOffW-1:0];
        end
        3'b010: begin  // sw
          store_data  = write_data_mem;
          store_wstrb = '1;
        end
        default: ;
      endcase
    end
  end

  assign pc_plus4 = pc + 4;

  // MEM/WB
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      reg_write_wb <= 1'b0;
      fp_load_wb   <= 1'b0;
    end else if (core_en && memwb_bubble) begin
      reg_write_wb <= 1'b0;
      fp_load_wb   <= 1'b0;
    end else if (core_en && memwb_en) begin
      result_src_wb <= result_src_mem;
      alu_result_wb <= alu_result_mem;
      pc_plus4_wb   <= pc_plus4_mem;
      reg_write_wb  <= reg_write_mem;
      fp_load_wb    <= fp_load_mem;
      load_data_wb  <= load_data;
      rd_wb         <= rd_mem;
    end
  end

  // Writeback
  always_comb begin
    case (result_src_wb)
      2'd0:    result = alu_result_wb;
      2'd1:    result = load_data_wb;
      2'd2:    result = pc_plus4_wb;
      default: result = '0;
    endcase
  end

  always_comb begin
    if (redirect_pending) pc_next = redirect_target;
    else if (trap_taken) pc_next = trap_vector;
    else if (mret_taken) pc_next = mepc_out;
    else if (mispredict) pc_next = correct_pc;
    else if (predict_taken) pc_next = predict_target;
    else pc_next = pc_plus4;
  end

`ifdef RISCV_FORMAL
  // RVFI shadow pipeline
  logic [XLEN-1:0] rvfi_insn_ex, rvfi_insn_mem, rvfi_insn_wb;
  logic [XLEN-1:0] rvfi_pc_mem, rvfi_pc_wb;
  logic [XLEN-1:0] rvfi_pcw_mem, rvfi_pcw_wb;
  logic [XLEN-1:0] rvfi_rs1d_mem, rvfi_rs1d_wb;
  logic [XLEN-1:0] rvfi_rs2d_mem, rvfi_rs2d_wb;
  logic [ XLEN-1:0] rvfi_memrd_wb;
  logic [StrbW-1:0] rvfi_wstrb_wb;
  logic [ XLEN-1:0] rvfi_wdata_wb;
  logic rvfi_trap_mem, rvfi_trap_wb;
  logic [    VlW-1:0] rvfi_vl_wb;
  logic [        7:0] rvfi_vtype_bits_wb;
  logic               rvfi_vtype_ill_wb;
  logic [VstartW-1:0] rvfi_vstart_wb;

  // Follows stage enables
  always_ff @(posedge clk) begin
    if (idex_en) rvfi_insn_ex <= instr_id;

    if (exmem_en) begin
      rvfi_insn_mem <= rvfi_insn_ex;
      rvfi_pc_mem   <= pc_ex;
      rvfi_rs1d_mem <= forwarded_rs1;
      rvfi_rs2d_mem <= forwarded_rs2;
      rvfi_trap_mem <= trap_taken;
      if (trap_taken) rvfi_pcw_mem <= trap_vector;
      else if (mret_taken) rvfi_pcw_mem <= mepc_out;
      else if (pc_src_ex) rvfi_pcw_mem <= pc_target_ex;
      else rvfi_pcw_mem <= pc_ex + 4;
    end

    if (memwb_en) begin
      rvfi_insn_wb  <= rvfi_insn_mem;
      rvfi_pc_wb    <= rvfi_pc_mem;
      rvfi_pcw_wb   <= rvfi_pcw_mem;
      rvfi_rs1d_wb  <= rvfi_rs1d_mem;
      rvfi_rs2d_wb  <= rvfi_rs2d_mem;
      rvfi_trap_wb  <= rvfi_trap_mem;
      rvfi_memrd_wb <= read_data;
      rvfi_wstrb_wb <= store_wstrb;
      rvfi_wdata_wb <= store_data;
      // Vector snapshot
      rvfi_vl_wb <= vl_q;
      rvfi_vtype_bits_wb <= csr_vtype_bits;
      rvfi_vtype_ill_wb <= csr_vtype_ill;
      rvfi_vstart_wb <= csr_vstart;
    end
  end

  assign dbg_valid      = valid_wb;
  assign dbg_ex_commit  = commit_valid && !trap_taken;
  assign dbg_ex_insn    = instr_ex;
  assign dbg_insn       = rvfi_insn_wb;
  assign dbg_pc_rdata   = rvfi_pc_wb;
  assign dbg_pc_wdata   = rvfi_pcw_wb;
  assign dbg_rs1_rdata  = rvfi_rs1d_wb;
  assign dbg_rs2_rdata  = rvfi_rs2d_wb;
  assign dbg_rd_wdata   = result;
  assign dbg_reg_write  = reg_write_wb;
  assign dbg_mem_addr   = alu_result_wb;
  assign dbg_mem_wmask  = rvfi_wstrb_wb;
  assign dbg_mem_wdata  = rvfi_wdata_wb;
  assign dbg_mem_rdata  = rvfi_memrd_wb;
  assign dbg_trap       = rvfi_trap_wb;
  assign dbg_vl         = rvfi_vl_wb;
  assign dbg_vtype_bits = rvfi_vtype_bits_wb;
  assign dbg_vtype_ill  = rvfi_vtype_ill_wb;
  assign dbg_vstart     = rvfi_vstart_wb;
`endif

`ifndef SYNTHESIS
  // Pipeline view taps
  (* keep *) logic [XLEN-1:0] dbg_pc_f, dbg_pc_d, dbg_pc_e, dbg_pc_m, dbg_pc_w;
  (* keep *) logic [XLEN-1:0] dbg_insn_f, dbg_insn_d, dbg_insn_e, dbg_insn_m, dbg_insn_w;
  (* keep *) logic dbg_valid_f, dbg_valid_d, dbg_valid_e, dbg_valid_m, dbg_valid_w;
  (* keep *) logic dbg_hold_f, dbg_hold_d, dbg_hold_e, dbg_hold_m;
  (* keep *) logic dbg_en_d, dbg_en_e, dbg_en_m, dbg_en_w;
  (* keep *) logic dbg_bubble_d, dbg_bubble_e, dbg_bubble_m;
  (* keep *) logic dbg_flush;
  (* keep *) logic [2:0] dbg_redirect_src;
  (* keep *) logic dbg_stall;
  (* keep *) logic [1:0] dbg_forward_a, dbg_forward_b;
  (* keep *) logic dbg_rf_we;
  (* keep *) logic [4:0] dbg_rf_waddr;
  (* keep *) logic [XLEN-1:0] dbg_rf_wdata;
  (* keep *) logic dbg_bus_req;
  (* keep *) logic [XLEN-1:0] dbg_bus_addr;
  (* keep *) logic [StrbW-1:0] dbg_bus_wstrb;
  (* keep *) logic [XLEN-1:0] dbg_bus_wdata;

  assign dbg_pc_f    = pc;
  assign dbg_insn_f  = instr;
  assign dbg_valid_f = !ifid_bubble;

  assign dbg_pc_d    = pc_id;
  assign dbg_insn_d  = instr_id;
  assign dbg_valid_d = valid_id;

  assign dbg_pc_e    = pc_ex;
  assign dbg_insn_e  = instr_ex;
  assign dbg_valid_e = valid_ex;

  assign dbg_valid_m = valid_mem;
  assign dbg_valid_w = valid_wb;

`ifdef RISCV_FORMAL
  // Reuse RVFI shadow
  assign dbg_pc_m   = rvfi_pc_mem;
  assign dbg_pc_w   = rvfi_pc_wb;
  assign dbg_insn_m = rvfi_insn_mem;
  assign dbg_insn_w = rvfi_insn_wb;
`else
  // Carry past execute
  always_ff @(posedge clk) begin
    if (exmem_en) begin
      dbg_pc_m   <= pc_ex;
      dbg_insn_m <= instr_ex;
    end
    if (memwb_en) begin
      dbg_pc_w   <= dbg_pc_m;
      dbg_insn_w <= dbg_insn_m;
    end
  end
`endif

  assign dbg_hold_f   = if_hold;
  assign dbg_hold_d   = id_hold;
  assign dbg_hold_e   = ex_hold;
  assign dbg_hold_m   = mem_hold;

  assign dbg_en_d     = ifid_en;
  assign dbg_en_e     = idex_en;
  assign dbg_en_m     = exmem_en;
  assign dbg_en_w     = memwb_en;

  assign dbg_bubble_d = ifid_bubble;
  assign dbg_bubble_e = idex_bubble;
  assign dbg_bubble_m = exmem_bubble;

  assign dbg_flush    = flush;

  // Mirrors pc_next priority
  always_comb begin
    if (redirect_pending) dbg_redirect_src = 3'd5;
    else if (trap_taken) dbg_redirect_src = 3'd1;
    else if (mret_taken) dbg_redirect_src = 3'd2;
    else if (mispredict) dbg_redirect_src = 3'd3;
    else if (predict_taken) dbg_redirect_src = 3'd4;
    else dbg_redirect_src = 3'd0;
  end

  assign dbg_stall     = hazard_stall;
  assign dbg_forward_a = forward_a;
  assign dbg_forward_b = forward_b;

  assign dbg_rf_we     = reg_write_wb;
  assign dbg_rf_waddr  = rd_wb;
  assign dbg_rf_wdata  = result;

  assign dbg_bus_req   = dmem_req;
  assign dbg_bus_addr  = alu_result_mem;
  assign dbg_bus_wstrb = store_wstrb;
  assign dbg_bus_wdata = store_data;
`endif

endmodule

`default_nettype wire
