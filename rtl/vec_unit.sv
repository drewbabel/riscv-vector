`default_nettype none

module vec_unit
  import vec_pkg::*;
#(
    parameter  int AWIDTH   = 5,
    parameter  int VLEN     = 128,
    localparam int MaxElems = VLEN / 8
) (
`ifdef RISCV_FORMAL
    output logic [       7:0] dbg_vec_tag,
    output logic              dbg_vec_retire,
    output logic [AWIDTH-1:0] dbg_vec_vd,
    output logic [       3:0] dbg_vec_regs,
    output logic              dbg_vec_idle,
`endif
    input logic clk,
    input logic rst_n,
    input logic core_en,

    // Execute stage
    input logic [31:0] instr,
    input logic        instr_valid,
    input logic        cancel,
    input logic [31:0] xdata,
    input logic [31:0] xstride,

    // Live configuration
    input logic       vill,
    input logic [7:0] vl,
    input logic [2:0] vsew,
    input logic [2:0] vlmul,
    input logic [1:0] vxrm,

    // Memory port
    input  logic [31:0] mem_rdata,
    input  logic        mem_ready,
    output logic        mem_req,
    output logic [31:0] mem_addr,
    output logic [31:0] mem_wdata,
    output logic [ 3:0] mem_wstrb,

    // Memory checks
    output logic        mem_misaligned,
    output logic [31:0] mem_bad_addr,

    // Pipeline handshake
    output logic is_vector,
    output logic vec_hold,
    output logic vec_idle,
    output logic load_pending,
    output logic store_pending
);

  // Decoded fields
  logic                    dec_valid;
  vec_op_e                 dec_op;
  vec_src_e                dec_src;
  logic                    dec_vm;
  logic     [  AWIDTH-1:0] dec_vs1;
  logic     [  AWIDTH-1:0] dec_vs2;
  logic     [  AWIDTH-1:0] dec_vd;
  logic     [         4:0] dec_simm;
  logic                    dec_reads_vd;
  logic     [         1:0] dec_width;
  logic                    dec_whole;
  logic                    dec_strided;

  // Issued instruction
  vec_op_e                 seq_op;
  vec_src_e                seq_src;
  logic                    seq_start;
  logic     [  AWIDTH-1:0] seq_vs1;
  logic     [  AWIDTH-1:0] seq_vs2;
  logic     [  AWIDTH-1:0] seq_vd;
  logic                    seq_vm;
  logic                    seq_reads_vd;
  logic     [         4:0] seq_simm;
  logic     [        31:0] seq_xdata;
  logic     [        31:0] seq_xstride;
  logic     [         7:0] seq_vl;
  logic     [         2:0] seq_vsew;
  logic     [         2:0] seq_vlmul;

  // Sequencer outputs
  logic     [  AWIDTH-1:0] raddr1;
  logic     [  AWIDTH-1:0] raddr2;
  logic     [  AWIDTH-1:0] raddr3;
  logic     [  AWIDTH-1:0] waddr;
  logic     [    VLEN-1:0] wstrb;
  logic                    wen;
  logic     [         7:0] elem_base;
  logic                    seq_busy;
  logic                    seq_done;

  // Register file data
  logic     [    VLEN-1:0] rdata1;
  logic     [    VLEN-1:0] rdata2;
  logic     [    VLEN-1:0] rdata0;
  logic     [    VLEN-1:0] alu_result;

  // Memory sequencer
  logic                    seq_mem;
  logic     [  AWIDTH-1:0] m_raddr;
  logic                    m_wen;
  logic     [    VLEN-1:0] m_wstrb;
  logic     [    VLEN-1:0] m_wdata;
  logic                    m_busy;
  logic                    m_done;

  logic     [MaxElems-1:0] mask_bits;

  // Mask is data
  logic v0_is_data;
  always_comb begin
    case (seq_op)
      VEC_ADC, VEC_SBC, VEC_MERGE: v0_is_data = 1'b1;
      default: v0_is_data = 1'b0;
    endcase
  end

  // Round three subset
  logic                    op_ready;
  logic                    accept_now;
  always_comb begin
    case (dec_op)
      VEC_ADD, VEC_SUB, VEC_RSUB, VEC_AND, VEC_OR, VEC_XOR, VEC_SLL, VEC_SRL, VEC_SRA, VEC_MINU,
      VEC_MIN, VEC_MAXU, VEC_MAX, VEC_ADC, VEC_SBC, VEC_MERGE, VEC_LOAD, VEC_STORE:
      op_ready = 1'b1;
      default: op_ready = 1'b0;
    endcase
  end

  // Memory snapshot
  logic               dec_mem;
  logic signed [ 3:0] emul_log2;
  logic               emul_ok;
  logic        [ 7:0] issue_vl;
  logic        [ 2:0] issue_vsew;
  logic        [31:0] issue_stride;
  logic               base_off;
  logic               stride_off;

  assign dec_mem = (dec_op == VEC_LOAD) || (dec_op == VEC_STORE);
  assign emul_log2 = 4'($signed(vlmul)) + $signed({2'b00, dec_width}) - $signed({1'b0, vsew});
  assign emul_ok = !dec_mem || dec_whole || (emul_log2 >= -4'sd3 && emul_log2 <= 4'sd3);

  assign issue_vl = (dec_mem && dec_whole) ? 8'(VLEN >> (3 + dec_width)) : vl;
  assign issue_vsew = dec_mem ? {1'b0, dec_width} : vsew;
  assign issue_stride = dec_strided ? xstride : (32'd1 << dec_width);

  // Alignment check
  assign base_off = (dec_width == 2'd2) ? (xdata[1:0] != 2'b00)
      : ((dec_width == 2'd1) && xdata[0]);
  assign stride_off = (dec_width == 2'd2) ? (issue_stride[1:0] != 2'b00)
      : ((dec_width == 2'd1) && issue_stride[0]);
  assign mem_misaligned = dec_mem && is_vector
      && (((issue_vl != 8'd0) && base_off) || ((issue_vl > 8'd1) && stride_off));
  assign mem_bad_addr = base_off ? xdata : (xdata + issue_stride);

  assign is_vector = dec_valid && op_ready && (dec_whole || !vill) && emul_ok;
  assign accept_now = instr_valid && is_vector;

  /* verilator lint_off PINCONNECTEMPTY */

  vec_decode u_decode (
      .instr(instr),
      .valid(dec_valid),
      .op(dec_op),
      .src(dec_src),
      .eew(),
      .vm(dec_vm),
      .vs1(dec_vs1),
      .vs2(dec_vs2),
      .vd(dec_vd),
      .simm(dec_simm),
      .reads_vd(dec_reads_vd),
      .reads_xreg(),
      .writes_xreg(),
      .writes_mask(),
      .mem_width(dec_width),
      .mem_whole(dec_whole),
      .mem_strided(dec_strided)
  );

  vec_issue #(
      .AWIDTH(AWIDTH)
  ) u_issue (
      .clk(clk),
      .rst_n(rst_n),
      .core_en(core_en),
      .instr_valid(accept_now),
      .cancel(cancel),
      .op(dec_op),
      .src(dec_src),
      .vs1(dec_vs1),
      .vs2(dec_vs2),
      .vd(dec_vd),
      .vm(dec_vm),
      .reads_vd(dec_reads_vd),
      .simm(dec_simm),
      .xdata(xdata),
      .xstride(issue_stride),
      .vl(issue_vl),
      .vsew(issue_vsew),
      .vlmul(vlmul),
      .vxrm(vxrm),
      .seq_busy(seq_busy || m_busy),
      .seq_done(seq_done || m_done),
      .seq_start(seq_start),
      .seq_op(seq_op),
      .seq_src(seq_src),
      .seq_vs1(seq_vs1),
      .seq_vs2(seq_vs2),
      .seq_vd(seq_vd),
      .seq_vm(seq_vm),
      .seq_reads_vd(seq_reads_vd),
      .seq_simm(seq_simm),
      .seq_xdata(seq_xdata),
      .seq_xstride(seq_xstride),
      .seq_vl(seq_vl),
      .seq_vsew(seq_vsew),
      .seq_vlmul(seq_vlmul),
      .seq_vxrm(),
      .vec_hold(vec_hold),
      .vec_idle(vec_idle),
      .load_pending(load_pending),
      .store_pending(store_pending)
  );

  // Single width only
  vec_sequencer #(
      .AWIDTH(AWIDTH),
      .VLEN  (VLEN)
  ) u_sequencer (
      .clk(clk),
      .rst_n(rst_n),
      .start(seq_start && !seq_mem),
      .vs1(seq_vs1),
      .vs2(seq_vs2),
      .vd(seq_vd),
      .reads_vd(seq_reads_vd),
      .vl(seq_vl),
      .vsew(seq_vsew),
      .vlmul(seq_vlmul),
      .vm(seq_vm || v0_is_data),
      .mask_bits(mask_bits),
      .pass_log2(2'd0),
      .raddr1(raddr1),
      .raddr2(raddr2),
      .raddr3(raddr3),
      .waddr(waddr),
      .wstrb(wstrb),
      .wen(wen),
      .elem_base(elem_base),
      .busy(seq_busy),
      .done(seq_done)
  );

  assign seq_mem = (seq_op == VEC_LOAD) || (seq_op == VEC_STORE);

  vec_mem #(
      .AWIDTH(AWIDTH),
      .VLEN  (VLEN)
  ) u_mem (
      .clk(clk),
      .rst_n(rst_n),
      .core_en(core_en),
      .start(seq_start && seq_mem),
      .load(seq_op == VEC_LOAD),
      .vm(seq_vm),
      .vd(seq_vd),
      .count(seq_vl),
      .width(seq_vsew[1:0]),
      .base(seq_xdata),
      .stride(seq_xstride),
      .v0(rdata0),
      .rdata(rdata1),
      .raddr(m_raddr),
      .wen(m_wen),
      .wstrb(m_wstrb),
      .wdata(m_wdata),
      .mem_rdata(mem_rdata),
      .mem_ready(mem_ready),
      .mem_req(mem_req),
      .mem_addr(mem_addr),
      .mem_wdata(mem_wdata),
      .mem_wstrb(mem_wstrb),
      .busy(m_busy),
      .done(m_done)
  );

  vec_regfile #(
      .AWIDTH(AWIDTH),
      .VLEN  (VLEN)
  ) u_regfile (
      .clk(clk),
      .core_en(core_en),
      .we(seq_mem ? m_wen : wen),
      .wstrb(seq_mem ? m_wstrb : wstrb),
      .waddr(seq_mem ? m_raddr : waddr),
      .wdata(seq_mem ? m_wdata : alu_result),
      .raddr1(seq_mem ? m_raddr : raddr1),
      .raddr2(raddr2),
      .raddr3(raddr3),
      .rdata1(rdata1),
      .rdata2(rdata2),
      .rdata3(),
      .rdata0(rdata0)
  );

  /* verilator lint_on PINCONNECTEMPTY */

  // Live mask bits

  for (genvar e = 0; e < MaxElems; e++) begin : g_mask
    logic [8:0] sel;
    assign sel = 9'(elem_base) + 9'(e);
    assign mask_bits[e] = (sel < 9'(VLEN)) ? rdata0[sel[6:0]] : 1'b0;
  end

  vec_alu #(
      .DLEN(VLEN)
  ) u_alu (
      .op(seq_op),
      .src(seq_src),
      .vsew(seq_vsew),
      .vm(seq_vm),
      .mask_bits(mask_bits),
      .vs2_data(rdata2),
      .vs1_data(rdata1),
      .xdata(seq_xdata),
      .simm(seq_simm),
      .result(alu_result)
  );

`ifdef RISCV_FORMAL
  // Retirement export
  logic [7:0] tag_q;
  always_ff @(posedge clk) begin
    if (!rst_n) tag_q <= 8'd0;
    else if (core_en && (seq_done || m_done)) tag_q <= tag_q + 8'd1;
  end

  // Registers written
  logic [3:0] regs_written;
  always_comb begin
    if (!seq_mem) regs_written = seq_vlmul[2] ? 4'd1 : 4'(4'd1 << seq_vlmul[1:0]);
    else if (seq_op == VEC_STORE || seq_vl == 8'd0) regs_written = 4'd0;
    else regs_written = 4'((seq_vl - 8'd1) >> (3'd4 - 3'(seq_vsew[1:0]))) + 4'd1;
  end

  assign dbg_vec_tag    = tag_q;
  assign dbg_vec_retire = seq_done || m_done;
  assign dbg_vec_vd     = seq_vd;
  assign dbg_vec_regs   = regs_written;
  assign dbg_vec_idle   = vec_idle;
`endif

endmodule

`default_nettype wire
