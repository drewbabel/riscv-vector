`default_nettype none

module vec_busy_bits_formal ();

  localparam int NREGS  = arch_pkg::NumRegs;
  localparam int AddrW  = $clog2(NREGS);
  localparam int CountW = AddrW + 1;

  logic              clk;

  (* anyseq *)logic              core_en;
  (* anyseq *)logic              start;
  (* anyseq *)logic [ AddrW-1:0] vd;
  (* anyseq *)logic [CountW-1:0] vd_regs;
  (* anyseq *)logic [ AddrW-1:0] vs1;
  (* anyseq *)logic [CountW-1:0] vs1_regs;
  (* anyseq *)logic [ AddrW-1:0] vs2;
  (* anyseq *)logic [CountW-1:0] vs2_regs;
  (* anyseq *)logic              masked;
  (* anyseq *)logic              clear;
  (* anyseq *)logic [ AddrW-1:0] clear_addr;

  logic              ready;
  logic              any;

  logic              rst_n;
  logic [       1:0] t = 2'd0;
  logic              f_past_valid = 1'b0;

  initial assume (t == 2'd0);
  always @(posedge clk) begin
    t <= (t == 2'd3) ? 2'd3 : t + 2'd1;
    f_past_valid <= 1'b1;
  end
  assign rst_n = (t != 2'd0);

  vec_busy_bits #(
      .NREGS(NREGS)
  ) dut (
      .clk(clk),
      .rst_n(rst_n),
      .core_en(core_en),
      .start(start),
      .vd(vd),
      .vd_regs(vd_regs),
      .vs1(vs1),
      .vs1_regs(vs1_regs),
      .vs2(vs2),
      .vs2_regs(vs2_regs),
      .masked(masked),
      .clear(clear),
      .clear_addr(clear_addr),
      .ready(ready),
      .any(any)
  );

  function automatic logic in_group(input int r, input logic [AddrW-1:0] base,
                                    input logic [CountW-1:0] regs);
    return (r >= int'(base)) && (r < int'(base) + int'(regs));
  endfunction

  // Issue waits ready
  always @(posedge clk) if (rst_n && start) assume (ready);

  // Busy registers
  logic [NREGS-1:0] f_busy;
  logic [NREGS-1:0] f_dest;
  logic [NREGS-1:0] f_need;

  always_comb begin
    for (int r = 0; r < NREGS; r++) begin
      f_dest[r] = in_group(r, vd, vd_regs);
      f_need[r] = f_dest[r] || in_group(r, vs1, vs1_regs) || in_group(r, vs2, vs2_regs) ||
          (masked && r == 0);
    end
  end

  always @(posedge clk) begin
    for (int r = 0; r < NREGS; r++) begin
      if (!rst_n) f_busy[r] <= 1'b0;
      else if (core_en) begin
        if (start && f_dest[r]) f_busy[r] <= 1'b1;
        else if (clear && clear_addr == AddrW'(r)) f_busy[r] <= 1'b0;
      end
    end
  end

  always @(posedge clk)
    if (rst_n) begin
      assert (ready == ((f_busy & f_need) == '0));
      assert (any == (f_busy != '0));
      assert (!start || (f_busy & f_dest) == '0);
    end

  // Covers
  always @(posedge clk)
    if (rst_n && core_en) begin
      cover (start && vd == AddrW'(8) && vd_regs == CountW'(8) && $past(f_busy[8] && clear));
      cover (!ready && (f_busy & f_dest) == '0 && f_busy[vs1]);
      cover (!ready && masked && f_busy[0] && (f_busy & ~NREGS'(1)) == '0);
      cover (f_busy == '1);
      cover (!any && $past(any && clear) && $past(f_past_valid));
    end

endmodule

`default_nettype wire
