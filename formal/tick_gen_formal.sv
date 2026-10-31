`default_nettype none

module tick_gen_formal #(
    parameter int DIVISOR = 4
) ();

  localparam int CntW = $clog2(DIVISOR + 1);

  logic clk;

  (* anyseq *)logic core_en;
  (* anyseq *)logic rst_n;
  (* anyseq *)logic clr;

  logic tick;

  tick_gen #(
      .DIVISOR(DIVISOR)
  ) dut (
      .clk(clk),
      .core_en(core_en),
      .rst_n(rst_n),
      .clr(clr),
      .tick(tick)
  );

  // Edges since tick
  logic [CntW-1:0] f_since = CntW'(DIVISOR - 1);

  always @(posedge clk) begin
    if (!rst_n) f_since <= '0;
    else if (core_en) begin
      if (clr || f_since == CntW'(DIVISOR - 1)) f_since <= '0;
      else f_since <= f_since + 1'b1;
    end
  end

  always @(posedge clk) begin
    assert (f_since <= CntW'(DIVISOR - 1));
    assert (tick == (f_since == CntW'(DIVISOR - 1)));
  end

  // Covers
  logic       f_past_valid = 1'b0;
  logic       f_rst_seen = 1'b0;
  logic       f_clr_seen = 1'b0;
  logic [1:0] f_periods = 2'd0;

  always @(posedge clk) begin
    f_past_valid <= 1'b1;
    if (!rst_n) f_rst_seen <= 1'b1;
    if (rst_n && core_en && clr) f_clr_seen <= 1'b1;
    if (rst_n && core_en && tick && !clr && f_periods != 2'd3) f_periods <= f_periods + 1'b1;
  end

  always @(posedge clk)
    if (f_past_valid) begin
      cover (tick && f_periods == 2'd2);
      cover (tick && f_rst_seen && !f_clr_seen);
      cover (tick && f_clr_seen && !f_rst_seen);
      cover (tick && $past(tick && !core_en));
    end

endmodule

`default_nettype wire
