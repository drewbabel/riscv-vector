`default_nettype none

module clint #(
    parameter  int XLEN      = arch_pkg::XLEN,
    localparam int WordBytes = XLEN / 8
) (
    input wire clk,
    input wire core_en,
    input wire rst_n,

    input  wire                  sel,
    input  wire  [WordBytes-1:0] wstrb,
    input  wire  [     XLEN-1:0] addr,
    input  wire  [     XLEN-1:0] wdata,
    output logic [     XLEN-1:0] rdata,

    output logic timer_irq
);

  localparam int TimeW = 64;
  localparam int TimeWords = TimeW / XLEN;
  localparam int OffW = 16;

  localparam logic [OffW-1:0] MtimecmpOff = 16'h4000;
  localparam logic [OffW-1:0] MtimeOff = 16'hBFF8;

  if ((XLEN > TimeW) || (TimeW % XLEN != 0)) begin : g_xlen
    $error("XLEN must divide the 64-bit timer");
  end

  logic [TimeW-1:0] mtime;
  logic [TimeW-1:0] mtimecmp;

  logic [ OffW-1:0] off;
  assign off = addr[OffW-1:0];

  logic [TimeWords-1:0] cmp_word;
  logic [TimeWords-1:0] time_word;

  always_comb begin
    for (int w = 0; w < TimeWords; w++) begin
      cmp_word[w]  = off == MtimecmpOff + OffW'(w * WordBytes);
      time_word[w] = off == MtimeOff + OffW'(w * WordBytes);
    end
  end

  assign timer_irq = mtime >= mtimecmp;

  always_comb begin
    rdata = '0;
    if (sel) begin
      for (int w = 0; w < TimeWords; w++) begin
        if (cmp_word[w]) rdata = mtimecmp[w*XLEN+:XLEN];
        if (time_word[w]) rdata = mtime[w*XLEN+:XLEN];
      end
    end
  end

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      mtime    <= '0;
      mtimecmp <= '1;  // never fire until software programs it
    end else if (core_en) begin
      mtime <= mtime + 1;
      if (sel && |wstrb) begin
        for (int b = 0; b < WordBytes; b++) begin
          if (wstrb[b]) begin
            for (int w = 0; w < TimeWords; w++) begin
              if (cmp_word[w]) mtimecmp[w*XLEN+8*b+:8] <= wdata[8*b+:8];
              if (time_word[w]) mtime[w*XLEN+8*b+:8] <= wdata[8*b+:8];
            end
          end
        end
      end
    end
  end

endmodule

`default_nettype wire
