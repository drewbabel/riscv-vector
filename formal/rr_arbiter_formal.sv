`default_nettype none

module rr_arbiter_formal ();

  localparam int N = 4;
  localparam int CtrW = $clog2(N + 1);

  logic         clk;

  (* anyseq *)logic         core_en;
  (* anyseq *)logic [N-1:0] req;
  (* anyseq *)logic         hold;

  logic [N-1:0] grant;
  logic         grant_valid;

  logic         rst_n;
  logic [  1:0] t = 2'd0;
  logic         f_past_valid = 1'b0;

  initial assume (t == 2'd0);
  always @(posedge clk) begin
    t <= (t == 2'd3) ? 2'd3 : t + 2'd1;
    f_past_valid <= 1'b1;
  end
  assign rst_n = (t != 2'd0);

  rr_arbiter #(
      .N(N)
  ) dut (
      .clk(clk),
      .rst_n(rst_n),
      .core_en(core_en),
      .req(req),
      .hold(hold),
      .grant(grant),
      .grant_valid(grant_valid)
  );

  // Locked grant
  logic         f_lock;
  logic [N-1:0] f_owner;

  always @(posedge clk) begin
    if (!rst_n) begin
      f_lock <= 1'b0;
    end else if (core_en) begin
      if (grant_valid) f_lock <= hold;
      if (!f_lock) f_owner <= grant;
    end
  end

  // Holder keeps request
  always @(posedge clk) if (rst_n && f_lock) assume ((req & f_owner) != '0);

  // Arbitration waits
  logic [CtrW-1:0] f_wait[N];

  for (genvar i = 0; i < N; i++) begin : g_wait
    always @(posedge clk) begin
      if (!rst_n) f_wait[i] <= '0;
      else if (core_en) begin
        if (!req[i] || grant[i]) f_wait[i] <= '0;
        else if (!f_lock) f_wait[i] <= f_wait[i] + 1'b1;
      end
    end
  end

  always @(posedge clk)
    if (rst_n) begin
      assert ((grant & (grant - 1'b1)) == '0);
      assert ((grant & ~req) == '0);
      assert (grant_valid == (grant != '0));
      for (int i = 0; i < N; i++) assert (f_wait[i] <= CtrW'(N - 1));
    end

  // Covers
  always @(posedge clk)
    if (rst_n && core_en) begin
      for (int i = 0; i < N; i++) cover (grant[i] && f_wait[i] == CtrW'(N - 1));
      cover (f_lock && req == '1 && $past(f_lock) && $past(f_lock, 2));
      cover (grant[0] && f_wait[0] == CtrW'(N - 1) && $past(f_lock));
      cover (req == '1 && grant[N-1] && $past(grant[N-1]) && $past(!f_lock));
    end

endmodule

`default_nettype wire
