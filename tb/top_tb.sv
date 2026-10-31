`default_nettype none

module top_tb ();

  localparam int Xlen = arch_pkg::XLEN;
  localparam int AWIDTH = arch_pkg::RegAddrW;
  localparam int LineWords = cache_pkg::LineWords;
  localparam int Words = arch_pkg::SimMemWords;
  localparam int Lines = Words / LineWords;
  localparam int MaxCycles = 45;
  localparam int RunCycles = 120;
  localparam int Rounds = 40;
  localparam int MaxStores = 16;
  localparam int MinChecks = 3000;
  localparam logic [Xlen-1:0] Nop = Xlen'(opcode_pkg::OpcodeOpImm);
  localparam logic [4:0] Base = 5'd10;
  localparam logic [11:0] DataAddr = 12'h040;

  int checks = 0;
  int errors = 0;
  int max_errors = 0;

  logic clk = 1'b0;
  logic rst_n;
  logic [Xlen-1:0] pc;
  logic [Xlen-1:0] alu_result;
  logic [Xlen-1:0] write_data;
  logic mem_write;

  logic [7:0] m_bytes[Words*4];
  logic [Xlen-1:0] m_regs[32];
  logic [Xlen-1:0] prog[Words];
  logic [Xlen-1:0] st_addr[MaxStores];
  logic [Xlen-1:0] st_data[MaxStores];
  logic st_word[MaxStores];
  int n_instr;
  int n_st;
  int loop_pc;

  always #5 clk = ~clk;

  top #(
      .XLEN(Xlen)
  ) dut (
      .clk             (clk),
      .rst_n           (rst_n),
      .pc              (pc),
      .alu_result      (alu_result),
      .write_data      (write_data),
      .mem_write       (mem_write),
      .sim_branch      (),
      .sim_branch_taken(),
      .sim_mispredict  (),
      .sim_muldiv_hold ()
  );

  initial void'($value$plusargs("max_errors=%d", max_errors));

  task automatic check(input string name, input logic [Xlen-1:0] got, input logic [Xlen-1:0] exp);
    checks++;
    if (got !== exp) begin
      errors++;
      $display("FAIL %s: got %h, expected %h", name, got, exp);
      if (errors == max_errors) $fatal(1, "TB STOPPED: %0d mismatches", errors);
    end
  endtask  // Automatic

  function automatic logic [31:0] enc_i(input logic [11:0] imm, input logic [4:0] rs1,
                                        input logic [2:0] f3, input logic [4:0] rd,
                                        input logic [6:0] opc);
    return {imm, rs1, f3, rd, opc};
  endfunction

  function automatic logic [31:0] enc_s(input logic [11:0] imm, input logic [4:0] rs2,
                                        input logic [4:0] rs1, input logic [2:0] f3);
    return {imm[11:5], rs2, rs1, f3, imm[4:0], 7'b0100011};
  endfunction

  task automatic do_reset();
    rst_n = 0;
    repeat (2) @(posedge clk);
    @(negedge clk);
    rst_n = 1;
  endtask  // Automatic

  task automatic load_image(input string path);
    for (int i = 0; i < Words; i++) dut.imem_inst.mem[i] = Nop;
    $readmemh(path, dut.imem_inst.mem);
  endtask  // Automatic

  task automatic emit(input logic [31:0] w);
    prog[n_instr++] = w;
  endtask  // Automatic

  task automatic emit_li(input logic [4:0] rd, input logic [11:0] v);
    emit(enc_i(v, 5'd0, 3'b000, rd, 7'b0010011));
    m_regs[rd] = Xlen'($signed(v));
  endtask  // Automatic

  task automatic emit_store(input logic [4:0] rs2, input logic [11:0] off, input logic [2:0] f3);
    logic [Xlen-1:0] a;
    a = Xlen'(DataAddr) + Xlen'(off);
    emit(enc_s(off, rs2, Base, f3));
    for (int b = 0; b < (1 << f3); b++) m_bytes[a+b] = m_regs[rs2][8*b+:8];
    st_addr[n_st] = a;
    st_data[n_st] = m_regs[rs2];
    st_word[n_st] = f3 == 3'b010;
    n_st++;
  endtask  // Automatic

  task automatic emit_load(input logic [4:0] rd, input logic [11:0] off, input logic [2:0] f3);
    logic [Xlen-1:0] a;
    logic [Xlen-1:0] w;
    a = Xlen'(DataAddr) + Xlen'(off);
    w = {m_bytes[a+3], m_bytes[a+2], m_bytes[a+1], m_bytes[a]};
    emit(enc_i(off, Base, f3, rd, 7'b0000011));
    case (f3)
      3'b000:  m_regs[rd] = Xlen'($signed(w[7:0]));
      3'b101:  m_regs[rd] = Xlen'(w[15:0]);
      default: m_regs[rd] = w;
    endcase
  endtask  // Automatic

  task automatic build_program();
    n_instr = 0;
    n_st = 0;
    for (int i = 0; i < Words * 4; i++) m_bytes[i] = 8'($urandom);
    for (int l = 0; l < Lines; l++)
      for (int b = 0; b < 4 * LineWords; b++) dut.dmem_inst.mem[l][8*b+:8] = m_bytes[16*l+b];
    for (int r = 0; r < 32; r++) m_regs[r] = '0;
    emit_li(Base, DataAddr);
    for (int w = 0; w < LineWords; w++) begin
      emit_li(5'(1 + w), 12'($urandom));
      emit_store(5'(1 + w), 12'(4 * w), 3'b010);
    end
    emit_li(5'd5, 12'($urandom));
    emit_li(5'd6, 12'($urandom));
    for (int k = 0; k < LineWords; k++) emit_store(5'd5, 12'(16 + 5 * k), 3'b000);
    emit_store(5'd6, 12'h022, 3'b001);
    emit_store(5'd6, 12'h028, 3'b001);
    for (int w = 0; w < 3 * LineWords; w++) emit_load(5'(11 + w), 12'(4 * w), 3'b010);
    emit_load(5'd23, 12'h011, 3'b000);
    emit_load(5'd24, 12'h022, 3'b101);
    emit(enc_i(12'h344, 5'd0, 3'b010, 5'd25, 7'b1110011));
    m_regs[25] = '0;
    loop_pc = 4 * n_instr;
    emit(32'h0000006f);
    for (int i = 0; i < Words; i++) dut.imem_inst.mem[i] = (i < n_instr) ? prog[i] : Nop;
  endtask  // Automatic

  task automatic run_round(input int r);
    int k;
    logic [Xlen-1:0] last;
    logic [Xlen-1:0] ex_res;
    logic looped;
    string tag;
    build_program();
    do_reset();
    k = 0;
    last = '0;
    ex_res = '0;
    looped = 1'b0;
    repeat (RunCycles) begin
      @(negedge clk);
      tag = $sformatf("round %0d pc %h", r, pc);
      if (!looped) begin
        check({tag, " pc step"}, Xlen'(pc == last || pc == last + 4 || pc == loop_pc), 1);
        looped = pc == loop_pc;
        last   = pc;
      end
      if (mem_write) begin
        if (k < n_st) begin
          check({tag, " store addr"}, ex_res, st_addr[k]);
          if (st_word[k]) check({tag, " store data"}, write_data, st_data[k]);
        end
        k++;
      end
      ex_res = alu_result;
    end
    check($sformatf("round %0d stores", r), Xlen'(k), Xlen'(n_st));
    check($sformatf("round %0d looped", r), Xlen'(looped), 1);
    for (int x = 1; x < 26; x++)
      check($sformatf("round %0d x%0d", r, x),
            dut.riscv_pipelined_inst.datapath_inst.regfile_inst.regfile_mem[x], m_regs[x]);
    for (int l = 0; l < Lines; l++)
      for (int b = 0; b < 4 * LineWords; b++)
        check($sformatf("round %0d byte %h", r, 16 * l + b), Xlen'(dut.dmem_inst.mem[l][8*b+:8]),
              Xlen'(m_bytes[16*l+b]));
    for (int i = 0; i < n_instr; i++)
      check($sformatf("round %0d imem %0d", r, i), dut.imem_inst.mem[i], prog[i]);
  endtask  // Automatic

  task automatic check_reg(input logic [AWIDTH-1:0] r, input logic [Xlen-1:0] exp);
    check($sformatf("x%0d", r), dut.riscv_pipelined_inst.datapath_inst.regfile_inst.regfile_mem[r],
          exp);
  endtask  // Automatic

  task automatic run_nodep();
    load_image("tests/pl_nodep.hex");
    do_reset();
    repeat (MaxCycles) @(negedge clk);
    check_reg(AWIDTH'(1), Xlen'(5));
    check_reg(AWIDTH'(2), Xlen'(3));
    check_reg(AWIDTH'(3), Xlen'(8));
    check_reg(AWIDTH'(4), Xlen'(2));
    check_reg(AWIDTH'(5), Xlen'(8));
    check_reg(AWIDTH'(6), Xlen'(6));
    check_reg(AWIDTH'(7), Xlen'(7));
    check_reg(AWIDTH'(8), Xlen'(5));
    check_reg(AWIDTH'(9), Xlen'(10));
    check_reg(AWIDTH'(11), Xlen'(15));
    check_reg(AWIDTH'(12), Xlen'(1));
  endtask  // Automatic

  task automatic run_rounds();
    for (int r = 0; r < Rounds; r++) run_round(r);
  endtask  // Automatic

  task automatic do_verdict();
    if (checks < MinChecks)
      $fatal(1, "TB UNDER-RAN: %0d checks, expected at least %0d", checks, MinChecks);
    if (errors == 0) $display("PASS: %0d checks, %0d mismatches", checks, errors);
    else $fatal(1, "FAIL: %0d mismatches, %0d checks", errors, checks);
    $finish;
  endtask  // Automatic

  initial begin
    $dumpfile("top_tb.vcd");
    $dumpvars(0, top_tb);

    run_nodep();
    run_rounds();

    do_verdict();
  end

endmodule

`default_nettype wire
