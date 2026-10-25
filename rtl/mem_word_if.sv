`default_nettype none

module mem_word_if
  import cache_pkg::*;
#(
    parameter  int XLEN     = arch_pkg::XLEN,
    parameter  bit RW       = 1'b0,
    parameter  int CPU_W    = XLEN,
    localparam int CpuBytes = CPU_W / 8,
    localparam int CpuLsb   = $clog2(CpuBytes),
    localparam int LaneW    = $clog2(LineBits / CPU_W)
) (
    input wire clk,
    input wire core_en,
    input wire rst_n,

    // Core
    input  wire                 cpu_valid,
    input  wire                 cpu_rw,
    input  wire  [    XLEN-1:0] cpu_addr,
    input  wire  [   CPU_W-1:0] cpu_wdata,
    input  wire  [CpuBytes-1:0] cpu_wstrb,
    output logic [   CPU_W-1:0] cpu_rdata,
    output logic                cpu_ready,

    // Memory
    output logic                 mem_valid,
    output logic                 mem_rw,
    output logic [     XLEN-1:0] mem_addr,
    output logic [ LineBits-1:0] mem_wdata,
    output logic [LineBytes-1:0] mem_wstrb,
    input  wire  [ LineBits-1:0] mem_rdata,
    input  wire                  mem_ready,

    // Counters
    output logic [XLEN-1:0] hit_count,
    output logic [XLEN-1:0] miss_count
);

  typedef enum logic {
    IDLE,
    ACCESS
  } state_t;

  state_t state, next_state;

  if ((CPU_W > LineBits) || (LineBits % CPU_W != 0)) begin : g_cpu_w
    $error("CPU_W must divide the line");
  end

  logic [    XLEN-1:0] req_addr;
  logic [   CPU_W-1:0] req_wdata;
  logic [CpuBytes-1:0] req_wstrb;
  logic [     LaneW:0] lane;
  logic                req_rw;
  logic                done;

  assign done = (state == ACCESS) && mem_ready;

  // Lane within line
  if (LaneW > 0) begin : g_lane
    assign lane = {1'b0, req_addr[CpuLsb+:LaneW]};
  end else begin : g_line_lane
    assign lane = '0;
  end

  // Response cycle only
  assign cpu_ready = done;
  assign cpu_rdata = CPU_W'(mem_rdata >> (lane * CPU_W));

  assign mem_valid = (state == ACCESS);
  assign mem_rw    = RW && req_rw;
  // Arbiter selects lanes
  assign mem_addr  = req_addr;
  assign mem_wdata = {(LineBits / CPU_W) {req_wdata}};
  assign mem_wstrb = RW ? LineBytes'(req_wstrb) << (lane * CpuBytes) : '0;

  // No line reuse
  assign hit_count = '0;

  always_comb begin
    next_state = state;
    case (state)
      IDLE: if (cpu_valid) next_state = ACCESS;
      ACCESS: if (mem_ready) next_state = IDLE;
      default: ;
    endcase
  end

  always_ff @(posedge clk) begin
    if (!rst_n) state <= IDLE;
    else if (core_en) state <= next_state;
  end

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      req_addr  <= '0;
      req_wdata <= '0;
      req_wstrb <= '0;
      req_rw    <= 1'b0;
    end else if (core_en && cpu_valid && (state == IDLE)) begin
      req_addr  <= cpu_addr;
      req_wdata <= cpu_wdata;
      req_wstrb <= cpu_wstrb;
      req_rw    <= cpu_rw;
    end
  end

  // Always a miss
  always_ff @(posedge clk) begin
    if (!rst_n) miss_count <= '0;
    else if (core_en && done) miss_count <= miss_count + 1;
  end

endmodule

`default_nettype wire
