`default_nettype none

module regfile_formal ();

  localparam int AWIDTH = arch_pkg::RegAddrW;
  localparam int XLEN   = arch_pkg::XLEN;

  logic              clk;

  (* anyconst *)logic [AWIDTH-1:0] f_addr;

  (* anyseq *)logic              core_en;
  (* anyseq *)logic              we;
  (* anyseq *)logic [AWIDTH-1:0] waddr;
  (* anyseq *)logic [  XLEN-1:0] wdata;
  (* anyseq *)logic [AWIDTH-1:0] raddr2;

  logic [AWIDTH-1:0] raddr1;
  logic [  XLEN-1:0] rdata1;
  logic [  XLEN-1:0] rdata2;

  // Port one watches
  assign raddr1 = f_addr;

  logic       rst_n;
  logic [1:0] t = 2'd0;
  logic       f_past_valid = 1'b0;

  initial assume (t == 2'd0);
  always @(posedge clk) begin
    t <= (t == 2'd3) ? 2'd3 : t + 2'd1;
    f_past_valid <= 1'b1;
  end
  assign rst_n = (t != 2'd0);

  regfile #(
      .AWIDTH(AWIDTH),
      .XLEN  (XLEN)
  ) dut (
      .clk(clk),
      .core_en(core_en),
      .rst_n(rst_n),
      .we(we),
      .waddr(waddr),
      .wdata(wdata),
      .raddr1(raddr1),
      .raddr2(raddr2),
      .rdata1(rdata1),
      .rdata2(rdata2)
  );

  // Last write
  logic [XLEN-1:0] f_val;
  logic [XLEN-1:0] f_read;

  always @(posedge clk) begin
    if (!rst_n) f_val <= '0;
    else if (core_en && we && waddr == f_addr && f_addr != '0) f_val <= wdata;
  end

  always_comb begin
    if (f_addr == '0) f_read = '0;
    else if (we && waddr == f_addr) f_read = wdata;
    else f_read = f_val;
  end

  always @(posedge clk)
    if (rst_n) begin
      assert (rdata1 == f_read);
      if (raddr2 == f_addr) assert (rdata2 == f_read);
      if (raddr2 == '0) assert (rdata2 == '0);
    end

  // Covers
  always @(posedge clk)
    if (rst_n && f_past_valid) begin
      cover (f_addr != '0 && we && waddr == f_addr && rdata1 == wdata && wdata != f_val);
      cover (f_addr != '0 && f_val != '0 && $past(we && waddr != f_addr) && rdata1 == f_val);
      cover (raddr2 == '0 && we && waddr == '0 && wdata != '0 && rdata2 == '0);
      cover (f_addr != '0 && !we && $past(!core_en && we && waddr == f_addr && wdata != f_val));
      cover (raddr2 == f_addr && f_addr != '0 && rdata2 != '0 && !we);
    end

endmodule

`default_nettype wire
