`default_nettype none

module mem_arb_tb ();

  localparam int MinChecks = 15500;

  int checks;
  int errors;
  int max_errors;
  int live_errors;

  mem_arb_bench mig_bench ();

  mem_arb_bench #(.APP_ADDR_WIDTH(27)) narrow_bench ();

  mem_arb_bench #(.APP_ADDR_WIDTH(30)) wide_bench ();

  task automatic check_floor(input string name, input int got, input int floor);
    if (got < floor)
      $fatal(1, "TB UNDER-RAN: %s %0d checks, expected at least %0d", name, got, floor);
  endtask  // Automatic

  task automatic do_verdict();
    checks = mig_bench.checks + narrow_bench.checks + wide_bench.checks;
    errors = mig_bench.errors + narrow_bench.errors + wide_bench.errors;
    check_floor("mig_bench", mig_bench.checks, MinChecks);
    check_floor("narrow_bench", narrow_bench.checks, MinChecks);
    check_floor("wide_bench", wide_bench.checks, MinChecks);
    if (errors == 0) $display("PASS: %0d checks, %0d mismatches", checks, errors);
    else $fatal(1, "FAIL: %0d mismatches, %0d checks", errors, checks);
    $finish;
  endtask  // Automatic

  initial begin
    $dumpfile("mem_arb_tb.vcd");
    $dumpvars(0, mem_arb_tb);
    wait (mig_bench.done && narrow_bench.done && wide_bench.done);
    do_verdict();
  end

  always_comb live_errors = mig_bench.errors + narrow_bench.errors + wide_bench.errors;

  initial begin
    if ($value$plusargs("max_errors=%d", max_errors) && max_errors > 0) begin
      wait (live_errors >= max_errors);
      $fatal(1, "TB STOPPED: %0d mismatches", live_errors);
    end
  end

endmodule

module mem_arb_bench
  import cache_pkg::*;
#(
    parameter int APP_ADDR_WIDTH = arch_pkg::MigAddrW
) ();

  localparam int Xlen = arch_pkg::XLEN;
  localparam int AppAddrW = APP_ADDR_WIDTH;
  localparam int MaskW = LineBits / 8;
  localparam int MemLines = 1024;
  localparam int QDepth = 8;
  localparam int RdLat = 12;
  localparam int CalibCycles = 4;
  localparam int BootGap = 40;
  localparam int MaxWait = 4000;
  localparam int TimeoutCycles = 400_000;

  localparam logic [2:0] AppWrite = 3'b000;
  localparam logic [2:0] AppRead = 3'b001;

  int checks = 0;
  int errors = 0;
  int max_errors = 0;
  logic done = 1'b0;
  int rd_lat = RdLat;
  int rdy_pct = 100;
  int wdf_pct = 100;
  int en_period = 1;
  int en_ctr = 0;

  logic clk = 1'b0;
  logic rst_n = 1'b0;
  logic core_en;
  logic calib_done;

  logic ic_req_valid;
  logic [Xlen-1:0] ic_req_addr;
  logic [LineBits-1:0] ic_resp_rdata;
  logic ic_resp_ready;

  logic dc_req_valid;
  logic dc_req_rw;
  logic [Xlen-1:0] dc_req_addr;
  logic [LineBits-1:0] dc_req_wdata;
  logic [MaskW-1:0] dc_req_wstrb;
  logic [LineBits-1:0] dc_resp_rdata;
  logic dc_resp_ready;

  logic boot_we;
  logic [Xlen-1:0] boot_addr;
  logic [Xlen-1:0] boot_wdata;

  logic [AppAddrW-1:0] app_addr;
  logic [2:0] app_cmd;
  logic app_en;
  logic app_rdy;

  logic [LineBits-1:0] app_wdf_data;
  logic [MaskW-1:0] app_wdf_mask;
  logic app_wdf_wren;
  logic app_wdf_end;
  logic app_wdf_rdy;

  logic [LineBits-1:0] app_rd_data;
  logic app_rd_data_valid;

  logic [AppAddrW-1:0] last_wr_addr;
  logic [LineBits-1:0] ic_got;
  logic [LineBits-1:0] dc_got;
  logic [LineBits-1:0] got;

  // Controller model
  logic [LineBits-1:0] mem[MemLines];

  logic [2:0] cq_cmd[QDepth];
  logic [AppAddrW-1:0] cq_addr[QDepth];
  int cq_wr = 0;
  int cq_rd = 0;

  logic [LineBits-1:0] wq_data[QDepth];
  logic [MaskW-1:0] wq_mask[QDepth];
  int wq_wr = 0;
  int wq_rd = 0;

  logic [RdLat:0] rd_v;
  logic [LineBits-1:0] rd_d[RdLat+1];

  logic cmd_accept;
  logic wdf_accept;
  logic cq_head_live;
  logic wq_head_live;
  int cq_wr_eff;
  int wq_wr_eff;
  logic [2:0] head_cmd;
  logic [AppAddrW-1:0] head_addr;
  logic [LineBits-1:0] head_data;
  logic [MaskW-1:0] head_mask;

  always #5 clk = ~clk;

  mem_arb #(
      .XLEN(Xlen),
      .APP_ADDR_WIDTH(AppAddrW)
  ) dut (
      .clk(clk),
      .rst_n(rst_n),
      .core_en(core_en),
      .calib_done(calib_done),
      .ic_req_valid(ic_req_valid),
      .ic_req_addr(ic_req_addr),
      .ic_resp_rdata(ic_resp_rdata),
      .ic_resp_ready(ic_resp_ready),
      .dc_req_valid(dc_req_valid),
      .dc_req_rw(dc_req_rw),
      .dc_req_addr(dc_req_addr),
      .dc_req_wdata(dc_req_wdata),
      .dc_req_wstrb(dc_req_wstrb),
      .dc_resp_rdata(dc_resp_rdata),
      .dc_resp_ready(dc_resp_ready),
      .boot_we(boot_we),
      .boot_addr(boot_addr),
      .boot_wdata(boot_wdata),
      .app_addr(app_addr),
      .app_cmd(app_cmd),
      .app_en(app_en),
      .app_rdy(app_rdy),
      .app_wdf_data(app_wdf_data),
      .app_wdf_mask(app_wdf_mask),
      .app_wdf_wren(app_wdf_wren),
      .app_wdf_end(app_wdf_end),
      .app_wdf_rdy(app_wdf_rdy),
      .app_rd_data(app_rd_data),
      .app_rd_data_valid(app_rd_data_valid)
  );

  task automatic check(input string name, input logic [LineBits-1:0] got,
                       input logic [LineBits-1:0] exp);
    checks++;
    if (got !== exp) begin
      errors++;
      $display("FAIL %m %s: got %h, expected %h", name, got, exp);
      if (errors == max_errors) $fatal(1, "TB STOPPED: %0d mismatches", errors);
    end
  endtask  // Automatic

  task automatic do_reset();
    @(negedge clk);
    rst_n        = 1'b0;
    calib_done   = 1'b0;
    ic_req_valid = 1'b0;
    ic_req_addr  = '0;
    dc_req_valid = 1'b0;
    dc_req_rw    = 1'b0;
    dc_req_addr  = '0;
    dc_req_wdata = '0;
    dc_req_wstrb = '0;
    boot_we      = 1'b0;
    boot_addr    = '0;
    boot_wdata   = '0;
    for (int i = 0; i < MemLines; i++) mem[i] = '0;
    for (int i = 0; i <= RdLat; i++) rd_d[i] = '0;
    repeat (2) @(posedge clk);
    @(negedge clk);
    rst_n = 1'b1;
    repeat (CalibCycles) @(negedge clk);
    calib_done = 1'b1;
    @(negedge clk);
  endtask  // Automatic

  task automatic idle(input int n);
    repeat (n) @(negedge clk);
  endtask  // Automatic

  task automatic set_controller(input int rdy, input int wdf);
    rdy_pct = rdy;
    wdf_pct = wdf;
  endtask  // Automatic

  task automatic set_core_period(input int period);
    en_period = period;
  endtask  // Automatic

  task automatic wait_ic();
    int guard;
    guard = 0;
    @(negedge clk);
    while (!ic_resp_ready) begin
      guard++;
      if (guard > MaxWait)
        $fatal(1, "instruction request held valid %0d cycles with no response ready", MaxWait);
      @(negedge clk);
    end
  endtask  // Automatic

  task automatic wait_dc();
    int guard;
    guard = 0;
    @(negedge clk);
    while (!dc_resp_ready) begin
      guard++;
      if (guard > MaxWait)
        $fatal(1, "data request held valid %0d cycles with no response ready", MaxWait);
      @(negedge clk);
    end
  endtask  // Automatic

  task automatic ic_read(input logic [Xlen-1:0] addr, output logic [LineBits-1:0] data);
    ic_req_valid = 1'b1;
    ic_req_addr  = addr;
    wait_ic();
    data = ic_resp_rdata;
    ic_req_valid = 1'b0;
    @(negedge clk);
  endtask  // Automatic

  task automatic dc_read(input logic [Xlen-1:0] addr, output logic [LineBits-1:0] data);
    dc_req_valid = 1'b1;
    dc_req_rw    = 1'b0;
    dc_req_addr  = addr;
    dc_req_wstrb = '0;
    wait_dc();
    data = dc_resp_rdata;
    dc_req_valid = 1'b0;
    @(negedge clk);
  endtask  // Automatic

  task automatic dc_write(input logic [Xlen-1:0] addr, input logic [LineBits-1:0] data);
    dc_req_valid = 1'b1;
    dc_req_rw    = 1'b1;
    dc_req_addr  = addr;
    dc_req_wdata = data;
    dc_req_wstrb = '0;
    wait_dc();
    dc_req_valid = 1'b0;
    @(negedge clk);
  endtask  // Automatic

  task automatic dc_word_write(input logic [Xlen-1:0] addr, input logic [WordBytes-1:0] strb,
                               input logic [Xlen-1:0] data);
    dc_req_valid = 1'b1;
    dc_req_rw    = 1'b1;
    dc_req_addr  = addr;
    dc_req_wdata = {LineWords{data}};
    dc_req_wstrb = MaskW'(strb) << (WordBytes * addr[WordLsb+:BlkOffLen]);
    wait_dc();
    dc_req_valid = 1'b0;
    dc_req_wstrb = '0;
    @(negedge clk);
  endtask  // Automatic

  task automatic boot_word(input logic [Xlen-1:0] addr, input logic [Xlen-1:0] data);
    boot_we    = 1'b1;
    boot_addr  = addr;
    boot_wdata = data;
    repeat (en_period) @(posedge clk);
    @(negedge clk);
    boot_we = 1'b0;
    idle(BootGap);
  endtask  // Automatic

  task automatic both_read(input logic [Xlen-1:0] ic_a, input logic [Xlen-1:0] dc_a);
    fork
      ic_read(ic_a, ic_got);
      dc_read(dc_a, dc_got);
    join
  endtask  // Automatic

  task automatic check_ic(input string name, input logic [Xlen-1:0] addr,
                          input logic [LineBits-1:0] exp);
    ic_read(addr, got);
    check(name, got, exp);
  endtask  // Automatic

  task automatic check_dc(input string name, input logic [Xlen-1:0] addr,
                          input logic [LineBits-1:0] exp);
    dc_read(addr, got);
    check(name, got, exp);
  endtask  // Automatic

  task automatic test_boot_lanes();
    for (int w = 0; w < LineWords; w++)
      boot_word(Xlen'(w * WordBytes), Xlen'('hAAAA_0000) + Xlen'(w));
    check_ic("line of four boot word writes reads back wrong", '0, line_seq(Xlen'('hAAAA_0000)));
    check_ic("boot word write disturbed the next line up", Xlen'(LineBytes), '0);
    boot_word(Xlen'(LineBytes + WordBytes), Xlen'('hCCCC_0001));
    check_ic("boot word write disturbed the other three words", Xlen'(LineBytes), word_at(
             1, Xlen'('hCCCC_0001)));
  endtask  // Automatic

  task automatic test_dc_lines();
    dc_write(Xlen'('h20), line_seq(Xlen'('hBBBB_0000)));
    check_dc("line reads back wrong after a data cache write", Xlen'('h20), line_seq(
             Xlen'('hBBBB_0000)));
    dc_write('0, line_seq(Xlen'('hDDDD_0000)));
    check_ic("full line write left previous bytes in place", '0, line_seq(Xlen'('hDDDD_0000)));
  endtask  // Automatic

  task automatic test_requester_tagging();
    dc_write(Xlen'('h100), line_seq(Xlen'('h1111_0000)));
    dc_write(Xlen'('h200), line_seq(Xlen'('h2222_0000)));
    both_read(Xlen'('h100), Xlen'('h200));
    check("concurrent reads: instruction response has the wrong line", ic_got, line_seq(
          Xlen'('h1111_0000)));
    check("concurrent reads: data response has the wrong line", dc_got, line_seq(Xlen'('h2222_0000)
          ));
  endtask  // Automatic

  task automatic test_word_lanes();
    logic [LineBits-1:0] want;
    for (int w = 0; w < LineWords; w++) begin
      dc_write(Xlen'('h400), line_seq(Xlen'('h8888_0000)));
      want = line_seq(Xlen'('h8888_0000));
      want[w*Xlen+:Xlen] = Xlen'('h9999_0000) + Xlen'(w);
      dc_word_write(Xlen'('h400) + Xlen'(w * WordBytes), '1, Xlen'('h9999_0000) + Xlen'(w));
      check_ic($sformatf("data cache word write hit the wrong word, word %0d", w), Xlen'('h400),
               want);
    end
  endtask  // Automatic

  task automatic test_byte_strobes();
    logic [ LineBits-1:0] want;
    logic [WordBytes-1:0] strobes[4];
    strobes = '{WordBytes'('b0001), WordBytes'('b1100), WordBytes'('b0110), '1};
    for (int s = 0; s < $size(strobes); s++) begin
      dc_write(Xlen'('h500), line_seq(Xlen'('hABAB_0000)));
      want = line_seq(Xlen'('hABAB_0000));
      for (int b = 0; b < WordBytes; b++) begin
        if (strobes[s][b]) want[Xlen+b*8+:8] = byte_ramp(b);
      end
      dc_word_write(Xlen'('h504), strobes[s], word_ramp());
      check_dc($sformatf("data cache word write ignored byte strobe %b", strobes[s]), Xlen'('h500),
               want);
    end
  endtask  // Automatic

  task automatic test_word_neighbours();
    dc_write(Xlen'('h600), line_seq(Xlen'('hFEED_0000)));
    dc_write(Xlen'('h610), line_seq(Xlen'('hF00D_0000)));
    dc_word_write(Xlen'('h608), '1, Xlen'('h0BAD_0000));
    check_ic("data cache word write disturbed the next line up", Xlen'('h610), line_seq(
             Xlen'('hF00D_0000)));
  endtask  // Automatic

  task automatic test_word_stalled();
    set_core_period(3);
    set_controller(30, 30);
    for (int i = 0; i < 8; i++) begin
      dc_write(Xlen'('h700), '0);
      dc_word_write(Xlen'('h700) + Xlen'((i % LineWords) * WordBytes), '1,
                    Xlen'('hC0DE_0000) + Xlen'(i));
      check_ic($sformatf("data cache word write lost under a stalling controller, pass %0d", i),
               Xlen'('h700), word_at(i % LineWords, Xlen'('hC0DE_0000) + Xlen'(i)));
    end
    set_core_period(1);
    set_controller(100, 100);
  endtask  // Automatic

  task automatic test_core_enable_sweep();
    int periods[5];
    periods = '{1, 2, 3, 5, 8};
    for (int p = 0; p < $size(periods); p++) begin
      set_core_period(periods[p]);
      idle(1);
      dc_write(Xlen'('h300), line_seq(Xlen'('h3333_0000)) + LineBits'(p));
      check_ic($sformatf("read after write reads back wrong, core_en 1 cycle in %0d", en_period),
               Xlen'('h300), line_seq(Xlen'('h3333_0000)) + LineBits'(p));
      boot_word(Xlen'('h310), Xlen'('hEEEE_0000) + Xlen'(p));
      check_ic($sformatf("boot word write did not land, core_en 1 cycle in %0d", en_period),
               Xlen'('h310), word_at(0, Xlen'('hEEEE_0000) + Xlen'(p)));
    end
    set_core_period(1);
  endtask  // Automatic

  task automatic write_read_sweep(input string tag, input logic [Xlen-1:0] base,
                                  input logic [Xlen-1:0] seed, input int n);
    logic [Xlen-1:0] a;
    logic [LineBits-1:0] d;
    for (int i = 0; i < n; i++) begin
      a = base + Xlen'(i * LineBytes);
      d = line_seq(seed + Xlen'(i));
      dc_write(a, d);
      check_ic($sformatf("read after write reads back wrong, %s, pass %0d", tag, i), a, d);
    end
  endtask  // Automatic

  task automatic test_stalled_controller();
    set_controller(25, 15);
    write_read_sweep("stalling controller", Xlen'('h1000), Xlen'('h4444_0000), 24);
    set_controller(100, 100);
  endtask  // Automatic

  task automatic test_slow_core_stalled();
    set_core_period(4);
    set_controller(40, 40);
    write_read_sweep("stalling controller and slow core", Xlen'('h2000), Xlen'('h5555_0000), 12);
    set_core_period(1);
    set_controller(100, 100);
  endtask  // Automatic

  task automatic test_fast_controller();
    logic [Xlen-1:0] a;
    logic [LineBits-1:0] d;
    for (int L = 0; L <= 3; L++) begin
      rd_lat = L;
      a = Xlen'('h3000) + Xlen'((L + 1) * LineBytes);
      d = line_seq(Xlen'('h6666_0000) + Xlen'(L));
      dc_write(a, d);
      check_ic($sformatf("read after write reads back wrong at a read latency of %0d", L), a, d);
      boot_word(a + Xlen'(WordBytes), Xlen'('h7777_0000) + Xlen'(L));
      check_dc($sformatf("boot word write did not land at a read latency of %0d", L), a, {
               d[LineBits-1:2*Xlen], Xlen'('h7777_0000) + Xlen'(L), d[Xlen-1:0]});
    end
    rd_lat = RdLat;
  endtask  // Automatic

  task automatic test_beyond_bram();
    logic [Xlen-1:0] highs[7];
    highs = '{
        Xlen'('h0001_0000),
        Xlen'('h0001_0004),
        Xlen'('h0040_0000),
        Xlen'('h00FF_FFF0),
        Xlen'('h00FF_FFFC),
        Xlen'((64'(1) << (AppAddrW - 1)) | 64'h40),
        Xlen'((64'(1) << AppAddrW) | 64'h84)
    };
    for (int h = 0; h < $size(highs); h++) begin
      boot_word(highs[h], Xlen'('hB007_0000) + Xlen'(h));
      check($sformatf("boot word address truncated above the old block ram cap, %h", highs[h]),
            LineBits'(last_wr_addr), LineBits'({highs[h][AppAddrW-1:IdxLsb], {IdxLsb{1'b0}}}));
      ic_read(highs[h], got);
      check($sformatf("boot word write did not land at %h", highs[h]),
            LineBits'(got[highs[h][WordLsb+:BlkOffLen]*Xlen+:Xlen]),
            LineBits'(Xlen'('hB007_0000) + Xlen'(h)));
    end
  endtask  // Automatic

  task automatic check_drained();
    check("commands left outstanding at the controller when the stimulus ended", LineBits'(cq_wr),
          LineBits'(cq_rd));
    check("write beats left outstanding at the controller when the stimulus ended",
          LineBits'(wq_wr), LineBits'(wq_rd));
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
    do_reset();

    test_boot_lanes();
    test_dc_lines();
    test_requester_tagging();
    test_word_lanes();
    test_byte_strobes();
    test_word_neighbours();
    test_word_stalled();
    test_core_enable_sweep();
    test_stalled_controller();
    test_slow_core_stalled();
    test_fast_controller();
    test_beyond_bram();
    check_drained();

    finish();
  end

  function automatic logic [LineBits-1:0] line_seq(input logic [Xlen-1:0] seed);
    for (int w = 0; w < LineWords; w++) line_seq[w*Xlen+:Xlen] = seed + Xlen'(w);
  endfunction

  function automatic logic [LineBits-1:0] word_at(input int w, input logic [Xlen-1:0] data);
    return LineBits'(data) << (w * Xlen);
  endfunction

  function automatic logic [7:0] byte_ramp(input int b);
    return 8'('h5A + b);
  endfunction

  function automatic logic [Xlen-1:0] word_ramp();
    for (int b = 0; b < WordBytes; b++) word_ramp[b*8+:8] = byte_ramp(b);
  endfunction

  function automatic int line_of(input logic [AppAddrW-1:0] a);
    line_of = (int'(a) >> IdxLsb) % MemLines;
  endfunction

  assign cmd_accept   = app_en && app_rdy;
  assign wdf_accept   = app_wdf_wren && app_wdf_rdy;
  assign cq_head_live = (cq_rd == cq_wr) && cmd_accept;
  assign wq_head_live = (wq_rd == wq_wr) && wdf_accept;
  assign cq_wr_eff    = cq_wr + (cmd_accept ? 1 : 0);
  assign wq_wr_eff    = wq_wr + (wdf_accept ? 1 : 0);
  assign head_cmd     = cq_head_live ? app_cmd : cq_cmd[cq_rd%QDepth];
  assign head_addr    = cq_head_live ? app_addr : cq_addr[cq_rd%QDepth];
  assign head_data    = wq_head_live ? app_wdf_data : wq_data[wq_rd%QDepth];
  assign head_mask    = wq_head_live ? app_wdf_mask : wq_mask[wq_rd%QDepth];

  // Ready generators
  always @(posedge clk) begin
    if (!calib_done) begin
      app_rdy     <= 1'b0;
      app_wdf_rdy <= 1'b0;
    end else begin
      app_rdy     <= ($urandom_range(99) < rdy_pct);
      app_wdf_rdy <= ($urandom_range(99) < wdf_pct);
    end
  end

  // Queues and memory
  always @(posedge clk) begin
    if (!rst_n) begin
      cq_wr <= 0;
      cq_rd <= 0;
      wq_wr <= 0;
      wq_rd <= 0;
      rd_v  <= '0;
    end else begin
      if (cmd_accept) begin
        check("command issued with 8 already unretired at the controller",
              LineBits'(cq_wr - cq_rd >= QDepth), '0);
        cq_cmd[cq_wr%QDepth]  <= app_cmd;
        cq_addr[cq_wr%QDepth] <= app_addr;
        cq_wr                 <= cq_wr + 1;
      end

      if (wdf_accept) begin
        check("write beat issued with 8 already unretired at the controller",
              LineBits'(wq_wr - wq_rd >= QDepth), '0);
        check("wdf_end low on an accepted write data beat", LineBits'(app_wdf_end),
              LineBits'(1'b1));
        wq_data[wq_wr%QDepth] <= app_wdf_data;
        wq_mask[wq_wr%QDepth] <= app_wdf_mask;
        wq_wr                 <= wq_wr + 1;
      end

      rd_v <= rd_v >> 1;
      for (int k = 0; k < RdLat; k++) rd_d[k] <= rd_d[k+1];

      // Service head
      if (cq_rd < cq_wr_eff) begin
        if (head_cmd == AppRead) begin
          rd_v[rd_lat] <= 1'b1;
          rd_d[rd_lat] <= mem[line_of(head_addr)];
          cq_rd        <= cq_rd + 1;
        end else if (wq_rd < wq_wr_eff) begin
          for (int b = 0; b < MaskW; b++) begin
            if (!head_mask[b]) mem[line_of(head_addr)][8*b+:8] <= head_data[8*b+:8];
          end
          cq_rd <= cq_rd + 1;
          wq_rd <= wq_rd + 1;
        end
      end
    end
  end

  assign app_rd_data_valid = rd_v[0];
  assign app_rd_data = rd_d[0];

  always @(posedge clk) if (cmd_accept && app_cmd == AppWrite) last_wr_addr <= app_addr;

  // Core enable
  always @(posedge clk) begin
    if (!rst_n) en_ctr <= 0;
    else en_ctr <= (en_ctr + 1) % en_period;
  end

  assign core_en = (en_ctr == 0);

  // Protocol checks
  always @(posedge clk) begin
    if (rst_n) begin
      check("app_en asserted before calib_done rose", LineBits'(app_en && !calib_done), '0);
      check("app_addr not aligned to the 16 byte transaction size",
            LineBits'(app_en && app_addr[IdxLsb-1:0] != '0), '0);
      check("instruction and data response ready both high in one cycle",
            LineBits'(ic_resp_ready && dc_resp_ready), '0);
      check("instruction response ready high while core_en is low",
            LineBits'(ic_resp_ready && !core_en), '0);
      check("data response ready high while core_en is low", LineBits'(dc_resp_ready && !core_en),
            '0);
    end
  end

endmodule

`default_nettype wire
