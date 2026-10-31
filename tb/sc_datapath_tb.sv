`default_nettype none

module sc_datapath_tb
  import alu_pkg::*;
  import opcode_pkg::*;
();

  localparam int XLEN = arch_pkg::XLEN;
  localparam int ILEN = arch_pkg::ILEN;
  localparam int NRegs = arch_pkg::NumRegs;
  localparam int RegAddrW = arch_pkg::RegAddrW;
  localparam int Shamt = $clog2(XLEN);
  localparam int Cycles = 40000;
  localparam int MinChecks = 280000;
  localparam logic [XLEN-1:0] ResetAddr = XLEN'(arch_pkg::ResetAddr);

  int checks = 0;
  int errors = 0;
  int max_errors = 0;

  logic clk = 1'b0;
  logic core_en;
  logic rst_n;
  logic reg_write;
  logic [ImmSrcW-1:0] imm_src;
  logic [SrcAW-1:0] alu_a_src;
  logic alu_src;
  logic [ResSrcW-1:0] result_src;
  logic csr_access;
  logic [XLEN-1:0] csr_rdata;
  alu_op_e alu_ctrl;
  logic pc_src;
  logic pc_target_src;
  logic trap_taken;
  logic [XLEN-1:0] trap_vector;
  logic mret_taken;
  logic [XLEN-1:0] mepc_out;
  logic [ILEN-1:0] instr;
  logic [XLEN-1:0] read_data;
  logic [XLEN-1:0] pc;
  logic [XLEN-1:0] alu_result;
  logic [XLEN-1:0] write_data;
  logic [XLEN-1:0] rs1_data;
  logic zero;
  logic lt;
  logic ltu;

  logic [XLEN-1:0] m_regs[NRegs];
  logic [XLEN-1:0] m_pc;

  sc_datapath #(
      .XLEN(XLEN)
  ) dut (
      .clk(clk),
      .core_en(core_en),
      .rst_n(rst_n),
      .reg_write(reg_write),
      .imm_src(imm_src),
      .alu_a_src(alu_a_src),
      .alu_src(alu_src),
      .result_src(result_src),
      .csr_access(csr_access),
      .csr_rdata(csr_rdata),
      .alu_ctrl(alu_ctrl),
      .pc_src(pc_src),
      .pc_target_src(pc_target_src),
      .trap_taken(trap_taken),
      .trap_vector(trap_vector),
      .mret_taken(mret_taken),
      .mepc_out(mepc_out),
      .instr(instr),
      .read_data(read_data),
      .pc(pc),
      .alu_result(alu_result),
      .write_data(write_data),
      .rs1_data(rs1_data),
      .zero(zero),
      .lt(lt),
      .ltu(ltu)
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

  function automatic logic [XLEN-1:0] reg_ref(input logic [RegAddrW-1:0] r);
    return (r == 0) ? '0 : m_regs[r];
  endfunction

  function automatic logic [XLEN-1:0] imm_ref();
    case (imm_src)
      ImmI: return XLEN'($signed(instr[31:20]));
      ImmS: return XLEN'($signed({instr[31:25], instr[11:7]}));
      ImmB: return XLEN'($signed({instr[31], instr[7], instr[30:25], instr[11:8], 1'b0}));
      ImmU: return {instr[31:12], 12'b0};
      default: return XLEN'($signed({instr[31], instr[19:12], instr[20], instr[30:21], 1'b0}));
    endcase
  endfunction

  function automatic logic [XLEN-1:0] alu_ref(input logic [XLEN-1:0] x, input logic [XLEN-1:0] y);
    case (alu_ctrl)
      ALU_ADD:  return x + y;
      ALU_SUB:  return x - y;
      ALU_SLL:  return x << y[Shamt-1:0];
      ALU_SLT:  return XLEN'($signed(x) < $signed(y));
      ALU_SLTU: return XLEN'(x < y);
      ALU_XOR:  return x ^ y;
      ALU_SRL:  return x >> y[Shamt-1:0];
      ALU_SRA:  return $signed(x) >>> y[Shamt-1:0];
      ALU_OR:   return x | y;
      ALU_AND:  return x & y;
      default:  return '0;
    endcase
  endfunction

  task automatic step();
    logic [XLEN-1:0] a;
    logic [XLEN-1:0] b;
    logic [XLEN-1:0] y;
    logic [XLEN-1:0] res;
    logic [XLEN-1:0] target;
    logic [XLEN-1:0] next;
    string tag;
    #1;
    case (alu_a_src)
      SrcARs1: a = reg_ref(instr[19:15]);
      SrcAPc:  a = m_pc;
      default: a = '0;
    endcase
    b   = alu_src ? imm_ref() : reg_ref(instr[24:20]);
    y   = alu_ref(a, b);
    tag = $sformatf("t=%0t instr %h", $time, instr);
    check({tag, " pc"}, pc, m_pc);
    check({tag, " rs1_data"}, rs1_data, reg_ref(instr[19:15]));
    check({tag, " write_data"}, write_data, reg_ref(instr[24:20]));
    check({tag, " alu_result"}, alu_result, y);
    check({tag, " zero"}, XLEN'(zero), XLEN'(y == '0));
    check({tag, " lt"}, XLEN'(lt), XLEN'($signed(a) < $signed(b)));
    check({tag, " ltu"}, XLEN'(ltu), XLEN'(a < b));
    if (csr_access) res = csr_rdata;
    else if (result_src == ResAlu) res = y;
    else if (result_src == ResMem) res = read_data;
    else if (result_src == ResPc4) res = m_pc + 4;
    else res = '0;
    target = pc_target_src ? {y[XLEN-1:1], 1'b0} : m_pc + imm_ref();
    if (trap_taken) next = trap_vector;
    else if (mret_taken) next = mepc_out;
    else next = pc_src ? target : m_pc + 4;
    if (core_en) begin
      m_pc = next;
      if (reg_write && instr[11:7] != 0) m_regs[instr[11:7]] = res;
    end
    @(posedge clk);
  endtask  // Automatic

  task automatic drive(input int span);
    core_en = $urandom_range(7) != 0;
    reg_write = 1'($urandom);
    imm_src = ImmSrcW'($urandom_range(4));
    alu_a_src = SrcAW'($urandom_range(3));
    alu_src = 1'($urandom);
    result_src = ResSrcW'($urandom);
    csr_access = $urandom_range(7) == 0;
    csr_rdata = XLEN'($urandom);
    alu_ctrl = alu_op_e'($urandom_range(2 ** $bits(alu_op_e) - 1));
    pc_src = 1'($urandom);
    pc_target_src = 1'($urandom);
    trap_taken = $urandom_range(15) == 0;
    trap_vector = XLEN'($urandom);
    mret_taken = $urandom_range(15) == 0;
    mepc_out = XLEN'($urandom);
    instr = ILEN'($urandom);
    instr[19:15] = RegAddrW'($urandom_range(span - 1));
    instr[24:20] = RegAddrW'($urandom_range(span - 1));
    instr[11:7] = RegAddrW'($urandom_range(span - 1));
    read_data = XLEN'($urandom);
    if ($urandom_range(3) == 0) read_data = XLEN'(1) << $urandom_range(XLEN - 1);
  endtask  // Automatic

  task automatic run(input int n, input int span);
    repeat (n) begin
      drive(span);
      step();
    end
  endtask  // Automatic

  task automatic test_fill();
    for (int r = 0; r < NRegs; r++) begin
      drive(NRegs);
      core_en = 1'b1;
      reg_write = 1'b1;
      csr_access = 1'b0;
      result_src = ResMem;
      instr[11:7] = RegAddrW'(r);
      step();
    end
    for (int r = 0; r < NRegs; r++) begin
      drive(NRegs);
      core_en = 1'b0;
      instr[19:15] = RegAddrW'(r);
      instr[24:20] = RegAddrW'(NRegs - 1 - r);
      step();
    end
  endtask  // Automatic

  task automatic do_reset();
    drive(NRegs);
    rst_n = 1'b0;
    for (int r = 0; r < NRegs; r++) m_regs[r] = '0;
    m_pc = ResetAddr;
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
    $dumpfile("sc_datapath_tb.vcd");
    $dumpvars(0, sc_datapath_tb);
    do_reset();

    test_fill();
    run(Cycles / 2, NRegs);
    run(Cycles / 2, 4);
    do_reset();
    test_fill();

    do_verdict();
  end

endmodule

`default_nettype wire
