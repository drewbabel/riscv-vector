`default_nettype none

module csr
  import csr_pkg::*;
#(
    parameter  int XLEN     = arch_pkg::XLEN,
    parameter  int VLEN     = arch_pkg::VLEN,
    localparam int VlW      = $clog2(VLEN + 1),
    localparam int VstartW  = $clog2(VLEN),
    localparam int RegAddrW = arch_pkg::RegAddrW,
    localparam int Funct3W  = opcode_pkg::Funct3W,
    localparam int InstrLsb = arch_pkg::InstrLsb,
    localparam int FlagW    = fp_pkg::FlagW,
    localparam int RmW      = fp_pkg::RmW
) (
`ifdef RISCV_FORMAL
    output logic [   XLEN-1:0] dbg_csr_wdata,
    output logic [   XLEN-1:0] dbg_mscratch,
    output logic [   XLEN-1:0] dbg_mstatus,
    output logic [   XLEN-1:0] dbg_mtvec,
    output logic [   XLEN-1:0] dbg_mepc,
    output logic [   XLEN-1:0] dbg_mcause,
    output logic [   XLEN-1:0] dbg_mtval,
    output logic [   XLEN-1:0] dbg_mie,
    output logic [   XLEN-1:0] dbg_mip,
    output logic [   XLEN-1:0] dbg_mcycle,
    output logic [   XLEN-1:0] dbg_minstret,
    output logic [   XLEN-1:0] dbg_mcycleh,
    output logic [   XLEN-1:0] dbg_minstreth,
    output logic [        7:0] dbg_vtype_bits,
    output logic               dbg_vtype_ill,
    output logic [VstartW-1:0] dbg_vstart,
    output logic [  FlagW-1:0] dbg_fflags,
`endif
    input  wire                clk,
    input  wire                core_en,
    input  wire                cycle_en,
    input  wire                rst_n,

    // Zicsr access
    input wire                csr_access,
    input wire [CsrAddrW-1:0] csr_addr,
    input wire [ Funct3W-1:0] funct3,
    input wire [    XLEN-1:0] rs1_data,
    input wire [RegAddrW-1:0] zimm,

    // Trapped-instruction context
    input wire [XLEN-1:0] pc,
    input wire [XLEN-1:0] bad_addr,

    // Exception sources
    input wire exc_illegal,
    input wire exc_ecall,
    input wire exc_ebreak,
    input wire exc_instr_misaligned,
    input wire exc_load_misaligned,
    input wire exc_store_misaligned,

    // Interrupts
    input wire is_mret,
    input wire timer_irq,
    input wire ext_irq,

    // Zicsr read value to writeback mux
    output logic [XLEN-1:0] csr_rdata,

    // Redirects into pc next-address mux
    output logic            trap_taken,
    output logic [XLEN-1:0] trap_vector,
    output logic            mret_taken,
    output logic [XLEN-1:0] mepc_out,

    // Vector configuration
    input  wire             is_vset,
    input  wire  [ VlW-1:0] vl_next,
    input  wire  [XLEN-1:0] vtype_next,
    input  wire             is_vec_instr,
    output logic [ VlW-1:0] vl_q,
    output logic [XLEN-1:0] vtype_q,

    // Fixed-point control
    input  wire  [   VxrmW-1:0] vec_vxrm,
    input  wire                 vec_vxsat,
    output logic                vec_csr_we,
    output logic [CsrAddrW-1:0] vec_csr_waddr,
    output logic [    XLEN-1:0] vec_csr_wdata,

    // Floating-point control
    input  wire              is_fp_instr,
    input  wire              fp_state_we,
    input  wire              fp_flags_we,
    input  wire  [FlagW-1:0] fp_flags,
    input  wire              fp_wb_flags_we,
    input  wire  [FlagW-1:0] fp_wb_flags,
    input  wire  [FlagW-1:0] vec_fflags,
    output logic [  RmW-1:0] frm_q,
    output logic             vstart_set
);

  if (XLEN != 32) begin : g_xlen
    $error("csr implements RV32 only");
  end

  logic [   XLEN-1:0] mstatus;
  logic [   XLEN-1:0] mtvec;
  logic [   XLEN-1:0] mepc;
  logic [   XLEN-1:0] mcause;
  logic [   XLEN-1:0] mtval;
  logic [   XLEN-1:0] mie;
  logic [   XLEN-1:0] mip;
  logic [   XLEN-1:0] mscratch;
  logic [   XLEN-1:0] mcycle;
  logic [   XLEN-1:0] minstret;
  logic [   XLEN-1:0] mcycleh;
  logic [   XLEN-1:0] minstreth;

  logic [    VlW-1:0] vl;
  logic [        7:0] vtype_bits;
  logic               vtype_ill;
  logic [VstartW-1:0] vstart;

  logic [  FlagW-1:0] fflags;
  logic [    RmW-1:0] frm;

  logic [   XLEN-1:0] mstatus_read;
  logic               vec_csr_addr;
  logic               fp_csr_addr;
  logic               exc_ro_write;
  logic [ CsrRoW-1:0] csr_access_bits;
  logic [   XLEN-1:0] mtvec_base;
  logic               exc_vs_off;
  logic               exc_fs_off;
  logic               illegal_any;

  logic [   XLEN-1:0] csr_wsrc;
  logic               csr_write;
  logic [   XLEN-1:0] csr_wdata;
  logic               csr_write_en;
  logic               timer_ready;
  logic               ext_ready;

  assign csr_wsrc = (funct3[2]) ? XLEN'(zimm) : rs1_data;
  assign csr_write = !funct3[1] || zimm != 0;
  assign csr_access_bits = csr_addr[CsrAddrW-1-:CsrRoW];
  assign mtvec_base = {mtvec[XLEN-1:MtvecModeW], MtvecModeW'(0)};
  always_comb begin
    case (funct3)
      Funct3Csrrw, Funct3Csrrwi: csr_wdata = csr_wsrc;
      Funct3Csrrs, Funct3Csrrsi: csr_wdata = csr_rdata | csr_wsrc;
      Funct3Csrrc, Funct3Csrrci: csr_wdata = csr_rdata & ~csr_wsrc;
      default:                   csr_wdata = csr_rdata;
    endcase
  end
  assign timer_ready = timer_irq & mstatus[MstatusMie] & mie[Mtie];
  assign ext_ready = ext_irq & mstatus[MstatusMie] & mie[Meie];
  assign trap_taken = illegal_any | exc_ecall | exc_ebreak | exc_instr_misaligned |
      exc_load_misaligned | exc_store_misaligned | timer_ready | ext_ready;
  // Reject if trap, or if set/clear with zero source
  assign csr_write_en = csr_access && !trap_taken && csr_write;
  assign trap_vector = mtvec_base;
  assign mret_taken = is_mret;
  assign mepc_out = mepc;

  assign vl_q = vl;
  assign vtype_q = vtype_ill ? {1'b1, {XLEN - 1{1'b0}}} : XLEN'(vtype_bits);
  assign frm_q = frm;
  assign vstart_set = vstart != '0;
  assign mstatus_read = mstatus | (XLEN'((mstatus[MstatusVsLo+1:MstatusVsLo] == VsDirty) ||
      (mstatus[MstatusFsLo+1:MstatusFsLo] == FsDirty)) << MstatusSd);
  assign vec_csr_addr = (csr_addr == VstartAddr) || (csr_addr == VlAddr) ||
      (csr_addr == VtypeAddr) || (csr_addr == VlenbAddr) || (csr_addr == VxsatAddr) ||
      (csr_addr == VxrmAddr) || (csr_addr == VcsrAddr);
  assign fp_csr_addr = (csr_addr == FflagsAddr) || (csr_addr == FrmAddr) || (csr_addr == FcsrAddr);
  assign vec_csr_we = csr_write_en &&
      ((csr_addr == VxsatAddr) || (csr_addr == VxrmAddr) || (csr_addr == VcsrAddr));
  assign vec_csr_waddr = csr_addr;
  assign vec_csr_wdata = csr_wdata;
  assign exc_ro_write = csr_access && (csr_access_bits == CsrRoAccess) && csr_write;
  assign exc_vs_off = (is_vec_instr || (csr_access && vec_csr_addr)) &&
      (mstatus[MstatusVsLo+1:MstatusVsLo] == VsOff);
  assign exc_fs_off = (is_fp_instr || (csr_access && fp_csr_addr)) &&
      (mstatus[MstatusFsLo+1:MstatusFsLo] == FsOff);
  assign illegal_any = exc_illegal || exc_ro_write || exc_vs_off || exc_fs_off;

  logic [XLEN-1:0] mip_read;
  always_comb begin
    mip_read = mip;
    mip_read[Mtip] = timer_irq;
    mip_read[Meip] = ext_irq;
  end

  // Read mux
  always_comb begin
    case (csr_addr)
      MstatusAddr: csr_rdata = mstatus_read;
      MieAddr: csr_rdata = mie;
      MtvecAddr: csr_rdata = mtvec;
      MscratchAddr: csr_rdata = mscratch;
      MepcAddr: csr_rdata = mepc;
      McauseAddr: csr_rdata = mcause;
      MtvalAddr: csr_rdata = mtval;
      MipAddr: csr_rdata = mip_read;
      McycleAddr: csr_rdata = mcycle;
      MinstretAddr: csr_rdata = minstret;
      McyclehAddr: csr_rdata = mcycleh;
      MinstrethAddr: csr_rdata = minstreth;
      VlAddr: csr_rdata = {{XLEN - VlW{1'b0}}, vl};
      VtypeAddr: csr_rdata = vtype_q;
      VlenbAddr: csr_rdata = XLEN'(VLEN / 8);
      VstartAddr: csr_rdata = {{XLEN - VstartW{1'b0}}, vstart};
      VxsatAddr: csr_rdata = {{XLEN - 1{1'b0}}, vec_vxsat};
      VxrmAddr: csr_rdata = XLEN'(vec_vxrm);
      VcsrAddr: csr_rdata = XLEN'({vec_vxrm, vec_vxsat});
      FflagsAddr: csr_rdata = XLEN'(fflags);
      FrmAddr: csr_rdata = XLEN'(frm);
      FcsrAddr: csr_rdata = XLEN'({frm, fflags});
      default: csr_rdata = '0;
    endcase
  end

  // Counts
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      mcycle  <= '0;
      mcycleh <= '0;
    end else begin
      if (cycle_en) begin
        mcycle  <= mcycle + 1;
        mcycleh <= (mcycle == '1) ? mcycleh + 1 : mcycleh;
      end
      if (core_en && csr_write_en) begin
        if (csr_addr == McycleAddr) mcycle <= csr_wdata;
        if (csr_addr == McyclehAddr) mcycleh <= csr_wdata;
      end
    end
  end

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      mstatus    <= '0;
      mtvec      <= '0;
      mepc       <= '0;
      mcause     <= '0;
      mtval      <= '0;
      mie        <= '0;
      mip        <= '0;
      mscratch   <= '0;
      minstret   <= '0;
      minstreth  <= '0;
      vl         <= '0;
      vtype_bits <= '0;
      vtype_ill  <= 1'b1;
      vstart     <= '0;
      frm        <= '0;
    end else if (core_en) begin
      if (vec_fflags != '0) mstatus[MstatusFsLo+1:MstatusFsLo] <= FsDirty;  // Late vector flags
      if (!trap_taken) begin  // retired only
        minstret  <= minstret + 1;
        minstreth <= (minstret == '1) ? minstreth + 1 : minstreth;
      end

      if (trap_taken) begin
        mstatus[MstatusMpie] <= mstatus[MstatusMie];
        mstatus[MstatusMie] <= 1'b0;
        mepc <= pc;
        if (exc_instr_misaligned) begin
          mcause <= {1'b0, (XLEN - 1)'(CauseInstrMisaligned)};
          mtval  <= bad_addr;
        end else if (illegal_any) begin
          mcause <= {1'b0, (XLEN - 1)'(CauseIllegalInstr)};
          mtval  <= '0;
        end else if (exc_ecall) begin
          mcause <= {1'b0, (XLEN - 1)'(CauseEcallM)};
          mtval  <= '0;
        end else if (exc_ebreak) begin
          mcause <= {1'b0, (XLEN - 1)'(CauseBreakpoint)};
          mtval  <= '0;
        end else if (exc_load_misaligned) begin
          mcause <= {1'b0, (XLEN - 1)'(CauseLoadMisaligned)};
          mtval  <= bad_addr;
        end else if (exc_store_misaligned) begin
          mcause <= {1'b0, (XLEN - 1)'(CauseStoreMisaligned)};
          mtval  <= bad_addr;
        end else begin
          mcause <= ext_ready ? {1'b1, (XLEN - 1)'(CauseMachineExternalIrq)} :
              {1'b1, (XLEN - 1)'(CauseMachineTimerIrq)};
          mtval <= '0;
        end
      end else begin
        if (is_mret) begin
          mstatus[MstatusMie]  <= mstatus[MstatusMpie];
          mstatus[MstatusMpie] <= 1'b1;
        end
        if (is_vset) begin  // store vec_config computation on config instr
          vl <= vl_next;
          vtype_bits <= vtype_next[$bits(vtype_bits)-1:0];
          vtype_ill <= vtype_next[XLEN-1];
        end
        if (is_vec_instr) begin
          vstart <= '0;  // Clear on vector finish
        end
        // Software directly writing
        if (csr_write_en && csr_addr == VstartAddr) begin
          vstart <= csr_wdata[VstartW-1:0];
        end
        if (is_vec_instr || (csr_write_en && vec_csr_addr)) begin
          mstatus[MstatusVsLo+1:MstatusVsLo] <= VsDirty;  // Assign dirty state
        end
        if ((is_fp_instr && fp_state_we) || (fp_flags_we && fp_flags != '0) ||
            (csr_write_en && fp_csr_addr)) begin
          mstatus[MstatusFsLo+1:MstatusFsLo] <= FsDirty;
        end
      end

      if (csr_write_en) begin
        case (csr_addr)
          MstatusAddr:   mstatus <= csr_wdata & MstatusMask;
          MieAddr:       mie <= csr_wdata;
          MtvecAddr:     mtvec <= csr_wdata;
          MscratchAddr:  mscratch <= csr_wdata;
          MepcAddr:      mepc <= {csr_wdata[XLEN-1:InstrLsb], InstrLsb'(0)};  // mepc word aligned
          McauseAddr:    mcause <= csr_wdata;
          MtvalAddr:     mtval <= csr_wdata;
          // Read only
          MipAddr:       mip <= csr_wdata & ~(XLEN'(1) << Mtip) & ~(XLEN'(1) << Meip);
          MinstretAddr:  minstret <= csr_wdata;
          MinstrethAddr: minstreth <= csr_wdata;
          FrmAddr:       frm <= csr_wdata[RmW-1:0];
          FcsrAddr:      frm <= csr_wdata[FlagW+:RmW];
          default:       ;
        endcase
      end
    end else if (cycle_en && (vec_fflags != '0)) begin
      mstatus[MstatusFsLo+1:MstatusFsLo] <= FsDirty;
    end
  end

  logic [FlagW-1:0] fp_wb_flags_live;
  logic [FlagW-1:0] fp_flags_live;
  assign fp_wb_flags_live = fp_wb_flags & {FlagW{fp_wb_flags_we}};
  assign fp_flags_live = fp_flags & {FlagW{core_en && !trap_taken && fp_flags_we}};

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      fflags <= '0;
    end else if (cycle_en) begin
      if (core_en && csr_write_en && ((csr_addr == FflagsAddr) || (csr_addr == FcsrAddr))) begin
        fflags <= csr_wdata[FlagW-1:0];
      end else begin
        fflags <= fflags | fp_wb_flags_live | vec_fflags | fp_flags_live;
      end
    end
  end

`ifdef RISCV_FORMAL
  assign dbg_csr_wdata  = csr_wdata;
  assign dbg_mscratch   = mscratch;
  assign dbg_mstatus    = mstatus;
  assign dbg_mtvec      = mtvec;
  assign dbg_mepc       = mepc;
  assign dbg_mcause     = mcause;
  assign dbg_mtval      = mtval;
  assign dbg_mie        = mie;
  assign dbg_mip        = mip;
  assign dbg_mcycle     = mcycle;
  assign dbg_minstret   = minstret;
  assign dbg_mcycleh    = mcycleh;
  assign dbg_minstreth  = minstreth;
  assign dbg_vtype_bits = vtype_bits;
  assign dbg_vtype_ill  = vtype_ill;
  assign dbg_vstart     = vstart;
  assign dbg_fflags     = fflags;
`endif
endmodule

`default_nettype wire
