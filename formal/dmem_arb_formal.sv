`default_nettype none

module dmem_arb_formal ();

  localparam int Xlen = 32;
  localparam int LatMax = 4;
  localparam int WaitMax = 2 * LatMax + 1;
  localparam int CtrW = 5;

  logic clk;

  // Free requester stimulus
  (* anyseq *)logic            core_en;
  (* anyseq *)logic            s_req;
  (* anyseq *)logic [Xlen-1:0] s_addr;
  (* anyseq *)logic [Xlen-1:0] s_wdata;
  (* anyseq *)logic [     3:0] s_wstrb;
  (* anyseq *)logic            v_req;
  (* anyseq *)logic [Xlen-1:0] v_addr;
  (* anyseq *)logic [Xlen-1:0] v_wdata;
  (* anyseq *)logic [     3:0] v_wstrb;

  // Free memory stimulus
  (* anyseq *)logic            ready;

  logic            s_ready;
  logic            v_ready;
  logic            req;
  logic [Xlen-1:0] addr;
  logic [Xlen-1:0] wdata;
  logic [     3:0] wstrb;

  logic            rst_n;
  logic [     1:0] t = 2'd0;
  logic            f_past_valid = 1'b0;

  initial assume (t == 2'd0);
  always @(posedge clk) begin
    t <= (t == 2'd3) ? 2'd3 : t + 2'd1;
    f_past_valid <= 1'b1;
  end
  assign rst_n = (t != 2'd0);

  dmem_arb #(
      .XLEN(Xlen)
  ) dut (
      .clk(clk),
      .rst_n(rst_n),
      .core_en(core_en),
      .s_req(s_req),
      .s_addr(s_addr),
      .s_wdata(s_wdata),
      .s_wstrb(s_wstrb),
      .s_ready(s_ready),
      .v_req(v_req),
      .v_addr(v_addr),
      .v_wdata(v_wdata),
      .v_wstrb(v_wstrb),
      .v_ready(v_ready),
      .req(req),
      .addr(addr),
      .wdata(wdata),
      .wstrb(wstrb),
      .ready(ready)
  );

  // Memory latch model
  logic            m_busy;
  logic [Xlen-1:0] m_addr;
  logic [Xlen-1:0] m_wdata;
  logic [     3:0] m_wstrb;
  logic [CtrW-1:0] m_age;

  always @(posedge clk) begin
    if (!rst_n) begin
      m_busy <= 1'b0;
      m_age  <= '0;
    end else if (core_en) begin
      if (ready) begin
        m_busy <= 1'b0;
        m_age  <= '0;
      end else if (req && !m_busy) begin
        m_busy  <= 1'b1;
        m_addr  <= addr;
        m_wdata <= wdata;
        m_wstrb <= wstrb;
        m_age   <= CtrW'(1);
      end else if (m_busy) begin
        m_age <= m_age + 1'b1;
      end
    end
  end

  // Requester contract
  always @(posedge clk)
    if (f_past_valid && $past(rst_n) && rst_n) begin
      if ($past(s_req) && !$past(s_ready && core_en)) begin
        assume (s_req);
        assume (s_addr == $past(s_addr));
        assume (s_wdata == $past(s_wdata));
        assume (s_wstrb == $past(s_wstrb));
      end
      if ($past(v_req) && !$past(v_ready && core_en)) begin
        assume (v_req);
        assume (v_addr == $past(v_addr));
        assume (v_wdata == $past(v_wdata));
        assume (v_wstrb == $past(v_wstrb));
      end
      if (!$past(core_en)) begin
        assume (s_req == $past(s_req));
        assume (v_req == $past(v_req));
        assume (ready == $past(ready));
      end
    end

  // Memory contract
  always @(posedge clk)
    if (rst_n) begin
      assume (!ready || req);
      assume (m_age <= CtrW'(LatMax));
    end

  // Wait counters
  logic [CtrW-1:0] s_wait;
  logic [CtrW-1:0] v_wait;

  always @(posedge clk) begin
    if (!rst_n) begin
      s_wait <= '0;
      v_wait <= '0;
    end else if (core_en) begin
      s_wait <= (s_req && !s_ready) ? s_wait + 1'b1 : '0;
      v_wait <= (v_req && !v_ready) ? v_wait + 1'b1 : '0;
    end
  end

  // Safety
  always @(posedge clk)
    if (rst_n) begin
      assert (!(s_ready && v_ready));
      assert (!s_ready || s_req);
      assert (!v_ready || v_req);
      if (m_busy) begin
        assert (addr == m_addr);
        assert (wdata == m_wdata);
        assert (wstrb == m_wstrb);
      end
      if (m_busy && s_ready) assert (s_addr == m_addr && s_wstrb == m_wstrb);
      if (m_busy && v_ready) assert (v_addr == m_addr && v_wstrb == m_wstrb);
    end

  // Bounded wait
  always @(posedge clk)
    if (rst_n) begin
      assert (s_wait <= CtrW'(WaitMax));
      assert (v_wait <= CtrW'(WaitMax));
    end

  // Covers
  always @(posedge clk)
    if (rst_n && core_en) begin
      cover (v_ready && s_req && s_wait > 0);
      cover (s_ready && v_req && v_wait > 0);
      cover (m_busy && ready && $past(!core_en));
      cover (v_ready && v_wait == CtrW'(WaitMax));
      cover (s_ready && s_wait == CtrW'(WaitMax));
    end

endmodule

`default_nettype wire
