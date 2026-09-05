`default_nettype none

module csr_tb;
  import csr_pkg::*;

  int checks = 0;
  int errors = 0;

  localparam int Xlen = 32;
  localparam int Vlen = 128;

  logic            clk;
  logic            rst_n;
  logic            csr_access;
  logic [    11:0] csr_addr;
  logic [     2:0] funct3;
  logic [Xlen-1:0] rs1_data;
  logic [     4:0] zimm;
  logic [     4:0] src_spec = 5'd1;  // rs1 field
  logic [Xlen-1:0] pc;
  logic [Xlen-1:0] bad_addr;
  logic            exc_illegal;
  logic            exc_ecall;
  logic            exc_ebreak;
  logic            exc_instr_misaligned;
  logic            exc_load_misaligned;
  logic            exc_store_misaligned;
  logic            is_mret;
  logic            timer_irq;
  logic            ext_irq;
  logic [Xlen-1:0] csr_rdata;
  logic            trap_taken;
  logic [Xlen-1:0] trap_vector;
  logic            mret_taken;
  logic [Xlen-1:0] mepc_out;

  logic            is_vset;
  logic [     7:0] vl_d;
  logic [Xlen-1:0] vtype_d;
  logic            is_vec_instr;
  logic [     7:0] vl_q;
  logic [Xlen-1:0] vtype_q;

  logic [Xlen-1:0] exp_mscratch;
  logic [     6:0] exp_vstart;

  initial clk = 0;
  always #5 clk = ~clk;

  csr #(
      .XLEN(Xlen),
      .VLEN(Vlen)
  ) dut (
      .clk                 (clk),
      .core_en             (1'b1),
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
      .vtype_q             (vtype_q)
  );

  task automatic check(input string name, input logic [Xlen-1:0] got, input logic [Xlen-1:0] exp);
    checks++;
    if (got !== exp) begin
      errors++;
      $error("%s: got %h exp %h", name, got, exp);
    end
  endtask

  // Idle inputs, reset
  task automatic do_reset();
    csr_access   = 0;
    csr_addr     = 0;
    funct3       = 0;
    rs1_data     = 0;
    zimm         = 0;
    pc           = 0;
    bad_addr     = 0;
    is_mret      = 0;
    timer_irq    = 0;
    ext_irq      = 0;
    is_vset      = 0;
    is_vec_instr = 0;
    vl_d         = 0;
    vtype_d      = 0;
    {exc_illegal, exc_ecall, exc_ebreak} = 0;
    {exc_instr_misaligned, exc_load_misaligned, exc_store_misaligned} = 0;
    exp_mscratch = 0;
    exp_vstart   = 0;
    rst_n        = 0;
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
  task automatic vec_instr(input logic set_cfg, input logic [7:0] next_vl,
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
  function automatic logic [6:0] model_vstart(input logic [2:0] op, input logic [6:0] cur,
                                              input logic [Xlen-1:0] src);
    for (int i = 0; i < 7; i++) begin
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

  task automatic verdict();
    if (errors == 0) $display("PASS: %0d checks, %0d mismatches", checks, errors);
    else $fatal(1, "FAIL: %0d mismatches, %0d checks", errors, checks);
    $finish;
  endtask

  initial begin
    $dumpfile("csr_tb.vcd");
    $dumpvars(0, csr_tb);
    do_reset();
    test_mscratch();
    test_mip();
    test_mtvec();
    test_vstart();
    test_config();
    test_mstatus();
    test_readonly();
    test_vs_off();
    verdict();
  end

endmodule

`default_nettype wire
