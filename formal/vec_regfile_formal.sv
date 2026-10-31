`default_nettype none

module vec_regfile_formal ();

  localparam int AWIDTH = arch_pkg::RegAddrW;
  localparam int VLEN   = arch_pkg::VLEN;

  logic              clk;

  (* anyconst *)logic [AWIDTH-1:0] f_addr;

  (* anyseq *)logic              core_en;
  (* anyseq *)logic              we;
  (* anyseq *)logic [  VLEN-1:0] wstrb;
  (* anyseq *)logic [AWIDTH-1:0] waddr;
  (* anyseq *)logic [  VLEN-1:0] wdata;
  (* anyseq *)logic [AWIDTH-1:0] raddr2;
  (* anyseq *)logic [AWIDTH-1:0] raddr3;

  logic [AWIDTH-1:0] raddr1;
  logic [  VLEN-1:0] rdata1;
  logic [  VLEN-1:0] rdata2;
  logic [  VLEN-1:0] rdata3;
  logic [  VLEN-1:0] rdata0;

  // Port one watches
  assign raddr1 = f_addr;

  logic f_past_valid = 1'b0;
  always @(posedge clk) f_past_valid <= 1'b1;

  vec_regfile #(
      .AWIDTH(AWIDTH),
      .VLEN  (VLEN)
  ) dut (
      .clk(clk),
      .core_en(core_en),
      .we(we),
      .wstrb(wstrb),
      .waddr(waddr),
      .wdata(wdata),
      .raddr1(raddr1),
      .raddr2(raddr2),
      .raddr3(raddr3),
      .rdata1(rdata1),
      .rdata2(rdata2),
      .rdata3(rdata3),
      .rdata0(rdata0)
  );

  // Last write
  logic [VLEN-1:0] f_val = '0;
  logic [VLEN-1:0] f_v0 = '0;

  always @(posedge clk)
    if (core_en && we) begin
      if (waddr == f_addr) f_val <= (f_val & ~wstrb) | (wdata & wstrb);
      if (waddr == '0) f_v0 <= (f_v0 & ~wstrb) | (wdata & wstrb);
    end

  always @(posedge clk) begin
    assert (rdata1 == f_val);
    assert (rdata0 == f_v0);
    if (raddr2 == f_addr) assert (rdata2 == f_val);
    if (raddr3 == f_addr) assert (rdata3 == f_val);
  end

  // Covers
  always @(posedge clk)
    if (f_past_valid) begin
      cover (rdata1 != '0 && $past(core_en && we && waddr == f_addr && wstrb == '1));
      cover (rdata1[0] && !rdata1[VLEN-1] && $past(
          core_en && we && waddr == f_addr && wdata == '1 && wstrb == VLEN'(1)
      ));
      cover (we && waddr == f_addr && wdata != f_val && rdata1 == f_val && wstrb == '1);
      cover (raddr3 == f_addr && f_addr != '0 && rdata3 != '0 && rdata0 != '0);
      cover (rdata1 == f_val && $past(
          !core_en && we && waddr == f_addr && wstrb == '1 && wdata != f_val
      ));
    end

endmodule

`default_nettype wire
