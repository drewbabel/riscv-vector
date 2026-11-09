`default_nettype none

module bram_watch_formal ();

  localparam int Width = 9;
  localparam int Depth = 2;
  localparam int AddrW = $clog2(Depth);
  localparam int Lanes = (Width + 7) / 8;

  logic             clk;

  // Watched index
  (* anyconst *)logic [AddrW-1:0] f_idx;

  (* anyseq *)logic             we;
  (* anyseq *)logic [Lanes-1:0] wlane;
  (* anyseq *)logic [AddrW-1:0] widx;
  (* anyseq *)logic [Width-1:0] wdata;
  (* anyseq *)logic             re;
  (* anyseq *)logic [AddrW-1:0] ridx;

  // Last read watched
  logic             f_valid = 1'b0;

  always @(posedge clk) if (re) f_valid <= (ridx == f_idx);

  for (genvar k = 0; k < 2; k++) begin : g_style
    logic [Width-1:0] rtl_rdata;
    logic [Width-1:0] watch_rdata;

    bram_sdp #(
        .Width(Width),
        .Depth(Depth),
        .Block(k == 1)
    ) u_rtl (
        .clk  (clk),
        .we   (we),
        .wlane(wlane),
        .widx (widx),
        .wdata(wdata),
        .re   (re),
        .ridx (ridx),
        .rdata(rtl_rdata)
    );

    // Sby swaps bram_watch
    bram_sdp #(
        .Width(Width),
        .Depth(Depth),
        .Block(k == 1)
    ) u_watch (
        .clk  (clk),
        .we   (we),
        .wlane(wlane),
        .widx (widx),
        .wdata(wdata),
        .re   (re),
        .ridx (ridx),
        .rdata(watch_rdata)
    );

    always @(posedge clk) begin
      if (f_valid) assert (watch_rdata == rtl_rdata);
      cover (f_valid && rtl_rdata[Width-1] && rtl_rdata[0]);
    end
  end

endmodule

`default_nettype wire
