`default_nettype none

module sc_core_top_tb;

  import cache_pkg::*;

  localparam int Xlen = arch_pkg::XLEN;
  localparam int AWIDTH = arch_pkg::RegAddrW;
  localparam int MemLines = 256;
  localparam int MaxTicks = 20000;
  localparam int TimeoutCycles = 200_000;
  localparam logic [7:0] PeriphTag = arch_pkg::GpioTag;
  localparam logic [Xlen-1:0] StoreAddr = Xlen'('h400);
  localparam logic [Xlen-1:0] Round = Xlen'('hABCD);
  localparam int MinRetired = 13;
  localparam int MinChecks = 1700;

  int                   checks = 0;
  int                   errors = 0;
  int                   max_errors = 0;
  int                   max_lat = 3;
  int                   en_period = 2;
  int                   periph_writes = 0;
  int                   i_ctr;
  int                   d_ctr;
  int                   en_ctr = 0;

  logic                 clk = 1'b0;
  logic                 rst_n;
  logic                 core_en;

  logic [     Xlen-1:0] instr;
  logic [     Xlen-1:0] read_data;
  logic [     Xlen-1:0] pc;
  logic [     Xlen-1:0] mem_addr;
  logic [   Xlen/8-1:0] store_wstrb;
  logic [     Xlen-1:0] store_data;
  logic                 imem_req;
  logic                 imem_ready;
  logic                 dmem_req;
  logic                 dmem_ready;
  logic                 periph_sel;
  logic                 irq_stim = 1'b0;

  logic [     Xlen-1:0] dc_rdata;
  logic                 dc_ready;

  logic                 ic_mem_valid;
  logic [     Xlen-1:0] ic_mem_addr;
  logic [ LineBits-1:0] ic_mem_rdata;
  logic                 ic_mem_ready;

  logic                 dc_mem_valid;
  logic                 dc_mem_rw;
  logic [     Xlen-1:0] dc_mem_addr;
  logic [ LineBits-1:0] dc_mem_wdata;
  logic [LineBytes-1:0] dc_mem_wstrb;
  logic [ LineBits-1:0] dc_mem_rdata;
  logic                 dc_mem_ready;

  logic [         31:0] ic_hits;
  logic [         31:0] ic_misses;
  logic [         31:0] dc_hits;
  logic [         31:0] dc_misses;

  logic [     Xlen-1:0] periph_reg;
  logic [ LineBits-1:0] mem               [            MemLines];
  logic [     Xlen-1:0] img               [MemLines * LineWords];

  logic                 i_busy;
  logic                 i_pend;
  logic [ LineBits-1:0] i_hold;
  logic                 d_busy;
  logic                 d_pend;
  logic [ LineBits-1:0] d_hold;

  logic [     Xlen-1:0] instr_h_q;
  logic [     Xlen-1:0] rdata_h_q;
  logic                 core_en_q;
  logic                 irq_h_q;

  always #5 clk = ~clk;

  sc_core_top #(
      .XLEN(Xlen)
  ) dut (
      .clk        (clk),
      .core_en    (core_en),
      .rst_n      (rst_n),
      .instr      (instr),
      .read_data  (read_data),
      .timer_irq  (irq_stim),
      .imem_ready (imem_ready),
      .dmem_ready (dmem_ready),
      .imem_req   (imem_req),
      .dmem_req   (dmem_req),
      .pc         (pc),
      .mem_write  (),
      .alu_result (),
      .write_data (),
      .store_wstrb(store_wstrb),
      .store_data (store_data),
      .mem_addr   (mem_addr)
  );

  mem_word_if #(
      .XLEN(Xlen),
      .RW  (1'b0)
  ) icache_inst (
      .clk       (clk),
      .core_en   (core_en),
      .rst_n     (rst_n),
      .cpu_valid (imem_req),
      .cpu_rw    (1'b0),
      .cpu_addr  (pc),
      .cpu_wdata ('0),
      .cpu_wstrb ('0),
      .cpu_rdata (instr),
      .cpu_ready (imem_ready),
      .mem_valid (ic_mem_valid),
      .mem_rw    (),
      .mem_addr  (ic_mem_addr),
      .mem_wdata (),
      .mem_wstrb (),
      .mem_rdata (ic_mem_rdata),
      .mem_ready (ic_mem_ready),
      .hit_count (ic_hits),
      .miss_count(ic_misses)
  );

  mem_word_if #(
      .XLEN(Xlen),
      .RW  (1'b1)
  ) dcache_inst (
      .clk       (clk),
      .core_en   (core_en),
      .rst_n     (rst_n),
      .cpu_valid (dmem_req && !periph_sel),
      .cpu_rw    (|store_wstrb),
      .cpu_addr  (mem_addr),
      .cpu_wdata (store_data),
      .cpu_wstrb (store_wstrb),
      .cpu_rdata (dc_rdata),
      .cpu_ready (dc_ready),
      .mem_valid (dc_mem_valid),
      .mem_rw    (dc_mem_rw),
      .mem_addr  (dc_mem_addr),
      .mem_wdata (dc_mem_wdata),
      .mem_wstrb (dc_mem_wstrb),
      .mem_rdata (dc_mem_rdata),
      .mem_ready (dc_mem_ready),
      .hit_count (dc_hits),
      .miss_count(dc_misses)
  );

  function automatic int line_of(input logic [Xlen-1:0] a);
    line_of = (int'(a) >> IdxLsb) % MemLines;
  endfunction

  function automatic int word_of(input logic [Xlen-1:0] a);
    word_of = (int'(a) >> WordLsb) % LineWords;
  endfunction

  function automatic logic [Xlen-1:0] reg_of(input logic [AWIDTH-1:0] n);
    reg_of = dut.riscv_single_inst.datapath_inst.regfile_inst.regfile_mem[n];
  endfunction

  task automatic check(input string name, input logic [Xlen-1:0] got, input logic [Xlen-1:0] exp);
    checks++;
    if (got !== exp) begin
      errors++;
      $display("FAIL %s: got %h, expected %h", name, got, exp);
      if (errors == max_errors) $fatal(1, "TB STOPPED: %0d mismatches", errors);
    end
  endtask  // Automatic

  task automatic do_reset();
    rst_n = 1'b0;
    repeat (4) @(posedge clk);
    @(negedge clk);
    rst_n = 1'b1;
  endtask  // Automatic

  task automatic load_image(input string path);
    for (int i = 0; i < $size(img); i++) img[i] = '0;
    $readmemh(path, img);
    if ($isunknown(img[0]) || img[0] == '0)
      $fatal(1, "sc_smoke.hex missing or empty, run make hex PROG=sc_smoke");
    for (int i = 0; i < $size(img); i++) mem[i/LineWords][(i%LineWords)*Xlen+:Xlen] = img[i];
  endtask  // Automatic

  task automatic run_to_done();
    int ticks = 0;
    while (reg_of(
        AWIDTH'(28)
    ) !== Xlen'(1) && ticks < MaxTicks) begin
      @(posedge clk);
      ticks++;
    end
    if (ticks >= MaxTicks) $fatal(1, "t=%0t  core never reached the done flag", $time);
    repeat (4) @(posedge clk);
    @(negedge clk);
  endtask  // Automatic

  task automatic watchdog(input int cycles);
    repeat (cycles) @(posedge clk);
    $fatal(1, "global time limit reached before the stimulus finished");
  endtask  // Automatic

  task automatic check_loads();
    check("x1 immediate", reg_of(AWIDTH'(1)), Round);
    check("x3 word load", reg_of(AWIDTH'(3)), Round);
    check("x7 byte load", reg_of(AWIDTH'(7)), Xlen'(Round[7:0]));
    check("x8 halfword load", reg_of(AWIDTH'(8)), Xlen'($signed(Round[15:0])));
  endtask  // Automatic

  task automatic check_peripheral();
    check("x11 peripheral read", reg_of(AWIDTH'(11)), Round);
    check("x28 done flag", reg_of(AWIDTH'(28)), Xlen'(1));
    check("peripheral write strobes", Xlen'(periph_writes), Xlen'(1));
  endtask  // Automatic

  task automatic check_mcycle();
    check("mcycle advanced past instructions retired", Xlen'(reg_of(AWIDTH'(10)) > MinRetired),
          Xlen'(1));
  endtask  // Automatic

  task automatic check_store_memory();
    check("store reached memory", mem[line_of(StoreAddr)][word_of(StoreAddr)*Xlen+:Xlen], Round);
  endtask  // Automatic

  task automatic do_verdict();
    if (checks < MinChecks)
      $fatal(1, "TB UNDER-RAN: %0d checks, expected at least %0d", checks, MinChecks);
    if (errors == 0) $display("PASS: %0d checks, %0d mismatches", checks, errors);
    else $fatal(1, "FAIL: %0d mismatches, %0d checks", errors, checks);
    $finish;
  endtask  // Automatic

  initial void'($value$plusargs("max_errors=%d", max_errors));

  initial watchdog(TimeoutCycles);

  initial begin
    $dumpfile("sc_core_top_tb.vcd");
    $dumpvars(0, sc_core_top_tb);
    load_image("tests/sc_smoke.hex");
    do_reset();
    run_to_done();
    check_loads();
    check_peripheral();
    check_mcycle();
    check_store_memory();
    do_verdict();
  end

  // Board decode
  assign periph_sel = mem_addr[Xlen-1-:$bits(PeriphTag)] == PeriphTag;
  assign dmem_ready = periph_sel ? 1'b1 : dc_ready;
  assign read_data  = periph_sel ? periph_reg : dc_rdata;

  // Peripheral stand in
  always @(posedge clk) begin
    if (!rst_n) begin
      periph_reg    <= '0;
      periph_writes <= 0;
    end else if (core_en && periph_sel && |store_wstrb) begin
      periph_reg    <= store_data;
      periph_writes <= periph_writes + 1;
    end
  end

  // Instruction responder
  always @(posedge clk) begin
    if (!rst_n) begin
      i_busy <= 1'b0;
      i_pend <= 1'b0;
      i_ctr  <= 0;
    end else begin
      if (!i_busy && !i_pend && ic_mem_valid) begin
        i_busy <= 1'b1;
        i_ctr  <= $urandom_range(max_lat);
      end else if (i_busy) begin
        if (i_ctr == 0) begin
          i_busy <= 1'b0;
          i_pend <= 1'b1;
          i_hold <= mem[line_of(ic_mem_addr)];
        end else begin
          i_ctr <= i_ctr - 1;
        end
      end
      if (i_pend && core_en) i_pend <= 1'b0;
    end
  end

  // Valid on ready
  assign ic_mem_ready = i_pend && core_en;
  assign ic_mem_rdata = ic_mem_ready ? i_hold : '1;

  // Data responder
  always @(posedge clk) begin
    if (!rst_n) begin
      d_busy <= 1'b0;
      d_pend <= 1'b0;
      d_ctr  <= 0;
    end else begin
      if (!d_busy && !d_pend && dc_mem_valid) begin
        d_busy <= 1'b1;
        d_ctr  <= $urandom_range(max_lat);
      end else if (d_busy) begin
        if (d_ctr == 0) begin
          d_busy <= 1'b0;
          d_pend <= 1'b1;
          if (dc_mem_rw) begin
            for (int b = 0; b < LineBytes; b++) begin
              if (dc_mem_wstrb[b]) mem[line_of(dc_mem_addr)][b*8+:8] <= dc_mem_wdata[b*8+:8];
            end
            d_hold <= '0;
          end else begin
            d_hold <= mem[line_of(dc_mem_addr)];
          end
        end else begin
          d_ctr <= d_ctr - 1;
        end
      end
      if (d_pend && core_en) d_pend <= 1'b0;
    end
  end

  // Valid on ready
  assign dc_mem_ready = d_pend && core_en;
  assign dc_mem_rdata = dc_mem_ready ? d_hold : '1;

  // Core enable
  always @(posedge clk) begin
    if (!rst_n) en_ctr <= 0;
    else en_ctr <= (en_ctr + 1) % en_period;
  end

  assign core_en = (en_ctr == 0);

  always @(posedge clk) irq_stim <= ~irq_stim;

  // Freeze checks
  always @(posedge clk) begin
    instr_h_q <= dut.instr_h;
    rdata_h_q <= dut.rdata_h;
    core_en_q <= core_en;
    irq_h_q   <= dut.irq_h;
    if (rst_n) begin
      check("core stepped on a hold capture cycle",
            Xlen'(dut.core_step && (dut.instr_cap || dut.data_cap)), '0);
      check("core stepped while core_en was low", Xlen'(dut.core_step && !core_en), '0);
      check("instruction hold captured while core_en was low", Xlen'(dut.instr_cap && !core_en),
            '0);
      check("data hold captured while core_en was low", Xlen'(dut.data_cap && !core_en), '0);
      check("instruction hold moved outside a core_en cycle",
            Xlen'((dut.instr_h !== instr_h_q) && !core_en_q), '0);
      check("data hold moved outside a core_en cycle",
            Xlen'((dut.rdata_h !== rdata_h_q) && !core_en_q), '0);
      check("interrupt hold moved outside a core_en cycle",
            Xlen'((dut.irq_h !== irq_h_q) && !core_en_q), '0);
      check("byte strobe live outside the request cycle", Xlen'(|store_wstrb && !dmem_req), '0);
      check("fetch and data request overlapped", Xlen'(imem_req && dmem_req), '0);
    end
  end

endmodule

`default_nettype wire
