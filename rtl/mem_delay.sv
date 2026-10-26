`default_nettype none

module mem_delay
  import cache_pkg::*;
#(
    parameter int XLEN = arch_pkg::XLEN,
    parameter int DEPTH = arch_pkg::MemWords,
    parameter int Latency = arch_pkg::MemLatency,
    localparam int Lines = DEPTH / LineWords,
    localparam int LineIdxLen = $clog2(Lines),
    localparam int CntWidth = $clog2(Latency + 1)
) (
    input wire clk,
    input wire core_en,
    input wire rst_n,

    // Line
    input  wire                 req_valid,
    input  wire                 req_rw,
    input  wire  [    XLEN-1:0] req_addr,
    input  wire  [LineBits-1:0] req_wdata,
    output logic [LineBits-1:0] resp_rdata,
    output logic                resp_ready,

    // Boot
    input wire            boot_we,
    input wire [XLEN-1:0] boot_addr,
    input wire [XLEN-1:0] boot_wdata
);

  if (Latency < 2) begin : g_latency
    $error("Latency must be at least 2");
  end

  logic [LineIdxLen-1:0] line_idx;
  logic [LineIdxLen-1:0] boot_idx;
  logic [LineIdxLen-1:0] wr_idx;

  logic [  CntWidth-1:0] cnt;
  logic                  busy;
  logic                  done;

  logic                  req_rw_q;
  logic [      XLEN-1:0] req_addr_q;
  logic [  LineBits-1:0] req_wdata_q;

  localparam int Lanes = LineBits / 8;

  logic [LineBits-1:0] wr_data;
  logic [   Lanes-1:0] wr_lane;
  logic                wr_en;
  logic                unused_addr;

  assign line_idx = req_addr_q[IdxLsb+:LineIdxLen];
  assign boot_idx = boot_addr[IdxLsb+:LineIdxLen];
  assign unused_addr = ^{
    boot_addr[XLEN-1:IdxLsb+LineIdxLen],
    boot_addr[WordLsb-1:0],
    req_addr_q[XLEN-1:IdxLsb+LineIdxLen],
    req_addr_q[IdxLsb-1:0]
  };

  assign done = busy && (int'(cnt) >= Latency - 1);

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      busy       <= 1'b0;
      cnt        <= '0;
      resp_ready <= 1'b0;
    end else if (core_en) begin
      resp_ready <= 1'b0;
      if (boot_we) begin
        busy <= 1'b0;
      end else if (!busy) begin
        if (req_valid && !resp_ready) begin
          busy        <= 1'b1;
          cnt         <= 1;
          req_rw_q    <= req_rw;
          req_addr_q  <= req_addr;
          req_wdata_q <= req_wdata;
        end
      end else if (done) begin
        busy       <= 1'b0;
        resp_ready <= 1'b1;
      end else begin
        cnt <= cnt + 1'b1;
      end
    end
  end

  // No read modify write
  assign wr_en   = boot_we || (done && req_rw_q);
  assign wr_idx  = boot_we ? boot_idx : line_idx;
  assign wr_data = boot_we ? {LineWords{boot_wdata}} : req_wdata_q;  // Boot word every slot

  // Strobe the boot word
  if (BlkOffLen > 0) begin : g_boot_word
    logic [BlkOffLen-1:0] boot_word;
    assign boot_word = boot_addr[WordLsb+:BlkOffLen];
    always_comb begin
      for (int b = 0; b < Lanes; b++) begin
        wr_lane[b] = !boot_we || (boot_word == BlkOffLen'(b / WordBytes));
      end
    end
  end else begin : g_line_word
    assign wr_lane = '1;
  end

  bram_sdp #(
      .Width(LineBits),
      .Depth(Lines)
  ) u_line (
      .clk  (clk),
      .we   (core_en && wr_en),
      .wlane(wr_lane),
      .widx (wr_idx),
      .wdata(wr_data),
      .re   (core_en && done),
      .ridx (line_idx),
      .rdata(resp_rdata)
  );

endmodule

`default_nettype wire
