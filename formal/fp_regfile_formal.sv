`default_nettype none

module fp_regfile_formal ();

  localparam int AWIDTH = arch_pkg::RegAddrW;
  localparam int FLEN   = fp_pkg::FLEN;

  logic              clk;

  (* anyconst *)logic [AWIDTH-1:0] f_addr;

  (* anyseq *)logic              core_en;
  (* anyseq *)logic              we;
  (* anyseq *)logic [AWIDTH-1:0] waddr;
  (* anyseq *)logic [  FLEN-1:0] wdata;
  (* anyseq *)logic              we2;
  (* anyseq *)logic [AWIDTH-1:0] waddr2;
  (* anyseq *)logic [  FLEN-1:0] wdata2;
  (* anyseq *)logic [AWIDTH-1:0] raddr2;
  (* anyseq *)logic [AWIDTH-1:0] raddr3;

  logic [AWIDTH-1:0] raddr1;
  logic [  FLEN-1:0] rdata1;
  logic [  FLEN-1:0] rdata2;
  logic [  FLEN-1:0] rdata3;

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

  fp_regfile #(
      .AWIDTH(AWIDTH),
      .FLEN  (FLEN)
  ) dut (
      .clk(clk),
      .core_en(core_en),
      .rst_n(rst_n),
      .we(we),
      .waddr(waddr),
      .wdata(wdata),
      .we2(we2),
      .waddr2(waddr2),
      .wdata2(wdata2),
      .raddr1(raddr1),
      .raddr2(raddr2),
      .raddr3(raddr3),
      .rdata1(rdata1),
      .rdata2(rdata2),
      .rdata3(rdata3)
  );

  // Last write
  logic [FLEN-1:0] f_val;
  logic [FLEN-1:0] f_read;

  always @(posedge clk) begin
    if (!rst_n) f_val <= '0;
    else if (core_en && we2 && waddr2 == f_addr) f_val <= wdata2;
    else if (core_en && we && waddr == f_addr) f_val <= wdata;
  end

  always_comb begin
    if (we2 && waddr2 == f_addr) f_read = wdata2;
    else if (we && waddr == f_addr) f_read = wdata;
    else f_read = f_val;
  end

  always @(posedge clk)
    if (rst_n) begin
      assert (rdata1 == f_read);
      if (raddr2 == f_addr) assert (rdata2 == f_read);
      if (raddr3 == f_addr) assert (rdata3 == f_read);
    end

  // Covers
  always @(posedge clk)
    if (rst_n && f_past_valid) begin
      cover (we && we2 && waddr == f_addr && waddr2 == f_addr && wdata != wdata2 &&
             rdata1 == wdata2);
      cover (we && waddr == f_addr && !(we2 && waddr2 == f_addr) && rdata1 == wdata &&
             wdata != f_val);
      cover (f_val != '0 && $past(
          we && we2 && waddr == f_addr && waddr2 != f_addr
      ) && rdata3 == f_val && raddr3 == f_addr);
      cover (!we && !we2 && $past(!core_en && we && waddr == f_addr && wdata != f_val));
      cover (raddr2 == f_addr && rdata2 != '0 && !we && !we2);
    end

endmodule

`default_nettype wire
