`default_nettype none

module vec_mem #(
    parameter  int AWIDTH = 5,
    parameter  int VLEN   = 128,
    localparam int Bytes  = VLEN / 8,
    localparam int OffW   = $clog2(Bytes)
) (
`ifdef RISCV_FORMAL
    output logic [7:0] dbg_elem,
    output logic       dbg_n_ok,
`endif
    input  wire        clk,
    input  wire        rst_n,
    input  wire        core_en,

    // Issued instruction
    input wire              start,
    input wire              load,
    input wire              vm,
    input wire [AWIDTH-1:0] vd,
    input wire [       7:0] count,
    input wire [       1:0] width,
    input wire [      31:0] base,
    input wire [      31:0] stride,

    // Register file
    input  wire  [  VLEN-1:0] v0,
    input  wire  [  VLEN-1:0] rdata,
    output logic [AWIDTH-1:0] raddr,
    output logic              wen,
    output logic [  VLEN-1:0] wstrb,
    output logic [  VLEN-1:0] wdata,

    // Memory port
    input  wire  [ VLEN-1:0] mem_rdata,
    input  wire              mem_ready,
    output logic             mem_req,
    output logic [     31:0] mem_addr,
    output logic [ VLEN-1:0] mem_wdata,
    output logic [Bytes-1:0] mem_wstrb,

    output logic reg_done,
    output logic busy,
    output logic done
);

  localparam logic [2:0] OffW3  = 3'(OffW);
  localparam logic [7:0] Bytes8 = 8'(Bytes);

  logic [      7:0] elem;
  logic [     31:0] addr;

  logic             unit;
  logic [ OffW-1:0] reg_off;
  logic [ OffW-1:0] line_off;
  logic [ OffW-1:0] shift;
  logic [      7:0] reg_idx;
  logic [      7:0] left;
  logic [      7:0] fit_line;
  logic [      7:0] fit_reg;
  logic [      7:0] n;
  logic [      7:0] beat_bytes;
  logic [Bytes-1:0] in_beat;
  logic [Bytes-1:0] byte_live;
  logic [Bytes-1:0] reg_mask;
  logic [      7:0] next_elem;

  // Beat geometry
  assign unit = (stride == (32'd1 << width));
  assign reg_idx = elem >> (OffW3 - 3'(width));
  assign reg_off = OffW'(elem << width);
  assign line_off = addr[OffW-1:0];
  assign shift = line_off - reg_off;

  // Next beat position
  logic [ 7:0] elem_d;
  logic [31:0] addr_d;
  logic [ 7:0] n_d;

  assign beat_bytes = n << width;
  assign next_elem = elem + n;
  assign elem_d = busy ? next_elem : 8'd0;
  assign addr_d = busy ? (addr + (unit ? 32'(beat_bytes) : stride)) : base;

  // Elements next beat
  assign left = count - elem_d;
  assign fit_line = (Bytes8 - 8'(addr_d[OffW-1:0])) >> width;
  assign fit_reg = (Bytes8 - 8'(OffW'(elem_d << width))) >> width;
  always_comb begin
    n_d = 8'd1;
    if (unit) begin
      n_d = left;
      if (fit_line < n_d) n_d = fit_line;
      if (fit_reg < n_d) n_d = fit_reg;
    end
  end

  always_ff @(posedge clk) begin
    if (core_en && (busy ? mem_ready : start)) n <= n_d;
  end

  // Register bytes moved
  assign in_beat = Bytes'(((33'd1 << beat_bytes) - 33'd1) << reg_off);
  always_comb begin
    for (int j = 0; j < Bytes; j++) begin
      byte_live[j] = vm || v0[7'((reg_idx<<(OffW3-3'(width)))+(8'(j)>>width))];
    end
  end
  assign reg_mask = in_beat & byte_live;

  // Store beat
  assign raddr = vd + AWIDTH'(reg_idx);
  assign mem_req = busy;
  assign mem_addr = addr;
  assign mem_wdata = (rdata << (8 * shift)) | (rdata >> (8 * (Bytes8 - 8'(shift))));
  assign mem_wstrb = load ? '0 : Bytes'({reg_mask, reg_mask} >> (Bytes8 - 8'(shift)));

  // Load beat
  assign wdata = (mem_rdata >> (8 * shift)) | (mem_rdata << (8 * (Bytes8 - 8'(shift))));
  always_comb begin
    for (int j = 0; j < Bytes; j++) wstrb[j*8+:8] = {8{reg_mask[j]}};
  end
  assign wen = busy && load && mem_ready && (|reg_mask);

  // Register finished
  assign reg_done = busy && load && mem_ready &&
      ((next_elem == count) || ((next_elem >> (OffW3 - 3'(width))) != reg_idx));

  // Walk the beats
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      elem <= 8'd0;
      addr <= 32'h0;
      busy <= 1'b0;
      done <= 1'b0;
    end else if (core_en) begin
      done <= 1'b0;
      if (!busy) begin
        if (start) begin
          elem <= 8'd0;
          addr <= base;
          if (count == 8'd0) done <= 1'b1;
          else busy <= 1'b1;
        end
      end else if (mem_ready) begin
        elem <= next_elem;
        addr <= addr_d;
        if (next_elem == count) begin
          busy <= 1'b0;
          done <= 1'b1;
        end
      end
    end
  end

`ifdef RISCV_FORMAL
  assign dbg_elem = elem;

  // Lookahead matches now
  logic [7:0] n_now;
  always_comb begin
    n_now = 8'd1;
    if (unit) begin
      n_now = count - elem;
      if (((Bytes8 - 8'(line_off)) >> width) < n_now) n_now = (Bytes8 - 8'(line_off)) >> width;
      if (((Bytes8 - 8'(reg_off)) >> width) < n_now) n_now = (Bytes8 - 8'(reg_off)) >> width;
    end
  end
  assign dbg_n_ok = !busy || (n == n_now);
`endif

endmodule

`default_nettype wire
