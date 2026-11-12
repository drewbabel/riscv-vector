`default_nettype none

module dcache_tb;

  import cache_pkg::*;

  localparam int SoakOps = 2000;
  localparam int CountOps = (1 << 14) + (1 << 10);
  localparam int MinChecks = 43 + 6 * DcWays + LineWords + 2 * (SoakOps + CountOps);
  localparam int PoisonWord = (LineWords > 1) ? 1 : 0;
  localparam int Xlen = arch_pkg::XLEN;
  localparam int Depth = 8192;
  localparam int Latency = 4;
  localparam int Guard = 200;
  localparam int SetStride = 1 << (IdxLsb + DcIdxLen);
  localparam int Sets = 7;
  localparam int Tags = DcWays + 2;
  localparam int TagSeedLsb = Xlen - 4;
  localparam int SetSeedLsb = Xlen - 12;
  localparam logic [Xlen-1:0] Poison = Xlen'('hDEAD_BEEF);
  localparam logic [Xlen-1:0] PatternSeed = Xlen'('h6000_0000);
  localparam logic [LineBytes-1:0] EndStrb = LineBytes'(1) | (LineBytes'(1) << (LineBytes - 1));
  localparam logic [LineBytes-1:0] GapStrb = ~LineBytes'(1);
  localparam int PlruW = DcWays - 1;
  localparam int TagPool = 6;
  localparam int SoakGuard = 1000;
  localparam int RstOdds = 3000;

  int checks = 0;
  int errors = 0;
  int max_errors = 0;
  int writebacks = 0;
  int reads = 0;
  int wb_mark = 0;
  int rd_mark = 0;
  int miss_mark = 0;

  logic clk = 1'b0;
  logic core_en;
  logic rst_n = 1'b1;

  logic cpu_valid;
  logic cpu_rw;
  logic [Xlen-1:0] cpu_addr;
  logic [LineBits-1:0] cpu_wdata;
  logic [LineBytes-1:0] cpu_wstrb;
  logic [LineBits-1:0] cpu_rdata;
  logic cpu_ready;
  logic [Xlen-1:0] rword;

  logic mem_valid;
  logic mem_rw;
  logic [Xlen-1:0] mem_addr;
  logic [LineBits-1:0] mem_wdata;
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

  logic [31:0] hit_count;
  logic [31:0] miss_count;

  // Soak model
  logic [DcTagLen-1:0] pool[TagPool];
  logic [LineBits-1:0] img[TagPool][DcSets];
  logic m_valid[DcSets][DcWays];
  logic m_dirty[DcSets][DcWays];
  logic [DcTagLen-1:0] m_tag[DcSets][DcWays];
  logic [LineBits-1:0] m_line[DcSets][DcWays];
  logic [PlruW-1:0] m_plru[DcSets];
  logic [31:0] m_hits = '0;
  logic [31:0] m_misses = '0;
  logic busy = 1'b0;
  logic p_hit;
  int p_set;
  int p_way;
  logic [DcTagLen-1:0] p_tag;
  logic [LineBits-1:0] p_rdata;
  logic [LineBits-1:0] p_line;
  logic q_rw[$];
  logic [Xlen-1:0] q_addr[$];
  logic [LineBits-1:0] q_wdata[$];
  int soak_wait = 0;
  int rst_left = 0;

  always #5 clk = ~clk;

  dcache #(
      .XLEN(Xlen)
  ) dut (
      .clk(clk),
      .core_en(core_en),
      .rst_n(rst_n),
      .cpu_valid(cpu_valid),
      .cpu_rw(cpu_rw),
      .cpu_addr(cpu_addr),
      .cpu_wdata(cpu_wdata),
      .cpu_wstrb(cpu_wstrb),
      .cpu_rdata(cpu_rdata),
      .cpu_ready(cpu_ready),
      .mem_valid(mem_valid),
      .mem_rw(mem_rw),
      .mem_addr(mem_addr),
      .mem_wdata(mem_wdata),
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
      .req_rw(mem_rw),
      .req_addr(mem_addr),
      .req_wdata(mem_wdata),
      .resp_rdata(dly_rdata),
      .resp_ready(dly_ready),
      .boot_we(boot_we),
      .boot_addr(boot_addr),
      .boot_wdata(boot_wdata)
  );

  assign mem_ready = soak_on ? soak_ready : dly_ready;
  assign mem_rdata = soak_on ? soak_rdata : dly_rdata;

  // Addressed word
  assign rword = cpu_rdata[word_of(cpu_addr)*Xlen+:Xlen];

  task automatic check(input string name, input logic [LineBits-1:0] got,
                       input logic [LineBits-1:0] exp);
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
    cpu_rw     = 1'b0;
    cpu_addr   = '0;
    cpu_wdata  = '0;
    cpu_wstrb  = '0;
    boot_we    = 1'b0;
    boot_addr  = '0;
    boot_wdata = '0;
    repeat (2) @(posedge clk);
    @(negedge clk);
    rst_n = 1'b1;
    // Wait reset walk
    repeat (DcSets + 2) @(posedge clk);
    @(negedge clk);
  endtask  // Automatic

  task automatic mark();
    wb_mark   = writebacks;
    rd_mark   = reads;
    miss_mark = int'(miss_count);
  endtask  // Automatic

  task automatic expect_traffic(input string name, input int wb, input int rd, input int miss);
    check({name, " write backs"}, LineBits'(writebacks - wb_mark), LineBits'(wb));
    check({name, " reads"}, LineBits'(reads - rd_mark), LineBits'(rd));
    check({name, " misses"}, LineBits'(int'(miss_count) - miss_mark), LineBits'(miss));
  endtask  // Automatic

  task automatic boot_word(input logic [Xlen-1:0] addr, input logic [Xlen-1:0] data);
    boot_we    = 1'b1;
    boot_addr  = addr;
    boot_wdata = data;
    @(negedge clk);
    boot_we = 1'b0;
    @(negedge clk);
  endtask  // Automatic

  task automatic boot_all();
    for (int s = 0; s < Sets; s++) begin
      for (int t = 0; t < Tags; t++) begin
        for (int w = 0; w < LineWords; w++) begin
          boot_word(addr_of(s, t) + Xlen'(w * WordBytes), seed_of(s, t) + Xlen'(w));
        end
      end
    end
  endtask  // Automatic

  task automatic cpu_access(input logic rw, input logic [Xlen-1:0] addr,
                            input logic [LineBytes-1:0] strb, input logic [LineBits-1:0] data);
    int guard;
    cpu_valid = 1'b1;
    cpu_rw    = rw;
    cpu_addr  = addr;
    cpu_wstrb = strb;
    cpu_wdata = data;
    guard     = 0;
    @(posedge clk);
    while (!cpu_ready) begin
      guard++;
      if (guard > Guard) $fatal(1, "cpu_ready never arrived for %h", addr);
      @(posedge clk);
    end
    @(negedge clk);
    cpu_valid = 1'b0;
    cpu_wstrb = '0;
    @(negedge clk);
  endtask  // Automatic

  task automatic read(input logic [Xlen-1:0] addr);
    cpu_access(1'b0, addr, '0, '0);
  endtask  // Automatic

  task automatic write_word(input logic [Xlen-1:0] addr, input logic [Xlen-1:0] data);
    int word;
    word = word_of(addr);
    cpu_access(1'b1, addr, LineBytes'({WordBytes{1'b1}}) << (WordBytes * word),
               LineBits'(data) << (Xlen * word));
  endtask  // Automatic

  task automatic write_line(input logic [Xlen-1:0] addr, input logic [LineBytes-1:0] strb,
                            input logic [LineBits-1:0] data);
    cpu_access(1'b1, addr, strb, data);
  endtask  // Automatic

  task automatic check_word(input string name, input logic [Xlen-1:0] addr,
                            input logic [Xlen-1:0] exp);
    read(addr);
    check(name, LineBits'(rword), LineBits'(exp));
  endtask  // Automatic

  task automatic read_word(input string name, input int set, input int tag, input int w);
    check_word(name, addr_of(set, tag) + Xlen'(w * WordBytes), seed_of(set, tag) + Xlen'(w));
  endtask  // Automatic

  task automatic read_line(input string name, input int set, input int tag,
                           input logic [LineBits-1:0] exp);
    read(addr_of(set, tag));
    check(name, cpu_rdata, exp);
  endtask  // Automatic

  task automatic fill_set(input int set, input int first, input int count);
    for (int t = first; t < first + count; t++) read_word("fill", set, t, 0);
  endtask  // Automatic

  task automatic rest_of_line(input int set, input int tag);
    for (int w = 1; w < LineWords; w++) read_word("rest of line", set, tag, w);
  endtask  // Automatic

  task automatic dirty_set(input int set, input int count);
    for (int t = 0; t < count; t++) write_word(addr_of(set, t), ~seed_of(set, t));
  endtask  // Automatic

  task automatic test_cold_miss();
    mark();
    read_word("cold miss", 0, 0, 0);
    expect_traffic("cold miss", 0, 1, 1);
  endtask  // Automatic

  task automatic test_rest_of_line();
    rest_of_line(0, 0);
    check("hits after line", LineBits'(hit_count), LineBits'(LineWords - 1));
    check("miss still one", LineBits'(miss_count), LineBits'(1));
  endtask  // Automatic

  task automatic test_store_hit();
    write_word(addr_of(0, 0) + Xlen'(PoisonWord * WordBytes), Poison);
    check_word("store hit", addr_of(0, 0) + Xlen'(PoisonWord * WordBytes), Poison);
    fill_set(0, 1, DcWays - 1);
  endtask  // Automatic

  task automatic test_every_way_kept();
    mark();
    check_word("dirty way kept", addr_of(0, 0) + Xlen'(PoisonWord * WordBytes), Poison);
    fill_set(0, 1, DcWays - 1);
    expect_traffic("every way kept", 0, 0, 0);
  endtask  // Automatic

  task automatic test_dirty_evict();
    mark();
    read_word("extra tag", 0, DcWays, 0);
    expect_traffic("dirty evict", 1, 1, 1);
    check_word("write back landed", addr_of(0, 0) + Xlen'(PoisonWord * WordBytes), Poison);
  endtask  // Automatic

  task automatic test_clean_evict();
    do_reset();
    mark();
    fill_set(1, 0, DcWays + 1);
    expect_traffic("clean evict", 0, DcWays + 1, DcWays + 1);
  endtask  // Automatic

  task automatic test_line_stores();
    read_line("whole line", 2, 0, line_of(seed_of(2, 0)));
    write_line(addr_of(2, 0), '1, pattern());
    read_line("line store", 2, 0, pattern());
    write_line(addr_of(2, 0), EndStrb, ~pattern());
    read_line("end bytes", 2, 0, merge(pattern(), EndStrb, ~pattern()));
  endtask  // Automatic

  task automatic test_clean_install();
    mark();
    write_line(addr_of(3, 0), '1, pattern());
    expect_traffic("clean install", 0, 0, 1);
    read_line("clean install", 3, 0, pattern());
    mark();
    fill_set(3, 1, DcWays);
    expect_traffic("install evicted", 1, DcWays, DcWays);
    read_line("install landed", 3, 0, pattern());
  endtask  // Automatic

  task automatic test_dirty_install();
    fill_set(4, 0, DcWays);
    dirty_set(4, DcWays);
    mark();
    write_line(addr_of(4, DcWays), '1, pattern());
    expect_traffic("dirty install", 1, 0, 1);
    read_line("dirty install", 4, DcWays, pattern());
    check_word("victim landed", addr_of(4, 0), ~seed_of(4, 0));
  endtask  // Automatic

  task automatic test_partial_miss();
    mark();
    write_line(addr_of(5, 0), GapStrb, pattern());
    expect_traffic("partial miss", 0, 1, 1);
    read_line("partial miss", 5, 0, merge(line_of(seed_of(5, 0)), GapStrb, pattern()));
  endtask  // Automatic

  task automatic test_install_recent();
    fill_set(6, 0, DcWays);
    read_word("victim off way 0", 6, 0, 0);
    write_line(addr_of(6, DcWays), '1, pattern());
    read_word("next miss", 6, DcWays + 1, 0);
    mark();
    read_line("install kept", 6, DcWays, pattern());
    expect_traffic("install kept", 0, 0, 0);
  endtask  // Automatic

  task automatic soak_init();
    for (int t = 0; t < TagPool; t++) begin
      pool[t] = DcTagLen'($urandom);
      for (int u = 0; u < t; u++) if (pool[u] == pool[t]) t--;
    end
    for (int t = 0; t < TagPool; t++) for (int s = 0; s < DcSets; s++) img[t][s] = rand_line();
    do_reset();
    model_reset();
    soak_on = 1'b1;
  endtask  // Automatic

  task automatic model_reset();
    for (int s = 0; s < DcSets; s++) begin
      m_plru[s] = '0;
      for (int w = 0; w < DcWays; w++) begin
        m_valid[s][w] = 1'b0;
        m_dirty[s][w] = 1'b0;
      end
    end
    m_hits   = 0;
    m_misses = 0;
    busy     = 1'b0;
    q_rw.delete();
    q_addr.delete();
    q_wdata.delete();
  endtask  // Automatic

  task automatic soak_issue(input logic sweep, input int n);
    int t;
    int victim;
    logic [LineBits-1:0] base;
    p_set = sweep ? n % DcSets : int'($urandom_range(DcSets - 1));
    t = sweep ? (n / DcSets) % TagPool : int'($urandom_range(TagPool - 1));
    p_tag = pool[t];
    cpu_valid = 1'b1;
    cpu_rw = sweep ? 1'b0 : 1'($urandom);
    cpu_addr = line_addr(p_tag, p_set) | Xlen'($urandom_range(LineBytes - 1));
    cpu_wdata = rand_line();
    case ($urandom_range(
        3
    ))
      0: cpu_wstrb = '1;
      1: cpu_wstrb = LineBytes'({WordBytes{1'b1}}) << (WordBytes * $urandom_range(LineWords - 1));
      default: cpu_wstrb = LineBytes'($urandom);
    endcase
    p_hit = 1'b0;
    for (int w = 0; w < DcWays; w++) begin
      if (m_valid[p_set][w] && (m_tag[p_set][w] == p_tag)) begin
        p_hit = 1'b1;
        p_way = w;
      end
    end
    if (p_hit) begin
      base = m_line[p_set][p_way];
    end else begin
      victim = plru_victim(m_plru[p_set]);
      for (int w = DcWays - 1; w >= 0; w--) if (!m_valid[p_set][w]) victim = w;
      p_way = victim;
      if (m_valid[p_set][victim] && m_dirty[p_set][victim]) begin
        q_rw.push_back(1'b1);
        q_addr.push_back(line_addr(m_tag[p_set][victim], p_set));
        q_wdata.push_back(m_line[p_set][victim]);
      end
      if (cpu_rw && (&cpu_wstrb)) begin
        base = '0;
      end else begin
        q_rw.push_back(1'b0);
        q_addr.push_back(line_addr(p_tag, p_set));
        q_wdata.push_back('0);
        base = img[t][p_set];
      end
    end
    p_rdata = base;
    p_line  = cpu_rw ? merge(base, cpu_wstrb, cpu_wdata) : base;
    busy    = 1'b1;
  endtask  // Automatic

  task automatic soak_commit();
    if (!cpu_rw) check("soak rdata", cpu_rdata, p_rdata);
    check("soak mem drained", LineBits'(q_rw.size()), '0);
    m_valid[p_set][p_way] = 1'b1;
    m_dirty[p_set][p_way] = cpu_rw || (p_hit && m_dirty[p_set][p_way]);
    m_tag[p_set][p_way]   = p_tag;
    m_line[p_set][p_way]  = p_line;
    m_plru[p_set]         = plru_touch(m_plru[p_set], p_way);
    if (p_hit) m_hits++;
    else m_misses++;
    busy = 1'b0;
  endtask  // Automatic

  task automatic soak_mem();
    int t;
    if (q_rw.size() == 0) check("soak spurious mem", LineBits'(mem_valid), '0);
    if (!mem_valid || (q_rw.size() == 0)) return;
    check("soak mem rw", LineBits'(mem_rw), LineBits'(q_rw[0]));
    check("soak mem addr", LineBits'(mem_addr), LineBits'(q_addr[0]));
    if (q_rw[0]) check("soak mem wdata", mem_wdata, q_wdata[0]);
    if (!core_en) return;
    if (soak_ready) begin
      t = pool_slot(mem_addr);
      if (mem_rw && (t >= 0)) img[t][mem_addr[IdxLsb+:DcIdxLen]] = mem_wdata;
      void'(q_rw.pop_front());
      void'(q_addr.pop_front());
      void'(q_wdata.pop_front());
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
        check("soak hits", LineBits'(hit_count), LineBits'(m_hits));
        check("soak misses", LineBits'(miss_count), LineBits'(m_misses));
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
      soak_rdata = (soak_ready && (t >= 0)) ? img[t][mem_addr[IdxLsb+:DcIdxLen]] : rand_line();
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
    soak(DcSets, 1'b1);
    rst_left = 2;
    soak(DcSets, 1'b1);
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
    $dumpfile("dcache_tb.vcd");
    $dumpvars(0, dcache_tb);
    do_reset();
    boot_all();

    test_cold_miss();
    test_rest_of_line();
    test_store_hit();
    test_every_way_kept();
    test_dirty_evict();
    test_clean_evict();
    test_line_stores();
    test_clean_install();
    test_dirty_install();
    test_partial_miss();
    test_install_recent();
    test_soak();

    do_verdict();
  end

  function automatic int word_of(input logic [Xlen-1:0] addr);
    return int'((addr >> WordLsb) % LineWords);
  endfunction

  function automatic logic [Xlen-1:0] addr_of(input int set, input int tag);
    return Xlen'(tag * SetStride + set * LineBytes);
  endfunction

  function automatic logic [Xlen-1:0] seed_of(input int set, input int tag);
    return (Xlen'(tag + 1) << TagSeedLsb) | (Xlen'(set) << SetSeedLsb);
  endfunction

  function automatic logic [LineBits-1:0] line_of(input logic [Xlen-1:0] seed);
    for (int w = 0; w < LineWords; w++) line_of[w*Xlen+:Xlen] = seed + Xlen'(w);
  endfunction

  function automatic logic [LineBits-1:0] pattern();
    return line_of(PatternSeed);
  endfunction

  function automatic logic [LineBits-1:0] merge(input logic [LineBits-1:0] line,
                                                input logic [LineBytes-1:0] strb,
                                                input logic [LineBits-1:0] data);
    merge = line;
    for (int b = 0; b < LineBytes; b++) if (strb[b]) merge[b*8+:8] = data[b*8+:8];
  endfunction

  function automatic logic [Xlen-1:0] line_addr(input logic [DcTagLen-1:0] tag, input int set);
    return {tag, DcIdxLen'(set), IdxLsb'(0)};
  endfunction

  function automatic int pool_slot(input logic [Xlen-1:0] addr);
    pool_slot = -1;
    for (int t = 0; t < TagPool; t++) if (pool[t] == addr[Xlen-1-:DcTagLen]) pool_slot = t;
  endfunction

  function automatic logic [LineBits-1:0] rand_line();
    for (int w = 0; w < LineWords; w++) rand_line[w*Xlen+:Xlen] = Xlen'($urandom);
  endfunction

  function automatic int plru_victim(input logic [PlruW-1:0] tree);
    int node;
    node = 0;
    plru_victim = 0;
    for (int lvl = DcWaySel - 1; lvl >= 0; lvl--) begin
      plru_victim |= int'(tree[node]) << lvl;
      node = 2 * node + 1 + int'(tree[node]);
    end
  endfunction

  function automatic logic [PlruW-1:0] plru_touch(input logic [PlruW-1:0] tree, input int way);
    int node;
    int b;
    node = 0;
    plru_touch = tree;
    for (int lvl = DcWaySel - 1; lvl >= 0; lvl--) begin
      b = (way >> lvl) & 1;
      plru_touch[node] = (b == 0);
      node = 2 * node + 1 + b;
    end
  endfunction

  // Count memory traffic
  always @(posedge clk) begin
    if (rst_n && mem_valid && mem_ready && mem_rw) writebacks++;
    if (rst_n && mem_valid && mem_ready && !mem_rw) reads++;
  end

endmodule

`default_nettype wire
