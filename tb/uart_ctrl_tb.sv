`default_nettype none

module uart_ctrl_tb ();

  localparam int Xlen = arch_pkg::XLEN;
  localparam int TagW = $bits(arch_pkg::UartTag);
  localparam int WordBytes = Xlen / 8;
  localparam logic [Xlen-1:0] UartBase = {arch_pkg::UartTag, (Xlen - TagW)'(0)};
  localparam logic [Xlen-1:0] TxDataAddr = UartBase + Xlen'(0 * WordBytes);
  localparam logic [Xlen-1:0] StatusAddr = UartBase + Xlen'(1 * WordBytes);
  localparam logic [Xlen-1:0] RxDataAddr = UartBase + Xlen'(2 * WordBytes);
  localparam logic [Xlen-1:0] CtrlAddr = UartBase + Xlen'(3 * WordBytes);
  localparam logic [7:0] DataMask = 8'((1 << arch_pkg::UartDataBits) - 1);
  localparam int MinChecks = 12022;

  int                checks = 0;
  int                errors = 0;
  int                max_errors = 0;

  logic              clk = 1'b0;
  logic              rst_n;
  logic              core_en = 1'b1;
  logic              sel;
  logic              req;
  logic [Xlen/8-1:0] wstrb;
  logic [  Xlen-1:0] addr;
  logic [  Xlen-1:0] wdata;
  logic [  Xlen-1:0] rdata;
  logic              rx_valid;
  logic [       7:0] rx_data;
  logic              tx_ready;
  logic              tx_valid;
  logic [       7:0] tx_data;
  logic              irq;

  always #5 clk = ~clk;

  uart_ctrl #(
      .XLEN(Xlen)
  ) dut (
      .clk     (clk),
      .core_en (core_en),
      .rst_n   (rst_n),
      .sel     (sel),
      .req     (req),
      .wstrb   (wstrb),
      .addr    (addr),
      .wdata   (wdata),
      .rdata   (rdata),
      .rx_valid(rx_valid),
      .rx_data (rx_data),
      .tx_ready(tx_ready),
      .tx_valid(tx_valid),
      .tx_data (tx_data),
      .irq     (irq)
  );

  task automatic check(input string name, input logic [Xlen-1:0] got, input logic [Xlen-1:0] exp);
    checks++;
    if (got !== exp) begin
      errors++;
      $display("FAIL %s: got %h, expected %h", name, got, exp);
      if (errors == max_errors) $fatal(1, "TB STOPPED: %0d mismatches", errors);
    end
  endtask  // Automatic

  task automatic do_reset();
    rst_n = 1'b0;
    sel = 1'b0;
    req = 1'b0;
    wstrb = '0;
    addr = '0;
    wdata = '0;
    rx_valid = 1'b0;
    rx_data = '0;
    tx_ready = 1'b1;
    repeat (2) @(posedge clk);
    @(negedge clk);
    rst_n = 1'b1;
  endtask  // Automatic

  task automatic bus_write(input logic [Xlen-1:0] a, input logic [Xlen-1:0] d);
    @(negedge clk);
    sel   = 1'b1;
    req   = 1'b1;
    addr  = a;
    wdata = d;
    wstrb = '1;
    @(negedge clk);
    sel   = 1'b0;
    req   = 1'b0;
    wstrb = '0;
  endtask  // Automatic

  task automatic bus_read(input logic [Xlen-1:0] a, output logic [Xlen-1:0] d);
    @(negedge clk);
    sel   = 1'b1;
    req   = 1'b1;
    addr  = a;
    wstrb = '0;
    @(posedge clk);
    d = rdata;
    @(negedge clk);
    sel = 1'b0;
    req = 1'b0;
  endtask  // Automatic

  task automatic peek(input logic [Xlen-1:0] a, output logic [Xlen-1:0] d);
    @(negedge clk);
    sel   = 1'b1;
    req   = 1'b0;
    addr  = a;
    wstrb = '0;
    @(posedge clk);
    d = rdata;
    @(negedge clk);
    sel = 1'b0;
  endtask  // Automatic

  task automatic arrive(input logic [7:0] b);
    @(negedge clk);
    rx_valid = 1'b1;
    rx_data  = b;
    @(negedge clk);
    rx_valid = 1'b0;
  endtask  // Automatic

  task automatic tx_store(input logic [7:0] b);
    @(negedge clk);
    sel   = 1'b1;
    req   = 1'b1;
    addr  = TxDataAddr;
    wdata = Xlen'(b);
    wstrb = '1;
    @(posedge clk);
    check("tx_valid", Xlen'(tx_valid), Xlen'(1'b1));
    check("tx_data", Xlen'(tx_data), Xlen'(b & DataMask));
    @(negedge clk);
    sel   = 1'b0;
    req   = 1'b0;
    wstrb = '0;
    @(posedge clk);
    check("tx_valid_clear", Xlen'(tx_valid), Xlen'(1'b0));
  endtask  // Automatic

  task automatic take_during_arrival(input logic [7:0] b);
    @(negedge clk);
    sel      = 1'b1;
    req      = 1'b1;
    addr     = RxDataAddr;
    wstrb    = '0;
    rx_valid = 1'b1;
    rx_data  = b;
    @(negedge clk);
    sel      = 1'b0;
    req      = 1'b0;
    rx_valid = 1'b0;
  endtask  // Automatic

  task automatic check_peek(input string name, input logic [Xlen-1:0] a,
                            input logic [Xlen-1:0] exp);
    logic [Xlen-1:0] got;
    peek(a, got);
    check(name, got, exp);
  endtask  // Automatic

  task automatic check_read(input string name, input logic [Xlen-1:0] a,
                            input logic [Xlen-1:0] exp);
    logic [Xlen-1:0] got;
    bus_read(a, got);
    check(name, got, exp);
  endtask  // Automatic

  task automatic check_irq(input string name, input logic exp);
    check(name, Xlen'(irq), Xlen'(exp));
  endtask  // Automatic

  task automatic test_reset();
    check_peek("status_reset", StatusAddr, Xlen'('b001));
    check_irq("irq_reset", 1'b0);
  endtask  // Automatic

  task automatic test_rx_irq();
    arrive(8'h5A);
    check_peek("status_full", StatusAddr, Xlen'('b011));
    check_irq("irq_masked", 1'b0);
    bus_write(CtrlAddr, Xlen'(1));
    check_peek("ctrl_readback", CtrlAddr, Xlen'(1));
    check_irq("irq_raised", 1'b1);
  endtask  // Automatic

  task automatic test_overrun();
    arrive(8'h77);
    check_peek("status_overrun", StatusAddr, Xlen'('b111));
    check_read("rx_byte", RxDataAddr, Xlen'(8'h5A & DataMask));
    check_irq("irq_cleared", 1'b0);
    check_peek("status_empty", StatusAddr, Xlen'('b001));
  endtask  // Automatic

  task automatic test_status_read();
    arrive(8'h2B);
    check_peek("status_full_again", StatusAddr, Xlen'('b011));
    check_read("status_read", StatusAddr, Xlen'('b011));
    check_irq("irq_held", 1'b1);
    check_read("rx_byte_again", RxDataAddr, Xlen'(8'h2B & DataMask));
    check_irq("irq_cleared_again", 1'b0);
  endtask  // Automatic

  task automatic test_take_race();
    take_during_arrival(8'h99);
    check_peek("status_race_full", StatusAddr, Xlen'('b011));
    check_read("rx_byte_race", RxDataAddr, Xlen'(8'h99 & DataMask));
  endtask  // Automatic

  task automatic test_take_when_full();
    arrive(8'h33);
    take_during_arrival(8'h44);
    check_peek("status_take_full", StatusAddr, Xlen'('b011));
    check_read("rx_byte_take_full", RxDataAddr, Xlen'(8'h44 & DataMask));
  endtask  // Automatic

  task automatic soak(input int n);
    logic [7:0] m_byte;
    logic m_full, m_ovr, m_ie, take;
    logic [1:0] off;
    logic [Xlen-1:0] exp;
    bus_read(RxDataAddr, exp);
    bus_write(CtrlAddr, Xlen'(0));
    m_byte = exp[7:0];
    m_full = 1'b0;
    m_ovr  = 1'b0;
    m_ie   = 1'b0;
    repeat (n) begin
      @(negedge clk);
      rst_n    = $urandom_range(63) != 0;
      core_en  = $urandom_range(3) != 0;
      sel      = $urandom_range(3) != 0;
      req      = 1'($urandom);
      wstrb    = ($urandom_range(2) == 0) ? '0 : (Xlen / 8)'($urandom);
      off      = 2'($urandom);
      addr     = (Xlen'($urandom) & ~Xlen'(3 * WordBytes)) | Xlen'(off * WordBytes);
      wdata    = Xlen'($urandom);
      rx_valid = $urandom_range(3) == 0;
      rx_data  = 8'($urandom);
      tx_ready = 1'($urandom);
      #1;
      case (off)
        2'd1: exp = Xlen'({m_ovr, m_full, tx_ready});
        2'd2: exp = Xlen'(m_byte);
        2'd3: exp = Xlen'(m_ie);
        default: exp = Xlen'(tx_ready);
      endcase
      check("soak rdata", rdata, exp);
      check("soak tx_valid", Xlen'(tx_valid), Xlen'(core_en && sel && |wstrb && off == 2'd0));
      check("soak tx_data", Xlen'(tx_data), Xlen'(wdata[7:0] & DataMask));
      check("soak irq", Xlen'(irq), Xlen'(m_full && m_ie));
      take = core_en && sel && req && !(|wstrb) && off == 2'd2;
      if (!rst_n) begin
        m_byte = '0;
        m_full = 1'b0;
        m_ovr  = 1'b0;
        m_ie   = 1'b0;
      end else if (core_en) begin
        if (rx_valid && (!m_full || take)) m_byte = rx_data & DataMask;
        if (rx_valid && m_full && !take) m_ovr = 1'b1;
        else if (take) m_ovr = 1'b0;
        if (rx_valid) m_full = 1'b1;
        else if (take) m_full = 1'b0;
        if (sel && |wstrb && off == 2'd3) m_ie = wdata[0];
      end
    end
    @(negedge clk);
    rst_n    = 1'b1;
    core_en  = 1'b1;
    sel      = 1'b0;
    req      = 1'b0;
    wstrb    = '0;
    rx_valid = 1'b0;
  endtask  // Automatic

  task automatic do_verdict();
    if (checks < MinChecks)
      $fatal(1, "TB UNDER-RAN: %0d checks, expected at least %0d", checks, MinChecks);
    if (errors == 0) $display("PASS: %0d checks, %0d mismatches", checks, errors);
    else $fatal(1, "FAIL: %0d mismatches, %0d checks", errors, checks);
    $finish;
  endtask  // Automatic

  initial void'($value$plusargs("max_errors=%d", max_errors));

  initial begin
    $dumpfile("uart_ctrl_tb.vcd");
    $dumpvars(0, uart_ctrl_tb);
    do_reset();
    test_reset();
    tx_store(8'h41);
    test_rx_irq();
    test_overrun();
    test_status_read();
    test_take_race();
    test_take_when_full();
    soak(3000);
    do_verdict();
  end

endmodule

`default_nettype wire
