`default_nettype none

module synchronizer_formal ();

  logic clk;

  (* anyseq *)logic core_en;
  (* anyseq *)logic d;

  logic q;

  synchronizer dut (
      .clk(clk),
      .core_en(core_en),
      .d(d),
      .q(q)
  );

  // Enabled samples
  logic       f_s1;
  logic       f_s2;
  logic [1:0] f_edges = 2'd0;
  logic [1:0] f_cycles = 2'd0;

  always @(posedge clk) begin
    if (f_cycles != 2'd3) f_cycles <= f_cycles + 1'b1;
    if (core_en) begin
      f_s1 <= d;
      f_s2 <= f_s1;
      if (f_edges != 2'd2) f_edges <= f_edges + 1'b1;
    end
  end

  always @(posedge clk) begin
    if (f_edges == 2'd2) assert (q == f_s2);
    if (f_cycles >= 2'd2 && $past(core_en) && $past(core_en, 2)) assert (q == $past(d, 2));
    if (f_cycles != 2'd0 && !$past(core_en)) assert (q == $past(q));
  end

  // Covers
  always @(posedge clk)
    if (f_cycles == 2'd3 && f_edges == 2'd2) begin
      cover (q && !$past(q) && $past(d, 2) && !$past(d, 3));
      cover (q && !$past(d) && $past(d, 2) && !$past(d, 3) && !$past(d, 1));
      cover (q && !$past(q) && $past(!core_en, 2) && $past(d, 3) && !$past(d, 2));
    end

endmodule

`default_nettype wire
