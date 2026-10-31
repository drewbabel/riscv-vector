`default_nettype none

module sc_csr_tb
  import csr_pkg::*;
();

  localparam int XLEN = arch_pkg::XLEN;
  localparam int RegAddrW = arch_pkg::RegAddrW;
  localparam int Funct3W = opcode_pkg::Funct3W;
  localparam int Cycles = 60000;
  localparam int MinChecks = 300000;
  localparam int NumAddrs = 13;

  int checks = 0;
  int errors = 0;
  int max_errors = 0;
  int exc_pct = 6;

  logic clk = 1'b0;
  logic core_en;
  logic cycle_en;
  logic rst_n;
  logic csr_access;
  logic [CsrAddrW-1:0] csr_addr;
  logic [Funct3W-1:0] funct3;
  logic [XLEN-1:0] rs1_data;
  logic [RegAddrW-1:0] zimm;
  logic [XLEN-1:0] pc;
  logic [XLEN-1:0] bad_addr;
  logic exc_illegal;
  logic exc_ecall;
  logic exc_ebreak;
  logic exc_instr_misaligned;
  logic exc_load_misaligned;
  logic exc_store_misaligned;
  logic is_mret;
  logic timer_irq;
  logic [XLEN-1:0] csr_rdata;
  logic trap_taken;
  logic [XLEN-1:0] trap_vector;
  logic mret_taken;
  logic [XLEN-1:0] mepc_out;

  logic [XLEN-1:0] m_mstatus;
  logic [XLEN-1:0] m_mtvec;
  logic [XLEN-1:0] m_mepc;
  logic [XLEN-1:0] m_mcause;
  logic [XLEN-1:0] m_mtval;
  logic [XLEN-1:0] m_mie;
  logic [XLEN-1:0] m_mip;
  logic [XLEN-1:0] m_mscratch;
  logic [XLEN-1:0] m_mcycle;
  logic [XLEN-1:0] m_mcycleh;
  logic [XLEN-1:0] m_minstret;
  logic [XLEN-1:0] m_minstreth;

  logic [CsrAddrW-1:0] addrs[NumAddrs] = '{
      MstatusAddr,
      MieAddr,
      MtvecAddr,
      MscratchAddr,
      MepcAddr,
      McauseAddr,
      MtvalAddr,
      MipAddr,
      McycleAddr,
      MinstretAddr,
      McyclehAddr,
      MinstrethAddr,
      CsrAddrW'('h7c0)
  };

  sc_csr #(
      .XLEN(XLEN)
  ) dut (
      .clk(clk),
      .core_en(core_en),
      .cycle_en(cycle_en),
      .rst_n(rst_n),
      .csr_access(csr_access),
      .csr_addr(csr_addr),
      .funct3(funct3),
      .rs1_data(rs1_data),
      .zimm(zimm),
      .pc(pc),
      .bad_addr(bad_addr),
      .exc_illegal(exc_illegal),
      .exc_ecall(exc_ecall),
      .exc_ebreak(exc_ebreak),
      .exc_instr_misaligned(exc_instr_misaligned),
      .exc_load_misaligned(exc_load_misaligned),
      .exc_store_misaligned(exc_store_misaligned),
      .is_mret(is_mret),
      .timer_irq(timer_irq),
      .csr_rdata(csr_rdata),
      .trap_taken(trap_taken),
      .trap_vector(trap_vector),
      .mret_taken(mret_taken),
      .mepc_out(mepc_out)
  );

  always #5 clk = ~clk;

  initial void'($value$plusargs("max_errors=%d", max_errors));

  task automatic check(input string name, input logic [XLEN-1:0] got, input logic [XLEN-1:0] exp);
    checks++;
    if (got !== exp) begin
      errors++;
      $display("FAIL %s: got %h, expected %h", name, got, exp);
      if (errors == max_errors) $fatal(1, "TB STOPPED: %0d mismatches", errors);
    end
  endtask  // Automatic

  task automatic model_reset();
    m_mstatus = '0;
    m_mtvec = '0;
    m_mepc = '0;
    m_mcause = '0;
    m_mtval = '0;
    m_mie = '0;
    m_mip = '0;
    m_mscratch = '0;
    m_mcycle = '0;
    m_mcycleh = '0;
    m_minstret = '0;
    m_minstreth = '0;
  endtask  // Automatic

  function automatic logic [XLEN-1:0] read_ref(input logic [CsrAddrW-1:0] a);
    case (a)
      MstatusAddr: return m_mstatus;
      MieAddr: return m_mie;
      MtvecAddr: return m_mtvec;
      MscratchAddr: return m_mscratch;
      MepcAddr: return m_mepc;
      McauseAddr: return m_mcause;
      MtvalAddr: return m_mtval;
      MipAddr: return (m_mip & ~(XLEN'(1) << Mtip)) | (XLEN'(timer_irq) << Mtip);
      McycleAddr: return m_mcycle;
      MinstretAddr: return m_minstret;
      McyclehAddr: return m_mcycleh;
      MinstrethAddr: return m_minstreth;
      default: return '0;
    endcase
  endfunction

  function automatic logic trap_ref();
    return exc_illegal || exc_ecall || exc_ebreak || exc_instr_misaligned ||
        exc_load_misaligned || exc_store_misaligned ||
        (timer_irq && m_mstatus[MstatusMie] && m_mie[Mtie]);
  endfunction

  task automatic check_outputs(input string tag);
    check({tag, " csr_rdata"}, csr_rdata, read_ref(csr_addr));
    check({tag, " trap_taken"}, XLEN'(trap_taken), XLEN'(trap_ref()));
    check({tag, " trap_vector"}, trap_vector, {m_mtvec[XLEN-1:MtvecModeW], MtvecModeW'(0)});
    check({tag, " mret_taken"}, XLEN'(mret_taken), XLEN'(is_mret));
    check({tag, " mepc_out"}, mepc_out, m_mepc);
  endtask  // Automatic

  task automatic model_step();
    logic [XLEN-1:0] src;
    logic [XLEN-1:0] old;
    logic [XLEN-1:0] wdata;
    logic set_clear;
    logic wen;
    logic trap;
    logic [XLEN-1:0] cyc;
    logic [XLEN-1:0] ret;
    trap = trap_ref();
    old = read_ref(csr_addr);
    src = funct3[2] ? XLEN'(zimm) : rs1_data;
    set_clear = funct3[1:0] == 2'b10 || funct3[1:0] == 2'b11;
    case (funct3[1:0])
      2'b01:   wdata = src;
      2'b10:   wdata = old | src;
      2'b11:   wdata = old & ~src;
      default: wdata = old;
    endcase
    wen = csr_access && !trap && !(set_clear && src == '0);
    cyc = m_mcycle;
    ret = m_minstret;
    if (cycle_en) begin
      m_mcycle = m_mcycle + 1;
      if (cyc == '1) m_mcycleh = m_mcycleh + 1;
    end
    if (!core_en) return;
    if (wen && csr_addr == McycleAddr) m_mcycle = wdata;
    if (wen && csr_addr == McyclehAddr) m_mcycleh = wdata;
    if (!trap) begin
      m_minstret = m_minstret + 1;
      if (ret == '1) m_minstreth = m_minstreth + 1;
    end
    if (trap) begin
      m_mstatus[MstatusMpie] = m_mstatus[MstatusMie];
      m_mstatus[MstatusMie] = 1'b0;
      m_mepc = pc;
      m_mtval = '0;
      if (exc_instr_misaligned) begin
        m_mcause = XLEN'(CauseInstrMisaligned);
        m_mtval  = bad_addr;
      end else if (exc_illegal) m_mcause = XLEN'(CauseIllegalInstr);
      else if (exc_ecall) m_mcause = XLEN'(CauseEcallM);
      else if (exc_ebreak) m_mcause = XLEN'(CauseBreakpoint);
      else if (exc_load_misaligned) begin
        m_mcause = XLEN'(CauseLoadMisaligned);
        m_mtval  = bad_addr;
      end else if (exc_store_misaligned) begin
        m_mcause = XLEN'(CauseStoreMisaligned);
        m_mtval  = bad_addr;
      end else m_mcause = {1'b1, (XLEN - 1)'(CauseMachineTimerIrq)};
    end else if (is_mret) begin
      m_mstatus[MstatusMie]  = m_mstatus[MstatusMpie];
      m_mstatus[MstatusMpie] = 1'b1;
    end
    if (wen) begin
      case (csr_addr)
        MstatusAddr: m_mstatus = wdata;
        MieAddr: m_mie = wdata;
        MtvecAddr: m_mtvec = wdata;
        MscratchAddr: m_mscratch = wdata;
        MepcAddr: m_mepc = wdata;
        McauseAddr: m_mcause = wdata;
        MtvalAddr: m_mtval = wdata;
        MipAddr: m_mip = wdata & ~(XLEN'(1) << Mtip);
        MinstretAddr: m_minstret = wdata;
        MinstrethAddr: m_minstreth = wdata;
        default: ;
      endcase
    end
  endtask  // Automatic

  function automatic logic [XLEN-1:0] value();
    case ($urandom_range(
        5
    ))
      0: return '0;
      1: return '1;
      2: return XLEN'(1) << $urandom_range(XLEN - 1);
      3: return XLEN'('h88);
      default: return XLEN'($urandom);
    endcase
  endfunction

  task automatic drive();
    core_en = $urandom_range(9) != 0;
    cycle_en = $urandom_range(9) != 0;
    csr_access = 1'($urandom);
    csr_addr = $urandom_range(7) == 0 ? CsrAddrW'($urandom) : addrs[$urandom_range(NumAddrs-1)];
    funct3 = Funct3W'($urandom);
    rs1_data = value();
    zimm = $urandom_range(3) == 0 ? '0 : RegAddrW'($urandom);
    pc = XLEN'($urandom);
    bad_addr = XLEN'($urandom);
    exc_illegal = $urandom_range(99) < exc_pct;
    exc_ecall = $urandom_range(99) < exc_pct;
    exc_ebreak = $urandom_range(99) < exc_pct;
    exc_instr_misaligned = $urandom_range(99) < exc_pct;
    exc_load_misaligned = $urandom_range(99) < exc_pct;
    exc_store_misaligned = $urandom_range(99) < exc_pct;
    is_mret = $urandom_range(9) == 0;
    timer_irq = 1'($urandom);
  endtask  // Automatic

  task automatic run(input int n);
    repeat (n) begin
      drive();
      #1;
      check_outputs($sformatf("t=%0t addr %h f3 %b", $time, csr_addr, funct3));
      model_step();
      @(posedge clk);
      #1;
    end
  endtask  // Automatic

  task automatic test_counters();
    drive();
    exc_illegal = 1'b0;
    {exc_ecall, exc_ebreak, exc_instr_misaligned} = '0;
    {exc_load_misaligned, exc_store_misaligned, timer_irq} = '0;
    core_en = 1'b1;
    cycle_en = 1'b1;
    csr_access = 1'b1;
    funct3 = Funct3Csrrw;
    rs1_data = '1;
    for (int i = 0; i < 4; i++) begin
      csr_addr = (i % 2 == 0) ? McycleAddr : MinstretAddr;
      #1;
      check_outputs("preload");
      model_step();
      @(posedge clk);
      #1;
    end
    csr_access = 1'b0;
    for (int i = 0; i < 4; i++) begin
      csr_addr = addrs[8+i];
      #1;
      check_outputs("carry");
      model_step();
      @(posedge clk);
      #1;
    end
  endtask  // Automatic

  task automatic do_reset();
    drive();
    rst_n = 1'b0;
    model_reset();
    repeat (2) @(posedge clk);
    #1;
    rst_n = 1'b1;
  endtask  // Automatic

  task automatic do_verdict();
    if (checks < MinChecks)
      $fatal(1, "TB UNDER-RAN: %0d checks, expected at least %0d", checks, MinChecks);
    if (errors == 0) $display("PASS: %0d checks, %0d mismatches", checks, errors);
    else $fatal(1, "FAIL: %0d mismatches, %0d checks", errors, checks);
    $finish;
  endtask  // Automatic

  initial begin
    $dumpfile("sc_csr_tb.vcd");
    $dumpvars(0, sc_csr_tb);
    do_reset();

    test_counters();
    run(Cycles / 2);
    exc_pct = 1;
    run(Cycles / 2);
    do_reset();
    test_counters();

    do_verdict();
  end

endmodule

`default_nettype wire
