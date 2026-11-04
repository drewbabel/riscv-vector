`default_nettype none

module vec_mem_data_formal ();

  localparam int XLEN = arch_pkg::XLEN;
  localparam int AWIDTH = arch_pkg::RegAddrW;
  localparam int VLEN = arch_pkg::VLEN;
  localparam int VlW = $clog2(VLEN + 1);
  localparam int Bytes = VLEN / 8;
  localparam int OffW = $clog2(Bytes);
  localparam int BitW = $clog2(VLEN);

  logic              clk;

  // Watched byte
  (* anyconst *)logic [  XLEN-1:0] f_addr;
  (* anyconst *)logic [       7:0] f_init;
  (* anyconst *)logic [   VlW-1:0] f_e;
  (* anyconst *)logic [       1:0] f_b;

  // Free issue stimulus
  (* anyseq *)logic              core_en;
  (* anyseq *)logic              start;
  (* anyseq *)logic              load;
  (* anyseq *)logic              vm;
  (* anyseq *)logic [AWIDTH-1:0] vd;
  (* anyseq *)logic [   VlW-1:0] count;
  (* anyseq *)logic [       1:0] width;
  (* anyseq *)logic [  XLEN-1:0] base;
  (* anyseq *)logic [  XLEN-1:0] stride;

  // Free register stimulus
  (* anyseq *)logic [  VLEN-1:0] v0;
  (* anyseq *)logic [  VLEN-1:0] rdata;
  (* anyseq *)logic [       7:0] f_rv_in;

  // Free memory stimulus
  (* anyseq *)logic              mem_ready;
  (* anyseq *)logic [  VLEN-1:0] mem_rdata;

  logic [AWIDTH-1:0] raddr;
  logic              wen;
  logic [  VLEN-1:0] wstrb;
  logic [  VLEN-1:0] wdata;
  logic              mem_req;
  logic [  XLEN-1:0] mem_addr;
  logic [  VLEN-1:0] mem_wdata;
  logic [ Bytes-1:0] mem_wstrb;
  logic [   VlW-1:0] dbg_elem;
  logic              dbg_n_ok;
  logic              busy;
  logic              done;

  logic              rst_n;
  logic [       1:0] t = 2'd0;
  logic              f_past_valid = 1'b0;

  initial assume (t == 2'd0);
  always @(posedge clk) begin
    t <= (t == 2'd3) ? 2'd3 : t + 2'd1;
    f_past_valid <= 1'b1;
  end
  assign rst_n = (t != 2'd0);

  vec_mem #(
      .XLEN  (XLEN),
      .AWIDTH(AWIDTH),
      .VLEN  (VLEN)
  ) dut (
      .dbg_elem(dbg_elem),
      .dbg_n_ok(dbg_n_ok),
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
      .reg_done(),
      .busy(busy),
      .done(done)
  );

  // Watched element
  logic [  XLEN-1:0] esize;
  logic              unit;
  logic [  XLEN-1:0] pos;
  logic [AWIDTH-1:0] f_reg;
  logic [  OffW-1:0] f_rb;
  logic [  XLEN-1:0] f_ua;
  logic              live;

  assign esize = XLEN'(1) << width;
  assign unit  = (stride == esize);
  assign pos   = (XLEN'(f_e) << width) + XLEN'(f_b);
  assign f_reg = vd + AWIDTH'(pos >> OffW);
  assign f_rb  = pos[OffW-1:0];
  assign f_ua  = base + pos;
  assign live  = (f_e < count) && (XLEN'(f_b) < esize) && (vm || v0[BitW'(f_e)]);

  // Instruction tracker
  logic            f_active;
  logic            f_take;
  logic            f_hs;
  logic [ VlW-1:0] f_k;
  logic [XLEN-1:0] f_cur;
  logic [     7:0] f_rv;
  logic            f_got;
  logic            f_put;
  logic            f_sa;
  logic            f_stored;

  assign f_take = rst_n && core_en && !f_active && start;
  assign f_hs   = rst_n && core_en && f_active && mem_req && mem_ready;

  // Strided element address
  logic f_on;
  assign f_on = (XLEN'(f_b) < esize) &&
      (unit ? (f_ua == f_addr) : ((f_k == f_e) && (f_cur + XLEN'(f_b) == f_addr)));

  // Watched register byte
  logic f_wr;
  assign f_wr = core_en && wen && (raddr == f_reg) && wstrb[8*f_rb] && (pos < XLEN'(VLEN)) &&
      (XLEN'(f_b) < esize);

  // Watched memory byte
  logic       f_line;
  logic [7:0] f_mem;
  logic       f_st;
  assign f_line = mem_addr[XLEN-1:OffW] == f_addr[XLEN-1:OffW];
  assign f_st   = f_hs && !load && f_line && mem_wstrb[f_addr[OffW-1:0]];

  always @(posedge clk) begin
    if (!rst_n) begin
      f_active <= 1'b0;
      f_stored <= 1'b0;
      f_mem    <= f_init;
    end else if (core_en) begin
      if (f_take) begin
        f_active <= 1'b1;
        f_k      <= '0;
        f_cur    <= base;
        f_rv     <= f_rv_in;
        f_got    <= 1'b0;
        f_put    <= 1'b0;
        f_sa     <= 1'b0;
      end else if (f_active) begin
        if (f_hs) begin
          f_k   <= f_k + VlW'(1);
          f_cur <= f_cur + stride;
          if (f_on && !load && !unit) f_sa <= 1'b1;
        end
        if (f_wr) f_got <= 1'b1;
        if (f_st && f_on) f_put <= 1'b1;
        if (done) f_active <= 1'b0;
        if (done && !load && f_put) f_stored <= 1'b1;
      end
      if (f_st) f_mem <= mem_wdata[8*f_addr[OffW-1:0]+:8];
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
    end

  always @(posedge clk)
    if (rst_n) begin
      if (f_active) assume (!start);
      assume (width != 2'd3);
      if (width == 2'd0) assume (count <= VlW'(VLEN));
      if (width == 2'd1) assume (count <= VlW'(VLEN / 2));
      if (width == 2'd2) assume (count <= VlW'(VLEN / 4));
      if (width == 2'd2) assume (base[1:0] == 2'b00 && stride[1:0] == 2'b00);
      if (width == 2'd1) assume (!base[0] && !stride[0]);
    end

  // Memory and registers
  always @(posedge clk)
    if (rst_n && f_active) begin
      if (mem_req && load && f_line) assume (mem_rdata[8*f_addr[OffW-1:0]+:8] == f_mem);
      if (!load && raddr == f_reg) assume (rdata[8*f_rb+:8] == f_rv);
    end

  // Walk position
  always @(posedge clk)
    if (rst_n && f_active && busy) begin
      if (unit) begin
        assert (mem_addr == base + (XLEN'(dbg_elem) << width));
      end else begin
        assert (mem_addr == f_cur && dbg_elem == f_k);
      end
    end

  // Tracker matches unit
  always @(posedge clk)
    if (rst_n) begin
      assert (f_active == (busy || done));
      assert (!(busy && done));
      if (busy) assert (dbg_elem < count);
      if (f_active && width == 2'd2) assert (f_cur[1:0] == 2'b00 && mem_addr[1:0] == 2'b00);
      if (f_active && width == 2'd1) assert (!f_cur[0] && !mem_addr[0]);
      assert (dbg_n_ok);
      if (f_active) assert (dbg_elem <= count);
      if (f_active && !done && f_e >= dbg_elem) assert (!f_got && !f_put && !f_sa);
      if (f_active && done) assert (dbg_elem == count);
      if (f_active && load && live && f_e < dbg_elem) assert (f_got);
      if (f_active && !load && live && unit && f_on && f_e < dbg_elem) assert (f_put);
      if (f_active && !load && live && !unit && f_sa) assert (f_put);
      if (f_active && f_put) assert (live && (unit ? f_on : f_sa));
      if (f_active && unit) assert (!f_sa);
      if (f_active && f_got) assert (load);
      if (f_active && (f_put || f_sa)) assert (!load);
    end

  // Load data
  always @(posedge clk)
    if (rst_n) begin
      if (f_wr) begin
        assert (f_active && load && live);
        if (!unit) assert (f_k == f_e);
        if (f_on) assert (wdata[8*f_rb+:8] == f_mem);
      end
      if (done && load && live) assert (f_got || f_wr);
    end

  // Store data
  logic [XLEN-1:0] f_off;
  assign f_off = unit ? (f_addr - base) : (f_addr - f_cur);

  always @(posedge clk)
    if (rst_n) begin
      if (f_st) begin
        if (unit) begin
          assert (f_off < (XLEN'(count) << width));
          assert (vm || v0[BitW'(f_off>>width)]);
        end else begin
          assert (f_off < esize && f_k < count);
          assert (vm || v0[BitW'(f_k)]);
        end
        if (f_on && live) assert (mem_wdata[8*f_addr[OffW-1:0]+:8] == f_rv);
      end
      if (done && !load && live && (unit ? f_on : f_sa)) assert (f_put);
      if (f_active && !load && unit && f_put) assert (f_mem == f_rv);
    end

  // Covers
  always @(posedge clk)
    if (rst_n && core_en) begin
      for (int w = 0; w < 3; w++) begin
        cover (done && load && f_got && f_on && width == 2'(w));
        cover (done && !load && f_put && width == 2'(w));
      end
      cover (f_wr && f_on && f_stored && unit);
      cover (f_wr && f_on && f_stored && !unit && f_e != '0);
      cover (done && load && !unit && f_got && f_e != '0);
      cover (done && load && !vm && !v0[BitW'(f_e)] && f_e < count && !f_got);
    end

endmodule

`default_nettype wire
