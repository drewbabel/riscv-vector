`default_nettype none

module dcache_tb;

  import cache_pkg::*;

  localparam int MinChecks = 71;
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

  logic [Xlen-1:0] boot_addr;
  logic [Xlen-1:0] boot_wdata;
  logic boot_we;

  logic [31:0] hit_count;
  logic [31:0] miss_count;

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
      .req_valid(mem_valid),
      .req_rw(mem_rw),
      .req_addr(mem_addr),
      .req_wdata(mem_wdata),
      .resp_rdata(mem_rdata),
      .resp_ready(mem_ready),
      .boot_we(boot_we),
      .boot_addr(boot_addr),
      .boot_wdata(boot_wdata)
  );

  // Addressed word
  assign rword = cpu_rdata[cpu_addr[WordLsb+:BlkOffLen]*Xlen+:Xlen];

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
    word = int'(addr[WordLsb+:BlkOffLen]);
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
    write_word(addr_of(0, 0) + Xlen'(WordBytes), Poison);
    check_word("store hit", addr_of(0, 0) + Xlen'(WordBytes), Poison);
    fill_set(0, 1, DcWays - 1);
  endtask  // Automatic

  task automatic test_every_way_kept();
    mark();
    check_word("dirty way kept", addr_of(0, 0) + Xlen'(WordBytes), Poison);
    fill_set(0, 1, DcWays - 1);
    expect_traffic("every way kept", 0, 0, 0);
  endtask  // Automatic

  task automatic test_dirty_evict();
    mark();
    read_word("extra tag", 0, DcWays, 0);
    expect_traffic("dirty evict", 1, 1, 1);
    check_word("write back landed", addr_of(0, 0) + Xlen'(WordBytes), Poison);
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

    do_verdict();
  end

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

  // Count memory traffic
  always @(posedge clk) begin
    if (rst_n && mem_valid && mem_ready && mem_rw) writebacks++;
    if (rst_n && mem_valid && mem_ready && !mem_rw) reads++;
  end

endmodule

`default_nettype wire
