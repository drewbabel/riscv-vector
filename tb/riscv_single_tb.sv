`default_nettype none

module riscv_single_tb ();

  localparam int XLEN = arch_pkg::XLEN;
  localparam int ILEN = arch_pkg::ILEN;
  localparam int StrbW = XLEN / 8;
  localparam int Words = 16384;
  localparam int Body = 500;
  localparam int Pad = 20;
  localparam int Programs = 40;
  localparam int MaxCycles = 30000;
  localparam int MinChecks = 60000;
  localparam logic [XLEN-1:0] DataBase = XLEN'('h8000);
  localparam logic [XLEN-1:0] Handler = XLEN'('h3000);
  localparam logic [4:0] BaseReg = 5'd31;
  localparam logic [4:0] CauseReg = 5'd30;
  localparam logic [4:0] EpcReg = 5'd29;
  localparam logic [4:0] FarReg = 5'd28;
  localparam int NumCsrs = 7;
  localparam logic [XLEN-1:0] IrqCause = {1'b1, 31'd7};

  int checks = 0;
  int errors = 0;
  int max_errors = 0;
  int stall_pct = 0;
  int irq_pct = 0;

  logic clk = 1'b0;
  logic core_en;
  logic cycle_en;
  logic rst_n;
  logic [ILEN-1:0] instr;
  logic [XLEN-1:0] read_data;
  logic timer_irq;
  logic [XLEN-1:0] pc;
  logic mem_write;
  logic [XLEN-1:0] alu_result;
  logic [XLEN-1:0] write_data;
  logic [StrbW-1:0] store_wstrb;
  logic [XLEN-1:0] store_data;

  logic [XLEN-1:0] mem[Words];
  logic [XLEN-1:0] m_mem[Words];
  logic [XLEN-1:0] m_regs[32];
  logic [XLEN-1:0] m_pc;
  logic [XLEN-1:0] m_mstatus;
  logic [XLEN-1:0] m_mie;
  logic [XLEN-1:0] m_mtvec;
  logic [XLEN-1:0] m_mscratch;
  logic [XLEN-1:0] m_mepc;
  logic [XLEN-1:0] m_mcause;
  logic [XLEN-1:0] m_mtval;
  int prog_words;
  logic far_jalr[Words];

  logic [11:0] csrs[NumCsrs] = '{12'h300, 12'h304, 12'h305, 12'h340, 12'h341, 12'h342, 12'h343};

  riscv_single #(
      .XLEN(XLEN)
  ) dut (
      .clk(clk),
      .core_en(core_en),
      .cycle_en(cycle_en),
      .rst_n(rst_n),
      .instr(instr),
      .read_data(read_data),
      .timer_irq(timer_irq),
      .pc(pc),
      .mem_write(mem_write),
      .alu_result(alu_result),
      .write_data(write_data),
      .store_wstrb(store_wstrb),
      .store_data(store_data)
  );

  always #5 clk = ~clk;

  assign instr = mem[pc[15:2]];
  assign read_data = mem[alu_result[15:2]];

  always @(posedge clk) begin
    if (rst_n && core_en)
      for (int b = 0; b < StrbW; b++)
      if (store_wstrb[b]) mem[alu_result[15:2]][8*b+:8] <= store_data[8*b+:8];
  end

  initial void'($value$plusargs("max_errors=%d", max_errors));

  task automatic check(input string name, input logic [XLEN-1:0] got, input logic [XLEN-1:0] exp);
    checks++;
    if (got !== exp) begin
      errors++;
      $display("FAIL %s: got %h, expected %h", name, got, exp);
      if (errors == max_errors) $fatal(1, "TB STOPPED: %0d mismatches", errors);
    end
  endtask  // Automatic

  function automatic logic [31:0] enc_r(input logic [6:0] f7, input logic [4:0] rs2,
                                        input logic [4:0] rs1, input logic [2:0] f3,
                                        input logic [4:0] rd);
    return {f7, rs2, rs1, f3, rd, 7'b0110011};
  endfunction

  function automatic logic [31:0] enc_i(input logic [11:0] imm, input logic [4:0] rs1,
                                        input logic [2:0] f3, input logic [4:0] rd,
                                        input logic [6:0] opc);
    return {imm, rs1, f3, rd, opc};
  endfunction

  function automatic logic [31:0] enc_s(input logic [11:0] imm, input logic [4:0] rs2,
                                        input logic [4:0] rs1, input logic [2:0] f3);
    return {imm[11:5], rs2, rs1, f3, imm[4:0], 7'b0100011};
  endfunction

  function automatic logic [31:0] enc_b(input logic [12:0] imm, input logic [4:0] rs2,
                                        input logic [4:0] rs1, input logic [2:0] f3);
    return {imm[12], imm[10:5], rs2, rs1, f3, imm[4:1], imm[11], 7'b1100011};
  endfunction

  function automatic logic [31:0] enc_j(input logic [20:0] imm, input logic [4:0] rd);
    return {imm[20], imm[10:1], imm[11], imm[19:12], rd, 7'b1101111};
  endfunction

  function automatic logic [4:0] rand_reg();
    return 5'($urandom_range(27));
  endfunction

  function automatic logic [11:0] mem_off(input logic [2:0] f3);
    logic [11:0] o;
    case (f3[1:0])
      2'b00:   o = 12'($urandom_range(255));
      2'b01:   o = 12'(2 * $urandom_range(127));
      default: o = 12'(4 * $urandom_range(63));
    endcase
    if ($urandom_range(15) == 0) o[1:0] = 2'($urandom);
    return o;
  endfunction

  function automatic logic [31:0] rand_csr();
    logic [ 2:0] f3;
    logic [11:0] a;
    a  = csrs[$urandom_range(NumCsrs-1)];
    f3 = 3'($urandom_range(1, 7));
    if (f3 == 3'b100) f3 = 3'b010;
    if (a == 12'h305) return enc_i(a, 5'd0, 3'b010, rand_reg(), 7'b1110011);
    return enc_i(a, $urandom_range(3) == 0 ? 5'd0 : rand_reg(), f3, rand_reg(), 7'b1110011);
  endfunction

  function automatic logic [31:0] rand_instr();
    logic [ 2:0] f3;
    logic [ 4:0] rd;
    logic [12:0] boff;
    rd   = rand_reg();
    f3   = 3'($urandom);
    boff = 13'(4 * $urandom_range(1, 16));
    if ($urandom_range(15) == 0) boff[1] = 1'b1;
    case ($urandom_range(
        13
    ))
      0, 1:
      return enc_r(
          {
            1'b0, 1'($urandom) && (f3 == 3'b000 || f3 == 3'b101), 5'b0
          },
          rand_reg(),
          rand_reg(),
          f3,
          rd
      );
      2, 3: begin
        if (f3 == 3'b001) return enc_i({7'b0, 5'($urandom)}, rand_reg(), f3, rd, 7'b0010011);
        if (f3 == 3'b101)
          return enc_i({1'b0, 1'($urandom), 5'b0, 5'($urandom)}, rand_reg(), f3, rd, 7'b0010011);
        return enc_i(12'($urandom), rand_reg(), f3, rd, 7'b0010011);
      end
      4: return {20'($urandom), rd, 1'($urandom) ? 7'b0110111 : 7'b0010111};
      5: begin
        case ($urandom_range(
            4
        ))
          0: f3 = 3'b000;
          1: f3 = 3'b100;
          2: f3 = 3'b001;
          3: f3 = 3'b101;
          default: f3 = 3'b010;
        endcase
        return enc_i(mem_off(f3), BaseReg, f3, rd, 7'b0000011);
      end
      6: begin
        f3 = 3'($urandom_range(2));
        return enc_s(mem_off(f3), rand_reg(), BaseReg, f3);
      end
      7: begin
        while (f3 == 3'b010 || f3 == 3'b011) f3 = 3'($urandom);
        return enc_b(boff, rand_reg(), rand_reg(), f3);
      end
      8: return enc_j({8'b0, boff}, rd);
      9: return rand_csr();
      10: begin
        case ($urandom_range(
            2
        ))
          0: return 32'h00000073;
          1: return 32'h00100073;
          default: return {25'($urandom), 7'b1111111};
        endcase
      end
      default: return 32'h0000000f;
    endcase
  endfunction

  task automatic skip_far(input int i);
    logic [31:0] w;
    logic [12:0] off;
    w = mem[i];
    if (w[6:0] == 7'b1100011) off = {w[31], w[7], w[30:25], w[11:8], 1'b0};
    else if (w[6:0] == 7'b1101111) off = 13'({w[31], w[19:12], w[20], w[30:21], 1'b0});
    else return;
    if (off[1:0] != 0 || !far_jalr[i+int'(off[12:2])]) return;
    if (w[6:0] == 7'b1101111) mem[i] = enc_j(21'(off + 13'd4), w[11:7]);
    else mem[i] = enc_b(off + 13'd4, w[24:20], w[19:15], w[14:12]);
  endtask  // Automatic

  task automatic build_program(input logic irq_on);
    int n;
    int h;
    int b;
    for (int i = 0; i < Words; i++) mem[i] = XLEN'($urandom);
    n = 0;
    mem[n++] = {DataBase[31:12], BaseReg, 7'b0110111};
    mem[n++] = {Handler[31:12], 5'd1, 7'b0110111};
    mem[n++] = enc_i(12'h305, 5'd1, 3'b001, 5'd0, 7'b1110011);
    if (irq_on) begin
      mem[n++] = enc_i(12'h300, 5'd8, 3'b110, 5'd0, 7'b1110011);
      mem[n++] = enc_i(12'h080, 5'd0, 3'b000, 5'd1, 7'b0010011);
      mem[n++] = enc_i(12'h304, 5'd1, 3'b010, 5'd0, 7'b1110011);
    end
    for (int r = 1; r < 28; r++) mem[n++] = enc_i(12'($urandom), 5'd0, 3'b000, 5'(r), 7'b0010011);
    for (int i = 0; i < Words; i++) far_jalr[i] = 1'b0;
    b = n;
    repeat (Body) begin
      if ($urandom_range(40) == 0) begin
        mem[n++] = {4'($urandom), 16'b0, FarReg, 7'b0010111};
        far_jalr[n] = 1'b1;
        mem[n++] = enc_i(12'd8, FarReg, 3'b000, rand_reg(), 7'b1100111);
      end else mem[n++] = rand_instr();
    end
    for (int i = b; i < n; i++) skip_far(i);
    repeat (Pad) mem[n++] = 32'h00000013;
    for (int r = 1; r < 32; r++) mem[n++] = enc_s(12'(4 * r), 5'(r), BaseReg, 3'b010);
    mem[n++] = enc_j(21'd0, 5'd0);
    prog_words = n;
    h = int'(Handler >> 2);
    mem[h++] = enc_i(12'h342, 5'd0, 3'b010, CauseReg, 7'b1110011);
    mem[h++] = enc_i(12'h341, 5'd0, 3'b010, EpcReg, 7'b1110011);
    mem[h++] = enc_b(13'd8, 5'd0, CauseReg, 3'b100);
    mem[h++] = enc_i(12'd4, EpcReg, 3'b000, EpcReg, 7'b0010011);
    mem[h++] = enc_i(12'h341, EpcReg, 3'b001, 5'd0, 7'b1110011);
    mem[h++] = 32'h30200073;
    for (int i = 0; i < Words; i++) m_mem[i] = mem[i];
  endtask  // Automatic

  function automatic logic [XLEN-1:0] rv(input logic [4:0] r);
    return (r == 0) ? '0 : m_regs[r];
  endfunction

  function automatic logic [XLEN-1:0] csr_read(input logic [11:0] a);
    case (a)
      12'h300: return m_mstatus;
      12'h304: return m_mie;
      12'h305: return m_mtvec;
      12'h340: return m_mscratch;
      12'h341: return m_mepc;
      12'h342: return m_mcause;
      default: return m_mtval;
    endcase
  endfunction

  task automatic csr_write(input logic [11:0] a, input logic [XLEN-1:0] v);
    case (a)
      12'h300: m_mstatus = v;
      12'h304: m_mie = v;
      12'h305: m_mtvec = v;
      12'h340: m_mscratch = v;
      12'h341: m_mepc = v;
      12'h342: m_mcause = v;
      default: m_mtval = v;
    endcase
  endtask  // Automatic

  task automatic take_trap(input logic [XLEN-1:0] cause, input logic [XLEN-1:0] tval);
    m_mstatus[7] = m_mstatus[3];
    m_mstatus[3] = 1'b0;
    m_mepc = m_pc;
    m_mcause = cause;
    m_mtval = tval;
    m_pc = {m_mtvec[XLEN-1:2], 2'b00};
  endtask  // Automatic

  task automatic model_step(output logic st, output logic [XLEN-1:0] addr,
                            output logic [StrbW-1:0] strb, output logic [XLEN-1:0] data);
    logic [31:0] i;
    logic [4:0] rd;
    logic [2:0] f3;
    logic [XLEN-1:0] a;
    logic [XLEN-1:0] b;
    logic [XLEN-1:0] res;
    logic [XLEN-1:0] next;
    logic [XLEN-1:0] w;
    logic [XLEN-1:0] src;
    logic wr;
    logic irq;
    i = m_mem[m_pc[15:2]];
    rd = i[11:7];
    f3 = i[14:12];
    a = rv(i[19:15]);
    b = rv(i[24:20]);
    next = m_pc + 4;
    wr = 1'b0;
    res = '0;
    st = 1'b0;
    addr = '0;
    strb = '0;
    data = '0;
    irq = timer_irq && m_mstatus[3] && m_mie[7];
    case (i[6:0])
      7'b0110011, 7'b0010011: begin
        if (i[6:0] == 7'b0010011) b = XLEN'($signed(i[31:20]));
        wr = 1'b1;
        case (f3)
          3'b000:  res = (i[5] && i[30]) ? a - b : a + b;
          3'b001:  res = a << b[4:0];
          3'b010:  res = XLEN'($signed(a) < $signed(b));
          3'b011:  res = XLEN'(a < b);
          3'b100:  res = a ^ b;
          3'b101:  res = i[30] ? XLEN'($signed(a) >>> b[4:0]) : a >> b[4:0];
          3'b110:  res = a | b;
          default: res = a & b;
        endcase
      end
      7'b0110111: begin
        wr  = 1'b1;
        res = {i[31:12], 12'b0};
      end
      7'b0010111: begin
        wr  = 1'b1;
        res = m_pc + {i[31:12], 12'b0};
      end
      7'b0001111: ;
      7'b0000011: begin
        addr = a + XLEN'($signed(i[31:20]));
        if ((f3[1:0] == 2'b01 && addr[0]) || (f3[1:0] == 2'b10 && addr[1:0] != 0)) begin
          take_trap(XLEN'(4), addr);
          return;
        end
        w  = m_mem[addr[15:2]];
        wr = 1'b1;
        case (f3)
          3'b000:  res = XLEN'($signed(w[8*addr[1:0]+:8]));
          3'b100:  res = XLEN'(w[8*addr[1:0]+:8]);
          3'b001:  res = XLEN'($signed(w[16*addr[1]+:16]));
          3'b101:  res = XLEN'(w[16*addr[1]+:16]);
          default: res = w;
        endcase
      end
      7'b0100011: begin
        addr = a + XLEN'($signed({i[31:25], i[11:7]}));
        if ((f3 == 3'b001 && addr[0]) || (f3 == 3'b010 && addr[1:0] != 0)) begin
          take_trap(XLEN'(6), addr);
          return;
        end
        st = 1'b1;
        case (f3)
          3'b000: begin
            strb = StrbW'(1) << addr[1:0];
            data = {4{b[7:0]}};
          end
          3'b001: begin
            strb = StrbW'(3) << addr[1:0];
            data = {2{b[15:0]}};
          end
          default: begin
            strb = '1;
            data = b;
          end
        endcase
        if (irq) begin
          st   = 1'b0;
          strb = '0;
        end else
          for (int k = 0; k < StrbW; k++) if (strb[k]) m_mem[addr[15:2]][8*k+:8] = data[8*k+:8];
      end
      7'b1100011: begin
        logic t;
        case (f3)
          3'b000:  t = a == b;
          3'b001:  t = a != b;
          3'b100:  t = $signed(a) < $signed(b);
          3'b101:  t = $signed(a) >= $signed(b);
          3'b110:  t = a < b;
          default: t = a >= b;
        endcase
        if (t) next = m_pc + XLEN'($signed({i[31], i[7], i[30:25], i[11:8], 1'b0}));
      end
      7'b1101111: begin
        wr   = 1'b1;
        res  = m_pc + 4;
        next = m_pc + XLEN'($signed({i[31], i[19:12], i[20], i[30:21], 1'b0}));
      end
      7'b1100111: begin
        wr   = 1'b1;
        res  = m_pc + 4;
        next = (a + XLEN'($signed(i[31:20]))) & ~XLEN'(1);
      end
      7'b1110011: begin
        if (f3 == 3'b000) begin
          if (i == 32'h30200073 && !irq) begin
            m_pc = m_mepc;
            m_mstatus[3] = m_mstatus[7];
            m_mstatus[7] = 1'b1;
            return;
          end
          if (i == 32'h00000073) begin
            take_trap(XLEN'(11), '0);
            return;
          end
          if (i == 32'h00100073) begin
            take_trap(XLEN'(3), '0);
            return;
          end
        end else if (f3 == 3'b100) begin
          take_trap(XLEN'(2), '0);
          return;
        end else if (!irq) begin
          w   = csr_read(i[31:20]);
          src = f3[2] ? XLEN'(i[19:15]) : a;
          wr  = 1'b1;
          res = w;
          if (f3[1:0] == 2'b01) csr_write(i[31:20], src);
          else if (src != 0) csr_write(i[31:20], f3[1:0] == 2'b10 ? w | src : w & ~src);
        end
      end
      default: begin
        take_trap(XLEN'(2), '0);
        return;
      end
    endcase
    if (next[1:0] != 0 && !irq) begin
      take_trap(XLEN'(0), next);
      return;
    end
    if (irq) begin
      take_trap(IrqCause, '0);
      return;
    end
    if (wr && rd != 0) m_regs[rd] = res;
    m_pc = next;
  endtask  // Automatic

  task automatic run_program(input int p);
    logic st;
    logic [XLEN-1:0] addr;
    logic [StrbW-1:0] strb;
    logic [XLEN-1:0] data;
    logic [13:0] done_idx;
    string tag;
    int n;
    build_program(p % 4 >= 2);
    done_idx = 14'(prog_words - 1);
    for (int r = 0; r < 32; r++) m_regs[r] = '0;
    m_pc = '0;
    m_mstatus = '0;
    m_mie = '0;
    m_mtvec = '0;
    m_mscratch = '0;
    m_mepc = '0;
    m_mcause = '0;
    m_mtval = '0;
    rst_n = 1'b0;
    core_en = 1'b1;
    timer_irq = 1'b0;
    repeat (2) @(posedge clk);
    #1;
    rst_n = 1'b1;
    n = 0;
    while (m_pc[15:2] != done_idx && n < MaxCycles) begin
      core_en   = $urandom_range(99) >= stall_pct;
      timer_irq = $urandom_range(99) < irq_pct;
      #1;
      tag = $sformatf("prog %0d pc %h instr %h", p, m_pc, m_mem[m_pc[15:2]]);
      check({tag, " pc"}, pc, m_pc);
      if (core_en) begin
        model_step(st, addr, strb, data);
        check({tag, " mem_write"}, XLEN'(mem_write), XLEN'(st));
        check({tag, " store_wstrb"}, XLEN'(store_wstrb), XLEN'(strb));
        if (st) begin
          check({tag, " store addr"}, alu_result, addr);
          for (int k = 0; k < StrbW; k++)
          if (strb[k]) check({tag, " store byte"}, XLEN'(store_data[8*k+:8]), XLEN'(data[8*k+:8]));
        end
        n++;
      end
      @(posedge clk);
      #1;
    end
    timer_irq = 1'b0;
    check({tag, " reached end"}, XLEN'(m_pc[15:2]), XLEN'(done_idx));
    for (int r = 1; r < 32; r++)
      check($sformatf("prog %0d dump x%0d", p, r), mem[(DataBase>>2)+r], m_mem[(DataBase>>2)+r]);
  endtask  // Automatic

  task automatic run_all();
    for (int p = 0; p < Programs; p++) begin
      stall_pct = (p % 2 == 0) ? 0 : 25;
      irq_pct   = (p % 4 >= 2) ? 3 : 0;
      run_program(p);
    end
  endtask  // Automatic

  task automatic do_reset();
    rst_n = 1'b0;
    core_en = 1'b1;
    cycle_en = 1'b1;
    timer_irq = 1'b0;
    repeat (2) @(posedge clk);
    #1;
  endtask  // Automatic

  task automatic do_verdict();
    if (checks < MinChecks)
      $fatal(1, "TB UNDER-RAN: %0d checks, expected at least %0d", checks, MinChecks);
    if (errors == 0) $display("PASS: %0d checks, %0d mismatches", checks, errors);
    else $fatal(1, "FAIL: %0d mismatches, %0d checks", errors, checks);
    $finish;
  endtask  // Automatic

  initial begin
    $dumpfile("riscv_single_tb.vcd");
    $dumpvars(0, riscv_single_tb);
    do_reset();

    run_all();

    do_verdict();
  end

endmodule

`default_nettype wire
