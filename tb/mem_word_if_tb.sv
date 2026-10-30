`default_nettype none

module mem_word_if_tb ();

  localparam int MinChecks = 40000;
  localparam int MinLineChecks = 39000;

  int checks;
  int errors;
  int max_errors;
  int live_errors;

  mem_word_if_bench xlen_bench ();

  mem_word_if_bench #(.CPU_W(cache_pkg::LineBits)) line_bench ();

  mem_word_if_bench #(.CPU_W(64)) dword_bench ();

  task automatic check_floor(input string name, input int got, input int floor);
    if (got < floor)
      $fatal(1, "TB UNDER-RAN: %s %0d checks, expected at least %0d", name, got, floor);
  endtask  // Automatic

  task automatic do_verdict();
    checks = xlen_bench.checks + line_bench.checks + dword_bench.checks;
    errors = xlen_bench.errors + line_bench.errors + dword_bench.errors;
    check_floor("xlen_bench", xlen_bench.checks, MinChecks);
    check_floor("line_bench", line_bench.checks, MinLineChecks);
    check_floor("dword_bench", dword_bench.checks, MinLineChecks);
    if (errors == 0) $display("PASS: %0d checks, %0d mismatches", checks, errors);
    else $fatal(1, "FAIL: %0d mismatches, %0d checks", errors, checks);
    $finish;
  endtask  // Automatic

  initial begin
    $dumpfile("mem_word_if_tb.vcd");
    $dumpvars(0, mem_word_if_tb);
    wait (xlen_bench.done && line_bench.done && dword_bench.done);
    do_verdict();
  end

  always_comb live_errors = xlen_bench.errors + line_bench.errors + dword_bench.errors;

  initial begin
    if ($value$plusargs("max_errors=%d", max_errors) && max_errors > 0) begin
      wait (live_errors >= max_errors);
      $fatal(1, "TB STOPPED: %0d mismatches", live_errors);
    end
  end

endmodule

module mem_word_if_bench
  import cache_pkg::*;
#(
    parameter int CPU_W = arch_pkg::XLEN
) ();

  localparam int Xlen = arch_pkg::XLEN;
  localparam int CpuW = CPU_W;
  localparam int CpuBytes = CpuW / 8;
  localparam int CpuLsb = $clog2(CpuBytes);
  localparam int Chunks = LineBits / CpuW;
  localparam int MemLines = 64;
  localparam int MaxLat = 6;
  localparam int MaxWait = 4000;
  localparam int TimeoutCycles = 400_000;
  localparam int ReuseRounds = 8;
  localparam int RandomOps = 200;

  int checks = 0;
  int errors = 0;
  int max_errors = 0;
  logic done = 1'b0;
  int max_lat = MaxLat;
  int en_period = 1;
  int en_ctr = 0;
  int i_done = 0;
  int d_done = 0;

  logic clk = 1'b0;
  logic rst_n = 1'b0;
  logic core_en;

  logic i_cpu_valid;
  logic [Xlen-1:0] i_cpu_addr;
  logic [CpuW-1:0] i_cpu_rdata;
  logic i_cpu_ready;
  logic i_mem_valid;
  logic i_mem_rw;
  logic [Xlen-1:0] i_mem_addr;
  logic [LineBits-1:0] i_mem_wdata;
  logic [LineBytes-1:0] i_mem_wstrb;
  logic [LineBits-1:0] i_mem_rdata;
  logic i_mem_ready;
  logic [31:0] i_hits;
  logic [31:0] i_misses;

  logic d_cpu_valid;
  logic d_cpu_rw;
  logic [Xlen-1:0] d_cpu_addr;
  logic [CpuW-1:0] d_cpu_wdata;
  logic [CpuBytes-1:0] d_cpu_wstrb;
  logic [CpuW-1:0] d_cpu_rdata;
  logic d_cpu_ready;
  logic d_mem_valid;
  logic d_mem_rw;
  logic [Xlen-1:0] d_mem_addr;
  logic [LineBits-1:0] d_mem_wdata;
  logic [LineBytes-1:0] d_mem_wstrb;
  logic [LineBits-1:0] d_mem_rdata;
  logic d_mem_ready;
  logic [31:0] d_hits;
  logic [31:0] d_misses;

  logic [CpuW-1:0] got;

  // Line memory model
  logic [LineBits-1:0] mem[MemLines];

  // Instruction responder
  logic i_busy;
  logic i_pend;
  int i_ctr;
  logic [LineBits-1:0] i_hold;

  // Data responder
  logic d_busy;
  logic d_pend;
  int d_ctr;
  logic [LineBits-1:0] d_hold;

  always #5 clk = ~clk;

  mem_word_if #(
      .XLEN (Xlen),
      .RW   (1'b0),
      .CPU_W(CpuW)
  ) i_dut (
      .clk(clk),
      .core_en(core_en),
      .rst_n(rst_n),
      .cpu_valid(i_cpu_valid),
      .cpu_rw(1'b1),
      .cpu_addr(i_cpu_addr),
      .cpu_wdata(CpuW'('hDEAD_BEEF)),
      .cpu_wstrb('1),
      .cpu_rdata(i_cpu_rdata),
      .cpu_ready(i_cpu_ready),
      .mem_valid(i_mem_valid),
      .mem_rw(i_mem_rw),
      .mem_addr(i_mem_addr),
      .mem_wdata(i_mem_wdata),
      .mem_wstrb(i_mem_wstrb),
      .mem_rdata(i_mem_rdata),
      .mem_ready(i_mem_ready),
      .hit_count(i_hits),
      .miss_count(i_misses)
  );

  mem_word_if #(
      .XLEN (Xlen),
      .RW   (1'b1),
      .CPU_W(CpuW)
  ) d_dut (
      .clk(clk),
      .core_en(core_en),
      .rst_n(rst_n),
      .cpu_valid(d_cpu_valid),
      .cpu_rw(d_cpu_rw),
      .cpu_addr(d_cpu_addr),
      .cpu_wdata(d_cpu_wdata),
      .cpu_wstrb(d_cpu_wstrb),
      .cpu_rdata(d_cpu_rdata),
      .cpu_ready(d_cpu_ready),
      .mem_valid(d_mem_valid),
      .mem_rw(d_mem_rw),
      .mem_addr(d_mem_addr),
      .mem_wdata(d_mem_wdata),
      .mem_wstrb(d_mem_wstrb),
      .mem_rdata(d_mem_rdata),
      .mem_ready(d_mem_ready),
      .hit_count(d_hits),
      .miss_count(d_misses)
  );

  task automatic check(input string name, input logic [CpuW-1:0] got, input logic [CpuW-1:0] exp);
    checks++;
    if (got !== exp) begin
      errors++;
      $display("FAIL %m %s: got %h, expected %h", name, got, exp);
      if (errors == max_errors) $fatal(1, "TB STOPPED: %0d mismatches", errors);
    end
  endtask  // Automatic

  task automatic do_reset();
    @(negedge clk);
    rst_n       = 1'b0;
    i_cpu_valid = 1'b0;
    i_cpu_addr  = '0;
    d_cpu_valid = 1'b0;
    d_cpu_rw    = 1'b0;
    d_cpu_addr  = '0;
    d_cpu_wdata = '0;
    d_cpu_wstrb = '0;
    repeat (3) @(posedge clk);
    @(negedge clk);
    rst_n = 1'b1;
    @(negedge clk);
  endtask  // Automatic

  task automatic init_memory();
    i_hold = '0;
    d_hold = '0;
    for (int i = 0; i < MemLines; i++) begin
      for (int w = 0; w < LineWords; w++)
      mem[i][w*Xlen+:Xlen] = Xlen'('h1000_0000) + Xlen'(i * LineWords + w);
    end
  endtask  // Automatic

  task automatic poke_word(input logic [Xlen-1:0] addr, input logic [CpuW-1:0] data);
    mem[line_of(addr)][word_of(addr)*CpuW+:CpuW] = data;
  endtask  // Automatic

  task automatic idle(input int n);
    repeat (n) @(negedge clk);
  endtask  // Automatic

  task automatic set_core(input int period, input int lat);
    en_period = period;
    max_lat   = lat;
  endtask  // Automatic

  task automatic wait_i();
    int guard;
    guard = 0;
    @(negedge clk);
    while (!i_cpu_ready) begin
      guard++;
      if (guard > MaxWait) $fatal(1, "instruction access never completed");
      @(negedge clk);
    end
  endtask  // Automatic

  task automatic wait_d();
    int guard;
    guard = 0;
    @(negedge clk);
    while (!d_cpu_ready) begin
      guard++;
      if (guard > MaxWait) $fatal(1, "data access never completed");
      @(negedge clk);
    end
  endtask  // Automatic

  task automatic fetch(input logic [Xlen-1:0] addr, output logic [CpuW-1:0] data);
    i_cpu_valid = 1'b1;
    i_cpu_addr  = addr;
    wait_i();
    data = i_cpu_rdata;
    i_cpu_valid = 1'b0;
    i_done++;
    @(negedge clk);
  endtask  // Automatic

  task automatic load(input logic [Xlen-1:0] addr, output logic [CpuW-1:0] data);
    d_cpu_valid = 1'b1;
    d_cpu_rw    = 1'b0;
    d_cpu_addr  = addr;
    d_cpu_wstrb = '0;
    wait_d();
    data = d_cpu_rdata;
    d_cpu_valid = 1'b0;
    d_done++;
    @(negedge clk);
  endtask  // Automatic

  task automatic store(input logic [Xlen-1:0] addr, input logic [CpuBytes-1:0] strb,
                       input logic [CpuW-1:0] data);
    d_cpu_valid = 1'b1;
    d_cpu_rw    = 1'b1;
    d_cpu_addr  = addr;
    d_cpu_wdata = data;
    d_cpu_wstrb = strb;
    wait_d();
    d_cpu_valid = 1'b0;
    d_cpu_wstrb = '0;
    d_done++;
    @(negedge clk);
  endtask  // Automatic

  task automatic check_fetch(input string name, input logic [Xlen-1:0] addr,
                             input logic [CpuW-1:0] exp);
    fetch(addr, got);
    check(name, got, exp);
  endtask  // Automatic

  task automatic check_load(input string name, input logic [Xlen-1:0] addr,
                            input logic [CpuW-1:0] exp);
    load(addr, got);
    check(name, got, exp);
  endtask  // Automatic

  task automatic test_word_select();
    logic [Xlen-1:0] a;
    for (int i = 0; i < MemLines; i++) begin
      for (int w = 0; w < Chunks; w++) begin
        a = Xlen'(i * LineBytes + w * CpuBytes);
        check_fetch($sformatf("instruction fetch selected the wrong word at %h", a), a,
                    mem[i][w*CpuW+:CpuW]);
        check_load($sformatf("load selected the wrong word at %h", a), a, mem[i][w*CpuW+:CpuW]);
      end
    end
  endtask  // Automatic

  task automatic test_no_line_reuse();
    for (int i = 0; i < ReuseRounds; i++) begin
      check_fetch("repeat fetch did not see the new memory contents", '0, chunk_at('0));
      poke_word('0, CpuW'('hFACE_0000) + CpuW'(i));
      check_load("repeat load did not see the new memory contents", Xlen'(CpuBytes), chunk_at(
                 Xlen'(CpuBytes)));
      poke_word(Xlen'(CpuBytes), CpuW'('hCAFE_0000) + CpuW'(i));
    end
  endtask  // Automatic

  task automatic test_store_lanes();
    logic [Xlen-1:0] a;
    logic [Xlen-1:0] next;
    for (int w = 0; w < Chunks; w++) begin
      a = Xlen'('h100) + Xlen'(w * CpuBytes);
      next = Xlen'('h100) + Xlen'(((w + 1) % Chunks) * CpuBytes);
      store(a, '1, CpuW'('h2222_0000) + CpuW'(w));
      check_fetch($sformatf("store did not land in word %0d of the line", w), a,
                  CpuW'('h2222_0000) + CpuW'(w));
      check_fetch($sformatf("store from word %0d overwrote a neighbouring word", w), next, chunk_at(
                  next));
    end
  endtask  // Automatic

  task automatic test_byte_strobes();
    logic [CpuBytes-1:0] strobes[4];
    logic [CpuW-1:0] want;
    strobes = '{CpuBytes'('b0001), CpuBytes'('b1100), CpuBytes'('b0110), '1};
    for (int s = 0; s < $size(strobes); s++) begin
      store(Xlen'('h200), '1, {CpuBytes{8'h33}});
      want = {CpuBytes{8'h33}};
      for (int i = 0; i < CpuBytes; i++) begin
        if (strobes[s][i]) want[i*8+:8] = byte_ramp(i);
      end
      store(Xlen'('h200), strobes[s], word_ramp());
      check_load($sformatf("store ignored byte strobe %b", strobes[s]), Xlen'('h200), want);
    end
  endtask  // Automatic

  task automatic test_core_enable_sweep();
    int periods[5];
    logic [Xlen-1:0] a;
    logic [CpuW-1:0] d;
    periods = '{1, 2, 3, 5, 8};
    for (int p = 0; p < $size(periods); p++) begin
      set_core(periods[p], (p % 3) * 5);
      idle(1);
      for (int i = 0; i < 6; i++) begin
        a = Xlen'('h300) + Xlen'(i * CpuBytes);
        d = CpuW'('h4444_0000) + CpuW'(p * 16 + i);
        store(a, '1, d);
        check_fetch($sformatf("store did not reach memory, core_en 1 cycle in %0d", en_period), a,
                    d);
      end
    end
    set_core(1, MaxLat);
  endtask  // Automatic

  task automatic random_traffic(input int n);
    logic [Xlen-1:0] a;
    logic [CpuW-1:0] d;
    logic [CpuBytes-1:0] strb;
    repeat (n) begin
      a    = Xlen'($urandom_range(MemLines * Chunks - 1) * CpuBytes);
      d    = CpuW'({32'($urandom), 32'($urandom), 32'($urandom), 32'($urandom)});
      strb = CpuBytes'($urandom);
      if (1'($urandom)) begin
        if (strb != '0) store(a, strb, d);
        load(a, got);
        check("random load returned the wrong word", got, chunk_at(a));
      end else begin
        fetch(a, got);
        check("random fetch returned the wrong word", got, chunk_at(a));
      end
    end
  endtask  // Automatic

  task automatic check_counters();
    check("instruction side reported hits", CpuW'(i_hits), '0);
    check("data side reported hits", CpuW'(d_hits), '0);
    check("instruction side missed on a different number of accesses", CpuW'(i_misses),
          CpuW'(i_done));
    check("data side missed on a different number of accesses", CpuW'(d_misses), CpuW'(d_done));
  endtask  // Automatic

  task automatic watchdog(input int n);
    repeat (n) @(posedge clk);
    $fatal(1, "global time limit reached before the stimulus finished");
  endtask  // Automatic

  task automatic finish();
    @(negedge clk);
    done = 1'b1;
  endtask  // Automatic

  initial void'($value$plusargs("max_errors=%d", max_errors));

  initial watchdog(TimeoutCycles);

  initial begin
    init_memory();
    do_reset();

    test_word_select();
    test_no_line_reuse();
    test_store_lanes();
    test_byte_strobes();
    test_core_enable_sweep();
    random_traffic(RandomOps);
    check_counters();

    finish();
  end

  function automatic int line_of(input logic [Xlen-1:0] a);
    line_of = (int'(a) >> IdxLsb) % MemLines;
  endfunction

  function automatic int word_of(input logic [Xlen-1:0] a);
    word_of = (int'(a) >> CpuLsb) % Chunks;
  endfunction

  function automatic logic [CpuW-1:0] chunk_at(input logic [Xlen-1:0] a);
    return mem[line_of(a)][word_of(a)*CpuW+:CpuW];
  endfunction

  function automatic logic [7:0] byte_ramp(input int b);
    return 8'('h70 + b);
  endfunction

  function automatic logic [CpuW-1:0] word_ramp();
    for (int b = 0; b < CpuBytes; b++) word_ramp[b*8+:8] = byte_ramp(b);
  endfunction

  always @(posedge clk) begin
    if (!rst_n) begin
      i_busy <= 1'b0;
      i_pend <= 1'b0;
      i_ctr  <= 0;
    end else begin
      if (!i_busy && !i_pend && i_mem_valid) begin
        i_busy <= 1'b1;
        i_ctr  <= $urandom_range(max_lat);
      end else if (i_busy) begin
        if (i_ctr == 0) begin
          i_busy <= 1'b0;
          i_pend <= 1'b1;
          i_hold <= mem[line_of(i_mem_addr)];
        end else begin
          i_ctr <= i_ctr - 1;
        end
      end
      if (i_pend && core_en) i_pend <= 1'b0;
    end
  end

  assign i_mem_ready = i_pend && core_en;
  assign i_mem_rdata = i_hold;

  always @(posedge clk) begin
    if (!rst_n) begin
      d_busy <= 1'b0;
      d_pend <= 1'b0;
      d_ctr  <= 0;
    end else begin
      if (!d_busy && !d_pend && d_mem_valid) begin
        d_busy <= 1'b1;
        d_ctr  <= $urandom_range(max_lat);
      end else if (d_busy) begin
        if (d_ctr == 0) begin
          d_busy <= 1'b0;
          d_pend <= 1'b1;
          if (d_mem_rw) begin
            for (int b = 0; b < LineBytes; b++) begin
              if (d_mem_wstrb[b]) mem[line_of(d_mem_addr)][b*8+:8] <= d_mem_wdata[b*8+:8];
            end
            d_hold <= '0;
          end else begin
            d_hold <= mem[line_of(d_mem_addr)];
          end
        end else begin
          d_ctr <= d_ctr - 1;
        end
      end
      if (d_pend && core_en) d_pend <= 1'b0;
    end
  end

  assign d_mem_ready = d_pend && core_en;
  assign d_mem_rdata = d_hold;

  // Core enable
  always @(posedge clk) begin
    if (!rst_n) en_ctr <= 0;
    else en_ctr <= (en_ctr + 1) % en_period;
  end

  assign core_en = (en_ctr == 0);

  // Protocol checks
  always @(posedge clk) begin
    if (rst_n) begin
      check("read only instance drove a write command at memory", CpuW'(i_mem_rw), '0);
      check("read only instance drove a nonzero byte strobe", CpuW'(i_mem_wstrb != '0), '0);
      check("instruction side asserted ready while core_en was low", CpuW'(i_cpu_ready && !core_en),
            '0);
      check("data side asserted ready while core_en was low", CpuW'(d_cpu_ready && !core_en), '0);
      check("instruction side answered without a memory response",
            CpuW'(i_cpu_ready && !i_mem_ready), '0);
      check("data side answered without a memory response", CpuW'(d_cpu_ready && !d_mem_ready), '0);
    end
  end

endmodule

`default_nettype wire
