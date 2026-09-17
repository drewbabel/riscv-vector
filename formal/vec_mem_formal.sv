`default_nettype none

module vec_mem_formal ();

  localparam int VLEN = 128;

  logic            clk;

  // Free issue stimulus
  (* anyseq *)logic            core_en;
  (* anyseq *)logic            start;
  (* anyseq *)logic            load;
  (* anyseq *)logic            vm;
  (* anyseq *)logic [     4:0] vd;
  (* anyseq *)logic [     7:0] count;
  (* anyseq *)logic [     1:0] width;
  (* anyseq *)logic [    31:0] base;
  (* anyseq *)logic [    31:0] stride;

  // Free register stimulus
  (* anyseq *)logic [VLEN-1:0] v0;
  (* anyseq *)logic [VLEN-1:0] rdata;

  // Free memory stimulus
  (* anyseq *)logic            mem_ready;
  (* anyseq *)logic [    31:0] mem_rdata;

  logic [     4:0] raddr;
  logic            wen;
  logic [VLEN-1:0] wstrb;
  logic [VLEN-1:0] wdata;
  logic            mem_req;
  logic [    31:0] mem_addr;
  logic [    31:0] mem_wdata;
  logic [     3:0] mem_wstrb;
  logic            busy;
  logic            done;

  logic            rst_n;
  logic [     1:0] t = 2'd0;
  logic            f_past_valid = 1'b0;

  initial assume (t == 2'd0);
  always @(posedge clk) begin
    t <= (t == 2'd3) ? 2'd3 : t + 2'd1;
    f_past_valid <= 1'b1;
  end
  assign rst_n = (t != 2'd0);

  vec_mem #(
      .VLEN(VLEN)
  ) dut (
      .clk(clk),
      .rst_n(rst_n),
      .core_en(core_en),
      .start(start),
      .load(load),
      .vm(vm),
      .vd(vd),
      .count(count),
      .width(width),
      .base(base),
      .stride(stride),
      .v0(v0),
      .rdata(rdata),
      .raddr(raddr),
      .wen(wen),
      .wstrb(wstrb),
      .wdata(wdata),
      .mem_rdata(mem_rdata),
      .mem_ready(mem_ready),
      .mem_req(mem_req),
      .mem_addr(mem_addr),
      .mem_wdata(mem_wdata),
      .mem_wstrb(mem_wstrb),
      .busy(busy),
      .done(done)
  );

  // Instruction tracker
  logic       f_active;
  logic [7:0] f_beats;
  logic [7:0] f_count;

  always @(posedge clk) begin
    if (!rst_n) begin
      f_active <= 1'b0;
      f_beats  <= 8'd0;
    end else if (core_en) begin
      if (!f_active && start) begin
        f_active <= 1'b1;
        f_beats  <= 8'd0;
        f_count  <= count;
      end else if (f_active) begin
        if (mem_req && mem_ready) f_beats <= f_beats + 8'd1;
        if (done) f_active <= 1'b0;
      end
    end
  end

  // Issue contract
  always @(posedge clk)
    if (f_past_valid && $past(rst_n) && rst_n) begin
      if (f_active || $past(start && !core_en)) begin
        assume (load == $past(load));
        assume (vm == $past(vm));
        assume (vd == $past(vd));
        assume (count == $past(count));
        assume (width == $past(width));
        assume (base == $past(base));
        assume (stride == $past(stride));
        assume (v0 == $past(v0));
      end
      if ($past(start && !core_en)) assume (start);
      if (raddr == $past(raddr) && !$past(wen && core_en)) assume (rdata == $past(rdata));
    end

  always @(posedge clk)
    if (rst_n) begin
      if (f_active) assume (!start);
      assume (width != 2'd3);
      if (width == 2'd0) assume (count <= 8'd128);
      if (width == 2'd1) assume (count <= 8'd64);
      if (width == 2'd2) assume (count <= 8'd32);
    end

  // Handshake safety
  always @(posedge clk)
    if (f_past_valid && $past(rst_n) && rst_n) begin
      if ($past(mem_req) && !$past(mem_ready && core_en)) begin
        assert (mem_req);
        assert (mem_addr == $past(mem_addr));
        assert (mem_wstrb == $past(mem_wstrb));
        if (mem_wstrb != 4'h0) assert (mem_wdata == $past(mem_wdata));
      end
      if (!$past(core_en)) assert (done == $past(done));
    end

  // Beat accounting
  always @(posedge clk)
    if (rst_n) begin
      assert (!mem_req || f_active);
      assert (f_beats <= f_count || !f_active);
      if (done) assert (f_active && f_beats == f_count);
      if (f_active && f_beats == f_count) assert (!mem_req);
      assert (mem_addr[1:0] == 2'b00);
      if (load) assert (mem_wstrb == 4'h0);
      if (wen) assert (load && mem_req && mem_ready);
    end

  // Covers
  always @(posedge clk)
    if (rst_n && core_en) begin
      cover (done && f_count == 8'd0);
      cover (done && f_count == 8'd3 && !load && !vm);
      cover (done && f_count == 8'd4 && load && width == 2'd2);
      cover (mem_req && !mem_ready && $past(mem_req) && !$past(core_en));
    end

endmodule

`default_nettype wire
