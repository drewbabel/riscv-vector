`default_nettype none

module vec_unit
  import vec_pkg::*;
#(
    parameter  int AWIDTH   = 5,
    parameter  int VLEN     = 128,
    localparam int MaxElems = VLEN / 8
) (
    input logic clk,
    input logic rst_n,
    input logic core_en,

    // Execute stage
    input logic [31:0] instr,
    input logic        instr_valid,
    input logic [31:0] xdata,

    // Live configuration
    input logic [7:0] vl,
    input logic [2:0] vsew,
    input logic [2:0] vlmul,
    input logic [1:0] vxrm,

    // Pipeline handshake
    output logic is_vector,
    output logic vec_hold,
    output logic vec_idle
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

  logic     [MaxElems-1:0] mask_bits;

  // Round three subset
  logic                    op_ready;
  always_comb begin
    case (dec_op)
      VEC_ADD, VEC_SUB, VEC_RSUB, VEC_AND, VEC_OR, VEC_XOR, VEC_SLL, VEC_SRL, VEC_SRA, VEC_MINU,
      VEC_MIN, VEC_MAXU, VEC_MAX, VEC_ADC, VEC_SBC, VEC_MERGE:
      op_ready = 1'b1;
      default: op_ready = 1'b0;
    endcase
  end

  assign is_vector = instr_valid && dec_valid && op_ready;

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
      .writes_mask()
  );

  vec_issue #(
      .AWIDTH(AWIDTH)
  ) u_issue (
      .clk(clk),
      .rst_n(rst_n),
      .core_en(core_en),
      .instr_valid(is_vector),
      .op(dec_op),
      .src(dec_src),
      .vs1(dec_vs1),
      .vs2(dec_vs2),
      .vd(dec_vd),
      .vm(dec_vm),
      .reads_vd(dec_reads_vd),
      .simm(dec_simm),
      .xdata(xdata),
      .vl(vl),
      .vsew(vsew),
      .vlmul(vlmul),
      .vxrm(vxrm),
      .seq_busy(seq_busy),
      .seq_done(seq_done),
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
      .seq_vl(seq_vl),
      .seq_vsew(seq_vsew),
      .seq_vlmul(seq_vlmul),
      .seq_vxrm(),
      .vec_hold(vec_hold),
      .vec_idle(vec_idle)
  );

  // Single width only
  vec_sequencer #(
      .AWIDTH(AWIDTH),
      .VLEN  (VLEN)
  ) u_sequencer (
      .clk(clk),
      .rst_n(rst_n),
      .start(seq_start),
      .vs1(seq_vs1),
      .vs2(seq_vs2),
      .vd(seq_vd),
      .reads_vd(seq_reads_vd),
      .vl(seq_vl),
      .vsew(seq_vsew),
      .vlmul(seq_vlmul),
      .vm(seq_vm),
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

  vec_regfile #(
      .AWIDTH(AWIDTH),
      .VLEN  (VLEN)
  ) u_regfile (
      .clk(clk),
      .core_en(core_en),
      .we(wen),
      .wstrb(wstrb),
      .waddr(waddr),
      .wdata(alu_result),
      .raddr1(raddr1),
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

endmodule

`default_nettype wire
