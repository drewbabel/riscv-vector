`default_nettype none

module vec_regfile_tb ();

  localparam int AWIDTH = 5;
  localparam int VLEN = 128;
  localparam int Depth = 2 ** AWIDTH;

  int checks = 0;
  int errors = 0;

  logic clk = 1'b0;
  logic core_en;
  logic we;
  logic [VLEN-1:0] wstrb;
  logic [AWIDTH-1:0] waddr;
  logic [VLEN-1:0] wdata;
  logic [AWIDTH-1:0] raddr1;
  logic [AWIDTH-1:0] raddr2;
  logic [AWIDTH-1:0] raddr3;
  logic [VLEN-1:0] rdata1;
  logic [VLEN-1:0] rdata2;
  logic [VLEN-1:0] rdata3;
  logic [VLEN-1:0] rdata0;

  logic [VLEN-1:0] shadow[Depth];

  always #5 clk = ~clk;

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

  // Reference model
  task automatic model_write(input logic [AWIDTH-1:0] addr, input logic [VLEN-1:0] data,
                             input logic [VLEN-1:0] strb);
    for (int b = 0; b < VLEN; b++) if (strb[b]) shadow[addr][b] = data[b];
  endtask

  task automatic init_signals();
    core_en = 1'b1;
    we      = 1'b0;
    wstrb   = '0;
    waddr   = '0;
    wdata   = '0;
    raddr1  = '0;
    raddr2  = '0;
    raddr3  = '0;
    for (int i = 0; i < Depth; i++) shadow[i] = '0;
  endtask

  // Stimulus
  task automatic drive_write(input logic [AWIDTH-1:0] addr, input logic [VLEN-1:0] data,
                             input logic [VLEN-1:0] strb, input logic en, input logic wen);
    #1;
    core_en = en;
    waddr   = addr;
    wdata   = data;
    wstrb   = strb;
    we      = wen;
    @(posedge clk);
    if (en && wen) model_write(addr, data, strb);
    @(negedge clk);
    we      = 1'b0;
    wstrb   = '0;
    core_en = 1'b1;
  endtask

  task automatic write_full(input logic [AWIDTH-1:0] addr, input logic [VLEN-1:0] data);
    drive_write(addr, data, '1, 1'b1, 1'b1);
  endtask

  task automatic write_masked(input logic [AWIDTH-1:0] addr, input logic [VLEN-1:0] data,
                              input logic [VLEN-1:0] strb);
    drive_write(addr, data, strb, 1'b1, 1'b1);
  endtask

  task automatic write_core_off(input logic [AWIDTH-1:0] addr, input logic [VLEN-1:0] data);
    drive_write(addr, data, '1, 1'b0, 1'b1);
  endtask

  task automatic write_we_off(input logic [AWIDTH-1:0] addr, input logic [VLEN-1:0] data);
    drive_write(addr, data, '1, 1'b1, 1'b0);
  endtask

  // Checks
  task automatic check_one(input logic [AWIDTH-1:0] addr, input logic [VLEN-1:0] got,
                           input string port);
    checks++;
    if (got !== shadow[addr]) begin
      errors++;
      $display("FAIL %s addr=%0d got=%h exp=%h at %0t", port, addr, got, shadow[addr], $time);
    end
  endtask

  task automatic check_reads(input logic [AWIDTH-1:0] a1, input logic [AWIDTH-1:0] a2,
                             input logic [AWIDTH-1:0] a3);
    #1;
    raddr1 = a1;
    raddr2 = a2;
    raddr3 = a3;
    #1;
    check_one(a1, rdata1, "rdata1");
    check_one(a2, rdata2, "rdata2");
    check_one(a3, rdata3, "rdata3");
  endtask

  task automatic check_all();
    for (int i = 0; i < Depth; i++) check_reads(AWIDTH'(i), AWIDTH'(i), AWIDTH'(i));
  endtask

  task automatic check_field(input logic [AWIDTH-1:0] addr, input int lo, input logic [3:0] exp);
    #1;
    raddr1 = addr;
    #1;
    checks++;
    if (rdata1[lo+:4] !== exp) begin
      errors++;
      $display("FAIL field addr=%0d lo=%0d got=%b exp=%b at %0t", addr, lo, rdata1[lo+:4], exp,
               $time);
    end
  endtask

  task automatic check_read_first(input logic [AWIDTH-1:0] addr, input logic [VLEN-1:0] data);
    logic [VLEN-1:0] prev;
    write_full(addr, ~data);
    prev = shadow[addr];
    #1;
    raddr1 = addr;
    waddr  = addr;
    wdata  = data;
    wstrb  = '1;
    we     = 1'b1;
    #1;
    checks++;
    if (rdata1 !== prev) begin
      errors++;
      $display("FAIL read first addr=%0d got=%h exp=%h at %0t", addr, rdata1, prev, $time);
    end
    @(posedge clk);
    model_write(addr, data, '1);
    @(negedge clk);
    we    = 1'b0;
    wstrb = '0;
    check_reads(addr, addr, addr);
  endtask

  task automatic soak(input int n);
    logic [VLEN-1:0] data;
    logic [VLEN-1:0] strb;
    for (int i = 0; i < n; i++) begin
      data = {$urandom, $urandom, $urandom, $urandom};
      strb = {$urandom, $urandom, $urandom, $urandom};
      write_masked(AWIDTH'($urandom), data, strb);
      check_reads(AWIDTH'($urandom), AWIDTH'($urandom), AWIDTH'($urandom));
    end
  endtask

  task automatic verdict();
    $display("checks=%0d errors=%0d", checks, errors);
    if (errors == 0) $display("PASS");
    else $display("FAIL");
    $finish;
  endtask

  initial begin
    $dumpfile("vec_regfile_tb.vcd");
    $dumpvars(0, vec_regfile_tb);

    init_signals();
    @(negedge clk);

    // Zero at startup
    check_all();

    // Full width write
    write_full(5, {4{32'hDEAD_BEEF}});
    check_reads(5, 5, 5);

    // v0 holds data
    write_full(0, {4{32'hA5A5_5A5A}});
    check_reads(0, 0, 0);

    // Three ports differ
    write_full(7, {4{32'h0000_0007}});
    write_full(9, {4{32'h0000_0009}});
    check_reads(5, 7, 9);

    // Byte strobe
    write_full(12, '1);
    write_masked(12, '0, {{VLEN - 8{1'b0}}, 8'hFF});
    check_reads(12, 12, 12);

    // Single bit strobe
    write_full(13, '1);
    write_masked(13, '0, {{VLEN - 4{1'b0}}, 4'b0010});
    check_reads(13, 13, 13);
    check_field(13, 0, 4'b1101);

    // Read before write
    check_read_first(17, {4{32'h2222_2222}});

    // Core disabled
    write_core_off(21, '1);
    check_reads(21, 21, 21);

    // Strobe without we
    write_we_off(25, '1);
    check_reads(25, 25, 25);

    // Randomized soak
    soak(2000);

    verdict();
  end

endmodule

`default_nettype wire
