`default_nettype none

module vec_unit
  import vec_pkg::*;
  import csr_pkg::VxrmAddr;
  import csr_pkg::VxsatAddr;
  import csr_pkg::VcsrAddr;
#(
    parameter  int AWIDTH   = 5,
    parameter  int VLEN     = 128,
    localparam int MaxElems = VLEN / 8
) (
`ifdef RISCV_FORMAL
    output logic [       7:0] dbg_vec_tag,
    output logic              dbg_vec_retire,
    output logic [      31:0] dbg_vec_wregs,
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

    // Fixed-point control
    input  logic        csr_we,
    input  logic [11:0] csr_waddr,
    input  logic [31:0] csr_wdata,
    input  logic        csr_wait,
    output logic [ 1:0] vxrm,
    output logic        vxsat,

    // Scalar result
    output logic        xreg_valid,
    output logic [31:0] xreg_result,

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
  vec_eew_e                dec_eew;
  logic                    dec_vm;
  logic     [  AWIDTH-1:0] dec_vs1;
  logic     [  AWIDTH-1:0] dec_vs2;
  logic     [  AWIDTH-1:0] dec_vd;
  logic     [         4:0] dec_simm;
  logic                    dec_reads_vd;
  logic                    dec_reads_xreg;
  logic                    dec_writes_xreg;
  logic                    dec_writes_mask;
  logic     [         1:0] dec_width;
  logic                    dec_whole;
  logic                    dec_mask_ls;
  logic                    dec_strided;

  // Issued instruction
  vec_op_e                 seq_op;
  vec_src_e                seq_src;
  vec_eew_e                seq_eew;
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
  logic     [         1:0] seq_vxrm;

  // Sequencer outputs
  logic     [  AWIDTH-1:0] raddr1;
  logic     [  AWIDTH-1:0] raddr2;
  logic     [  AWIDTH-1:0] raddr3;
  logic     [  AWIDTH-1:0] waddr;
  logic     [    VLEN-1:0] wstrb;
  logic                    wen;
  logic     [         6:0] s1_off;
  logic     [         6:0] s2_off;
  logic     [         6:0] d_off;
  logic     [         7:0] elem_base;
  logic     [         4:0] elem_count;
  logic     [MaxElems-1:0] elem_active;
  logic                    seq_last;
  logic                    seq_busy;
  logic                    seq_done;

  // Register file data
  logic     [    VLEN-1:0] rdata1;
  logic     [    VLEN-1:0] rdata2;
  logic     [    VLEN-1:0] rdata3;
  logic     [    VLEN-1:0] rdata0;

  // Lane results
  logic     [    VLEN-1:0] alu_result;
  logic     [    VLEN-1:0] mixed_result;
  logic     [    VLEN-1:0] red_result;
  logic     [    VLEN-1:0] mask_result;
  logic     [        31:0] mask_xresult;
  logic     [    VLEN-1:0] raw_result;
  logic     [    VLEN-1:0] wdata;

  // Memory sequencer
  logic                    seq_mem;
  logic     [  AWIDTH-1:0] m_raddr;
  logic                    m_wen;
  logic     [    VLEN-1:0] m_wstrb;
  logic     [    VLEN-1:0] m_wdata;
  logic                    m_busy;
  logic                    m_done;

  logic     [MaxElems-1:0] mask_bits;
  logic                    issue_hold;

  // Instruction classes
  vec_cls_e                dec_cls;
  vec_cls_e                seq_cls;
  vec_geom_t               dec_geom_s;
  vec_geom_t               seq_geom_s;

  assign dec_cls = vec_class(dec_op);
  assign seq_cls = vec_class(seq_op);
  assign dec_geom_s = vec_geom(dec_op, dec_eew);
  assign seq_geom_s = vec_geom(seq_op, seq_eew);

  // Mask is data
  logic v0_is_data;
  always_comb begin
    case (seq_op)
      VEC_ADC, VEC_SBC, VEC_MERGE: v0_is_data = 1'b1;
      default: v0_is_data = 1'b0;
    endcase
  end

  // Element widths
  logic [2:0] lsew;
  logic [2:0] dec_ld;
  logic [2:0] dec_ls1;
  logic [2:0] dec_ls2;
  logic       width_legal;

  assign lsew = vsew + 3'd3;
  assign dec_ld = vec_rel_log2(dec_geom_s.d, lsew);
  assign dec_ls1 = vec_rel_log2(dec_geom_s.s1, lsew);
  assign dec_ls2 = vec_rel_log2(dec_geom_s.s2, lsew);
  assign width_legal = (dec_ld >= 3'd3) && (dec_ld <= 3'd5) && (dec_ls1 >= 3'd3)
      && (dec_ls1 <= 3'd5) && (dec_ls2 >= 3'd3) && (dec_ls2 <= 3'd5);

  // Scalar forms
  logic scalar_legal;
  assign scalar_legal = ((dec_cls != VEC_CLS_XS) && (dec_cls != VEC_CLS_SX)
      && (dec_cls != VEC_CLS_MLOG)) || dec_vm;

  // Memory snapshot
  logic               dec_mem;
  logic signed [ 3:0] emul_log2;
  logic               emul_ok;
  logic        [ 7:0] issue_vl;
  logic        [ 2:0] issue_vsew;
  logic        [31:0] issue_stride;
  logic               base_off;
  logic               stride_off;

  assign dec_mem = (dec_cls == VEC_CLS_MEM);
  assign emul_log2 = 4'($signed(vlmul)) + $signed({2'b00, dec_width}) - $signed({1'b0, vsew});
  assign emul_ok = !dec_mem || dec_whole || dec_mask_ls
      || (emul_log2 >= -4'sd3 && emul_log2 <= 4'sd3);

  assign issue_vl = (dec_mem && dec_whole) ? 8'(VLEN >> (3 + dec_width))
      : ((dec_mem && dec_mask_ls) ? 8'((vl + 8'd7) >> 3)
      : ((dec_cls == VEC_CLS_XS) ? 8'd1 : vl));
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

  // Register count of a group
  function automatic logic [5:0] group_regs(input logic signed [3:0] emul);
    if (emul <= 4'sd0) group_regs = 6'd1;
    else group_regs = 6'(6'd1 << emul[2:0]);
  endfunction

  // Multiplier in range
  function automatic logic width_in_range(input logic signed [3:0] emul, input logic used);
    width_in_range = !used || ((emul >= -4'sd3) && (emul <= 4'sd3));
  endfunction

  // Permitted overlap
  function automatic logic pair_ok(input logic [5:0] bd, input logic [5:0] nd,
                                   input logic [2:0] wd, input logic [5:0] bs,
                                   input logic [5:0] ns, input logic [2:0] ws,
                                   input logic src_whole);
    logic hit;
    begin
      hit = (bd < (bs + ns)) && (bs < (bd + nd));
      if (!hit) pair_ok = 1'b1;
      else if (wd == ws) pair_ok = 1'b1;
      else if (wd < ws) pair_ok = (bd == bs);
      else pair_ok = src_whole && (bs == ((bd + nd) - ns));
    end
  endfunction

  // Group legality
  logic               dec_store;
  logic               dec_ext;
  logic               has_vd;
  logic               uses_vs1;
  logic               uses_vs2;
  logic signed [ 3:0] lmul_log2;
  logic signed [ 3:0] d_delta;
  logic signed [ 3:0] s1_delta;
  logic signed [ 3:0] s2_delta;
  logic signed [ 3:0] d_emul;
  logic signed [ 3:0] s1_emul;
  logic signed [ 3:0] s2_emul;
  logic        [ 5:0] d_regs;
  logic        [ 5:0] s1_regs;
  logic        [ 5:0] s2_regs;
  logic               emul_legal;
  logic               align_ok;
  logic               overlap_ok;
  logic               mask_ok;
  logic               group_legal;

  assign dec_store = (dec_op == VEC_STORE);
  assign has_vd = (dec_cls != VEC_CLS_XS) && (dec_cls != VEC_CLS_XM);
  assign dec_ext = (dec_op == VEC_ZEXT2) || (dec_op == VEC_ZEXT4) || (dec_op == VEC_SEXT2)
      || (dec_op == VEC_SEXT4);
  assign uses_vs1 = !dec_mem && !dec_ext && (dec_cls != VEC_CLS_XS) && (dec_cls != VEC_CLS_SX)
      && (dec_cls != VEC_CLS_XM) && (dec_cls != VEC_CLS_MSET) && (dec_cls != VEC_CLS_IOTA)
      && (dec_src == VEC_SRC_VV);
  assign uses_vs2 = !dec_mem && (dec_cls != VEC_CLS_SX);

  assign lmul_log2 = 4'($signed(vlmul));
  assign d_delta = 4'($signed({1'b0, dec_ld})) - 4'($signed({1'b0, lsew}));
  assign s1_delta = 4'($signed({1'b0, dec_ls1})) - 4'($signed({1'b0, lsew}));
  assign s2_delta = 4'($signed({1'b0, dec_ls2})) - 4'($signed({1'b0, lsew}));

  assign d_emul = dec_mem ? ((dec_whole || dec_mask_ls) ? 4'sd0 : emul_log2)
      : ((dec_geom_s.single_write || dec_geom_s.mask_dest) ? 4'sd0 : (lmul_log2 + d_delta));
  assign s1_emul = (dec_geom_s.single_write || dec_geom_s.mask_src) ? 4'sd0
      : (lmul_log2 + s1_delta);
  assign s2_emul = ((dec_cls == VEC_CLS_XS) || dec_geom_s.mask_src) ? 4'sd0
      : (lmul_log2 + s2_delta);

  assign d_regs = group_regs(d_emul);
  assign s1_regs = uses_vs1 ? group_regs(s1_emul) : 6'd1;
  assign s2_regs = uses_vs2 ? group_regs(s2_emul) : 6'd1;

  assign emul_legal = width_in_range(d_emul, has_vd) && width_in_range(s1_emul, uses_vs1)
      && width_in_range(s2_emul, uses_vs2);

  assign align_ok = (!has_vd || ((6'(dec_vd) & (d_regs - 6'd1)) == 6'd0))
      && (!uses_vs1 || ((6'(dec_vs1) & (s1_regs - 6'd1)) == 6'd0))
      && (!uses_vs2 || ((6'(dec_vs2) & (s2_regs - 6'd1)) == 6'd0));

  assign overlap_ok = dec_mem || !has_vd || dec_geom_s.single_write || dec_geom_s.mask_dest
      || ((!uses_vs1 || pair_ok(6'(dec_vd), d_regs, dec_ld, 6'(dec_vs1), s1_regs, dec_ls1,
                                s1_emul >= 4'sd0))
      && (!uses_vs2 || pair_ok(6'(dec_vd), d_regs, dec_ld, 6'(dec_vs2), s2_regs, dec_ls2,
                               s2_emul >= 4'sd0)));

  assign mask_ok = dec_vm || dec_store || !has_vd || dec_geom_s.single_write
      || dec_writes_mask
      || (6'(dec_vd) >= d_regs);

  assign group_legal = emul_legal && align_ok && overlap_ok && mask_ok;

  // Rounding and saturation
  logic [1:0] vxrm_q;
  logic       vxsat_q;
  logic       sat_set;

  // Saturating lane pending
  assign sat_set = 1'b0;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      vxrm_q  <= 2'd0;
      vxsat_q <= 1'b0;
    end else begin
      if (sat_set) vxsat_q <= 1'b1;
      if (csr_we) begin
        case (csr_waddr)
          VxrmAddr:  vxrm_q <= csr_wdata[1:0];
          VxsatAddr: vxsat_q <= csr_wdata[0];
          VcsrAddr: begin
            vxrm_q  <= csr_wdata[2:1];
            vxsat_q <= csr_wdata[0];
          end
          default: ;
        endcase
      end
    end
  end

  assign vxrm  = vxrm_q;
  assign vxsat = vxsat_q;

  // Accepted instruction
  logic op_ready;
  logic accept_now;

  // Multiply lane pending
  assign op_ready = (dec_cls != VEC_CLS_NONE) && (dec_cls != VEC_CLS_MUL) && group_legal
      && (dec_mem || (width_legal && scalar_legal));
  assign is_vector = dec_valid && op_ready && (dec_whole || !vill) && emul_ok;
  assign accept_now = instr_valid && is_vector;

  vec_decode u_decode (
      .instr(instr),
      .valid(dec_valid),
      .op(dec_op),
      .src(dec_src),
      .eew(dec_eew),
      .vm(dec_vm),
      .vs1(dec_vs1),
      .vs2(dec_vs2),
      .vd(dec_vd),
      .simm(dec_simm),
      .reads_vd(dec_reads_vd),
      .reads_xreg(dec_reads_xreg),
      .writes_xreg(dec_writes_xreg),
      .writes_mask(dec_writes_mask),
      .mem_width(dec_width),
      .mem_whole(dec_whole),
      .mem_mask(dec_mask_ls),
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
      .eew(dec_eew),
      .writes_xreg(dec_writes_xreg),
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
      .vxrm(vxrm_q),
      .seq_busy(seq_busy || m_busy),
      .seq_done(seq_done || m_done),
      .seq_start(seq_start),
      .seq_op(seq_op),
      .seq_src(seq_src),
      .seq_eew(seq_eew),
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
      .seq_vxrm(seq_vxrm),
      .vec_hold(issue_hold),
      .vec_idle(vec_idle),
      .load_pending(load_pending),
      .store_pending(store_pending)
  );

  vec_sequencer #(
      .AWIDTH(AWIDTH),
      .VLEN  (VLEN)
  ) u_sequencer (
      .clk(clk),
      .rst_n(rst_n),
      .core_en(core_en),
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
      .v0_bits(rdata0),
      .d_rel(seq_geom_s.d),
      .s1_rel(seq_geom_s.s1),
      .s2_rel(seq_geom_s.s2),
      .mul_rate(seq_geom_s.mul_rate),
      .single_write(seq_geom_s.single_write),
      .mask_dest(seq_geom_s.mask_dest),
      .mask_whole(seq_geom_s.mask_whole),
      .mask_src(seq_geom_s.mask_src),
      .raddr1(raddr1),
      .raddr2(raddr2),
      .raddr3(raddr3),
      .waddr(waddr),
      .wstrb(wstrb),
      .wen(wen),
      .s1_off(s1_off),
      .s2_off(s2_off),
      .d_off(d_off),
      .elem_base(elem_base),
      .elem_count(elem_count),
      .elem_active(elem_active),
      .last(seq_last),
      .busy(seq_busy),
      .done(seq_done)
  );

  assign seq_mem = (seq_cls == VEC_CLS_MEM);

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

  // No vector write
  logic vreg_write;
  assign vreg_write = wen && (seq_cls != VEC_CLS_XS) && (seq_cls != VEC_CLS_XM);

  vec_regfile #(
      .AWIDTH(AWIDTH),
      .VLEN  (VLEN)
  ) u_regfile (
      .clk(clk),
      .core_en(core_en),
      .we(seq_mem ? m_wen : vreg_write),
      .wstrb(seq_mem ? m_wstrb : wstrb),
      .waddr(seq_mem ? m_raddr : waddr),
      .wdata(seq_mem ? m_wdata : wdata),
      .raddr1(seq_mem ? m_raddr : raddr1),
      .raddr2(raddr2),
      .raddr3(raddr3),
      .rdata1(rdata1),
      .rdata2(rdata2),
      .rdata3(rdata3),
      .rdata0(rdata0)
  );

  // Live mask bits
  for (genvar e = 0; e < MaxElems; e++) begin : g_mask
    logic [8:0] sel;
    assign sel = 9'(elem_base) + 9'(e);
    assign mask_bits[e] = (sel < 9'(VLEN)) ? rdata0[sel[6:0]] : 1'b0;
  end

  // Aligned operands
  logic [VLEN-1:0] vs1_data;
  logic [VLEN-1:0] vs2_data;

  assign vs1_data = rdata1 >> s1_off;
  assign vs2_data = rdata2 >> s2_off;

  vec_alu #(
      .DLEN(VLEN)
  ) u_alu (
      .op(seq_op),
      .src(seq_src),
      .vsew(seq_vsew),
      .vm(seq_vm),
      .mask_bits(mask_bits),
      .vs2_data(vs2_data),
      .vs1_data(vs1_data),
      .xdata(seq_xdata),
      .simm(seq_simm),
      .result(alu_result)
  );

  vec_mixed #(
      .DLEN(VLEN)
  ) u_mixed (
      .op(seq_op),
      .src(seq_src),
      .eew(seq_eew),
      .vsew(seq_vsew),
      .vs2_data(vs2_data),
      .vs1_data(vs1_data),
      .xdata(seq_xdata),
      .simm(seq_simm),
      .result(mixed_result)
  );

  vec_reduce #(
      .DLEN(VLEN)
  ) u_reduce (
      .clk(clk),
      .rst_n(rst_n),
      .core_en(core_en),
      .op(seq_op),
      .vsew(seq_vsew),
      .widen(seq_geom_s.widen),
      .first(seq_busy && (elem_base == 8'd0)),
      .step(seq_busy && (seq_cls == VEC_CLS_RED)),
      .vs2_data(vs2_data),
      .vs1_data(vs1_data),
      .elem_active(elem_active),
      .result(red_result)
  );

  vec_mask #(
      .DLEN(VLEN)
  ) u_mask (
      .op(seq_op),
      .src(seq_src),
      .vsew(seq_vsew),
      .vm(seq_vm),
      .vs2_data(vs2_data),
      .vs1_data(vs1_data),
      .v0_bits(rdata0),
      .xdata(seq_xdata),
      .simm(seq_simm),
      .elem_base(elem_base),
      .vl(seq_vl),
      .result(mask_result),
      .xresult(mask_xresult)
  );

  // Result select
  always_comb begin
    case (seq_cls)
      VEC_CLS_MIXED: raw_result = mixed_result;
      VEC_CLS_RED:   raw_result = red_result;
      VEC_CLS_SX:    raw_result = VLEN'(seq_xdata);
      VEC_CLS_CMP, VEC_CLS_MLOG, VEC_CLS_MSET, VEC_CLS_IOTA: raw_result = mask_result;
      default:       raw_result = alu_result;
    endcase
  end

  assign wdata = raw_result << d_off;

  // Scalar return path
  logic [31:0] xres_q;
  logic [31:0] elem_zero;
  logic [31:0] xs_val;
  logic [31:0] xm_val;

  always_comb begin
    case (seq_vsew)
      3'd0:    elem_zero = 32'($signed(rdata2[7:0]));
      3'd1:    elem_zero = 32'($signed(rdata2[15:0]));
      default: elem_zero = rdata2[31:0];
    endcase
  end

  // Slot holds it
  logic slot_first;
  always_ff @(posedge clk) begin
    if (!rst_n) slot_first <= 1'b0;
    else if (core_en) slot_first <= seq_start && !seq_mem;
  end

`ifdef RISCV_FORMAL_ABSTRACT_XRES
  // Free scalar result
  (* anyseq *) logic [31:0] fv_xres;
  assign xs_val = fv_xres;
  assign xm_val = fv_xres;
`else
  assign xs_val = elem_zero;
  assign xm_val = mask_xresult;
`endif

  always_ff @(posedge clk) begin
    if (!rst_n) xres_q <= 32'd0;
    else if (core_en) begin
      if (seq_busy && (elem_base == 8'd0) && (seq_cls == VEC_CLS_XS)) xres_q <= xs_val;
      else if ((seq_busy || slot_first) && (seq_cls == VEC_CLS_XM)) xres_q <= xm_val;
    end
  end

  assign xreg_valid  = dec_writes_xreg && is_vector;
  assign xreg_result = xres_q;
  assign vec_hold    = issue_hold || (csr_wait && !vec_idle);

`ifdef RISCV_FORMAL
  // Retirement export
  logic [7:0] tag_q;
  always_ff @(posedge clk) begin
    if (!rst_n) tag_q <= 8'd0;
    else if (core_en && (seq_done || m_done)) tag_q <= tag_q + 8'd1;
  end

  // Registers written
  logic [31:0] wr_mask_q;
  logic        wr_en;
  logic [ 4:0] wr_addr;

  assign wr_en   = seq_mem ? m_wen : vreg_write;
  assign wr_addr = seq_mem ? m_raddr : waddr;

  always_ff @(posedge clk) begin
    if (!rst_n) wr_mask_q <= 32'd0;
    else if (core_en) begin
      if (seq_start) wr_mask_q <= 32'd0;
      else if (wr_en) wr_mask_q[wr_addr] <= 1'b1;
    end
  end

  assign dbg_vec_tag    = tag_q;
  assign dbg_vec_retire = seq_done || m_done;
  assign dbg_vec_wregs  = wr_mask_q;
  assign dbg_vec_idle   = vec_idle;
`endif

endmodule

`default_nettype wire
