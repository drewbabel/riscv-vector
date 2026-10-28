`default_nettype none

module csr_tb
  import csr_pkg::*;
  import fp_pkg::FlagNv, fp_pkg::FlagDz, fp_pkg::FlagOf, fp_pkg::FlagUf, fp_pkg::FlagNx;
();

  localparam int Xlen = arch_pkg::XLEN;
  localparam int Vlen = arch_pkg::VLEN;
  localparam int VlW = $clog2(Vlen + 1);
  localparam int VstartW = $clog2(Vlen);
  localparam int AddrW = $bits(MstatusAddr);
  localparam int Funct3W = $bits(Funct3Priv);
  localparam int ZimmW = arch_pkg::RegAddrW;
  localparam int FlagW = $bits(FlagNv);
  localparam int RmW = $bits(fp_pkg::RmRne);
  localparam int FcsrW = RmW + FlagW;
  localparam int StateW = $bits(VsOff);
  localparam logic [FlagW-1:0] FlagAll = FlagNv | FlagDz | FlagOf | FlagUf | FlagNx;
  localparam int MinChecks = 13000;

  int checks = 0;
  int errors = 0;
  int max_errors = 0;

  logic clk = 1'b0;
  logic rst_n;
  logic csr_access;
  logic [AddrW-1:0] csr_addr;
  logic [Funct3W-1:0] funct3;
  logic [Xlen-1:0] rs1_data;
  logic [ZimmW-1:0] zimm;
  logic [ZimmW-1:0] src_spec = ZimmW'(1);  // rs1 field
  logic [Xlen-1:0] pc;
  logic [Xlen-1:0] bad_addr;
  logic exc_illegal;
  logic exc_ecall;
  logic exc_ebreak;
  logic exc_instr_misaligned;
  logic exc_load_misaligned;
  logic exc_store_misaligned;
  logic is_mret;
  logic timer_irq;
  logic ext_irq;
  logic [Xlen-1:0] csr_rdata;
  logic trap_taken;
  logic [Xlen-1:0] trap_vector;
  logic mret_taken;
  logic [Xlen-1:0] mepc_out;

  logic is_vset;
  logic [VlW-1:0] vl_next;
  logic [Xlen-1:0] vtype_next;
  logic is_vec_instr;
  logic [1:0] vec_vxrm;
  logic vec_vxsat;
  logic vec_csr_we;
  logic [AddrW-1:0] vec_csr_waddr;
  logic [Xlen-1:0] vec_csr_wdata;
  logic [VlW-1:0] vl_q;
  logic [Xlen-1:0] vtype_q;

  logic core_en;
  logic is_fp_instr;
  logic fp_state_we;
  logic fp_flags_we;
  logic [FlagW-1:0] fp_flags;
  logic fp_wb_flags_we;
  logic [FlagW-1:0] fp_wb_flags;
  logic [FlagW-1:0] vec_fflags;
  logic [RmW-1:0] frm_q;
  logic vstart_set;

  logic [Xlen-1:0] exp_mscratch;
  logic [VstartW-1:0] exp_vstart;
  logic [FlagW-1:0] exp_fflags;
  logic [RmW-1:0] exp_frm;

  logic [Funct3W-1:0] csr_ops[6] = '{
      Funct3Csrrw,
      Funct3Csrrs,
      Funct3Csrrc,
      Funct3Csrrwi,
      Funct3Csrrsi,
      Funct3Csrrci
  };
  logic [AddrW-1:0] fp_addrs[3] = '{FflagsAddr, FrmAddr, FcsrAddr};

  initial void'($value$plusargs("max_errors=%d", max_errors));

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
      .vl_next             (vl_next),
      .vtype_next          (vtype_next),
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
      .fp_wb_flags_we      (fp_wb_flags_we),
      .fp_wb_flags         (fp_wb_flags),
      .vec_fflags          (vec_fflags),
      .frm_q               (frm_q),
      .vstart_set          (vstart_set)
  );

  task automatic check(input string name, input logic [Xlen-1:0] got, input logic [Xlen-1:0] exp);
    checks++;
    if (got !== exp) begin
      errors++;
      $display("FAIL %s: got %h, expected %h", name, got, exp);
      if (errors == max_errors) $fatal(1, "TB STOPPED: %0d mismatches", errors);
    end
  endtask  // Automatic

  task automatic idle_retire();
    core_en        = 1'b1;
    exc_illegal    = 1'b0;
    is_fp_instr    = 1'b0;
    fp_state_we    = 1'b0;
    fp_flags_we    = 1'b0;
    fp_flags       = '0;
    fp_wb_flags_we = 1'b0;
    fp_wb_flags    = '0;
    vec_fflags     = '0;
  endtask  // Automatic

  // Idle inputs, reset
  task automatic do_reset();
    rst_n = 1'b0;
    csr_access = 1'b0;
    csr_addr = '0;
    funct3 = '0;
    rs1_data = '0;
    zimm = '0;
    pc = '0;
    bad_addr = '0;
    is_mret = 1'b0;
    timer_irq = 1'b0;
    ext_irq = 1'b0;
    is_vset = 1'b0;
    is_vec_instr = 1'b0;
    vec_vxrm = '0;
    vec_vxsat = 1'b0;
    vl_next = '0;
    vtype_next = '0;
    {exc_ecall, exc_ebreak} = '0;
    {exc_instr_misaligned, exc_load_misaligned, exc_store_misaligned} = '0;
    idle_retire();
    exp_mscratch = '0;
    exp_vstart = '0;
    exp_fflags = '0;
    exp_frm = '0;
    repeat (2) @(posedge clk);
    @(negedge clk);
    rst_n = 1'b1;
  endtask  // Automatic

  // Drive one access
  task automatic csr_drive(input logic [Funct3W-1:0] op, input logic [AddrW-1:0] addr,
                           input logic [Xlen-1:0] val);
    @(negedge clk);
    csr_addr   = addr;
    funct3     = op;
    rs1_data   = val;
    zimm       = op[2] ? val[ZimmW-1:0] : src_spec;
    csr_access = 1'b1;
  endtask  // Automatic

  task automatic csr_release();
    @(negedge clk);
    csr_access = 1'b0;
    idle_retire();
  endtask  // Automatic

  // Commit the access
  task automatic csr_commit();
    @(posedge clk);
    csr_release();
  endtask  // Automatic

  // Access any address
  task automatic csr_op(input logic [Funct3W-1:0] op, input logic [AddrW-1:0] addr,
                        input logic [Xlen-1:0] val);
    csr_drive(op, addr, val);
    csr_commit();
  endtask  // Automatic

  // Access, sample trap
  task automatic csr_trap(input string name, input logic [Funct3W-1:0] op,
                          input logic [AddrW-1:0] addr, input logic [Xlen-1:0] val,
                          input logic exp);
    csr_drive(op, addr, val);
    @(posedge clk);
    check(name, Xlen'(trap_taken), Xlen'(exp));
    csr_release();
  endtask  // Automatic

  task automatic csr_forward(input string name, input logic [Funct3W-1:0] op,
                             input logic [AddrW-1:0] addr, input logic [Xlen-1:0] val,
                             input logic exp_we, input logic [Xlen-1:0] exp_wdata);
    csr_drive(op, addr, val);
    @(posedge clk);
    check({name, "_forwards"}, Xlen'(vec_csr_we), Xlen'(exp_we));
    if (exp_we) begin
      check({name, "_address"}, Xlen'(vec_csr_waddr), Xlen'(addr));
      check({name, "_data"}, vec_csr_wdata, exp_wdata);
    end
    csr_release();
  endtask  // Automatic

  // Read without writing
  task automatic csr_peek(input logic [AddrW-1:0] addr);
    @(negedge clk);
    csr_access = 1'b0;
    csr_addr   = addr;
    @(negedge clk);
  endtask  // Automatic

  // One vector instruction
  task automatic vec_instr(input logic set_cfg, input logic [VlW-1:0] next_vl,
                           input logic [Xlen-1:0] next_vtype);
    @(negedge clk);
    is_vec_instr = 1'b1;
    is_vset      = set_cfg;
    vl_next      = next_vl;
    vtype_next   = next_vtype;
    @(posedge clk);
    @(negedge clk);
    is_vec_instr = 1'b0;
    is_vset      = 1'b0;
  endtask  // Automatic

  // Vector instruction, sample trap
  task automatic vec_trap(input string name, input logic exp);
    @(negedge clk);
    is_vec_instr = 1'b1;
    @(posedge clk);
    check(name, Xlen'(trap_taken), Xlen'(exp));
    @(negedge clk);
    is_vec_instr = 1'b0;
  endtask  // Automatic

  // Interrupt lines
  task automatic set_irq(input logic timer, input logic ext);
    @(negedge clk);
    timer_irq = timer;
    ext_irq   = ext;
    @(negedge clk);
  endtask  // Automatic

  task automatic set_fixed(input logic [1:0] vxrm, input logic vxsat);
    @(negedge clk);
    vec_vxrm  = vxrm;
    vec_vxsat = vxsat;
  endtask  // Automatic

  task automatic set_pc(input logic [Xlen-1:0] addr);
    @(negedge clk);
    pc = addr;
  endtask  // Automatic

  // Set vector status
  task automatic set_vs(input logic [StateW-1:0] vs);
    csr_op(Funct3Csrrw, MstatusAddr, Xlen'(vs) << MstatusVsLo);
  endtask  // Automatic

  task automatic set_status(input logic [StateW-1:0] fs, input logic [StateW-1:0] vs);
    csr_op(Funct3Csrrw, MstatusAddr, (Xlen'(fs) << MstatusFsLo) | (Xlen'(vs) << MstatusVsLo));
  endtask  // Automatic

  task automatic stage_fp(input logic en, input logic ill, input logic fp, input logic state_we,
                          input logic we, input logic [FlagW-1:0] flags);
    core_en     = en;
    exc_illegal = ill;
    is_fp_instr = fp;
    fp_state_we = state_we;
    fp_flags_we = we;
    fp_flags    = flags;
  endtask  // Automatic

  task automatic stage_late(input logic we, input logic [FlagW-1:0] flags);
    fp_wb_flags_we = we;
    fp_wb_flags    = flags;
  endtask  // Automatic

  task automatic retire_cycle();
    @(posedge clk);
    @(negedge clk);
    idle_retire();
  endtask  // Automatic

  task automatic fp_instr(input logic en, input logic state_we, input logic we,
                          input logic [FlagW-1:0] flags);
    @(negedge clk);
    stage_fp(en, 1'b0, 1'b1, state_we, we, flags);
    retire_cycle();
  endtask  // Automatic

  task automatic fp_trap(input string name, input logic [FlagW-1:0] flags, input logic exp);
    @(negedge clk);
    stage_fp(1'b1, 1'b0, 1'b1, 1'b1, 1'b1, flags);
    @(posedge clk);
    check(name, Xlen'(trap_taken), Xlen'(exp));
    @(negedge clk);
    idle_retire();
  endtask  // Automatic

  task automatic retire_flags(input logic en, input logic ill, input logic [FlagW-1:0] flags);
    @(negedge clk);
    stage_fp(en, ill, 1'b0, 1'b0, 1'b1, flags);
    retire_cycle();
  endtask  // Automatic

  task automatic late_flags(input logic en, input logic ill, input logic we,
                            input logic [FlagW-1:0] flags);
    @(negedge clk);
    stage_fp(en, ill, 1'b0, 1'b0, 1'b0, '0);
    stage_late(we, flags);
    retire_cycle();
  endtask  // Automatic

  task automatic retire_and_late(input logic [FlagW-1:0] flags, input logic [FlagW-1:0] late);
    @(negedge clk);
    stage_fp(1'b1, 1'b0, 1'b0, 1'b0, 1'b1, flags);
    stage_late(1'b1, late);
    retire_cycle();
  endtask  // Automatic

  task automatic vec_flags(input logic en, input logic ill, input logic [FlagW-1:0] flags);
    @(negedge clk);
    stage_fp(en, ill, 1'b0, 1'b0, 1'b0, '0);
    vec_fflags = flags;
    retire_cycle();
  endtask  // Automatic

  task automatic csr_retire(input logic [Funct3W-1:0] op, input logic [AddrW-1:0] addr,
                            input logic [Xlen-1:0] val, input logic [FlagW-1:0] flags);
    csr_drive(op, addr, val);
    stage_fp(1'b1, 1'b0, 1'b0, 1'b0, 1'b1, flags);
    csr_commit();
  endtask  // Automatic

  task automatic csr_late(input logic [Funct3W-1:0] op, input logic [AddrW-1:0] addr,
                          input logic [Xlen-1:0] val, input logic [FlagW-1:0] flags);
    csr_drive(op, addr, val);
    stage_late(1'b1, flags);
    csr_commit();
  endtask  // Automatic

  task automatic csr_vec(input logic [Funct3W-1:0] op, input logic [AddrW-1:0] addr,
                         input logic [Xlen-1:0] val, input logic [FlagW-1:0] flags);
    csr_drive(op, addr, val);
    vec_fflags = flags;
    csr_commit();
  endtask  // Automatic

  function automatic logic [Funct3W-1:0] rand_op();
    rand_op = csr_ops[$urandom_range($size(csr_ops)-1)];
  endfunction

  function automatic logic [AddrW-1:0] rand_fp_addr();
    rand_fp_addr = fp_addrs[$urandom_range($size(fp_addrs)-1)];
  endfunction

  // Model, write, read back
  task automatic apply(input logic [Funct3W-1:0] op, input logic [Xlen-1:0] val);
    exp_mscratch = op_result(op, exp_mscratch, val);
    csr_op(op, MscratchAddr, val);
    check("mscratch", csr_rdata, exp_mscratch);
  endtask  // Automatic

  task automatic test_mscratch();
    apply(Funct3Csrrw, Xlen'('hDEAD_BEEF));
    apply(Funct3Csrrs, Xlen'('h0000_00F0));
    apply(Funct3Csrrc, Xlen'('h0000_BEE0));
    apply(Funct3Csrrwi, Xlen'('h0000_0015));
    apply(Funct3Csrrsi, Xlen'('h0000_001F));
    apply(Funct3Csrrci, Xlen'('h0000_000A));
    repeat (200) apply(rand_op(), Xlen'($urandom));
    csr_peek(MtvecAddr);
    check("mtvec_untouched", csr_rdata, '0);
  endtask  // Automatic

  task automatic test_mip();
    csr_op(Funct3Csrrw, MipAddr, '1);
    check("mip_mtip_masked", Xlen'(csr_rdata[Mtip]), Xlen'(0));
    check("mip_meip_masked", Xlen'(csr_rdata[Meip]), Xlen'(0));
    set_irq(1'b1, 1'b1);
    check("mip_mtip_line", Xlen'(csr_rdata[Mtip]), Xlen'(1));
    check("mip_meip_line", Xlen'(csr_rdata[Meip]), Xlen'(1));
    set_irq(1'b0, 1'b0);
  endtask  // Automatic

  task automatic test_mtvec();
    csr_op(Funct3Csrrw, MtvecAddr, '1);
    check("mtvec_wlrl", csr_rdata, '1);
    check("mtvec_vector_aligned", trap_vector, Xlen'('hFFFF_FFFC));
  endtask  // Automatic

  task automatic test_vstart();
    set_vs(VsClean);
    exp_vstart = '0;
    for (int t = 0; t < 300; t++) begin
      logic [Funct3W-1:0] op;
      logic [Xlen-1:0] val;
      op = t < $size(csr_ops) ? csr_ops[t] : rand_op();
      val = t < $size(csr_ops) ? Xlen'('h0000_007F) : Xlen'($urandom);
      exp_vstart = model_vstart(op, exp_vstart, op[2] ? Xlen'(val[ZimmW-1:0]) : val);
      csr_op(op, VstartAddr, val);
      csr_peek(VstartAddr);
      check("vstart_rw", csr_rdata, Xlen'(exp_vstart));
      check("vstart_set_port", Xlen'(vstart_set), Xlen'(exp_vstart != 0));
    end
  endtask  // Automatic

  task automatic test_config();
    set_vs(VsClean);
    vec_instr(1'b1, VlW'(12), Xlen'('h0000_00C3));
    csr_peek(VlAddr);
    check("vl_read", csr_rdata, Xlen'(12));
    csr_peek(VtypeAddr);
    check("vtype_read", csr_rdata, Xlen'('h0000_00C3));
    csr_peek(VlenbAddr);
    check("vlenb_read", csr_rdata, Xlen'(Vlen / 8));
    check("vl_port", Xlen'(vl_q), Xlen'(12));
    check("vtype_port", vtype_q, Xlen'('h0000_00C3));
    csr_peek(VstartAddr);
    check("vstart_zeroed", csr_rdata, '0);
    check("vstart_set_zeroed", Xlen'(vstart_set), '0);

    vec_instr(1'b1, '0, Xlen'(1) << (Xlen - 1));
    csr_peek(VtypeAddr);
    check("vtype_illegal", csr_rdata, Xlen'(1) << (Xlen - 1));
    check("vtype_port_illegal", vtype_q, Xlen'(1) << (Xlen - 1));
    csr_peek(VlAddr);
    check("vl_zeroed", csr_rdata, '0);
  endtask  // Automatic

  task automatic test_mstatus();
    csr_op(Funct3Csrrw, MstatusAddr, '1);
    csr_peek(MstatusAddr);
    check("mstatus_masked", csr_rdata, MstatusMask | (Xlen'(1) << MstatusSd));

    set_vs(VsClean);
    csr_peek(MstatusAddr);
    check("sd_clear_when_clean", Xlen'(csr_rdata[MstatusSd]), Xlen'(0));
    check("vs_holds_clean", Xlen'(csr_rdata[MstatusVsLo+:StateW]), Xlen'(VsClean));

    vec_instr(1'b0, '0, '0);
    csr_peek(MstatusAddr);
    check("vs_dirty", Xlen'(csr_rdata[MstatusVsLo+:StateW]), Xlen'(VsDirty));
    check("sd_follows_dirty", Xlen'(csr_rdata[MstatusSd]), Xlen'(1));

    set_vs(VsClean);
    csr_op(Funct3Csrrs, MstatusAddr, Xlen'(1) << MstatusSd);
    csr_peek(MstatusAddr);
    check("sd_not_writable", Xlen'(csr_rdata[MstatusSd]), Xlen'(0));
  endtask  // Automatic

  task automatic test_readonly();
    set_vs(VsClean);
    vec_instr(1'b1, VlW'(7), Xlen'('h0000_0041));

    csr_trap("vl_write_traps", Funct3Csrrw, VlAddr, '1, 1'b1);
    csr_peek(VlAddr);
    check("vl_write_ignored", csr_rdata, Xlen'(7));

    csr_trap("vtype_write_traps", Funct3Csrrw, VtypeAddr, '1, 1'b1);
    csr_peek(VtypeAddr);
    check("vtype_write_ignored", csr_rdata, Xlen'('h0000_0041));

    csr_trap("vlenb_write_traps", Funct3Csrrw, VlenbAddr, '1, 1'b1);
    csr_peek(VlenbAddr);
    check("vlenb_write_ignored", csr_rdata, Xlen'(Vlen / 8));

    src_spec = '0;
    csr_trap("vl_set_zero_no_trap", Funct3Csrrs, VlAddr, '0, 1'b0);
    csr_peek(VlAddr);
    check("vl_set_zero_reads", csr_rdata, Xlen'(7));
    csr_trap("vtype_clear_zero_no_trap", Funct3Csrrc, VtypeAddr, '0, 1'b0);
    src_spec = ZimmW'(1);
    csr_trap("vlenb_seti_zero_no_trap", Funct3Csrrsi, VlenbAddr, '0, 1'b0);
  endtask  // Automatic

  // Fixed-point registers
  task automatic test_fixed_point();
    set_fixed(2'd2, 1'b1);
    csr_peek(VxrmAddr);
    check("vxrm_reads_the_unit", csr_rdata, Xlen'(2));
    csr_peek(VxsatAddr);
    check("vxsat_reads_the_unit", csr_rdata, Xlen'(1));
    csr_peek(VcsrAddr);
    check("vcsr_mirrors_both", csr_rdata, Xlen'(5));

    csr_forward("vxrm_write", Funct3Csrrw, VxrmAddr, Xlen'(1), 1'b1, Xlen'(1));
    csr_forward("vcsr_clear", Funct3Csrrc, VcsrAddr, Xlen'(1), 1'b1, Xlen'(4));
    csr_forward("vxsat_read_only", Funct3Csrrsi, VxsatAddr, '0, 1'b0, '0);

    csr_peek(MstatusAddr);
    check("fixed_point_write_dirties", Xlen'(csr_rdata[MstatusVsLo+:StateW]), Xlen'(VsDirty));
    set_fixed(2'd0, 1'b0);
  endtask  // Automatic

  task automatic test_vs_off();
    set_vs(VsOff);

    csr_trap("vstart_off_traps", Funct3Csrrw, VstartAddr, Xlen'(1), 1'b1);
    csr_peek(VstartAddr);
    check("vstart_off_ignored", csr_rdata, '0);

    csr_trap("vl_off_traps", Funct3Csrrs, VlAddr, '0, 1'b1);

    vec_trap("vec_instr_off_traps", 1'b1);
    csr_peek(VlAddr);
    check("vl_off_unchanged", csr_rdata, Xlen'(7));
  endtask  // Automatic

  task automatic fp_apply(input logic [Funct3W-1:0] op, input logic [AddrW-1:0] addr,
                          input logic [Xlen-1:0] val);
    logic [Xlen-1:0] old;
    old = fp_model_read(addr);
    csr_drive(op, addr, val);
    @(posedge clk);
    check($sformatf("fp_%h_no_trap", addr), Xlen'(trap_taken), '0);
    check($sformatf("fp_%h_read_old", addr), csr_rdata, old);
    csr_release();
    if (op_writes(op, val[ZimmW-1:0])) fp_model_write(addr, FcsrW'(op_result(op, old, val)));
    check($sformatf("fp_%h_read_new", addr), csr_rdata, fp_model_read(addr));
    check("frm_q_tracks_frm", Xlen'(frm_q), Xlen'(exp_frm));
  endtask  // Automatic

  task automatic check_fs(input string name, input logic [StateW-1:0] fs, input logic sd);
    csr_peek(MstatusAddr);
    check({name, "_fs"}, Xlen'(csr_rdata[MstatusFsLo+:StateW]), Xlen'(fs));
    check({name, "_sd"}, Xlen'(csr_rdata[MstatusSd]), Xlen'(sd));
  endtask  // Automatic

  task automatic check_trap_record(input string name, input logic [Xlen-1:0] epc);
    check({name, "_mepc"}, mepc_out, epc);
    csr_peek(McauseAddr);
    check({name, "_mcause"}, csr_rdata, Xlen'(CauseIllegalInstr));
  endtask  // Automatic

  task automatic test_fp_reset();
    csr_peek(FflagsAddr);
    check("fflags_reset", csr_rdata, '0);
    csr_peek(FrmAddr);
    check("frm_reset", csr_rdata, '0);
    csr_peek(FcsrAddr);
    check("fcsr_reset", csr_rdata, '0);
    check("frm_q_reset", Xlen'(frm_q), '0);
    check_fs("fs_reset", FsOff, 1'b0);
  endtask  // Automatic

  task automatic test_fp_rw();
    set_status(FsInitial, VsClean);
    for (int a = 0; a < $size(fp_addrs); a++) begin
      fp_apply(Funct3Csrrw, fp_addrs[a], Xlen'('hFFFF_FF55));
      fp_apply(Funct3Csrrc, fp_addrs[a], Xlen'('h0000_0F0F));
      fp_apply(Funct3Csrrs, fp_addrs[a], Xlen'('h0000_00A0));
      fp_apply(Funct3Csrrwi, fp_addrs[a], Xlen'('h0000_0015));
      fp_apply(Funct3Csrrsi, fp_addrs[a], Xlen'('h0000_000A));
      fp_apply(Funct3Csrrci, fp_addrs[a], Xlen'('h0000_0013));
    end
    repeat (120) fp_apply(rand_op(), rand_fp_addr(), Xlen'($urandom));
  endtask  // Automatic

  task automatic test_fp_alias();
    set_status(FsDirty, VsClean);
    fp_apply(Funct3Csrrw, FcsrAddr, Xlen'('hFFFF_FFB6));
    csr_peek(FflagsAddr);
    check("fcsr_to_fflags", csr_rdata, Xlen'('h16));
    csr_peek(FrmAddr);
    check("fcsr_to_frm", csr_rdata, Xlen'('h5));
    check("fcsr_to_frm_q", Xlen'(frm_q), Xlen'('h5));

    fp_apply(Funct3Csrrw, FrmAddr, Xlen'('h3));
    csr_peek(FcsrAddr);
    check("frm_to_fcsr", csr_rdata, Xlen'('h76));
    fp_apply(Funct3Csrrw, FflagsAddr, Xlen'('h9));
    csr_peek(FcsrAddr);
    check("fflags_to_fcsr", csr_rdata, Xlen'('h69));
    fp_apply(Funct3Csrrs, FrmAddr, Xlen'('h4));
    csr_peek(FcsrAddr);
    check("frm_set_to_fcsr", csr_rdata, Xlen'('hE9));
    fp_apply(Funct3Csrrci, FflagsAddr, Xlen'('h1));
    csr_peek(FcsrAddr);
    check("fflags_clear_to_fcsr", csr_rdata, Xlen'('hE8));
  endtask  // Automatic

  task automatic test_fs_off();
    set_status(FsDirty, VsClean);
    fp_apply(Funct3Csrrw, FcsrAddr, Xlen'('hA7));
    set_status(FsOff, VsClean);

    for (int a = 0; a < $size(fp_addrs); a++) begin
      for (int k = 0; k < 2; k++) begin
        logic [AddrW-1:0] addr;
        logic [ Xlen-1:0] epc;
        addr = fp_addrs[a];
        epc  = Xlen'('h0000_2000) + Xlen'(a * 16 + k * 4);
        csr_op(Funct3Csrrw, McauseAddr, '0);
        set_pc(epc);
        src_spec = k[0] ? ZimmW'(0) : ZimmW'(1);
        csr_trap($sformatf("fs_off_%h_traps", addr), k[0] ? Funct3Csrrs : Funct3Csrrw, addr,
                 Xlen'('h18), 1'b1);
        src_spec = ZimmW'(1);
        check_trap_record($sformatf("fs_off_%h", addr), epc);
        csr_peek(addr);
        check($sformatf("fs_off_%h_unchanged", addr), csr_rdata, fp_model_read(addr));
        check("fs_off_frm_q_unchanged", Xlen'(frm_q), Xlen'(exp_frm));
        check_fs("fs_off_stays_off", FsOff, 1'b0);
      end
    end

    csr_op(Funct3Csrrw, McauseAddr, '0);
    set_pc(Xlen'('h0000_2100));
    fp_trap("fp_instr_off_traps", FlagNv | FlagDz, 1'b1);
    check_trap_record("fp_instr_off", Xlen'('h0000_2100));
    csr_peek(FflagsAddr);
    check("fp_instr_off_no_accrue", csr_rdata, Xlen'(exp_fflags));
    check_fs("fp_instr_off_stays_off", FsOff, 1'b0);
    set_pc('0);
  endtask  // Automatic

  task automatic test_fs_dirty();
    for (int f = 0; f < 2 ** StateW; f++) begin
      for (int v = 0; v < 2 ** StateW; v++) begin
        set_status(StateW'(f), StateW'(v));
        csr_peek(MstatusAddr);
        check("fs_writable", Xlen'(csr_rdata[MstatusFsLo+:StateW]), Xlen'(f));
        check("vs_beside_fs", Xlen'(csr_rdata[MstatusVsLo+:StateW]), Xlen'(v));
        check("sd_either_dirty", Xlen'(csr_rdata[MstatusSd]),
              Xlen'(StateW'(f) == FsDirty || StateW'(v) == VsDirty));
      end
    end

    set_status(FsClean, VsClean);
    fp_instr(1'b1, 1'b1, 1'b0, '0);
    check_fs("fp_state_we_dirties", FsDirty, 1'b1);

    set_status(FsInitial, VsClean);
    fp_instr(1'b1, 1'b0, 1'b0, '0);
    check_fs("fp_instr_alone_keeps_initial", FsInitial, 1'b0);
    fp_instr(1'b1, 1'b0, 1'b1, '0);
    check_fs("zero_flags_keep_initial", FsInitial, 1'b0);
    fp_instr(1'b1, 1'b0, 1'b0, FlagAll);
    check_fs("flags_without_we_keep_initial", FsInitial, 1'b0);
    fp_instr(1'b1, 1'b0, 1'b1, FlagOf);
    exp_fflags = exp_fflags | FlagOf;
    check_fs("fp_flags_dirty", FsDirty, 1'b1);

    set_status(FsClean, VsClean);
    retire_flags(1'b1, 1'b0, FlagNx);
    exp_fflags = exp_fflags | FlagNx;
    check_fs("fp_flags_alone_dirty", FsDirty, 1'b1);

    for (int a = 0; a < $size(fp_addrs); a++) begin
      set_status(FsClean, VsClean);
      fp_apply(Funct3Csrrwi, fp_addrs[a], Xlen'('h3));
      check_fs($sformatf("fp_%h_write_dirties", fp_addrs[a]), FsDirty, 1'b1);
    end

    set_status(FsClean, VsClean);
    src_spec = '0;
    fp_apply(Funct3Csrrs, FflagsAddr, '0);
    src_spec = ZimmW'(1);
    fp_apply(Funct3Csrrci, FcsrAddr, '0);
    check_fs("fp_read_stays_clean", FsClean, 1'b0);

    fp_instr(1'b0, 1'b1, 1'b1, FlagAll);
    check_fs("fp_instr_core_en_low", FsClean, 1'b0);
  endtask  // Automatic

  task automatic test_fp_accrue();
    set_status(FsDirty, VsClean);
    fp_apply(Funct3Csrrw, FflagsAddr, '0);

    fp_instr(1'b0, 1'b1, 1'b1, FlagAll);
    csr_peek(FflagsAddr);
    check("accrue_core_en_low", csr_rdata, '0);

    fp_instr(1'b1, 1'b1, 1'b1, FlagNx);
    fp_instr(1'b1, 1'b1, 1'b1, FlagOf);
    fp_instr(1'b1, 1'b1, 1'b0, FlagNv);
    fp_instr(1'b1, 1'b1, 1'b1, FlagOf);
    csr_peek(FflagsAddr);
    check("accrue_or", csr_rdata, Xlen'(FlagOf | FlagNx));
    exp_fflags = FlagOf | FlagNx;

    retire_flags(1'b1, 1'b1, FlagNv | FlagDz | FlagUf);
    csr_peek(FflagsAddr);
    check("accrue_blocked_by_trap", csr_rdata, Xlen'(FlagOf | FlagNx));

    for (int t = 0; t < 200; t++) begin
      logic en;
      logic we;
      logic [FlagW-1:0] flags;
      if (t % 8 == 0) fp_apply(Funct3Csrrw, FflagsAddr, '0);
      en = $urandom_range(0, 3) != 0;
      we = $urandom_range(0, 3) != 0;
      flags = $urandom_range(0, 3) == 0 ? FlagW'($urandom) : FlagW'(1 << $urandom_range(FlagW - 1));
      fp_instr(en, 1'b1, we, flags);
      if (en && we) exp_fflags = exp_fflags | flags;
      csr_peek(FflagsAddr);
      check("fflags_accrue", csr_rdata, Xlen'(exp_fflags));
    end

    fp_apply(Funct3Csrrw, FcsrAddr, Xlen'(FlagNx));
    csr_retire(Funct3Csrrw, FflagsAddr, Xlen'(FlagNv), FlagDz | FlagOf);
    csr_peek(FflagsAddr);
    check("fflags_write_wins", csr_rdata, Xlen'(FlagNv));

    csr_retire(Funct3Csrrw, FcsrAddr, Xlen'('h41), FlagNv | FlagDz | FlagOf | FlagUf);
    csr_peek(FcsrAddr);
    check("fcsr_write_wins", csr_rdata, Xlen'('h41));

    csr_retire(Funct3Csrrs, FflagsAddr, Xlen'(FlagUf), FlagNv | FlagDz | FlagOf);
    csr_peek(FflagsAddr);
    check("fflags_set_wins", csr_rdata, Xlen'(FlagUf | FlagNx));

    csr_retire(Funct3Csrrw, FrmAddr, Xlen'('h6), FlagNv);
    csr_peek(FcsrAddr);
    check("frm_write_keeps_accrue", csr_rdata, Xlen'('hD3));
    exp_fflags = FlagNv | FlagUf | FlagNx;
    exp_frm    = RmW'('h6);
  endtask  // Automatic

  task automatic test_frm_q();
    set_status(FsDirty, VsClean);
    for (int r = 0; r < 2 ** RmW; r++) begin
      fp_apply(Funct3Csrrwi, FrmAddr, Xlen'(r));
      check("frm_q_value", Xlen'(frm_q), Xlen'(r));
    end
    fp_apply(Funct3Csrrw, FcsrAddr, Xlen'('h40));
    check("frm_q_from_fcsr", Xlen'(frm_q), Xlen'('h2));
    fp_instr(1'b1, 1'b1, 1'b1, FlagAll);
    exp_fflags = FlagAll;
    check("frm_q_holds_on_accrue", Xlen'(frm_q), Xlen'('h2));
  endtask  // Automatic

  task automatic test_fp_random();
    logic [StateW-1:0] exp_fs;
    set_status(FsDirty, VsClean);
    exp_fs = FsDirty;
    for (int t = 0; t < 2000; t++) begin
      int                 kind;
      logic [Funct3W-1:0] op;
      logic [  AddrW-1:0] addr;
      logic [   Xlen-1:0] val;
      logic [   Xlen-1:0] old;
      logic [  FlagW-1:0] flags;
      logic [ StateW-1:0] new_fs;
      logic               en;
      logic               fp;
      logic               we;
      logic               st;
      logic               ill;
      logic               acc;
      logic               wr;
      logic               trap;
      kind     = $urandom_range(0, 15);
      op       = rand_op();
      addr     = rand_fp_addr();
      val      = Xlen'($urandom);
      flags    = FlagW'($urandom);
      new_fs   = StateW'($urandom);
      src_spec = $urandom_range(0, 7) == 0 ? ZimmW'(0) : ZimmW'(1);
      en       = $urandom_range(0, 7) != 0;
      ill      = $urandom_range(0, 15) == 0;
      fp       = kind != 10 && $urandom_range(0, 2) == 0;
      st       = fp && 1'($urandom);
      we       = kind != 10 && (fp || exp_fs != FsOff) && 1'($urandom);
      acc      = kind < 10;
      wr       = acc && op_writes(op, val[ZimmW-1:0]);
      trap     = ill || ((fp || acc) && exp_fs == FsOff);
      old      = fp_model_read(addr);

      if (acc) csr_drive(op, addr, val);
      else if (kind == 10)
        csr_drive(Funct3Csrrw, MstatusAddr,
                  (Xlen'(new_fs) << MstatusFsLo) | (Xlen'(VsClean) << MstatusVsLo));
      else @(negedge clk);
      stage_fp(en, ill, fp, st, we, flags);
      @(posedge clk);
      check("rand_trap", Xlen'(trap_taken), Xlen'(trap));
      if (acc) check("rand_read_old", csr_rdata, old);
      csr_release();

      if (en && !trap) begin
        if (wr) fp_model_write(addr, FcsrW'(op_result(op, old, val)));
        if (we && !(wr && addr != FrmAddr)) exp_fflags = exp_fflags | flags;
        if (kind == 10) exp_fs = new_fs;
        else if ((fp && st) || (we && flags != '0) || wr) exp_fs = FsDirty;
      end
      csr_peek(FcsrAddr);
      check("rand_fcsr", csr_rdata, Xlen'({exp_frm, exp_fflags}));
      check("rand_frm_q", Xlen'(frm_q), Xlen'(exp_frm));
      check_fs("rand", exp_fs, exp_fs == FsDirty);
    end
    src_spec = ZimmW'(1);
  endtask  // Automatic

  task automatic test_fp_late_flags();
    set_status(FsDirty, VsClean);
    fp_apply(Funct3Csrrw, FflagsAddr, '0);
    exp_fflags = '0;

    late_flags(1'b0, 1'b0, 1'b1, FlagUf);
    csr_peek(FflagsAddr);
    check("late_flags_without_commit", csr_rdata, Xlen'(FlagUf));

    late_flags(1'b1, 1'b1, 1'b1, FlagDz);
    csr_peek(FflagsAddr);
    check("late_flags_beside_trap", csr_rdata, Xlen'(FlagDz | FlagUf));

    late_flags(1'b1, 1'b0, 1'b0, FlagNv);
    csr_peek(FflagsAddr);
    check("late_flags_need_we", csr_rdata, Xlen'(FlagDz | FlagUf));

    retire_and_late(FlagNx, FlagOf);
    csr_peek(FflagsAddr);
    check("late_and_retire_flags_merge", csr_rdata,
          Xlen'(FlagW'(FlagDz | FlagOf | FlagUf | FlagNx)));

    csr_late(Funct3Csrrw, FflagsAddr, Xlen'(FlagNv), FlagNx);
    csr_peek(FflagsAddr);
    check("late_flags_fflags_write_wins", csr_rdata, Xlen'(FlagNv));
    exp_fflags = FlagNv;
  endtask  // Automatic

  // Late vector flags
  task automatic test_vec_flags();
    set_status(FsDirty, VsClean);
    fp_apply(Funct3Csrrw, FflagsAddr, '0);
    set_status(FsClean, VsClean);

    vec_flags(1'b0, 1'b0, '0);
    check_fs("vec_zero_flags_keep_clean", FsClean, 1'b0);

    vec_flags(1'b0, 1'b0, FlagOf);
    csr_peek(FflagsAddr);
    check("vec_flags_without_commit", csr_rdata, Xlen'(FlagOf));
    check_fs("vec_flags_dirty_off_commit", FsDirty, 1'b1);

    set_status(FsClean, VsClean);
    vec_flags(1'b1, 1'b1, FlagNx);
    csr_peek(FflagsAddr);
    check("vec_flags_beside_trap", csr_rdata, Xlen'(FlagOf | FlagNx));
    check_fs("vec_flags_dirty_beside_trap", FsDirty, 1'b1);

    set_status(FsClean, VsClean);
    vec_flags(1'b1, 1'b0, FlagDz);
    check_fs("vec_flags_dirty_on_commit", FsDirty, 1'b1);

    csr_vec(Funct3Csrrw, MstatusAddr,
            (Xlen'(FsClean) << MstatusFsLo) | (Xlen'(VsClean) << MstatusVsLo), FlagNv);
    check_fs("mstatus_write_beats_vec_flags", FsClean, 1'b0);
    csr_peek(FflagsAddr);
    check("vec_flags_beside_mstatus_write", csr_rdata,
          Xlen'(FlagW'(FlagNv | FlagDz | FlagOf | FlagNx)));
    exp_fflags = FlagNv | FlagDz | FlagOf | FlagNx;
  endtask  // Automatic

  task automatic test_fp_reset_clears();
    set_status(FsDirty, VsClean);
    fp_apply(Funct3Csrrw, FcsrAddr, Xlen'('hFF));
    do_reset();
    test_fp_reset();
  endtask  // Automatic

  task automatic do_verdict();
    if (checks < MinChecks)
      $fatal(1, "TB UNDER-RAN: %0d checks, expected at least %0d", checks, MinChecks);
    if (errors == 0) $display("PASS: %0d checks, %0d mismatches", checks, errors);
    else $fatal(1, "FAIL: %0d mismatches, %0d checks", errors, checks);
    $finish;
  endtask  // Automatic

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
    test_fp_late_flags();
    test_vec_flags();
    test_fp_reset_clears();
    do_verdict();
  end

  // Bitwise reference
  function automatic logic [VstartW-1:0] model_vstart(
      input logic [Funct3W-1:0] op, input logic [VstartW-1:0] cur, input logic [Xlen-1:0] src);
    for (int i = 0; i < VstartW; i++) begin
      case (op)
        Funct3Csrrw, Funct3Csrrwi: model_vstart[i] = src[i];
        Funct3Csrrs, Funct3Csrrsi: model_vstart[i] = cur[i] | src[i];
        Funct3Csrrc, Funct3Csrrci: model_vstart[i] = cur[i] & ~src[i];
        default: model_vstart[i] = cur[i];
      endcase
    end
  endfunction

  function automatic logic [Xlen-1:0] fp_model_read(input logic [AddrW-1:0] addr);
    case (addr)
      FflagsAddr: fp_model_read = Xlen'(exp_fflags);
      FrmAddr: fp_model_read = Xlen'(exp_frm);
      default: fp_model_read = Xlen'({exp_frm, exp_fflags});
    endcase
  endfunction

  function automatic void fp_model_write(input logic [AddrW-1:0] addr,
                                         input logic [FcsrW-1:0] wdata);
    case (addr)
      FflagsAddr: exp_fflags = wdata[FlagW-1:0];
      FrmAddr: exp_frm = wdata[RmW-1:0];
      default: {exp_frm, exp_fflags} = wdata;
    endcase
  endfunction

  function automatic logic [Xlen-1:0] op_result(
      input logic [Funct3W-1:0] op, input logic [Xlen-1:0] cur, input logic [Xlen-1:0] val);
    logic [Xlen-1:0] wsrc;
    wsrc = op[2] ? Xlen'(val[ZimmW-1:0]) : val;
    case (op)
      Funct3Csrrw, Funct3Csrrwi: op_result = wsrc;
      Funct3Csrrs, Funct3Csrrsi: op_result = cur | wsrc;
      Funct3Csrrc, Funct3Csrrci: op_result = cur & ~wsrc;
      default: op_result = cur;
    endcase
  endfunction

  function automatic logic op_writes(input logic [Funct3W-1:0] op, input logic [ZimmW-1:0] imm);
    case (op)
      Funct3Csrrw, Funct3Csrrwi: op_writes = 1'b1;
      Funct3Csrrs, Funct3Csrrc: op_writes = src_spec != '0;
      default: op_writes = imm != '0;
    endcase
  endfunction

endmodule

`default_nettype wire
