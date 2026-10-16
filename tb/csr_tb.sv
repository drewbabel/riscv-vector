`default_nettype none

module csr_tb;
  import csr_pkg::*;

  int checks = 0;
  int errors = 0;
  int max_errors = 0;

  localparam int Xlen = arch_pkg::XLEN;
  localparam int Vlen = arch_pkg::VLEN;
  localparam int VlW = $clog2(Vlen + 1);
  localparam int VstartW = $clog2(Vlen);
  localparam int MinChecks = 853;

  logic               clk;
  logic               rst_n;
  logic               csr_access;
  logic [       11:0] csr_addr;
  logic [        2:0] funct3;
  logic [   Xlen-1:0] rs1_data;
  logic [        4:0] zimm;
  logic [        4:0] src_spec = 5'd1;  // rs1 field
  logic [   Xlen-1:0] pc;
  logic [   Xlen-1:0] bad_addr;
  logic               exc_illegal;
  logic               exc_ecall;
  logic               exc_ebreak;
  logic               exc_instr_misaligned;
  logic               exc_load_misaligned;
  logic               exc_store_misaligned;
  logic               is_mret;
  logic               timer_irq;
  logic               ext_irq;
  logic [   Xlen-1:0] csr_rdata;
  logic               trap_taken;
  logic [   Xlen-1:0] trap_vector;
  logic               mret_taken;
  logic [   Xlen-1:0] mepc_out;

  logic               is_vset;
  logic [    VlW-1:0] vl_d;
  logic [   Xlen-1:0] vtype_d;
  logic               is_vec_instr;
  logic [        1:0] vec_vxrm;
  logic               vec_vxsat;
  logic               vec_csr_we;
  logic [       11:0] vec_csr_waddr;
  logic [   Xlen-1:0] vec_csr_wdata;
  logic [    VlW-1:0] vl_q;
  logic [   Xlen-1:0] vtype_q;

  logic               core_en;
  logic               is_fp_instr;
  logic               fp_state_we;
  logic               fp_flags_we;
  logic [        4:0] fp_flags;
  logic [        2:0] frm_q;

  logic [   Xlen-1:0] exp_mscratch;
  logic [VstartW-1:0] exp_vstart;
  logic [        4:0] exp_fflags;
  logic [        2:0] exp_frm;

  initial void'($value$plusargs("max_errors=%d", max_errors));

  initial clk = 0;
  always #5 clk = ~clk;

  csr #(
      .XLEN(Xlen),
      .VLEN(Vlen)
  ) dut (
      .clk                 (clk),
      .core_en             (core_en),
      .cycle_en            (1'b1),
      .rst_n               (rst_n),
      .csr_access          (csr_access),
      .csr_addr            (csr_addr),
      .funct3              (funct3),
      .rs1_data            (rs1_data),
      .zimm                (zimm),
      .pc                  (pc),
      .bad_addr            (bad_addr),
      .exc_illegal         (exc_illegal),
      .exc_ecall           (exc_ecall),
      .exc_ebreak          (exc_ebreak),
      .exc_instr_misaligned(exc_instr_misaligned),
      .exc_load_misaligned (exc_load_misaligned),
      .exc_store_misaligned(exc_store_misaligned),
      .is_mret             (is_mret),
      .timer_irq           (timer_irq),
      .ext_irq             (ext_irq),
      .csr_rdata           (csr_rdata),
      .trap_taken          (trap_taken),
      .trap_vector         (trap_vector),
      .mret_taken          (mret_taken),
      .mepc_out            (mepc_out),
      .is_vset             (is_vset),
      .vl_d                (vl_d),
      .vtype_d             (vtype_d),
      .is_vec_instr        (is_vec_instr),
      .vl_q                (vl_q),
      .vtype_q             (vtype_q),
      .vec_vxrm            (vec_vxrm),
      .vec_vxsat           (vec_vxsat),
      .vec_csr_we          (vec_csr_we),
      .vec_csr_waddr       (vec_csr_waddr),
      .vec_csr_wdata       (vec_csr_wdata),
      .is_fp_instr         (is_fp_instr),
      .fp_state_we         (fp_state_we),
      .fp_flags_we         (fp_flags_we),
      .fp_flags            (fp_flags),
      .frm_q               (frm_q)
  );

  task automatic check(input string name, input logic [Xlen-1:0] got, input logic [Xlen-1:0] exp);
    checks++;
    if (got !== exp) begin
      errors++;
      $error("%s: got %h exp %h", name, got, exp);
      if (errors == max_errors) $fatal(1, "TB STOPPED: %0d mismatches", errors);
    end
  endtask

  // Idle inputs, reset
  task automatic do_reset();
    csr_access                                                        = 0;
    csr_addr                                                          = 0;
    funct3                                                            = 0;
    rs1_data                                                          = 0;
    zimm                                                              = 0;
    pc                                                                = 0;
    bad_addr                                                          = 0;
    is_mret                                                           = 0;
    timer_irq                                                         = 0;
    ext_irq                                                           = 0;
    is_vset                                                           = 0;
    is_vec_instr                                                      = 0;
    vec_vxrm                                                          = 2'd0;
    vec_vxsat                                                         = 1'b0;
    vl_d                                                              = 0;
    vtype_d                                                           = 0;
    {exc_illegal, exc_ecall, exc_ebreak}                              = 0;
    {exc_instr_misaligned, exc_load_misaligned, exc_store_misaligned} = 0;
    exp_mscratch                                                      = 0;
    exp_vstart                                                        = 0;
    core_en                                                           = 1;
    is_fp_instr                                                       = 0;
    fp_state_we                                                       = 0;
    fp_flags_we                                                       = 0;
    fp_flags                                                          = 0;
    exp_fflags                                                        = 0;
    exp_frm                                                           = 0;
    rst_n                                                             = 0;
    @(posedge clk);
    @(posedge clk);
    rst_n = 1;
  endtask

  // Drive one access
  task automatic csr_drive(input logic [2:0] op, input logic [11:0] addr,
                           input logic [Xlen-1:0] val);
    #1;
    csr_addr   = addr;
    funct3     = op;
    rs1_data   = val;
    zimm       = op[2] ? val[4:0] : src_spec;
    csr_access = 1;
  endtask

  // Commit the access
  task automatic csr_commit();
    @(posedge clk);
    #1;
    csr_access = 0;
  endtask

  // Access any address
  task automatic csr_op(input logic [2:0] op, input logic [11:0] addr, input logic [Xlen-1:0] val);
    csr_drive(op, addr, val);
    csr_commit();
  endtask

  // Access, sample trap
  task automatic csr_trap(input string name, input logic [2:0] op, input logic [11:0] addr,
                          input logic [Xlen-1:0] val, input logic exp);
    csr_drive(op, addr, val);
    #1;
    check(name, Xlen'(trap_taken), Xlen'(exp));
    csr_commit();
  endtask

  // Read without writing
  task automatic csr_peek(input logic [11:0] addr);
    #1;
    csr_access = 0;
    csr_addr   = addr;
    #1;
  endtask

  // One vector instruction
  task automatic vec_instr(input logic set_cfg, input logic [VlW-1:0] next_vl,
                           input logic [Xlen-1:0] next_vtype);
    #1;
    is_vec_instr = 1;
    is_vset      = set_cfg;
    vl_d         = next_vl;
    vtype_d      = next_vtype;
    @(posedge clk);
    #1;
    is_vec_instr = 0;
    is_vset      = 0;
  endtask

  // Vector instruction, sample trap
  task automatic vec_trap(input string name, input logic exp);
    #1;
    is_vec_instr = 1;
    #1;
    check(name, Xlen'(trap_taken), Xlen'(exp));
    @(posedge clk);
    #1;
    is_vec_instr = 0;
  endtask

  // Interrupt lines
  task automatic set_irq(input logic timer, input logic ext);
    timer_irq = timer;
    ext_irq   = ext;
    #1;
  endtask

  // Set vector status
  task automatic set_vs(input logic [1:0] vs);
    csr_op(Funct3Csrrw, MstatusAddr, Xlen'(vs) << MstatusVsLo);
  endtask

  function automatic logic [2:0] op_of(input int idx);
    case (idx)
      0: op_of = Funct3Csrrw;
      1: op_of = Funct3Csrrs;
      2: op_of = Funct3Csrrc;
      3: op_of = Funct3Csrrwi;
      4: op_of = Funct3Csrrsi;
      default: op_of = Funct3Csrrci;
    endcase
  endfunction

  // Bitwise reference
  function automatic logic [VstartW-1:0] model_vstart(
      input logic [2:0] op, input logic [VstartW-1:0] cur, input logic [Xlen-1:0] src);
    for (int i = 0; i < VstartW; i++) begin
      case (op)
        Funct3Csrrw, Funct3Csrrwi: model_vstart[i] = src[i];
        Funct3Csrrs, Funct3Csrrsi: model_vstart[i] = cur[i] | src[i];
        Funct3Csrrc, Funct3Csrrci: model_vstart[i] = cur[i] & ~src[i];
        default: model_vstart[i] = cur[i];
      endcase
    end
  endfunction

  // Model, write, read back
  task automatic apply(input logic [2:0] op, input logic [Xlen-1:0] val);
    logic [Xlen-1:0] wsrc;
    wsrc = op[2] ? {{(Xlen - 5) {1'b0}}, val[4:0]} : val;
    case (op)
      Funct3Csrrw, Funct3Csrrwi: exp_mscratch = wsrc;
      Funct3Csrrs, Funct3Csrrsi: exp_mscratch = exp_mscratch | wsrc;
      Funct3Csrrc, Funct3Csrrci: exp_mscratch = exp_mscratch & ~wsrc;
      default: ;
    endcase
    csr_op(op, MscratchAddr, val);
    check("mscratch", csr_rdata, exp_mscratch);
  endtask

  task automatic test_mscratch();
    apply(Funct3Csrrw, 32'hDEAD_BEEF);
    apply(Funct3Csrrs, 32'h0000_00F0);
    apply(Funct3Csrrc, 32'h0000_BEE0);
    apply(Funct3Csrrwi, 32'h0000_0015);
    apply(Funct3Csrrsi, 32'h0000_001F);
    apply(Funct3Csrrci, 32'h0000_000A);
    repeat (200) apply(op_of($urandom_range(0, 5)), $urandom);
    csr_peek(MtvecAddr);
    check("mtvec_untouched", csr_rdata, 32'h0);
  endtask

  task automatic test_mip();
    csr_op(Funct3Csrrw, MipAddr, 32'hFFFF_FFFF);
    check("mip_mtip_masked", Xlen'(csr_rdata[Mtip]), Xlen'(0));
    check("mip_meip_masked", Xlen'(csr_rdata[Meip]), Xlen'(0));
    set_irq(1'b1, 1'b1);
    check("mip_mtip_line", Xlen'(csr_rdata[Mtip]), Xlen'(1));
    check("mip_meip_line", Xlen'(csr_rdata[Meip]), Xlen'(1));
    set_irq(1'b0, 1'b0);
  endtask

  task automatic test_mtvec();
    csr_op(Funct3Csrrw, MtvecAddr, 32'hFFFF_FFFF);
    check("mtvec_wlrl", csr_rdata, 32'hFFFF_FFFF);
    check("mtvec_vector_aligned", trap_vector, 32'hFFFF_FFFC);
  endtask

  task automatic test_vstart();
    set_vs(VsClean);
    exp_vstart = 0;
    for (int t = 0; t < 300; t++) begin
      logic [2:0] op;
      logic [Xlen-1:0] val;
      op = op_of(t < 6 ? t : $urandom_range(0, 5));
      val = t < 6 ? 32'h0000_007F : $urandom;
      exp_vstart = model_vstart(op, exp_vstart, op[2] ? Xlen'(val[4:0]) : val);
      csr_op(op, VstartAddr, val);
      csr_peek(VstartAddr);
      check("vstart_rw", csr_rdata, Xlen'(exp_vstart));
    end
  endtask

  task automatic test_config();
    set_vs(VsClean);
    vec_instr(1'b1, 8'd12, 32'h0000_00C3);
    csr_peek(VlAddr);
    check("vl_read", csr_rdata, 32'd12);
    csr_peek(VtypeAddr);
    check("vtype_read", csr_rdata, 32'h0000_00C3);
    csr_peek(VlenbAddr);
    check("vlenb_read", csr_rdata, Xlen'(Vlen / 8));
    check("vl_port", Xlen'(vl_q), 32'd12);
    check("vtype_port", vtype_q, 32'h0000_00C3);
    csr_peek(VstartAddr);
    check("vstart_zeroed", csr_rdata, 32'h0);

    vec_instr(1'b1, 8'd0, 32'h8000_0000);
    csr_peek(VtypeAddr);
    check("vtype_illegal", csr_rdata, 32'h8000_0000);
    check("vtype_port_illegal", vtype_q, 32'h8000_0000);
    csr_peek(VlAddr);
    check("vl_zeroed", csr_rdata, 32'h0);
  endtask

  task automatic test_mstatus();
    csr_op(Funct3Csrrw, MstatusAddr, 32'hFFFF_FFFF);
    csr_peek(MstatusAddr);
    check("mstatus_masked", csr_rdata, MstatusMask | (Xlen'(1) << MstatusSd));

    set_vs(VsClean);
    csr_peek(MstatusAddr);
    check("sd_clear_when_clean", Xlen'(csr_rdata[MstatusSd]), Xlen'(0));
    check("vs_holds_clean", Xlen'(csr_rdata[MstatusVsLo+1:MstatusVsLo]), Xlen'(VsClean));

    vec_instr(1'b0, 8'd0, 32'h0);
    csr_peek(MstatusAddr);
    check("vs_dirty", Xlen'(csr_rdata[MstatusVsLo+1:MstatusVsLo]), Xlen'(VsDirty));
    check("sd_follows_dirty", Xlen'(csr_rdata[MstatusSd]), Xlen'(1));

    set_vs(VsClean);
    csr_op(Funct3Csrrs, MstatusAddr, Xlen'(1) << MstatusSd);
    csr_peek(MstatusAddr);
    check("sd_not_writable", Xlen'(csr_rdata[MstatusSd]), Xlen'(0));
  endtask

  task automatic test_readonly();
    set_vs(VsClean);
    vec_instr(1'b1, 8'd7, 32'h0000_0041);

    csr_trap("vl_write_traps", Funct3Csrrw, VlAddr, 32'hFFFF_FFFF, 1'b1);
    csr_peek(VlAddr);
    check("vl_write_ignored", csr_rdata, 32'd7);

    csr_trap("vtype_write_traps", Funct3Csrrw, VtypeAddr, 32'hFFFF_FFFF, 1'b1);
    csr_peek(VtypeAddr);
    check("vtype_write_ignored", csr_rdata, 32'h0000_0041);

    csr_trap("vlenb_write_traps", Funct3Csrrw, VlenbAddr, 32'hFFFF_FFFF, 1'b1);
    csr_peek(VlenbAddr);
    check("vlenb_write_ignored", csr_rdata, Xlen'(Vlen / 8));

    src_spec = 5'd0;
    csr_trap("vl_set_zero_no_trap", Funct3Csrrs, VlAddr, 32'h0, 1'b0);
    csr_peek(VlAddr);
    check("vl_set_zero_reads", csr_rdata, 32'd7);
    csr_trap("vtype_clear_zero_no_trap", Funct3Csrrc, VtypeAddr, 32'h0, 1'b0);
    src_spec = 5'd1;
    csr_trap("vlenb_seti_zero_no_trap", Funct3Csrrsi, VlenbAddr, 32'h0, 1'b0);
  endtask

  // Fixed-point registers
  task automatic test_fixed_point();
    vec_vxrm  = 2'd2;
    vec_vxsat = 1'b1;
    csr_peek(VxrmAddr);
    check("vxrm_reads_the_unit", csr_rdata, 32'd2);
    csr_peek(VxsatAddr);
    check("vxsat_reads_the_unit", csr_rdata, 32'd1);
    csr_peek(VcsrAddr);
    check("vcsr_mirrors_both", csr_rdata, 32'd5);

    csr_drive(Funct3Csrrw, VxrmAddr, 32'd1);
    #1;
    check("vxrm_write_forwards", Xlen'(vec_csr_we), 32'd1);
    check("vxrm_write_address", Xlen'(vec_csr_waddr), Xlen'(VxrmAddr));
    check("vxrm_write_data", vec_csr_wdata, 32'd1);
    csr_commit();

    csr_drive(Funct3Csrrc, VcsrAddr, 32'd1);
    #1;
    check("vcsr_clear_forwards", Xlen'(vec_csr_we), 32'd1);
    check("vcsr_clear_data", vec_csr_wdata, 32'd4);
    csr_commit();

    csr_drive(Funct3Csrrsi, VxsatAddr, 32'd0);
    #1;
    check("vxsat_read_only_access", Xlen'(vec_csr_we), 32'd0);
    csr_commit();

    csr_peek(MstatusAddr);
    check("fixed_point_write_dirties", Xlen'(csr_rdata[MstatusVsLo+1:MstatusVsLo]), Xlen'(VsDirty));
    vec_vxrm  = 2'd0;
    vec_vxsat = 1'b0;
  endtask

  task automatic test_vs_off();
    set_vs(VsOff);

    csr_trap("vstart_off_traps", Funct3Csrrw, VstartAddr, 32'h1, 1'b1);
    csr_peek(VstartAddr);
    check("vstart_off_ignored", csr_rdata, 32'h0);

    csr_trap("vl_off_traps", Funct3Csrrs, VlAddr, 32'h0, 1'b1);

    vec_trap("vec_instr_off_traps", 1'b1);
    csr_peek(VlAddr);
    check("vl_off_unchanged", csr_rdata, 32'd7);
  endtask

  task automatic set_status(input logic [1:0] fs, input logic [1:0] vs);
    csr_op(Funct3Csrrw, MstatusAddr, (Xlen'(fs) << MstatusFsLo) | (Xlen'(vs) << MstatusVsLo));
  endtask

  task automatic fp_instr(input logic state_we, input logic we, input logic [4:0] flags);
    #1;
    is_fp_instr = 1;
    fp_state_we = state_we;
    fp_flags_we = we;
    fp_flags    = flags;
    @(posedge clk);
    #1;
    is_fp_instr = 0;
    fp_state_we = 0;
    fp_flags_we = 0;
    fp_flags    = 0;
  endtask

  task automatic fp_trap(input string name, input logic [4:0] flags, input logic exp);
    #1;
    is_fp_instr = 1;
    fp_state_we = 1;
    fp_flags_we = 1;
    fp_flags    = flags;
    #1;
    check(name, Xlen'(trap_taken), Xlen'(exp));
    @(posedge clk);
    #1;
    is_fp_instr = 0;
    fp_state_we = 0;
    fp_flags_we = 0;
    fp_flags    = 0;
  endtask

  function automatic logic [11:0] fp_addr_of(input int idx);
    case (idx)
      0: fp_addr_of = FflagsAddr;
      1: fp_addr_of = FrmAddr;
      default: fp_addr_of = FcsrAddr;
    endcase
  endfunction

  function automatic logic [Xlen-1:0] fp_model_read(input logic [11:0] addr);
    case (addr)
      FflagsAddr: fp_model_read = Xlen'(exp_fflags);
      FrmAddr: fp_model_read = Xlen'(exp_frm);
      default: fp_model_read = Xlen'({exp_frm, exp_fflags});
    endcase
  endfunction

  function automatic void fp_model_write(input logic [11:0] addr, input logic [7:0] wdata);
    case (addr)
      FflagsAddr: exp_fflags = wdata[4:0];
      FrmAddr: exp_frm = wdata[2:0];
      default: {exp_frm, exp_fflags} = wdata[7:0];
    endcase
  endfunction

  function automatic logic [Xlen-1:0] op_result(input logic [2:0] op, input logic [Xlen-1:0] cur,
                                                input logic [Xlen-1:0] val);
    logic [Xlen-1:0] wsrc;
    wsrc = op[2] ? {{(Xlen - 5) {1'b0}}, val[4:0]} : val;
    case (op)
      Funct3Csrrw, Funct3Csrrwi: op_result = wsrc;
      Funct3Csrrs, Funct3Csrrsi: op_result = cur | wsrc;
      Funct3Csrrc, Funct3Csrrci: op_result = cur & ~wsrc;
      default: op_result = cur;
    endcase
  endfunction

  function automatic logic op_writes(input logic [2:0] op, input logic [4:0] imm);
    case (op)
      Funct3Csrrw, Funct3Csrrwi: op_writes = 1'b1;
      Funct3Csrrs, Funct3Csrrc: op_writes = src_spec != 5'd0;
      default: op_writes = imm != 5'd0;
    endcase
  endfunction

  task automatic fp_apply(input logic [2:0] op, input logic [11:0] addr,
                          input logic [Xlen-1:0] val);
    logic [Xlen-1:0] old;
    old = fp_model_read(addr);
    csr_drive(op, addr, val);
    #1;
    check($sformatf("fp_%h_no_trap", addr), Xlen'(trap_taken), 32'h0);
    check($sformatf("fp_%h_read_old", addr), csr_rdata, old);
    csr_commit();
    if (op_writes(op, val[4:0])) fp_model_write(addr, 8'(op_result(op, old, val)));
    check($sformatf("fp_%h_read_new", addr), csr_rdata, fp_model_read(addr));
    check("frm_q_tracks_frm", Xlen'(frm_q), Xlen'(exp_frm));
  endtask

  task automatic check_fs(input string name, input logic [1:0] fs, input logic sd);
    csr_peek(MstatusAddr);
    check({name, "_fs"}, Xlen'(csr_rdata[MstatusFsLo+1:MstatusFsLo]), Xlen'(fs));
    check({name, "_sd"}, Xlen'(csr_rdata[MstatusSd]), Xlen'(sd));
  endtask

  task automatic check_trap_record(input string name, input logic [Xlen-1:0] epc);
    check({name, "_mepc"}, mepc_out, epc);
    csr_peek(McauseAddr);
    check({name, "_mcause"}, csr_rdata, Xlen'(CauseIllegalInstr));
  endtask

  task automatic test_fp_reset();
    csr_peek(FflagsAddr);
    check("fflags_reset", csr_rdata, 32'h0);
    csr_peek(FrmAddr);
    check("frm_reset", csr_rdata, 32'h0);
    csr_peek(FcsrAddr);
    check("fcsr_reset", csr_rdata, 32'h0);
    check("frm_q_reset", Xlen'(frm_q), 32'h0);
    check_fs("fs_reset", FsOff, 1'b0);
  endtask

  task automatic test_fp_rw();
    set_status(FsInitial, VsClean);
    for (int a = 0; a < 3; a++) begin
      fp_apply(Funct3Csrrw, fp_addr_of(a), 32'hFFFF_FF55);
      fp_apply(Funct3Csrrc, fp_addr_of(a), 32'h0000_0F0F);
      fp_apply(Funct3Csrrs, fp_addr_of(a), 32'h0000_00A0);
      fp_apply(Funct3Csrrwi, fp_addr_of(a), 32'h0000_0015);
      fp_apply(Funct3Csrrsi, fp_addr_of(a), 32'h0000_000A);
      fp_apply(Funct3Csrrci, fp_addr_of(a), 32'h0000_0013);
    end
    repeat (120) fp_apply(op_of($urandom_range(0, 5)), fp_addr_of($urandom_range(0, 2)), $urandom);
  endtask

  task automatic test_fp_alias();
    set_status(FsDirty, VsClean);
    fp_apply(Funct3Csrrw, FcsrAddr, 32'hFFFF_FFB6);
    csr_peek(FflagsAddr);
    check("fcsr_to_fflags", csr_rdata, 32'h16);
    csr_peek(FrmAddr);
    check("fcsr_to_frm", csr_rdata, 32'h5);
    check("fcsr_to_frm_q", Xlen'(frm_q), 32'h5);

    fp_apply(Funct3Csrrw, FrmAddr, 32'h3);
    csr_peek(FcsrAddr);
    check("frm_to_fcsr", csr_rdata, 32'h76);
    fp_apply(Funct3Csrrw, FflagsAddr, 32'h9);
    csr_peek(FcsrAddr);
    check("fflags_to_fcsr", csr_rdata, 32'h69);
    fp_apply(Funct3Csrrs, FrmAddr, 32'h4);
    csr_peek(FcsrAddr);
    check("frm_set_to_fcsr", csr_rdata, 32'hE9);
    fp_apply(Funct3Csrrci, FflagsAddr, 32'h1);
    csr_peek(FcsrAddr);
    check("fflags_clear_to_fcsr", csr_rdata, 32'hE8);
  endtask

  task automatic test_fs_off();
    set_status(FsDirty, VsClean);
    fp_apply(Funct3Csrrw, FcsrAddr, 32'hA7);
    set_status(FsOff, VsClean);

    for (int a = 0; a < 3; a++) begin
      for (int k = 0; k < 2; k++) begin
        logic [11:0] addr;
        logic [Xlen-1:0] epc;
        addr = fp_addr_of(a);
        epc  = 32'h0000_2000 + 32'(a * 16 + k * 4);
        csr_op(Funct3Csrrw, McauseAddr, 32'h0);
        pc = epc;
        src_spec = k[0] ? 5'd0 : 5'd1;
        csr_trap($sformatf("fs_off_%h_traps", addr), k[0] ? Funct3Csrrs : Funct3Csrrw, addr, 32'h18,
                 1'b1);
        src_spec = 5'd1;
        check_trap_record($sformatf("fs_off_%h", addr), epc);
        csr_peek(addr);
        check($sformatf("fs_off_%h_unchanged", addr), csr_rdata, fp_model_read(addr));
        check("fs_off_frm_q_unchanged", Xlen'(frm_q), Xlen'(exp_frm));
        check_fs("fs_off_stays_off", FsOff, 1'b0);
      end
    end

    csr_op(Funct3Csrrw, McauseAddr, 32'h0);
    pc = 32'h0000_2100;
    fp_trap("fp_instr_off_traps", 5'h18, 1'b1);
    check_trap_record("fp_instr_off", 32'h0000_2100);
    csr_peek(FflagsAddr);
    check("fp_instr_off_no_accrue", csr_rdata, Xlen'(exp_fflags));
    check_fs("fp_instr_off_stays_off", FsOff, 1'b0);
    pc = 0;
  endtask

  task automatic test_fs_dirty();
    for (int f = 0; f < 4; f++) begin
      for (int v = 0; v < 4; v++) begin
        set_status(2'(f), 2'(v));
        csr_peek(MstatusAddr);
        check("fs_writable", Xlen'(csr_rdata[MstatusFsLo+1:MstatusFsLo]), Xlen'(f));
        check("vs_beside_fs", Xlen'(csr_rdata[MstatusVsLo+1:MstatusVsLo]), Xlen'(v));
        check("sd_either_dirty", Xlen'(csr_rdata[MstatusSd]), Xlen'(f == 3 || v == 3));
      end
    end

    set_status(FsClean, VsClean);
    fp_instr(1'b1, 1'b0, 5'h0);
    check_fs("fp_state_we_dirties", FsDirty, 1'b1);

    set_status(FsInitial, VsClean);
    fp_instr(1'b0, 1'b0, 5'h0);
    check_fs("fp_instr_alone_keeps_initial", FsInitial, 1'b0);
    fp_instr(1'b0, 1'b1, 5'h0);
    check_fs("zero_flags_keep_initial", FsInitial, 1'b0);
    fp_instr(1'b0, 1'b0, 5'h1F);
    check_fs("flags_without_we_keep_initial", FsInitial, 1'b0);
    fp_instr(1'b0, 1'b1, 5'h04);
    exp_fflags = exp_fflags | 5'h04;
    check_fs("fp_flags_dirty", FsDirty, 1'b1);

    set_status(FsClean, VsClean);
    #1;
    fp_flags_we = 1;
    fp_flags    = 5'h01;
    @(posedge clk);
    #1;
    fp_flags_we = 0;
    fp_flags    = 0;
    exp_fflags  = exp_fflags | 5'h01;
    check_fs("fp_flags_alone_dirty", FsDirty, 1'b1);

    for (int a = 0; a < 3; a++) begin
      set_status(FsClean, VsClean);
      fp_apply(Funct3Csrrwi, fp_addr_of(a), 32'h3);
      check_fs($sformatf("fp_%h_write_dirties", fp_addr_of(a)), FsDirty, 1'b1);
    end

    set_status(FsClean, VsClean);
    src_spec = 5'd0;
    fp_apply(Funct3Csrrs, FflagsAddr, 32'h0);
    src_spec = 5'd1;
    fp_apply(Funct3Csrrci, FcsrAddr, 32'h0);
    check_fs("fp_read_stays_clean", FsClean, 1'b0);

    core_en = 0;
    fp_instr(1'b1, 1'b1, 5'h1F);
    core_en = 1;
    check_fs("fp_instr_core_en_low", FsClean, 1'b0);
  endtask

  task automatic test_fp_accrue();
    set_status(FsDirty, VsClean);
    fp_apply(Funct3Csrrw, FflagsAddr, 32'h0);

    core_en = 0;
    fp_instr(1'b1, 1'b1, 5'h1F);
    core_en = 1;
    csr_peek(FflagsAddr);
    check("accrue_core_en_low", csr_rdata, 32'h0);

    fp_instr(1'b1, 1'b1, 5'h01);
    fp_instr(1'b1, 1'b1, 5'h04);
    fp_instr(1'b1, 1'b0, 5'h10);
    fp_instr(1'b1, 1'b1, 5'h04);
    csr_peek(FflagsAddr);
    check("accrue_or", csr_rdata, 32'h05);
    exp_fflags = 5'h05;

    #1;
    exc_illegal = 1;
    fp_flags_we = 1;
    fp_flags    = 5'h1A;
    @(posedge clk);
    #1;
    exc_illegal = 0;
    fp_flags_we = 0;
    fp_flags    = 0;
    csr_peek(FflagsAddr);
    check("accrue_blocked_by_trap", csr_rdata, 32'h05);

    for (int t = 0; t < 200; t++) begin
      logic en;
      logic we;
      logic [4:0] flags;
      if (t % 8 == 0) fp_apply(Funct3Csrrw, FflagsAddr, 32'h0);
      en = $urandom_range(0, 3) != 0;
      we = $urandom_range(0, 3) != 0;
      flags = $urandom_range(0, 3) == 0 ? 5'($urandom) : 5'(1 << $urandom_range(0, 4));
      core_en = en;
      fp_instr(1'b1, we, flags);
      core_en = 1;
      if (en && we) exp_fflags = exp_fflags | flags;
      csr_peek(FflagsAddr);
      check("fflags_accrue", csr_rdata, Xlen'(exp_fflags));
    end

    fp_apply(Funct3Csrrw, FcsrAddr, 32'h01);
    csr_drive(Funct3Csrrw, FflagsAddr, 32'h10);
    fp_flags_we = 1;
    fp_flags    = 5'h0C;
    csr_commit();
    fp_flags_we = 0;
    fp_flags    = 0;
    csr_peek(FflagsAddr);
    check("fflags_write_wins", csr_rdata, 32'h10);

    csr_drive(Funct3Csrrw, FcsrAddr, 32'h41);
    fp_flags_we = 1;
    fp_flags    = 5'h1E;
    csr_commit();
    fp_flags_we = 0;
    fp_flags    = 0;
    csr_peek(FcsrAddr);
    check("fcsr_write_wins", csr_rdata, 32'h41);

    csr_drive(Funct3Csrrs, FflagsAddr, 32'h02);
    fp_flags_we = 1;
    fp_flags    = 5'h1C;
    csr_commit();
    fp_flags_we = 0;
    fp_flags    = 0;
    csr_peek(FflagsAddr);
    check("fflags_set_wins", csr_rdata, 32'h03);

    csr_drive(Funct3Csrrw, FrmAddr, 32'h6);
    fp_flags_we = 1;
    fp_flags    = 5'h10;
    csr_commit();
    fp_flags_we = 0;
    fp_flags    = 0;
    csr_peek(FcsrAddr);
    check("frm_write_keeps_accrue", csr_rdata, 32'hD3);
    exp_fflags = 5'h13;
    exp_frm    = 3'h6;
  endtask

  task automatic test_frm_q();
    set_status(FsDirty, VsClean);
    for (int r = 0; r < 8; r++) begin
      fp_apply(Funct3Csrrwi, FrmAddr, Xlen'(r));
      check("frm_q_value", Xlen'(frm_q), Xlen'(r));
    end
    fp_apply(Funct3Csrrw, FcsrAddr, 32'h40);
    check("frm_q_from_fcsr", Xlen'(frm_q), 32'h2);
    fp_instr(1'b1, 1'b1, 5'h1F);
    exp_fflags = 5'h1F;
    check("frm_q_holds_on_accrue", Xlen'(frm_q), 32'h2);
  endtask

  task automatic test_fp_random();
    logic [1:0] exp_fs;
    set_status(FsDirty, VsClean);
    exp_fs = FsDirty;
    for (int t = 0; t < 2000; t++) begin
      int              kind;
      logic [     2:0] op;
      logic [    11:0] addr;
      logic [Xlen-1:0] val;
      logic [Xlen-1:0] old;
      logic [     4:0] flags;
      logic [     1:0] new_fs;
      logic            en;
      logic            fp;
      logic            we;
      logic            st;
      logic            ill;
      logic            acc;
      logic            wr;
      logic            trap;
      kind     = $urandom_range(0, 15);
      op       = op_of($urandom_range(0, 5));
      addr     = fp_addr_of($urandom_range(0, 2));
      val      = $urandom;
      flags    = 5'($urandom);
      new_fs   = 2'($urandom_range(0, 3));
      src_spec = $urandom_range(0, 7) == 0 ? 5'd0 : 5'd1;
      en       = $urandom_range(0, 7) != 0;
      ill      = $urandom_range(0, 15) == 0;
      fp       = kind != 10 && $urandom_range(0, 2) == 0;
      st       = fp && $urandom_range(0, 1) == 1;
      we       = kind != 10 && (fp || exp_fs != FsOff) && $urandom_range(0, 1) == 1;
      acc      = kind < 10;
      wr       = acc && op_writes(op, val[4:0]);
      trap     = ill || ((fp || acc) && exp_fs == FsOff);
      old      = fp_model_read(addr);

      if (acc) csr_drive(op, addr, val);
      else if (kind == 10)
        csr_drive(Funct3Csrrw, MstatusAddr,
                  (Xlen'(new_fs) << MstatusFsLo) | (Xlen'(VsClean) << MstatusVsLo));
      else #1;
      core_en     = en;
      exc_illegal = ill;
      is_fp_instr = fp;
      fp_state_we = st;
      fp_flags_we = we;
      fp_flags    = flags;
      #1;
      check("rand_trap", Xlen'(trap_taken), Xlen'(trap));
      if (acc) check("rand_read_old", csr_rdata, old);
      @(posedge clk);
      #1;
      csr_access  = 0;
      core_en     = 1;
      exc_illegal = 0;
      is_fp_instr = 0;
      fp_state_we = 0;
      fp_flags_we = 0;
      fp_flags    = 0;

      if (en && !trap) begin
        if (wr) fp_model_write(addr, 8'(op_result(op, old, val)));
        if (we && !(wr && addr != FrmAddr)) exp_fflags = exp_fflags | flags;
        if (kind == 10) exp_fs = new_fs;
        else if ((fp && st) || (we && flags != 5'd0) || wr) exp_fs = FsDirty;
      end
      csr_peek(FcsrAddr);
      check("rand_fcsr", csr_rdata, Xlen'({exp_frm, exp_fflags}));
      check("rand_frm_q", Xlen'(frm_q), Xlen'(exp_frm));
      check_fs("rand", exp_fs, exp_fs == FsDirty);
    end
    src_spec = 5'd1;
  endtask

  task automatic test_fp_reset_clears();
    set_status(FsDirty, VsClean);
    fp_apply(Funct3Csrrw, FcsrAddr, 32'hFF);
    do_reset();
    test_fp_reset();
  endtask

  task automatic verdict();
    if (checks < MinChecks) $fatal(1, "TB UNDER-RAN: %0d checks, floor %0d", checks, MinChecks);
    if (errors == 0) $display("PASS: %0d checks, %0d mismatches", checks, errors);
    else $fatal(1, "FAIL: %0d mismatches, %0d checks", errors, checks);
    $finish;
  endtask

  initial begin
    $dumpfile("csr_tb.vcd");
    $dumpvars(0, csr_tb);
    do_reset();
    test_fp_reset();
    test_mscratch();
    test_mip();
    test_mtvec();
    test_vstart();
    test_config();
    test_mstatus();
    test_readonly();
    test_fixed_point();
    test_vs_off();
    test_fp_rw();
    test_fp_alias();
    test_fs_off();
    test_fs_dirty();
    test_fp_accrue();
    test_frm_q();
    test_fp_random();
    test_fp_reset_clears();
    verdict();
  end

endmodule

`default_nettype wire
