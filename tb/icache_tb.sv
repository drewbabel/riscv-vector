`default_nettype none

module icache_tb;

  import cache_pkg::*;

  localparam int SoakOps = 2000;
  localparam int CountOps = (1 << 16) + (1 << 10);
  localparam int MinChecks = 10 + LineWords + 2 * (SoakOps + CountOps);
  localparam int TagPool = 6;
  localparam int SoakGuard = 1000 + 2 * IcSets;
  localparam int RstOdds = 3000;
  localparam int Xlen = arch_pkg::XLEN;
  localparam int Depth = 8192;
  localparam int Latency = 4;
  localparam int Stride = 1 << (IdxLsb + IcIdxLen);
  localparam int MaxWait = 200;
  localparam logic [Xlen-1:0] SeedA = Xlen'('hA000_0000);
  localparam logic [Xlen-1:0] SeedB = Xlen'('hB000_0000);
  localparam logic [Xlen-1:0] SeedC = Xlen'('hC000_0000);

  int checks = 0;
  int errors = 0;
  int max_errors = 0;

  logic clk = 1'b0;
  logic core_en;
  logic rst_n = 1'b1;

  logic cpu_valid;
  logic [Xlen-1:0] cpu_addr;
  logic [Xlen-1:0] cpu_rdata;
  logic cpu_ready;

  logic mem_valid;
  logic [Xlen-1:0] mem_addr;
  logic [LineBits-1:0] mem_rdata;
  logic mem_ready;
  logic [LineBits-1:0] dly_rdata;
  logic dly_ready;
  logic soak_on = 1'b0;
  logic soak_ready = 1'b0;
  logic [LineBits-1:0] soak_rdata = '0;

  logic [Xlen-1:0] boot_addr;
  logic [Xlen-1:0] boot_wdata;
  logic boot_we;

  logic [Xlen-1:0] hit_count;
  logic [Xlen-1:0] miss_count;

  // Soak model
  logic [IcTagLen-1:0] pool[TagPool];
  logic [LineBits-1:0] img[TagPool][IcSets];
  logic m_valid[IcSets];
  logic [IcTagLen-1:0] m_tag[IcSets];
  logic [Xlen-1:0] m_hits = '0;
  logic [Xlen-1:0] m_misses = '0;
  logic busy = 1'b0;
  logic p_hit;
  int p_set;
  logic [IcTagLen-1:0] p_tag;
  logic [Xlen-1:0] p_rdata;
  int q_left = 0;
  int soak_wait = 0;
  int rst_left = 0;

  always #5 clk = ~clk;

  icache #(
      .XLEN(Xlen)
  ) dut (
      .clk(clk),
      .core_en(core_en),
      .rst_n(rst_n),
      .cpu_valid(cpu_valid),
      .cpu_addr(cpu_addr),
      .cpu_rdata(cpu_rdata),
      .cpu_ready(cpu_ready),
      .mem_valid(mem_valid),
      .mem_addr(mem_addr),
      .mem_rdata(mem_rdata),
      .mem_ready(mem_ready),
      .hit_count(hit_count),
      .miss_count(miss_count)
  );

  mem_delay #(
      .XLEN(Xlen),
      .DEPTH(Depth),
      .Latency(Latency)
  ) memory (
      .clk(clk),
      .core_en(core_en),
      .rst_n(rst_n),
      .req_valid(mem_valid && !soak_on),
      .req_rw(1'b0),
      .req_addr(mem_addr),
      .req_wdata('0),
      .resp_rdata(dly_rdata),
      .resp_ready(dly_ready),
      .boot_we(boot_we),
      .boot_addr(boot_addr),
      .boot_wdata(boot_wdata)
  );

  assign mem_ready = soak_on ? soak_ready : dly_ready;
  assign mem_rdata = soak_on ? soak_rdata : dly_rdata;

  task automatic check(input string name, input logic [Xlen-1:0] got, input logic [Xlen-1:0] exp);
    checks++;
    if (got !== exp) begin
      errors++;
      $display("FAIL %s: got %h, expected %h", name, got, exp);
      if (errors == max_errors) $fatal(1, "TB STOPPED: %0d mismatches", errors);
    end
  endtask  // Automatic

  task automatic do_reset();
    @(negedge clk);
    rst_n      = 1'b0;
    core_en    = 1'b1;
    cpu_valid  = 1'b0;
    cpu_addr   = '0;
    boot_we    = 1'b0;
    boot_addr  = '0;
    boot_wdata = '0;
    repeat (2) @(posedge clk);
    @(negedge clk);
    rst_n = 1'b1;
    // Wait reset walk
    repeat (IcSets + 2) @(posedge clk);
    @(negedge clk);
  endtask  // Automatic

  task automatic boot_word(input logic [Xlen-1:0] addr, input logic [Xlen-1:0] data);
    boot_we    = 1'b1;
    boot_addr  = addr;
    boot_wdata = data;
    @(negedge clk);
    boot_we = 1'b0;
    @(negedge clk);
  endtask  // Automatic

  task automatic boot_line(input logic [Xlen-1:0] base, input logic [Xlen-1:0] seed);
    for (int w = 0; w < LineWords; w++) boot_word(base + Xlen'(w * WordBytes), seed + Xlen'(w));
  endtask  // Automatic

  task automatic fetch(input logic [Xlen-1:0] addr);
    int guard;
    cpu_valid = 1'b1;
    cpu_addr  = addr;
    guard     = 0;
    @(posedge clk);
    while (!cpu_ready) begin
      guard++;
      if (guard > MaxWait) $fatal(1, "cpu_ready never arrived for %h", addr);
      @(posedge clk);
    end
    @(negedge clk);
    cpu_valid = 1'b0;
    @(negedge clk);
  endtask  // Automatic

  task automatic check_fetch(input string name, input logic [Xlen-1:0] addr,
                             input logic [Xlen-1:0] exp);
    fetch(addr);
    check(name, cpu_rdata, exp);
  endtask  // Automatic

  task automatic check_counts(input string name, input int hits, input int misses);
    check({name, " hits"}, Xlen'(hit_count), Xlen'(hits));
    check({name, " misses"}, Xlen'(miss_count), Xlen'(misses));
  endtask  // Automatic

  task automatic load_lines();
    boot_line('0, SeedA);
    boot_line(Xlen'(Stride), SeedB);
    boot_line(Xlen'(LineBytes), SeedC);
  endtask  // Automatic

  task automatic test_cold_miss();
    check_fetch("cold miss data", '0, SeedA);
    check_counts("cold", 0, 1);
  endtask  // Automatic

  task automatic test_neighbours();
    for (int w = 1; w < LineWords; w++)
      check_fetch($sformatf("neighbour %0d", w), Xlen'(w * WordBytes), SeedA + Xlen'(w));
    check_counts("neighbours", LineWords - 1, 1);
  endtask  // Automatic

  task automatic test_other_index();
    check_fetch("second index", Xlen'(LineBytes), SeedC);
    check_fetch("first index kept", '0, SeedA);
    check("two misses", Xlen'(miss_count), Xlen'(2));
  endtask  // Automatic

  task automatic test_conflict();
    check_fetch("conflicting tag", Xlen'(Stride), SeedB);
    check_fetch("conflict evicted", '0, SeedA);
    check("conflict misses", Xlen'(miss_count), Xlen'(4));
  endtask  // Automatic

  task automatic soak_init();
    for (int t = 0; t < TagPool; t++) begin
      pool[t] = IcTagLen'($urandom);
      for (int u = 0; u < t; u++) if (pool[u] == pool[t]) t--;
    end
    for (int t = 0; t < TagPool; t++) for (int s = 0; s < IcSets; s++) img[t][s] = rand_line();
    do_reset();
    model_reset();
    soak_on = 1'b1;
  endtask  // Automatic

  task automatic model_reset();
    for (int s = 0; s < IcSets; s++) m_valid[s] = 1'b0;
    m_hits   = '0;
    m_misses = '0;
    busy     = 1'b0;
    q_left   = 0;
  endtask  // Automatic

  task automatic soak_issue(input logic sweep, input int n);
    int t;
    logic [Xlen-1:0] low;
    p_set = sweep ? n % IcSets : int'($urandom_range(IcSets - 1));
    t = sweep ? (n / IcSets) % TagPool : int'($urandom_range(TagPool - 1));
    p_tag = pool[t];
    low = Xlen'($urandom_range(LineBytes - 1));
    cpu_valid = 1'b1;
    cpu_addr = line_addr(p_tag, p_set) | low;
    p_hit = m_valid[p_set] && (m_tag[p_set] == p_tag);
    q_left = p_hit ? 0 : 1;
    p_rdata = img[t][p_set][(low>>WordLsb)*Xlen+:Xlen];
    busy = 1'b1;
  endtask  // Automatic

  task automatic soak_commit();
    check("soak rdata", cpu_rdata, p_rdata);
    check("soak mem drained", Xlen'(q_left), '0);
    m_valid[p_set] = 1'b1;
    m_tag[p_set]   = p_tag;
    if (p_hit) m_hits++;
    else m_misses++;
    busy = 1'b0;
  endtask  // Automatic

  task automatic soak_mem();
    if (q_left == 0) check("soak spurious mem", Xlen'(mem_valid), '0);
    if (!mem_valid || (q_left == 0)) return;
    check("soak mem addr", mem_addr, line_addr(p_tag, p_set));
    if (!core_en) return;
    if (soak_ready) begin
      q_left--;
      soak_wait = int'($urandom_range(3));
    end else begin
      soak_wait--;
    end
  endtask  // Automatic

  task automatic soak(input int n, input logic sweep);
    int done;
    int age;
    int t;
    done = 0;
    age  = 0;
    while (done < n) begin
      @(negedge clk);
      if (!busy) begin
        check("soak hits", hit_count, m_hits);
        check("soak misses", miss_count, m_misses);
      end
      if ((rst_left == 0) && !sweep && ($urandom_range(RstOdds - 1) == 0))
        rst_left = 1 + int'($urandom_range(2));
      core_en = $urandom_range(4) != 0;
      if (rst_left > 0) begin
        rst_left--;
        rst_n = 1'b0;
        model_reset();
        soak_wait = 0;
        age = 0;
      end else begin
        rst_n = 1'b1;
      end
      if (!busy && rst_n && ($urandom_range(3) != 0)) begin
        soak_issue(sweep, done);
      end else if (!busy) begin
        cpu_valid = 1'b0;
        cpu_addr  = Xlen'($urandom);
      end
      soak_ready = mem_valid && (soak_wait == 0);
      t = pool_slot(mem_addr);
      soak_rdata = (soak_ready && (t >= 0)) ? img[t][mem_addr[IdxLsb+:IcIdxLen]] : rand_line();
      #1;
      if (rst_n) begin
        soak_mem();
        if (core_en && cpu_valid && cpu_ready) begin
          soak_commit();
          done++;
          age = 0;
        end else if (busy) begin
          age++;
          if (age > SoakGuard) $fatal(1, "soak stuck at %h", cpu_addr);
        end
      end
    end
  endtask  // Automatic

  task automatic test_soak();
    soak_init();
    soak(SoakOps, 1'b0);
    soak(IcSets, 1'b1);
    rst_left = 2;
    soak(IcSets, 1'b1);
    soak(CountOps, 1'b1);
    soak(SoakOps / 10, 1'b0);
    @(negedge clk);
    cpu_valid = 1'b0;
    core_en   = 1'b1;
    rst_n     = 1'b1;
    soak_on   = 1'b0;
  endtask  // Automatic

  task automatic do_verdict();
    if (checks < MinChecks)
      $fatal(1, "TB UNDER-RAN: %0d checks, expected at least %0d", checks, MinChecks);
    if (errors == 0) $display("PASS: %0d checks, %0d mismatches", checks, errors);
    else $fatal(1, "FAIL: %0d mismatches, %0d checks", errors, checks);
    $finish;
  endtask  // Automatic

  initial void'($value$plusargs("max_errors=%d", max_errors));

  initial begin
    $dumpfile("icache_tb.vcd");
    $dumpvars(0, icache_tb);
    do_reset();

    load_lines();
    test_cold_miss();
    test_neighbours();
    test_other_index();
    test_conflict();
    test_soak();

    do_verdict();
  end

  function automatic logic [Xlen-1:0] line_addr(input logic [IcTagLen-1:0] tag, input int set);
    return {tag, IcIdxLen'(set), IdxLsb'(0)};
  endfunction

  function automatic int pool_slot(input logic [Xlen-1:0] addr);
    pool_slot = -1;
    for (int t = 0; t < TagPool; t++) if (pool[t] == addr[Xlen-1-:IcTagLen]) pool_slot = t;
  endfunction

  function automatic logic [LineBits-1:0] rand_line();
    for (int w = 0; w < LineWords; w++) rand_line[w*Xlen+:Xlen] = Xlen'($urandom);
  endfunction

endmodule

`default_nettype wire
