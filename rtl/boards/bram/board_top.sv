`default_nettype none

module board_top
  import cache_pkg::*;
#(
    parameter  int XLEN       = arch_pkg::XLEN,
    parameter  int VLEN       = arch_pkg::VLEN,
    parameter  int ELEN       = arch_pkg::ELEN,
    parameter  int MUL_LANES  = arch_pkg::MulLanes,
    parameter  int DEPTH      = arch_pkg::MemWords,
    parameter  int ClkDiv     = arch_pkg::ClkDiv,
    parameter  int BoardClkHz = arch_pkg::BoardClkHz,
    parameter  int MemLatency = arch_pkg::MemLatency,
    localparam int GpioW      = 16,
    localparam int ILEN       = arch_pkg::ILEN
) (
`ifdef SIM_BACKDOOR
    output logic             sim_branch,
    output logic             sim_branch_taken,
    output logic             sim_mispredict,
    output logic             sim_muldiv_hold,
`endif
    input  wire              clk,
    input  wire              rst,
    input  wire  [GpioW-1:0] sw,
    output logic [GpioW-1:0] led,
    input  wire              uart_rx,
    output logic             uart_tx
);

  localparam int DataBits = arch_pkg::UartDataBits;
  localparam int TagW = arch_pkg::PeriphTagW;
  localparam int PorW = arch_pkg::PorW;
  localparam logic [GpioW-1:0] LoadPattern = {(GpioW / 2) {2'b01}};

  logic                 rst_n;
  logic [     ILEN-1:0] instr;
  logic [     XLEN-1:0] pc;
  logic [     XLEN-1:0] mem_addr;
  logic [   XLEN/8-1:0] store_wstrb;
  logic [     XLEN-1:0] store_data;

  logic [     XLEN-1:0] read_data;
  logic [     XLEN-1:0] clint_rdata;
  logic [     XLEN-1:0] gpio_rdata;
  logic [     XLEN-1:0] uart_rdata;
  logic                 clint_sel;
  logic                 gpio_sel;
  logic                 uart_sel;
  logic                 tx_ready;
  logic                 timer_irq;
  logic                 ext_irq;
  logic                 tx_valid;
  logic [ DataBits-1:0] tx_byte;
  logic [    GpioW-1:0] led_raw;

  logic                 core_rst_n;
  logic                 loading;
  logic                 boot_we;
  logic [     XLEN-1:0] boot_waddr;
  logic [     XLEN-1:0] boot_wdata;
  logic [ DataBits-1:0] rx_byte;
  logic                 rx_valid_w;


  logic [     XLEN-1:0] pmu_rdata;
  logic                 pmu_sel;
  logic                 periph_sel;

  logic                 imem_ready;
  logic                 dmem_ready;
  logic                 dmem_req;
  logic                 dc_ready;
  logic [     XLEN-1:0] dc_rdata;

  logic [ LineBits-1:0] dc_line;
  logic [ LineBits-1:0] dc_wdata;
  logic [LineBytes-1:0] dc_wstrb;
  logic [ LineBits-1:0] core_rdata;

  logic                 ic_mem_valid;
  logic [     XLEN-1:0] ic_mem_addr;
  logic [ LineBits-1:0] ic_mem_rdata;
  logic                 ic_mem_ready;

  logic                 dc_mem_valid;
  logic                 dc_mem_rw;
  logic [     XLEN-1:0] dc_mem_addr;
  logic [ LineBits-1:0] dc_mem_wdata;
  logic [ LineBits-1:0] dc_mem_rdata;
  logic                 dc_mem_ready;

  logic [     XLEN-1:0] ic_hits;
  logic [     XLEN-1:0] ic_misses;
  logic [     XLEN-1:0] dc_hits;
  logic [     XLEN-1:0] dc_misses;

  localparam int CoreClkHz = BoardClkHz / ClkDiv;
  logic [TagW-1:0] periph_tag;
  logic core_en;

  tick_gen #(
      .DIVISOR(ClkDiv)
  ) core_en_inst (
      .clk    (clk),
      .core_en(1'b1),
      .rst_n  (1'b1),
      .clr    (1'b0),
      .tick   (core_en)
  );

  logic            rx_error;
  logic            core_mem_write;
  logic [XLEN-1:0] core_alu_result;
  logic [XLEN-1:0] core_write_data;
  logic            unused_core;
  assign unused_core = ^{rx_error, core_mem_write, core_alu_result, core_write_data};

  // Power on reset
  logic [PorW-1:0] por;
  initial por = '0;
  always @(posedge clk) if (core_en && !por[PorW-1]) por <= por + 1'b1;
  assign rst_n      = por[PorW-1] & ~rst;

  // Load holds reset
  assign core_rst_n = rst_n & ~loading;

  // Decode on mem_addr
  assign periph_tag = mem_addr[XLEN-1-:TagW];
  assign clint_sel  = periph_tag == arch_pkg::ClintTag;
  assign gpio_sel   = periph_tag == arch_pkg::GpioTag;
  assign uart_sel   = periph_tag == arch_pkg::UartTag;
  assign pmu_sel    = periph_tag == arch_pkg::PmuTag;
  assign periph_sel = clint_sel || gpio_sel || uart_sel || pmu_sel;

  // Peripheral read mux
  always_comb begin
    if (uart_sel) read_data = uart_rdata;
    else if (gpio_sel) read_data = gpio_rdata;
    else if (clint_sel) read_data = clint_rdata;
    else if (pmu_sel) read_data = pmu_rdata;
    else read_data = dc_rdata;
  end

  assign dmem_ready = periph_sel ? 1'b1 : dc_ready;

  assign led = loading ? LoadPattern : led_raw;

  pmu #(
      .XLEN(XLEN),
      .CLK_FREQ_HZ(CoreClkHz)
  ) pmu_inst (
      .addr     (mem_addr),
      .rdata    (pmu_rdata),
      .ic_hits  (ic_hits),
      .ic_misses(ic_misses),
      .dc_hits  (dc_hits),
      .dc_misses(dc_misses)
  );

  gpio #(
      .XLEN (XLEN),
      .WIDTH(GpioW)
  ) gpio_inst (
      .clk    (clk),
      .core_en(core_en),
      .rst_n  (core_rst_n),
      .sel    (gpio_sel),
      .wstrb  (store_wstrb),
      .addr   (mem_addr),
      .wdata  (store_data),
      .rdata  (gpio_rdata),
      .sw     (sw),
      .led    (led_raw)
  );

  uart_rx #(
      .CLK_FREQ_HZ(CoreClkHz),
      .BAUD_RATE  (arch_pkg::BaudRate),
      .DATA_BITS  (DataBits)
  ) uart_rx_inst (
      .clk      (clk),
      .core_en  (core_en),
      .rst_n    (rst_n),
      .rx_serial(uart_rx),
      .rx_data  (rx_byte),
      .rx_valid (rx_valid_w),
      .rx_error (rx_error)
  );

  uart_tx #(
      .CLK_FREQ_HZ(CoreClkHz),
      .BAUD_RATE  (arch_pkg::BaudRate),
      .DATA_BITS  (DataBits)
  ) uart_tx_inst (
      .clk      (clk),
      .core_en  (core_en),
      .rst_n    (rst_n),
      .tx_data  (tx_byte),
      .tx_valid (tx_valid),
      .tx_ready (tx_ready),
      .tx_serial(uart_tx)
  );

  uart_ctrl #(
      .XLEN     (XLEN),
      .DATA_BITS(DataBits)
  ) uart_ctrl_inst (
      .clk     (clk),
      .core_en (core_en),
      .rst_n   (core_rst_n),
      .sel     (uart_sel),
      .req     (dmem_req),
      .wstrb   (store_wstrb),
      .addr    (mem_addr),
      .wdata   (store_data),
      .rdata   (uart_rdata),
      .rx_valid(rx_valid_w),
      .rx_data (rx_byte),
      .tx_ready(tx_ready),
      .tx_valid(tx_valid),
      .tx_data (tx_byte),
      .irq     (ext_irq)
  );

  boot_loader #(
      .XLEN     (XLEN),
      .DEPTH    (DEPTH),
      .DATA_BITS(DataBits)
  ) boot_loader_inst (
      .clk     (clk),
      .core_en (core_en),
      .rst_n   (rst_n),
      .rx_valid(rx_valid_w),
      .rx_data (rx_byte),
      .we      (boot_we),
      .waddr   (boot_waddr),
      .wdata   (boot_wdata),
      .loading (loading)
  );

  riscv_pipelined #(
      .XLEN     (XLEN),
      .VLEN     (VLEN),
      .ELEN     (ELEN),
      .MUL_LANES(MUL_LANES)
  ) riscv_pipelined_inst (
`ifdef SIM_BACKDOOR
      .sim_branch      (sim_branch),
      .sim_branch_taken(sim_branch_taken),
      .sim_mispredict  (sim_mispredict),
      .sim_muldiv_hold (sim_muldiv_hold),
`endif
`ifdef RISCV_FORMAL
      .dbg_valid       (),
      .dbg_insn        (),
      .dbg_pc_rdata    (),
      .dbg_pc_wdata    (),
      .dbg_rs1_rdata   (),
      .dbg_rs2_rdata   (),
      .dbg_rd_wdata    (),
      .dbg_reg_write   (),
      .dbg_mem_addr    (),
      .dbg_mem_wmask   (),
      .dbg_mem_wdata   (),
      .dbg_mem_rdata   (),
      .dbg_trap        (),
      .dbg_csr_wdata   (),
      .dbg_mscratch    (),
      .dbg_mstatus     (),
      .dbg_mtvec       (),
      .dbg_mepc        (),
      .dbg_mcause      (),
      .dbg_mtval       (),
      .dbg_mie         (),
      .dbg_mip         (),
      .dbg_mcycle      (),
      .dbg_minstret    (),
      .dbg_mcycleh     (),
      .dbg_minstreth   (),
      .dbg_fflags      (),
      .dbg_vl          (),
      .dbg_vtype_bits  (),
      .dbg_vtype_ill   (),
      .dbg_vstart      (),
      .dbg_vec_tag     (),
      .dbg_vec_retire  (),
      .dbg_vec_wregs   (),
      .dbg_vec_idle    (),
      .dbg_ex_commit   (),
      .dbg_ex_insn     (),
      .dbg_s_take      (),
      .dbg_v_take      (),
`endif
      .clk             (clk),
      .core_en         (core_en),
      .rst_n           (core_rst_n),
      .instr           (instr),
      .read_data       (core_rdata),
      .timer_irq       (timer_irq),
      .ext_irq         (ext_irq),
      .imem_ready      (imem_ready),
      .dmem_ready      (dmem_ready),
      .dmem_req        (dmem_req),
      .pc              (pc),
      .mem_write       (core_mem_write),
      .alu_result      (core_alu_result),
      .write_data      (core_write_data),
      .store_wstrb     (dc_wstrb),
      .store_data      (dc_wdata),
      .mem_addr        (mem_addr)
  );

  icache #(
      .XLEN(XLEN)
  ) icache_inst (
      .clk       (clk),
      .core_en   (core_en),
      .rst_n     (core_rst_n),
      .cpu_valid (1'b1),
      .cpu_addr  (pc),
      .cpu_rdata (instr),
      .cpu_ready (imem_ready),
      .mem_valid (ic_mem_valid),
      .mem_addr  (ic_mem_addr),
      .mem_rdata (ic_mem_rdata),
      .mem_ready (ic_mem_ready),
      .hit_count (ic_hits),
      .miss_count(ic_misses)
  );

  // Word views of line
  assign dc_rdata = dc_line[mem_addr[WordLsb+:BlkOffLen]*XLEN+:XLEN];
  assign core_rdata = periph_sel ? {LineWords{read_data}} : dc_line;
  assign store_data = dc_wdata[mem_addr[WordLsb+:BlkOffLen]*XLEN+:XLEN];
  assign store_wstrb = dc_wstrb[mem_addr[WordLsb+:BlkOffLen]*WordBytes+:WordBytes];

  dcache #(
      .XLEN(XLEN)
  ) dcache_inst (
      .clk       (clk),
      .core_en   (core_en),
      .rst_n     (core_rst_n),
      .cpu_valid (dmem_req && !periph_sel),
      .cpu_rw    (|dc_wstrb),
      .cpu_addr  (mem_addr),
      .cpu_wdata (dc_wdata),
      .cpu_wstrb (dc_wstrb),
      .cpu_rdata (dc_line),
      .cpu_ready (dc_ready),
      .mem_valid (dc_mem_valid),
      .mem_rw    (dc_mem_rw),
      .mem_addr  (dc_mem_addr),
      .mem_wdata (dc_mem_wdata),
      .mem_rdata (dc_mem_rdata),
      .mem_ready (dc_mem_ready),
      .hit_count (dc_hits),
      .miss_count(dc_misses)
  );

  mem_delay #(
      .XLEN   (XLEN),
      .DEPTH  (DEPTH),
      .Latency(MemLatency)
  ) imem_inst (
      .clk       (clk),
      .core_en   (core_en),
      .rst_n     (rst_n),
      .req_valid (ic_mem_valid),
      .req_rw    (1'b0),
      .req_addr  (ic_mem_addr),
      .req_wdata ('0),
      .resp_rdata(ic_mem_rdata),
      .resp_ready(ic_mem_ready),
      .boot_we   (loading && boot_we),
      .boot_addr (boot_waddr),
      .boot_wdata(boot_wdata)
  );

  mem_delay #(
      .XLEN   (XLEN),
      .DEPTH  (DEPTH),
      .Latency(MemLatency)
  ) dmem_inst (
      .clk       (clk),
      .core_en   (core_en),
      .rst_n     (rst_n),
      .req_valid (dc_mem_valid),
      .req_rw    (dc_mem_rw),
      .req_addr  (dc_mem_addr),
      .req_wdata (dc_mem_wdata),
      .resp_rdata(dc_mem_rdata),
      .resp_ready(dc_mem_ready),
      .boot_we   (loading && boot_we),
      .boot_addr (boot_waddr),
      .boot_wdata(boot_wdata)
  );

  clint #(
      .XLEN(XLEN)
  ) clint_inst (
      .clk      (clk),
      .core_en  (core_en),
      .rst_n    (core_rst_n),
      .sel      (clint_sel),
      .wstrb    (store_wstrb),
      .addr     (mem_addr),
      .wdata    (store_data),
      .rdata    (clint_rdata),
      .timer_irq(timer_irq)
  );

endmodule

`default_nettype wire
