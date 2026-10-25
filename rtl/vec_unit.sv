`default_nettype none

module vec_unit
  import vec_pkg::*;
  import csr_pkg::VxrmAddr;
  import csr_pkg::VxsatAddr;
  import csr_pkg::VcsrAddr;
  import csr_pkg::VxrmW;
  import fp_pkg::FlagW, fp_pkg::RmW, fp_pkg::RmRmm;
#(
    parameter  int XLEN      = arch_pkg::XLEN,
    parameter  int AWIDTH    = arch_pkg::RegAddrW,
    parameter  int VLEN      = arch_pkg::VLEN,
    parameter  int ELEN      = arch_pkg::ELEN,
    parameter  int MUL_LANES = arch_pkg::MulLanes,
    localparam int MaxElems  = VLEN / 8,
    localparam int VlW       = $clog2(VLEN + 1),
    localparam int NRegs     = 1 << AWIDTH
) (
`ifdef RISCV_FORMAL
    output logic [vec_pkg::VecTagW-1:0] dbg_vec_tag,
    output logic                        dbg_vec_retire,
    output logic [           NRegs-1:0] dbg_vec_wregs,
    output logic                        dbg_vec_idle,
`endif
    input  wire                         clk,
    input  wire                         rst_n,
    input  wire                         core_en,

    // Execute stage
    input wire vec_dec_t            dec,
    input wire                      instr_valid,
    input wire                      cancel,
    input wire                      ex_advance,
    input wire           [XLEN-1:0] xdata,
    input wire           [XLEN-1:0] xstride,
    input wire           [XLEN-1:0] fdata,

    // Live configuration
    input wire                       vill,
    input wire [            VlW-1:0] vl,
    input wire [ vec_pkg::VsewW-1:0] vsew,
    input wire [vec_pkg::VlmulW-1:0] vlmul,

    // Memory port
    input  wire  [  VLEN-1:0] mem_rdata,
    input  wire               mem_ready,
    output logic              mem_req,
    output logic [  XLEN-1:0] mem_addr,
    output logic [  VLEN-1:0] mem_wdata,
    output logic [VLEN/8-1:0] mem_wstrb,

    // Memory checks
    output logic            mem_misaligned,
    output logic [XLEN-1:0] mem_bad_addr,

    // Fixed-point control
    input  wire              csr_we,
    input  wire  [     11:0] csr_waddr,
    input  wire  [ XLEN-1:0] csr_wdata,
    input  wire              csr_wait,
    output logic [VxrmW-1:0] vxrm,
    output logic             vxsat,

    // Float control
    input  wire  [  RmW-1:0] frm,
    output logic [FlagW-1:0] fflags,

    // Nonzero vstart
    input wire vstart_set,

    // Scalar result
    output logic            xreg_valid,
    output logic [XLEN-1:0] xreg_result,

    // Pipeline handshake
    output logic is_vector,
    output logic vec_hold,
    output logic vec_idle,
    output logic load_pending,
    output logic store_pending
);

  if (ELEN != 32) begin : g_elen
    $error("ELEN must be 32 (Zve32f)");
  end

  localparam int OffW = $clog2(VLEN);
  localparam int CountW = $clog2(MaxElems + 1);
  localparam int GrpW = AWIDTH + 1;
  localparam int Widths = $clog2(ELEN / 8) + 1;
  localparam int WSelW = $clog2(Widths);
  localparam int SelW = VlW + 1;
  localparam int SumW = VlW + 4;
  localparam int RegBytes = VLEN / 8;
  localparam int RegByteW = $clog2(RegBytes);

  // Writeback depths
  localparam int ShallowWb = 2;
  localparam int DeepWb = 3;
  localparam int LaneWb = 5;
  localparam int FpWb = VecFpLatency + 1;
  localparam int SlotW = $clog2(FpWb + 1);
  localparam int FpW = fp_pkg::FLEN;
  localparam int HalfW = FpW / 2;
  localparam logic [2:0] ElenLog2 = 3'($clog2(ELEN));

  // Float stage sized
  if (FpWb != LaneWb + 1) begin : g_fp_depth
    $error("vector float lane latency needs one stage after X4");
  end

  if (MUL_LANES * ELEN > VLEN) begin : g_lane_fit
    $error("MUL_LANES * ELEN must not exceed VLEN");
  end

  if (MUL_LANES * FpW > VLEN) begin : g_fp_fit
    $error("MUL_LANES * FLEN must not exceed VLEN");
  end

  if (FpW > ELEN) begin : g_fp_elen
    $error("FLEN must not exceed ELEN");
  end

  // Decoded fields
  logic                            dec_valid;
  vec_op_e                         dec_op;
  vec_src_e                        dec_src;
  vec_eew_e                        dec_eew;
  logic                            dec_vm;
  logic      [         AWIDTH-1:0] dec_vs1;
  logic      [         AWIDTH-1:0] dec_vs2;
  logic      [         AWIDTH-1:0] dec_vd;
  logic      [                4:0] dec_simm;
  logic                            dec_reads_vd;
  logic                            dec_reads_xreg;
  logic                            dec_writes_xreg;
  logic                            dec_writes_freg;
  logic                            dec_writes_mask;
  logic      [                1:0] dec_width;
  logic                            dec_whole;
  logic      [                2:0] dec_nf;
  logic                            dec_mask_ls;
  logic                            dec_strided;

  // Issued instruction
  vec_op_e                         seq_op;
  vec_src_e                        seq_src;
  vec_eew_e                        seq_eew;
  logic                            seq_start;
  logic      [         AWIDTH-1:0] seq_vs1;
  logic      [         AWIDTH-1:0] seq_vs2;
  logic      [         AWIDTH-1:0] seq_vd;
  logic                            seq_vm;
  logic                            seq_reads_vd;
  logic      [                4:0] seq_simm;
  logic      [           XLEN-1:0] seq_xdata;
  logic      [           XLEN-1:0] seq_xstride;
  logic      [            VlW-1:0] seq_vl;
  logic      [ vec_pkg::VsewW-1:0] seq_vsew;
  logic      [vec_pkg::VlmulW-1:0] seq_vlmul;
  logic      [          VxrmW-1:0] seq_vxrm;
  vec_fop_e                        seq_fop;
  logic      [            RmW-1:0] seq_frm;

  // Sequencer outputs
  logic      [         AWIDTH-1:0] raddr1;
  logic      [         AWIDTH-1:0] raddr2;
  logic      [         AWIDTH-1:0] raddr3;
  logic      [         AWIDTH-1:0] waddr;
  logic      [           VLEN-1:0] wstrb;
  logic                            wen;
  logic      [           OffW-1:0] s1_off;
  logic      [           OffW-1:0] s2_off;
  logic      [           OffW-1:0] d_off;
  logic      [            VlW-1:0] elem_base;
  logic      [         CountW-1:0] elem_count;
  logic      [       MaxElems-1:0] elem_active;
  logic                            seq_last;
  logic                            seq_reg_done;
  logic                            m_reg_done;
  logic                            seq_busy;
  logic                            seq_done;

  // Register file data
  logic      [           VLEN-1:0] rdata1;
  logic      [           VLEN-1:0] rdata2;
  logic      [           VLEN-1:0] rdata3;
  logic      [           VLEN-1:0] rdata0;

  // Lane results
  logic      [           VLEN-1:0] alu_result;
  logic      [           VLEN-1:0] mixed_result;
  logic      [           VLEN-1:0] red_result;
  logic      [           VLEN-1:0] mask_result;
  logic      [           XLEN-1:0] mask_xresult;
  logic      [           VLEN-1:0] raw_result;
  logic      [           VLEN-1:0] wdata;

  // Memory sequencer
  logic                            seq_mem;
  logic      [         AWIDTH-1:0] m_raddr;
  logic                            m_wen;
  logic      [           VLEN-1:0] m_wstrb;
  logic      [           VLEN-1:0] m_wdata;
  logic                            m_busy;
  logic                            m_done;

  // Slide lane
  logic                            seq_slide;
  logic      [         AWIDTH-1:0] sl_raddr_lo;
  logic      [         AWIDTH-1:0] sl_raddr_hi;
  logic                            sl_wen;
  logic      [         AWIDTH-1:0] sl_waddr;
  logic      [           VLEN-1:0] sl_wstrb;
  logic      [           VLEN-1:0] sl_wdata;
  logic                            sl_busy;
  logic                            sl_done;

  logic      [       MaxElems-1:0] mask_bits;
  logic                            issue_hold;
  logic                            x_done;

  // Pipeline registers
  logic                            valid_ex;
  vec_op_e                         op_ex;
  vec_src_e                        src_ex;
  vec_eew_e                        eew_ex;
  logic      [ vec_pkg::VsewW-1:0] vsew_ex;
  logic      [          VxrmW-1:0] vxrm_ex;
  vec_fop_e                        fop_ex;
  logic      [            RmW-1:0] frm_ex;
  logic                            vm_ex;
  logic      [                4:0] simm_ex;
  logic      [           XLEN-1:0] xdata_ex;
  logic      [            VlW-1:0] vl_ex;
  logic      [           VLEN-1:0] rdata1_ex;
  logic      [           VLEN-1:0] rdata2_ex;
  logic      [           VLEN-1:0] rdata3_ex;
  logic      [           VLEN-1:0] rdata0_ex;
  logic      [       MaxElems-1:0] mask_bits_ex;
  logic      [       MaxElems-1:0] elem_active_ex;
  logic      [            VlW-1:0] elem_base_ex;
  logic      [           OffW-1:0] s1_off_ex;
  logic      [           OffW-1:0] s2_off_ex;
  logic      [           OffW-1:0] d_off_ex;
  logic      [         AWIDTH-1:0] waddr_ex;
  logic      [           VLEN-1:0] wstrb_ex;
  logic                            wen_ex;
  logic                            reg_done_ex;
  logic                            last_ex;
  logic                            slot_first_ex;

  logic                            valid_x2;
  vec_cls_e                        cls_x2;
  vec_op_e                         op_x2;
  vec_fop_e                        fop_x2;
  logic      [            RmW-1:0] frm_x2;
  logic      [ vec_pkg::VsewW-1:0] vsew_x2;
  logic      [          VxrmW-1:0] vxrm_x2;
  logic                            wmul_x2;
  logic      [           OffW-1:0] d_off_x2;
  logic      [         AWIDTH-1:0] waddr_x2;
  logic      [           VLEN-1:0] wstrb_x2;
  logic                            wen_x2;
  logic                            reg_done_x2;
  logic                            last_x2;

  logic                            valid_x3;
  vec_cls_e                        cls_x3;
  vec_op_e                         op_x3;
  logic      [ vec_pkg::VsewW-1:0] vsew_x3;
  logic      [          VxrmW-1:0] vxrm_x3;
  logic                            wmul_x3;
  logic      [           OffW-1:0] d_off_x3;
  logic      [         AWIDTH-1:0] waddr_x3;
  logic      [           VLEN-1:0] wstrb_x3;
  logic                            wen_x3;
  logic                            reg_done_x3;
  logic                            last_x3;
  logic                            valid_x4;
  vec_cls_e                        cls_x4;
  vec_op_e                         op_x4;
  logic      [ vec_pkg::VsewW-1:0] vsew_x4;
  logic                            wmul_x4;
  logic      [           OffW-1:0] d_off_x4;
  logic      [         AWIDTH-1:0] waddr_x4;
  logic      [           VLEN-1:0] wstrb_x4;
  logic                            wen_x4;
  logic                            reg_done_x4;
  logic                            last_x4;
  logic                            valid_x5;
  vec_cls_e                        cls_x5;
  logic      [           OffW-1:0] d_off_x5;
  logic      [         AWIDTH-1:0] waddr_x5;
  logic      [           VLEN-1:0] wstrb_x5;
  logic                            wen_x5;
  logic                            reg_done_x5;
  logic                            last_x5;

  vec_cls_e                        cls_wb;
  logic      [           XLEN-1:0] xdata_wb;
  logic      [           VLEN-1:0] alu_result_wb;
  logic      [           VLEN-1:0] mixed_result_wb;
  logic      [           VLEN-1:0] red_result_wb;
  logic      [           VLEN-1:0] mask_result_wb;
  logic      [           VLEN-1:0] lane_result_wb;
  logic      [           OffW-1:0] d_off_wb;
  logic      [         AWIDTH-1:0] waddr_wb;
  logic      [           VLEN-1:0] wstrb_wb;
  logic                            valid_wb;
  logic                            wen_wb;
  logic                            reg_done_wb;
  logic                            last_wb;

  // Instruction classes
  vec_cls_e                        dec_cls;
  vec_cls_e                        seq_cls;
  vec_cls_e                        cls_ex;
  vec_geom_t                       dec_geom_s;
  vec_geom_t                       seq_geom_s;
  vec_geom_t                       geom_ex;

  // Divide forms
  function automatic logic is_div(input vec_op_e op);
    is_div = (op == VEC_DIVU) || (op == VEC_DIV) || (op == VEC_REMU) || (op == VEC_REM);
  endfunction

  // Float divide forms
  function automatic logic is_fdiv(input vec_fop_e fop);
    is_fdiv = (fop == VEC_FDIV) || (fop == VEC_FRDIV) || (fop == VEC_FSQRT);
  endfunction

  // Conversion forms
  function automatic logic is_fcvt(input vec_fop_e fop);
    is_fcvt = (fop == VEC_FCVT_XU_F) || (fop == VEC_FCVT_X_F) || (fop == VEC_FCVT_RTZ_XU_F) ||
        (fop == VEC_FCVT_RTZ_X_F) || (fop == VEC_FCVT_F_XU) || (fop == VEC_FCVT_F_X);
  endfunction

  assign dec_cls = vec_class(dec_op);
  assign seq_cls = vec_class(seq_op);
  assign dec_geom_s = vec_geom(dec_op, dec_eew);
  assign seq_geom_s = vec_geom(seq_op, seq_eew);
  assign cls_ex = vec_class(op_ex);
  assign geom_ex = vec_geom(op_ex, eew_ex);

  // Mask is data
  logic v0_is_data;
  always_comb begin
    case (seq_op)
      VEC_ADC, VEC_SBC, VEC_MADC, VEC_MSBC, VEC_MERGE: v0_is_data = 1'b1;
      default: v0_is_data = 1'b0;
    endcase
  end

  // Element widths
  logic [vec_pkg::SewLog2W-1:0] lsew;
  logic [vec_pkg::SewLog2W-1:0] dec_ld;
  logic [vec_pkg::SewLog2W-1:0] dec_ls1;
  logic [vec_pkg::SewLog2W-1:0] dec_ls2;
  logic                         width_legal;

  // Element width fits
  function automatic logic width_fits(input logic [vec_pkg::SewLog2W-1:0] lw);
    width_fits = (lw >= ByteLog2) && (lw <= ElenLog2);
  endfunction

  assign lsew = vsew + ByteLog2;
  assign dec_ld = vec_rel_log2(dec_geom_s.d, lsew);
  assign dec_ls1 = vec_rel_log2(dec_geom_s.s1, lsew);
  assign dec_ls2 = vec_rel_log2(dec_geom_s.s2, lsew);
  assign width_legal = width_fits(dec_ld) && width_fits(dec_ls1) && width_fits(dec_ls2);

  // Scalar forms
  logic scalar_legal;
  assign scalar_legal = ((dec_cls != VEC_CLS_XS) && (dec_cls != VEC_CLS_SX) &&
                         (dec_cls != VEC_CLS_MLOG)) || dec_vm;

  // Carry forms masked
  logic carry_legal;
  assign carry_legal = ((dec_op != VEC_ADC) && (dec_op != VEC_SBC)) || !dec_vm;

  // Slideup groups apart
  logic slide_legal;
  assign slide_legal = ((dec_op != VEC_SLIDEUP) && (dec_op != VEC_SLIDE1UP)) || (dec_vd != dec_vs2);

  // Whole register forms
  logic                             dec_mvnr;
  logic                             dec_full;
  logic        [               2:0] full_nf;
  logic signed [vec_pkg::EmulW-1:0] full_emul;
  logic                             full_nop;

  assign dec_mvnr  = (dec_op == VEC_MVNRR);
  assign dec_full  = dec_whole || dec_mvnr;
  assign full_nf   = dec_mvnr ? dec_simm[2:0] : dec_nf;
  assign full_emul = 4'(full_nf[0]) + 4'(full_nf[1]) + 4'(full_nf[2]);

  // Copy onto itself
  assign full_nop  = dec_mvnr && (dec_vd == dec_vs2);

  // Memory snapshot
  logic                              dec_mem;
  logic signed [ vec_pkg::EmulW-1:0] emul_log2;
  logic                              emul_ok;
  logic        [            VlW-1:0] issue_vl;
  logic        [ vec_pkg::VsewW-1:0] issue_vsew;
  logic        [vec_pkg::VlmulW-1:0] issue_vlmul;
  logic        [           XLEN-1:0] issue_stride;
  logic                              base_off;
  logic                              stride_off;

  // Multiplier in range
  function automatic logic width_in_range(input logic signed [vec_pkg::EmulW-1:0] emul,
                                          input logic used);
    width_in_range = !used || ((emul >= -4'sd3) && (emul <= 4'sd3));
  endfunction

  // Address misaligned
  function automatic logic misaligned(input logic [1:0] addr, input logic [1:0] width);
    case (width)
      2'd2:    misaligned = (addr[1:0] != 2'b00);
      2'd1:    misaligned = addr[0];
      default: misaligned = 1'b0;
    endcase
  endfunction

  assign dec_mem   = (dec_cls == VEC_CLS_MEM);
  assign emul_log2 = 4'($signed(vlmul)) + $signed({2'b00, dec_width}) - $signed({1'b0, vsew});
  assign emul_ok   = !dec_mem || dec_whole || dec_mask_ls || width_in_range(emul_log2, 1'b1);

  always_comb begin
    if (full_nop) issue_vl = '0;
    else if (dec_full) issue_vl = VlW'((VLEN >> (3 + dec_width)) << full_emul);
    else if (dec_mem && dec_mask_ls) issue_vl = VlW'((vl + VlW'(7)) >> 3);
    else if (dec_cls == VEC_CLS_XS) issue_vl = VlW'(1);
    else issue_vl = vl;
  end

  always_comb begin
    if (dec_mem) issue_vsew = {1'b0, dec_width};
    else if (dec_mvnr) issue_vsew = Sew8;
    else issue_vsew = vsew;
  end

  assign issue_vlmul = dec_mvnr ? 3'(full_emul) : vlmul;
  assign issue_stride = dec_strided ? xstride : (XLEN'(1) << dec_width);

  // Alignment check
  assign base_off = misaligned(xdata[1:0], dec_width);
  assign stride_off = misaligned(issue_stride[1:0], dec_width);
  assign mem_misaligned = dec_mem && is_vector &&
      (((issue_vl != '0) && base_off) || ((issue_vl > VlW'(1)) && stride_off));
  assign mem_bad_addr = base_off ? xdata : (xdata + issue_stride);

  // Permitted overlap
  function automatic logic pair_ok(input logic [GrpW-1:0] bd, input logic [GrpW-1:0] nd,
                                   input logic [vec_pkg::SewLog2W-1:0] wd,
                                   input logic [GrpW-1:0] bs, input logic [GrpW-1:0] ns,
                                   input logic [vec_pkg::SewLog2W-1:0] ws, input logic src_whole);
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
  logic                                dec_store;
  logic                                dec_ext;
  logic                                dec_funary;
  logic                                dec_fcvt;
  logic                                has_vd;
  logic                                uses_vs1;
  logic                                uses_vs2;
  logic signed [   vec_pkg::EmulW-1:0] lmul_log2;
  logic signed [   vec_pkg::EmulW-1:0] d_delta;
  logic signed [   vec_pkg::EmulW-1:0] s1_delta;
  logic signed [   vec_pkg::EmulW-1:0] s2_delta;
  logic signed [   vec_pkg::EmulW-1:0] d_emul;
  logic signed [   vec_pkg::EmulW-1:0] s1_emul;
  logic signed [   vec_pkg::EmulW-1:0] s2_emul;
  logic        [             GrpW-1:0] d_regs;
  logic        [             GrpW-1:0] s1_regs;
  logic        [             GrpW-1:0] s2_regs;
  logic                                emul_legal;
  logic                                align_ok;
  logic        [vec_pkg::SewLog2W-1:0] dest_lw;
  logic                                overlap_ok;
  logic                                mask_ok;
  logic                                group_legal;

  assign dec_store = (dec_op == VEC_STORE);
  assign has_vd = (dec_cls != VEC_CLS_XS) && (dec_cls != VEC_CLS_XM);
  assign dec_ext = (dec_op == VEC_ZEXT2) || (dec_op == VEC_ZEXT4) || (dec_op == VEC_SEXT2) ||
      (dec_op == VEC_SEXT4);
  assign dec_fcvt = is_fcvt(dec.fop);
  assign dec_funary = (dec_cls == VEC_CLS_FP) &&
      ((dec.fop == VEC_FCLASS) || (dec.fop == VEC_FREC7) || (dec.fop == VEC_FRSQRT7) ||
       (dec.fop == VEC_FSQRT) || dec_fcvt);
  assign uses_vs1 = !dec_mem && !dec_ext && !dec_funary && (dec_cls != VEC_CLS_XS) &&
      (dec_cls != VEC_CLS_SX) && (dec_cls != VEC_CLS_XM) && (dec_cls != VEC_CLS_MSET) &&
      (dec_cls != VEC_CLS_IOTA) && (dec_src == VEC_SRC_VV);
  assign uses_vs2 = !dec_mem && (dec_cls != VEC_CLS_SX);

  assign lmul_log2 = 4'($signed(vlmul));
  assign d_delta = 4'($signed({1'b0, dec_ld})) - 4'($signed({1'b0, lsew}));
  assign s1_delta = 4'($signed({1'b0, dec_ls1})) - 4'($signed({1'b0, lsew}));
  assign s2_delta = 4'($signed({1'b0, dec_ls2})) - 4'($signed({1'b0, lsew}));

  always_comb begin
    if (dec_full) d_emul = full_emul;
    else if (dec_mem && dec_mask_ls) d_emul = 4'sd0;
    else if (dec_mem) d_emul = emul_log2;
    else if (dec_geom_s.single_write || dec_geom_s.mask_dest) d_emul = 4'sd0;
    else d_emul = lmul_log2 + d_delta;
  end

  assign
      s1_emul = (dec_geom_s.single_write || dec_geom_s.mask_src) ? 4'sd0 : (lmul_log2 + s1_delta);

  always_comb begin
    if (dec_mvnr) s2_emul = full_emul;
    else if ((dec_cls == VEC_CLS_XS) || dec_geom_s.mask_src) s2_emul = 4'sd0;
    else s2_emul = lmul_log2 + s2_delta;
  end

  assign d_regs = GrpW'(vec_group_regs(d_emul));
  assign s1_regs = uses_vs1 ? GrpW'(vec_group_regs(s1_emul)) : GrpW'(1);
  assign s2_regs = uses_vs2 ? GrpW'(vec_group_regs(s2_emul)) : GrpW'(1);

  assign emul_legal = width_in_range(
      d_emul, has_vd
  ) && width_in_range(
      s1_emul, uses_vs1
  ) && width_in_range(
      s2_emul, uses_vs2
  );

  assign align_ok = (!has_vd || ((GrpW'(dec_vd) & (d_regs - GrpW'(1))) == '0)) &&
      (!uses_vs1 || ((GrpW'(dec_vs1) & (s1_regs - GrpW'(1))) == '0)) &&
      (!uses_vs2 || ((GrpW'(dec_vs2) & (s2_regs - GrpW'(1))) == '0));

  // Mask EEW one
  assign dest_lw = dec_geom_s.mask_dest ? 3'd0 : dec_ld;

  assign overlap_ok = dec_mem || !has_vd || dec_geom_s.single_write ||
      (dec_geom_s.mask_dest && dec_geom_s.mask_src) || ((!uses_vs1 || pair_ok(
      GrpW'(dec_vd), d_regs, dest_lw, GrpW'(dec_vs1), s1_regs, dec_ls1, s1_emul >= 4'sd0
  )) && (!uses_vs2 || pair_ok(
      GrpW'(dec_vd), d_regs, dest_lw, GrpW'(dec_vs2), s2_regs, dec_ls2, s2_emul >= 4'sd0
  )));

  assign mask_ok = dec_vm || dec_store || !has_vd || dec_geom_s.single_write || dec_writes_mask ||
      (GrpW'(dec_vd) >= d_regs);

  assign group_legal = emul_legal && align_ok && overlap_ok && mask_ok;

  // Busy groups
  logic [GrpW-1:0] load_regs;
  logic [GrpW-1:0] wr_regs;
  logic [GrpW-1:0] rd1_regs;
  logic [GrpW-1:0] rd2_regs;
  logic            seq_clear;

  assign load_regs = GrpW'(((SumW'(issue_vl) << dec_width) + SumW'(RegBytes - 1)) >> RegByteW);
  always_comb begin
    if (!has_vd || dec_store || (issue_vl == '0)) wr_regs = '0;
    else if (dec_mem) wr_regs = load_regs;
    else wr_regs = d_regs;
  end

  always_comb begin
    if (dec_store) rd1_regs = d_regs;
    else if (uses_vs1) rd1_regs = s1_regs;
    else rd1_regs = '0;
  end

  assign rd2_regs  = uses_vs2 ? s2_regs : '0;
  assign seq_clear = seq_reg_done && (seq_cls != VEC_CLS_XS) && (seq_cls != VEC_CLS_XM);

  // Rounding and saturation
  logic [VxrmW-1:0] vxrm_q;
  logic             vxsat_q;
  logic             sat_set;

  logic             sat_wb;

  assign sat_set = sat_wb;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      vxrm_q  <= '0;
      vxsat_q <= 1'b0;
    end else begin
      if (sat_set) vxsat_q <= 1'b1;
      if (csr_we) begin
        case (csr_waddr)
          VxrmAddr:  vxrm_q <= csr_wdata[VxrmW-1:0];
          VxsatAddr: vxsat_q <= csr_wdata[0];
          VcsrAddr: begin
            vxrm_q  <= csr_wdata[VxrmW:1];
            vxsat_q <= csr_wdata[0];
          end
          default:   ;
        endcase
      end
    end
  end

  assign vxrm  = vxrm_q;
  assign vxsat = vxsat_q;

  // Accepted instruction
  logic op_ready;
  logic accept_now;

  // Nonzero vstart traps
  logic vstart_legal;
  assign vstart_legal = !vstart_set || dec_mem;

  // Mask set overlap
  logic mset_legal;
  assign mset_legal = (dec_cls != VEC_CLS_MSET) ||
      ((dec_vd != dec_vs2) && (dec_vm || (dec_vd != '0)));

  // Iota source overlap
  logic iota_legal;
  assign iota_legal = (dec_op != VEC_IOTA) || (GrpW'(dec_vs2) < GrpW'(dec_vd)) ||
      (GrpW'(dec_vs2) >= (GrpW'(dec_vd) + d_regs));

  // Index reads none
  logic id_legal;
  assign id_legal = (dec_op != VEC_ID) || (dec_vs2 == '0);

  // Float needs e32
  logic                      dec_fp;
  logic                      dec_fcvt_wn;
  logic [vec_pkg::VsewW-1:0] fp_sew;
  logic                      fp_legal;
  assign dec_fp = vec_is_fp(dec_op, dec.reads_freg, dec_writes_freg);

  // Wide conversions e16
  assign dec_fcvt_wn = (dec_cls == VEC_CLS_FP) && (dec_eew != VEC_EEW_SAME);
  assign fp_sew = dec_fcvt_wn ? FpHalfSew : FpSew;
  assign fp_legal = !dec_fp || ((vsew == fp_sew) && (frm <= RmRmm));

  assign op_ready = (dec_cls != VEC_CLS_NONE) && fp_legal && group_legal && vstart_legal &&
      mset_legal && iota_legal && id_legal &&
      (dec_mem || dec_mvnr || (width_legal && scalar_legal && carry_legal && slide_legal));
  assign is_vector = dec_valid && op_ready && (dec_whole || !vill) && emul_ok;
  assign accept_now = instr_valid && is_vector;

  assign dec_valid = dec.valid;
  assign dec_op = dec.op;
  assign dec_src = dec.src;
  assign dec_eew = dec.eew;
  assign dec_vm = dec.vm;
  assign dec_vs1 = AWIDTH'(dec.vs1);
  assign dec_vs2 = AWIDTH'(dec.vs2);
  assign dec_vd = AWIDTH'(dec.vd);
  assign dec_simm = dec.simm;
  assign dec_reads_vd = dec.reads_vd;
  assign dec_reads_xreg = dec.reads_xreg;
  assign dec_writes_xreg = dec.writes_xreg;
  assign dec_writes_freg = dec.writes_freg;
  assign dec_writes_mask = dec.writes_mask;
  assign dec_width = dec.mem_width;
  assign dec_whole = dec.mem_whole;
  assign dec_nf = dec.mem_nf;
  assign dec_mask_ls = dec.mem_mask;
  assign dec_strided = dec.mem_strided;

  // Register write port
  logic              rf_we;
  logic [  VLEN-1:0] rf_wstrb;
  logic [AWIDTH-1:0] rf_waddr;
  logic [  VLEN-1:0] rf_wdata;
  logic [AWIDTH-1:0] rf_raddr1;
  logic [AWIDTH-1:0] clear_addr;

  assign rf_we = wen_wb || m_wen || sl_wen;

  always_comb begin
    if (wen_wb) begin
      rf_wstrb = wstrb_wb;
      rf_waddr = waddr_wb;
      rf_wdata = wdata;
    end else if (sl_wen) begin
      rf_wstrb = sl_wstrb;
      rf_waddr = sl_waddr;
      rf_wdata = sl_wdata;
    end else begin
      rf_wstrb = m_wstrb;
      rf_waddr = m_raddr;
      rf_wdata = m_wdata;
    end
  end

  always_comb begin
    if (seq_mem) rf_raddr1 = m_raddr;
    else if (seq_slide) rf_raddr1 = sl_raddr_lo;
    else rf_raddr1 = raddr1;
  end

  always_comb begin
    if (reg_done_wb) clear_addr = waddr_wb;
    else if (sl_busy) clear_addr = sl_waddr;
    else clear_addr = m_raddr;
  end

  vec_issue #(
      .XLEN  (XLEN),
      .AWIDTH(AWIDTH),
      .VLEN  (VLEN)
  ) u_issue (
      .clk(clk),
      .rst_n(rst_n),
      .core_en(core_en),
      .instr_valid(accept_now),
      .cancel(cancel),
      .ex_advance(ex_advance),
      .op(dec_op),
      .src(dec_src),
      .eew(dec_eew),
      .writes_xreg(dec_writes_xreg || dec_writes_freg),
      .vs1(dec_vs1),
      .vs2(dec_vs2),
      .vd(dec_vd),
      .vm(dec_vm),
      .reads_vd(dec_reads_vd),
      .simm(dec_simm),
      .xdata(dec.reads_freg ? fdata : xdata),
      .xstride(issue_stride),
      .fop(dec.fop),
      .wr_regs(wr_regs),
      .rd1(dec_store ? dec_vd : dec_vs1),
      .rd1_regs(rd1_regs),
      .rd2_regs(rd2_regs),
      .clear(reg_done_wb || m_reg_done || sl_busy),
      .clear_addr(clear_addr),
      .vl(issue_vl),
      .vsew(issue_vsew),
      .vlmul(issue_vlmul),
      .vxrm(vxrm_q),
      .frm(frm),
      .seq_busy(seq_busy || m_busy || sl_busy),
      .seq_done(seq_done || m_done || sl_done),
      .pipe_busy(valid_ex || valid_x2 || valid_x3 || valid_x4 || valid_x5 || valid_wb),
      .x_done(x_done),
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
      .seq_fop(seq_fop),
      .seq_frm(seq_frm),
      .vec_hold(issue_hold),
      .vec_idle(vec_idle),
      .load_pending(load_pending),
      .store_pending(store_pending)
  );

  // Divide lanes
  logic                 div_op_x2;
  logic                 div_op_x4;
  logic                 div_go;
  logic                 div_run_q;
  logic                 div_tail_q;
  logic                 div_stall;
  logic                 div_hold;
  logic [MUL_LANES-1:0] div_pend_q;
  logic [MUL_LANES-1:0] div_done;
  logic                 fdiv_ex;
  logic                 fdiv_x2;
  logic                 fdiv_x3;
  logic                 fdiv_x4;
  logic                 fdiv_x5;
  logic                 fdiv_wb;

  // Book the write
  logic                 seq_lane;
  logic                 seq_deep;
  logic                 seq_fp;
  logic                 slot_free;
  logic                 seq_hold;
  logic [    SlotW-1:0] seq_depth;

  assign seq_lane = (seq_cls == VEC_CLS_MUL) || (seq_cls == VEC_CLS_SAT);
  assign seq_fp   = (seq_cls == VEC_CLS_FP) || (seq_cls == VEC_CLS_FCMP);
  assign seq_deep = (seq_cls == VEC_CLS_RED) || seq_lane;

  // Float sum gap
  logic seq_fsum;
  logic sum_gap_q;

  assign seq_fsum = (seq_op == VEC_FRED) &&
      ((seq_fop == VEC_FREDOSUM) || (seq_fop == VEC_FREDUSUM));

  assign seq_hold = seq_busy && (!slot_free || div_hold || sum_gap_q);

  always_ff @(posedge clk) begin
    if (!rst_n) sum_gap_q <= 1'b0;
    else if (core_en) sum_gap_q <= seq_busy && !seq_hold && seq_fsum;
  end

  always_comb begin
    if (seq_fp) seq_depth = SlotW'(FpWb);
    else if (seq_lane || seq_fsum) seq_depth = SlotW'(LaneWb);
    else if (seq_deep) seq_depth = SlotW'(DeepWb);
    else seq_depth = SlotW'(ShallowWb);
  end

  vec_write_slots #(
      .DEPTH(FpWb)
  ) u_slots (
      .clk(clk),
      .rst_n(rst_n),
      .core_en(core_en),
      .start(seq_busy && !seq_hold),
      .depth(seq_depth),
      .free(slot_free)
  );

  vec_sequencer #(
      .AWIDTH   (AWIDTH),
      .VLEN     (VLEN),
      .ELEN     (ELEN),
      .MUL_LANES(MUL_LANES)
  ) u_sequencer (
      .clk(clk),
      .rst_n(rst_n),
      .core_en(core_en && !seq_hold),
      .start(seq_start && !seq_mem && !seq_slide),
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
      .serial(seq_fsum),
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
      .reg_done(seq_reg_done),
      .busy(seq_busy),
      .done(seq_done)
  );

  assign seq_mem = (seq_cls == VEC_CLS_MEM);

  vec_mem #(
      .XLEN  (XLEN),
      .AWIDTH(AWIDTH),
      .VLEN  (VLEN)
  ) u_mem (
`ifdef RISCV_FORMAL
      .dbg_elem(),
      .dbg_n_ok(),
`endif
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
      .reg_done(m_reg_done),
      .busy(m_busy),
      .done(m_done)
  );

  assign seq_slide = (seq_cls == VEC_CLS_SLIDE);

  vec_slide #(
      .XLEN  (XLEN),
      .AWIDTH(AWIDTH),
      .VLEN  (VLEN)
  ) u_slide (
      .clk(clk),
      .rst_n(rst_n),
      .core_en(core_en),
      .start(seq_start && seq_slide),
      .op(seq_op),
      .vm(seq_vm),
      .vs2(seq_vs2),
      .vd(seq_vd),
      .vl(seq_vl),
      .vsew(seq_vsew),
      .vlmul(seq_vlmul),
      .offset((seq_src == VEC_SRC_VI) ? XLEN'(seq_simm) : seq_xdata),
      .scalar(seq_xdata),
      .v0(rdata0),
      .rdata_lo(rdata1),
      .rdata_hi(rdata2),
      .raddr_lo(sl_raddr_lo),
      .raddr_hi(sl_raddr_hi),
      .wen(sl_wen),
      .waddr(sl_waddr),
      .wstrb(sl_wstrb),
      .wdata(sl_wdata),
      .busy(sl_busy),
      .done(sl_done)
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
      .we(rf_we),
      .wstrb(rf_wstrb),
      .waddr(rf_waddr),
      .wdata(rf_wdata),
      .raddr1(rf_raddr1),
      .raddr2(seq_slide ? sl_raddr_hi : raddr2),
      .raddr3(raddr3),
      .rdata1(rdata1),
      .rdata2(rdata2),
      .rdata3(rdata3),
      .rdata0(rdata0)
  );

  // Live mask bits
  for (genvar e = 0; e < MaxElems; e++) begin : g_mask
    logic [SelW-1:0] sel;
    assign sel = SelW'(elem_base) + SelW'(e);
    assign mask_bits[e] = (sel < SelW'(VLEN)) ? rdata0[sel[OffW-1:0]] : 1'b0;
  end

  // Slot holds it
  logic slot_first;
  always_ff @(posedge clk) begin
    if (!rst_n) slot_first <= 1'b0;
    else if (core_en) slot_first <= seq_start && !seq_mem && !seq_slide;
  end

  // RD/EX
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      valid_ex      <= 1'b0;
      wen_ex        <= 1'b0;
      reg_done_ex   <= 1'b0;
      last_ex       <= 1'b0;
      slot_first_ex <= 1'b0;
    end else if (core_en) begin
      valid_ex       <= seq_busy && !seq_hold;
      wen_ex         <= vreg_write && !seq_hold;
      reg_done_ex    <= seq_clear && !seq_hold;
      last_ex        <= seq_busy && seq_last && !seq_hold;
      slot_first_ex  <= slot_first;
      op_ex          <= seq_op;
      src_ex         <= seq_src;
      eew_ex         <= seq_eew;
      vsew_ex        <= seq_vsew;
      vxrm_ex        <= seq_vxrm;
      fop_ex         <= seq_fop;
      frm_ex         <= seq_frm;
      vm_ex          <= seq_vm;
      simm_ex        <= seq_simm;
      xdata_ex       <= seq_xdata;
      vl_ex          <= seq_vl;
      rdata1_ex      <= rdata1;
      rdata2_ex      <= rdata2;
      rdata3_ex      <= rdata3;
      rdata0_ex      <= rdata0;
      mask_bits_ex   <= mask_bits;
      elem_active_ex <= elem_active;
      elem_base_ex   <= elem_base;
      s1_off_ex      <= s1_off;
      s2_off_ex      <= s2_off;
      d_off_ex       <= d_off;
      waddr_ex       <= waddr;
      wstrb_ex       <= wstrb;
    end
  end

  // Aligned operands
  logic [VLEN-1:0] vs1_data;
  logic [VLEN-1:0] vs2_data;

  assign vs1_data = rdata1_ex >> s1_off_ex;
  assign vs2_data = rdata2_ex >> s2_off_ex;

  vec_alu #(
      .DLEN(VLEN),
      .ELEN(ELEN),
      .XLEN(XLEN)
  ) u_alu (
      .op(op_ex),
      .src(src_ex),
      .vsew(vsew_ex),
      .vm(vm_ex),
      .mask_bits(mask_bits_ex),
      .vs2_data(vs2_data),
      .vs1_data(vs1_data),
      .xdata(xdata_ex),
      .simm(simm_ex),
      .result(alu_result)
  );

  vec_mixed #(
      .DLEN(VLEN),
      .ELEN(ELEN),
      .XLEN(XLEN)
  ) u_mixed (
      .op(op_ex),
      .src(src_ex),
      .eew(eew_ex),
      .vsew(vsew_ex),
      .vs2_data(vs2_data),
      .vs1_data(vs1_data),
      .xdata(xdata_ex),
      .simm(simm_ex),
      .result(mixed_result)
  );

  vec_reduce #(
      .DLEN(VLEN),
      .ELEN(ELEN)
  ) u_reduce (
      .clk(clk),
      .rst_n(rst_n),
      .core_en(core_en),
      .op(op_ex),
      .vsew(vsew_ex),
      .widen(geom_ex.widen),
      .first(valid_ex && (elem_base_ex == '0)),
      .step(valid_ex && (cls_ex == VEC_CLS_RED)),
      .vs2_data(vs2_data),
      .vs1_data(vs1_data),
      .elem_active(elem_active_ex),
      .result(red_result)
  );

  // Float reduce
  logic [ VLEN-1:0] fred_result;
  logic [FlagW-1:0] fred_flags;
  logic [FlagW-1:0] fred_flags_wb;
  logic [  FpW-1:0] fred_sum;
  logic [ VLEN-1:0] red_pick;
  logic             fsum_ex;
  logic             fsum_x2;
  logic             fsum_x3;
  logic             fsum_x4;

  assign fsum_ex = (op_ex == VEC_FRED) && ((fop_ex == VEC_FREDOSUM) || (fop_ex == VEC_FREDUSUM));

  always_comb begin
    if (valid_x4 && fsum_x4) red_pick = VLEN'(fred_sum);
    else if (op_x2 == VEC_FRED) red_pick = fred_result;
    else red_pick = red_result;
  end

  vec_fp_reduce #(
      .DLEN(VLEN)
  ) u_fp_reduce (
      .clk(clk),
      .rst_n(rst_n),
      .core_en(core_en),
      .op(fop_ex),
      .first(valid_ex && (elem_base_ex == '0)),
      .step(valid_ex && (op_ex == VEC_FRED)),
      .vs2_data(vs2_data),
      .vs1_data(vs1_data),
      .elem_active(elem_active_ex[VLEN/FpW-1:0]),
      .rm(frm_ex),
      .result(fred_result),
      .sum_result(fred_sum),
      .fflags(fred_flags)
  );

  always_ff @(posedge clk) begin
    if (!rst_n) fred_flags_wb <= '0;
    else if (core_en) fred_flags_wb <= fred_flags;
  end

  vec_mask #(
      .DLEN(VLEN),
      .ELEN(ELEN),
      .XLEN(XLEN)
  ) u_mask (
      .op(op_ex),
      .src(src_ex),
      .vsew(vsew_ex),
      .vm(vm_ex),
      .vs2_data(vs2_data),
      .vs1_data(vs1_data),
      .v0_bits(rdata0_ex),
      .mask_bits(mask_bits_ex),
      .xdata(xdata_ex),
      .simm(simm_ex),
      .elem_base(elem_base_ex),
      .vl(vl_ex),
      .result(mask_result),
      .xresult(mask_xresult)
  );

  // Multiply operand select
  logic                    narrow_ex;
  logic                    wmul_ex;
  logic                    vd_mul_ex;
  logic    [     VLEN-1:0] vd_data;
  logic    [     ELEN-1:0] imm_ex;
  vec_op_e                 mul_op_x2;
  logic    [     ELEN-1:0] lane_res  [MUL_LANES];
  logic    [MUL_LANES-1:0] lane_sat;
  logic    [MUL_LANES-1:0] active_x2;
  logic    [MUL_LANES-1:0] active_x3;
  logic    [MUL_LANES-1:0] active_x4;
  logic                    lane_x2;

  assign narrow_ex = (eew_ex == VEC_EEW_NARROW);
  assign wmul_ex = (cls_ex == VEC_CLS_MUL) && geom_ex.widen;
  assign vd_mul_ex = (op_ex == VEC_MADD) || (op_ex == VEC_NMSUB);
  assign vd_data = rdata3_ex >> d_off_ex;
  assign imm_ex = ((op_ex == VEC_SSRL) || (op_ex == VEC_SSRA) || narrow_ex) ?
      ELEN'(simm_ex) : {{(ELEN - 5) {simm_ex[4]}}, simm_ex};
  assign mul_op_x2 = vec_pkg::vec_op_e'((op_x2 == VEC_SMUL) ? VEC_MULH : op_x2);

  // Float lane outputs
  logic                 fp_ex;
  logic [      FpW-1:0] fp_res    [MUL_LANES];
  logic [    FlagW-1:0] fp_flag   [MUL_LANES];
  logic [MUL_LANES-1:0] fp_cmp;
  logic                 fcvt_ex;
  logic [      FpW-1:0] cvt_res   [MUL_LANES];
  logic [    FlagW-1:0] cvt_flag  [MUL_LANES];
  logic [MUL_LANES-1:0] cvt_vld;
  logic [MUL_LANES-1:0] active_x5;
  logic [MUL_LANES-1:0] active_wb;

  assign fp_ex = (cls_ex == VEC_CLS_FP) || (cls_ex == VEC_CLS_FCMP);
  assign fcvt_ex = (cls_ex == VEC_CLS_FP) && is_fcvt(fop_ex);
  assign lane_x2 = (cls_x2 == VEC_CLS_MUL) || (cls_x2 == VEC_CLS_SAT) || (cls_x2 == VEC_CLS_FP) ||
      (cls_x2 == VEC_CLS_FCMP) || fsum_x2;

  for (genvar l = 0; l < MUL_LANES; l++) begin : g_lane
    logic [     ELEN-1:0] a_w     [Widths];
    logic [     ELEN-1:0] b_w     [Widths];
    logic [     ELEN-1:0] s_w     [Widths];
    logic [     ELEN-1:0] d_w     [Widths];
    logic [     ELEN-1:0] a_ex;
    logic [     ELEN-1:0] b_ex;
    logic [     ELEN-1:0] c_ex;
    logic [     ELEN-1:0] a_x2;
    logic [     ELEN-1:0] b_x2;
    logic [     ELEN-1:0] c_x2;
    logic [     ELEN-1:0] a_x3;
    logic [     ELEN-1:0] b_x3;
    logic [     ELEN-1:0] div_x3;
    logic [     ELEN-1:0] div_x4;
    logic [     ELEN-1:0] mul_x4;
    logic [     ELEN-1:0] mul_res;
    logic [     ELEN-1:0] sat_res;
    logic [     ELEN-1:0] div_res;
    logic [     ELEN-1:0] res_sel;
    logic [   2*ELEN-1:0] product;
    logic                 sat;
    logic                 idone;
    logic                 fdone;
    logic [      FpW-1:0] fdv_res;
    logic [    FlagW-1:0] fdv_flg;
    logic [FlagW+FpW-1:0] fdv_q;

    for (genvar w = 0; w < Widths; w++) begin : g_w
      localparam int ElemW = 8 << w;
      localparam int WideW =
          ((2 * ElemW <= ELEN) && ((l + 1) * 2 * ElemW <= VLEN)) ? 2 * ElemW : ElemW;
      assign a_w[w] = narrow_ex ? ELEN'(vs2_data[l*WideW+:WideW]) : ELEN'(vs2_data[l*ElemW+:ElemW]);
      assign b_w[w] = ELEN'(vs1_data[l*ElemW+:ElemW]);
      assign s_w[w] = ELEN'(vs2_data[l*ElemW+:ElemW]);
      assign d_w[w] = wmul_ex ? ELEN'(vd_data[l*WideW+:WideW]) : ELEN'(vd_data[l*ElemW+:ElemW]);
    end

    assign a_ex = vd_mul_ex ? d_w[vsew_ex[WSelW-1:0]] : a_w[vsew_ex[WSelW-1:0]];
    assign c_ex = vd_mul_ex ? s_w[vsew_ex[WSelW-1:0]] : d_w[vsew_ex[WSelW-1:0]];
    always_comb begin
      case (src_ex)
        VEC_SRC_VX: b_ex = ELEN'(xdata_ex);
        VEC_SRC_VI: b_ex = imm_ex;
        default:    b_ex = b_w[vsew_ex[WSelW-1:0]];
      endcase
    end

    always_ff @(posedge clk) begin
      if (core_en) begin
        a_x2   <= a_ex;
        b_x2   <= b_ex;
        c_x2   <= c_ex;
        a_x3   <= a_x2;
        b_x3   <= b_x2;
        div_x3 <= div_res;
        div_x4 <= div_x3;
        mul_x4 <= mul_res;
        if (fdone) fdv_q <= {fdv_flg, fdv_res};
      end
    end

    vec_mul_lane #(
        .ELEN(ELEN)
    ) u_mul (
        .clk(clk),
        .core_en(core_en),
        .op(mul_op_x2),
        .vsew(vsew_x2),
        .a(a_x2),
        .b(b_x2),
        .c(c_x2),
        .result(mul_res),
        .product(product)
    );

    vec_sat_lane #(
        .ELEN(ELEN)
    ) u_sat (
        .clk(clk),
        .core_en(core_en),
        .op(op_x3),
        .vsew(vsew_x3),
        .vxrm(vxrm_x3),
        .a(a_x3),
        .b(b_x3),
        .product(product),
        .result(sat_res),
        .sat(sat)
    );

    vec_div_lane #(
        .ELEN(ELEN)
    ) u_div (
        .clk(clk),
        .rst_n(rst_n),
        .core_en(core_en),
        .start(div_go && active_x2[l] && !fdiv_x2),
        .op(op_x2),
        .vsew(vsew_x2),
        .a(a_x2),
        .b(b_x2),
        .result(div_res),
        .busy(),
        .done(idone)
    );

    vec_fp_div_lane u_fdiv (
        .clk(clk),
        .rst_n(rst_n),
        .core_en(core_en),
        .start(div_go && active_x2[l] && fdiv_x2),
        .op(fop_x2),
        .rm(frm_x2),
        .a(FpW'(a_x2)),
        .b(FpW'(b_x2)),
        .result(fdv_res),
        .fflags(fdv_flg),
        .busy(),
        .done(fdone)
    );

    assign div_done[l] = idone || fdone;

    always_comb begin
      if (cls_x4 == VEC_CLS_SAT) res_sel = sat_res;
      else if (div_op_x4) res_sel = div_x4;
      else res_sel = mul_x4;
    end

    assign lane_res[l] = res_sel;
    assign lane_sat[l] = sat && active_x4[l];

    // Float element operands
    logic [FpW-1:0] fp_b_ex;
    assign fp_b_ex = (src_ex == VEC_SRC_VX) ? FpW'(xdata_ex) : vs1_data[l*FpW+:FpW];

    logic [  FpW-1:0] fpl_res;
    logic [FlagW-1:0] fpl_flag;

    vec_fp_lane u_fp (
        .clk(clk),
        .rst_n(rst_n),
        .core_en(core_en),
        .valid(valid_ex && fp_ex),
        .op(fop_ex),
        .rm(frm_ex),
        .a(vs2_data[l*FpW+:FpW]),
        .b(fp_b_ex),
        .c(vd_data[l*FpW+:FpW]),
        .result(fpl_res),
        .fflags(fpl_flag),
        .result_valid()
    );

    assign {fp_flag[l], fp_res[l]} = fdiv_wb ? fdv_q : {fpl_flag, fpl_res};

    assign fp_cmp[l] = fp_res[l][0];

    // Conversion lane
    logic [FpW-1:0] cvt_a_ex;
    assign cvt_a_ex = (eew_ex == VEC_EEW_WIDEN) ?
        FpW'(vs2_data[l*HalfW+:HalfW]) : vs2_data[l*FpW+:FpW];

    vec_fp_cvt_lane u_cvt (
        .clk(clk),
        .rst_n(rst_n),
        .core_en(core_en),
        .valid(valid_ex && fcvt_ex),
        .op(fop_ex),
        .eew(eew_ex),
        .vsew(vsew_ex),
        .rm(frm_ex),
        .a(cvt_a_ex),
        .result(cvt_res[l]),
        .fflags(cvt_flag[l]),
        .result_valid(cvt_vld[l])
    );
  end

  // Narrow conversion tail
  logic [VecFpLatency-1:0] fncvt_q;

  always_ff @(posedge clk) begin
    if (!rst_n) fncvt_q <= '0;
    else if (core_en) fncvt_q <= {fncvt_q[VecFpLatency-2:0], valid_ex && fcvt_ex && narrow_ex};
  end

  // Pack float results
  logic [ VLEN-1:0] fp_pack;
  logic [FlagW-1:0] fp_flags_or;

  always_comb begin
    fp_pack     = '0;
    fp_flags_or = '0;
    for (int l = 0; l < MUL_LANES; l++) begin
      if (fncvt_q[VecFpLatency-1]) fp_pack[l*HalfW+:HalfW] = cvt_res[l][HalfW-1:0];
      else fp_pack[l*FpW+:FpW] = cvt_vld[l] ? cvt_res[l] : fp_res[l];
      if (active_wb[l]) fp_flags_or = fp_flags_or | (cvt_vld[l] ? cvt_flag[l] : fp_flag[l]);
    end
  end

  // Pack lane results
  logic [VLEN-1:0] lane_pack[Widths];
  logic [VLEN-1:0] lane_result;

  for (genvar w = 0; w < Widths; w++) begin : g_pack
    localparam int ElemW = 8 << w;
    for (genvar l = 0; l < MUL_LANES; l++) begin : g_l
      assign lane_pack[w][l*ElemW+:ElemW] = lane_res[l][ElemW-1:0];
    end
    if (MUL_LANES * ElemW < VLEN) begin : g_top
      assign lane_pack[w][VLEN-1:MUL_LANES*ElemW] = '0;
    end
  end

  assign lane_result = lane_pack[vsew_x4[WSelW-1:0]+WSelW'(wmul_x4)];

  // Divide stall
  assign fdiv_ex = (cls_ex == VEC_CLS_FP) && is_fdiv(fop_ex);
  assign fdiv_x2 = (cls_x2 == VEC_CLS_FP) && is_fdiv(fop_x2);
  assign div_op_x2 = is_div(op_x2) || fdiv_x2;
  assign div_op_x4 = is_div(op_x4);
  assign div_go = valid_x2 && div_op_x2 && !div_run_q;
  assign div_stall = valid_x2 && div_op_x2 && (!div_run_q || ((div_pend_q & ~div_done) != '0));
  assign div_hold = (valid_ex && is_div(
      op_ex
  )) || (valid_ex && fdiv_ex) || div_stall || div_run_q || div_tail_q || (valid_x4 && fdiv_x4);

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      div_run_q  <= 1'b0;
      div_tail_q <= 1'b0;
      div_pend_q <= '0;
    end else if (core_en) begin
      div_run_q  <= div_stall;
      div_tail_q <= div_run_q;
      if (div_go) div_pend_q <= active_x2;
      else div_pend_q <= div_pend_q & ~div_done;
    end
  end

  // Deep units
  logic deep_ex;
  assign deep_ex = (cls_ex == VEC_CLS_RED) || (cls_ex == VEC_CLS_MUL) || (cls_ex == VEC_CLS_SAT) ||
      fp_ex;

  // EX/X2
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      valid_x2    <= 1'b0;
      wen_x2      <= 1'b0;
      reg_done_x2 <= 1'b0;
      last_x2     <= 1'b0;
    end else if (core_en && !div_stall) begin
      valid_x2    <= valid_ex && deep_ex;
      wen_x2      <= wen_ex && deep_ex;
      reg_done_x2 <= reg_done_ex && deep_ex;
      last_x2     <= last_ex && deep_ex;
      cls_x2      <= cls_ex;
      op_x2       <= op_ex;
      fop_x2      <= fop_ex;
      frm_x2      <= frm_ex;
      vsew_x2     <= vsew_ex;
      vxrm_x2     <= vxrm_ex;
      wmul_x2     <= wmul_ex;
      active_x2   <= elem_active_ex[MUL_LANES-1:0];
      fsum_x2     <= fsum_ex;
      d_off_x2    <= d_off_ex;
      waddr_x2    <= waddr_ex;
      wstrb_x2    <= wstrb_ex;
    end
  end

  // X2/X3
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      valid_x3    <= 1'b0;
      wen_x3      <= 1'b0;
      reg_done_x3 <= 1'b0;
      last_x3     <= 1'b0;
    end else if (core_en) begin
      valid_x3    <= valid_x2 && lane_x2 && !div_stall;
      wen_x3      <= wen_x2 && lane_x2 && !div_stall;
      reg_done_x3 <= reg_done_x2 && lane_x2 && !div_stall;
      last_x3     <= last_x2 && lane_x2 && !div_stall;
      cls_x3      <= cls_x2;
      op_x3       <= op_x2;
      fdiv_x3     <= fdiv_x2;
      vsew_x3     <= vsew_x2;
      vxrm_x3     <= vxrm_x2;
      wmul_x3     <= wmul_x2;
      active_x3   <= active_x2;
      fsum_x3     <= fsum_x2;
      d_off_x3    <= d_off_x2;
      waddr_x3    <= waddr_x2;
      wstrb_x3    <= wstrb_x2;
    end
  end

  // X3/X4
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      valid_x4    <= 1'b0;
      wen_x4      <= 1'b0;
      reg_done_x4 <= 1'b0;
      last_x4     <= 1'b0;
    end else if (core_en) begin
      valid_x4    <= valid_x3;
      wen_x4      <= wen_x3;
      reg_done_x4 <= reg_done_x3;
      last_x4     <= last_x3;
      cls_x4      <= cls_x3;
      op_x4       <= op_x3;
      fdiv_x4     <= fdiv_x3;
      vsew_x4     <= vsew_x3;
      wmul_x4     <= wmul_x3;
      active_x4   <= active_x3;
      fsum_x4     <= fsum_x3;
      d_off_x4    <= d_off_x3;
      waddr_x4    <= waddr_x3;
      wstrb_x4    <= wstrb_x3;
    end
  end

  // Float lane tail
  logic fp_x4;
  logic fp_wb;

  assign fp_x4 = (cls_x4 == VEC_CLS_FP) || (cls_x4 == VEC_CLS_FCMP);
  assign fp_wb = (cls_wb == VEC_CLS_FP) || (cls_wb == VEC_CLS_FCMP);

  // X4/X5
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      valid_x5    <= 1'b0;
      wen_x5      <= 1'b0;
      reg_done_x5 <= 1'b0;
      last_x5     <= 1'b0;
    end else if (core_en) begin
      valid_x5    <= valid_x4 && fp_x4;
      wen_x5      <= wen_x4 && fp_x4;
      reg_done_x5 <= reg_done_x4 && fp_x4;
      last_x5     <= last_x4 && fp_x4;
      cls_x5      <= cls_x4;
      fdiv_x5     <= fdiv_x4;
      active_x5   <= active_x4;
      d_off_x5    <= d_off_x4;
      waddr_x5    <= waddr_x4;
      wstrb_x5    <= wstrb_x4;
    end
  end

  // Writeback stage
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      valid_wb    <= 1'b0;
      wen_wb      <= 1'b0;
      reg_done_wb <= 1'b0;
      last_wb     <= 1'b0;
      sat_wb      <= 1'b0;
    end else if (core_en) begin
      sat_wb <= valid_x4 && (cls_x4 == VEC_CLS_SAT) && (lane_sat != '0);
      if (valid_x5) begin  // Slot keeps one
        valid_wb    <= 1'b1;
        wen_wb      <= wen_x5;
        reg_done_wb <= reg_done_x5;
        last_wb     <= last_x5;
        cls_wb      <= cls_x5;
        d_off_wb    <= d_off_x5;
        waddr_wb    <= waddr_x5;
        wstrb_wb    <= wstrb_x5;
      end else if (valid_x4 && !fp_x4) begin
        valid_wb    <= 1'b1;
        wen_wb      <= wen_x4;
        reg_done_wb <= reg_done_x4;
        last_wb     <= last_x4;
        cls_wb      <= cls_x4;
        d_off_wb    <= d_off_x4;
        waddr_wb    <= waddr_x4;
        wstrb_wb    <= wstrb_x4;
      end else if (valid_x2 && !lane_x2) begin
        valid_wb    <= 1'b1;
        wen_wb      <= wen_x2;
        reg_done_wb <= reg_done_x2;
        last_wb     <= last_x2;
        cls_wb      <= cls_x2;
        d_off_wb    <= d_off_x2;
        waddr_wb    <= waddr_x2;
        wstrb_wb    <= wstrb_x2;
      end else begin
        valid_wb    <= valid_ex && !deep_ex;
        wen_wb      <= wen_ex && !deep_ex;
        reg_done_wb <= reg_done_ex && !deep_ex;
        last_wb     <= last_ex && !deep_ex;
        cls_wb      <= cls_ex;
        d_off_wb    <= d_off_ex;
        waddr_wb    <= waddr_ex;
        wstrb_wb    <= wstrb_ex;
      end
      xdata_wb        <= xdata_ex;
      alu_result_wb   <= alu_result;
      mixed_result_wb <= mixed_result;
      red_result_wb   <= red_pick;
      mask_result_wb  <= mask_result;
      lane_result_wb  <= lane_result;
      active_wb       <= active_x5;
      fdiv_wb         <= fdiv_x5;
    end
  end

  // Result select
  always_comb begin
    case (cls_wb)
      VEC_CLS_MIXED:                                         raw_result = mixed_result_wb;
      VEC_CLS_RED:                                           raw_result = red_result_wb;
      VEC_CLS_MUL, VEC_CLS_SAT:                              raw_result = lane_result_wb;
      VEC_CLS_FP:                                            raw_result = fp_pack;
      VEC_CLS_FCMP:                                          raw_result = VLEN'(fp_cmp);
      VEC_CLS_SX:                                            raw_result = VLEN'(xdata_wb);
      VEC_CLS_CMP, VEC_CLS_MLOG, VEC_CLS_MSET, VEC_CLS_IOTA: raw_result = mask_result_wb;
      default:                                               raw_result = alu_result_wb;
    endcase
  end

  assign wdata = raw_result << d_off_wb;

  // Scalar return path
  logic [XLEN-1:0] xres_q;
  logic [XLEN-1:0] elem_zero;
  logic [XLEN-1:0] xs_val;
  logic [XLEN-1:0] xm_val;

  logic [XLEN-1:0] elem_zero_w[Widths];

  for (genvar w = 0; w < Widths; w++) begin : g_zero
    localparam int ElemW = 8 << w;
    assign elem_zero_w[w] = XLEN'($signed(rdata2[ElemW-1:0]));
  end

  assign elem_zero = elem_zero_w[vec_sew_index(seq_vsew, Widths)];

`ifdef RISCV_FORMAL_ABSTRACT_XRES
  // Free scalar result
  (* anyseq *) logic [XLEN-1:0] fv_xres;
  assign xs_val = fv_xres;
  assign xm_val = fv_xres;
`else
  assign xs_val = elem_zero;
  assign xm_val = mask_xresult;
`endif

  always_ff @(posedge clk) begin
    if (!rst_n) xres_q <= '0;
    else if (core_en) begin
      if (seq_busy && (elem_base == '0) && (seq_cls == VEC_CLS_XS)) xres_q <= xs_val;
      else if ((valid_ex || slot_first_ex) && (cls_ex == VEC_CLS_XM)) xres_q <= xm_val;
    end
  end

  // Final capture
  assign x_done = (seq_busy && (elem_base == '0) && (seq_cls == VEC_CLS_XS)) ||
      ((cls_ex == VEC_CLS_XM) && ((valid_ex && last_ex) || (slot_first_ex && (vl_ex == '0))));

  assign xreg_valid = dec_writes_xreg && is_vector;
  assign xreg_result = xres_q;
  assign vec_hold = issue_hold || (csr_wait && !vec_idle);
  assign fflags = ((valid_wb && fp_wb) ? fp_flags_or : '0) | fred_flags_wb;

`ifdef RISCV_FORMAL
  // Retire after last write
  logic                          retire_wb_q;
  logic                          zero_q;
  logic                          retire;
  logic [$bits(dbg_vec_tag)-1:0] tag_q;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      retire_wb_q <= 1'b0;
      zero_q      <= 1'b0;
    end else if (core_en) begin
      retire_wb_q <= last_wb;
      zero_q      <= seq_start && !seq_mem && !seq_slide && (seq_vl == '0);
    end
  end

  assign retire = retire_wb_q || m_done || sl_done || zero_q;

  always_ff @(posedge clk) begin
    if (!rst_n) tag_q <= '0;
    else if (core_en && retire) tag_q <= tag_q + 1'b1;
  end

  // Registers written
  logic [ NRegs-1:0] wr_mask_q;
  logic              wr_en;
  logic [AWIDTH-1:0] wr_addr;

  assign wr_en   = rf_we;
  assign wr_addr = rf_waddr;

  always_ff @(posedge clk) begin
    if (!rst_n) wr_mask_q <= '0;
    else if (core_en) begin
      if (retire) wr_mask_q <= wr_en ? (NRegs'(1) << wr_addr) : '0;
      else if (wr_en) wr_mask_q[wr_addr] <= 1'b1;
    end
  end

  assign dbg_vec_tag    = tag_q;
  assign dbg_vec_retire = retire;
  assign dbg_vec_wregs  = wr_mask_q;
  assign dbg_vec_idle   = vec_idle;
`endif

endmodule

`default_nettype wire
