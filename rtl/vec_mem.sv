`default_nettype none

module vec_mem #(
    parameter  int XLEN   = arch_pkg::XLEN,
    parameter  int AWIDTH = arch_pkg::RegAddrW,
    parameter  int VLEN   = arch_pkg::VLEN,
    localparam int Bytes  = VLEN / 8,
    localparam int OffW   = $clog2(Bytes),
    localparam int VlW    = $clog2(VLEN + 1)
) (
`ifdef RISCV_FORMAL
    output logic [VlW-1:0] dbg_elem,
    output logic           dbg_n_ok,
`endif
    input  wire            clk,
    input  wire            rst_n,
    input  wire            core_en,

    // Issued instruction
    input wire              start,
    input wire              load,
    input wire              vm,
    input wire [AWIDTH-1:0] vd,
    input wire [   VlW-1:0] count,
    input wire [       1:0] width,
    input wire [  XLEN-1:0] base,
    input wire [  XLEN-1:0] stride,

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
    output logic [ XLEN-1:0] mem_addr,
    output logic [ VLEN-1:0] mem_wdata,
    output logic [Bytes-1:0] mem_wstrb,

    output logic reg_done,
    output logic busy,
    output logic done
);

  localparam int ShW = $clog2(OffW + 1);
  localparam int BitW = $clog2(VLEN);
  localparam int MaskW = Bytes + 1;
  localparam logic [ShW-1:0] OffWS = ShW'(OffW);
  localparam logic [VlW-1:0] BytesV = VlW'(Bytes);

  logic [  VlW-1:0] elem;
  logic [ XLEN-1:0] addr;

  logic             unit;
  logic [ OffW-1:0] reg_off;
  logic [ OffW-1:0] line_off;
  logic [ OffW-1:0] shift;
  logic [  VlW-1:0] reg_idx;
  logic [  VlW-1:0] left;
  logic [  VlW-1:0] fit_line;
  logic [  VlW-1:0] fit_reg;
  logic [  VlW-1:0] n;
  logic [  VlW-1:0] beat_bytes;
  logic [Bytes-1:0] in_beat;
  logic [Bytes-1:0] byte_live;
  logic [Bytes-1:0] reg_mask;
  logic [  VlW-1:0] next_elem;

  // Beat geometry
  assign unit = (stride == (XLEN'(1) << width));
  assign reg_idx = elem >> (OffWS - ShW'(width));
  assign reg_off = OffW'(elem << width);
  assign line_off = addr[OffW-1:0];
  assign shift = line_off - reg_off;

  // Next beat position
  logic [ VlW-1:0] elem_d;
  logic [XLEN-1:0] addr_d;
  logic [ VlW-1:0] n_d;

  assign beat_bytes = n << width;
  assign next_elem = elem + n;
  assign elem_d = busy ? next_elem : '0;
  assign addr_d = busy ? (addr + (unit ? XLEN'(beat_bytes) : stride)) : base;

  // Elements next beat
  assign left = count - elem_d;
  assign fit_line = (BytesV - VlW'(addr_d[OffW-1:0])) >> width;
  assign fit_reg = (BytesV - VlW'(OffW'(elem_d << width))) >> width;
  always_comb begin
    n_d = VlW'(1);
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
  assign in_beat = Bytes'(((MaskW'(1) << beat_bytes) - MaskW'(1)) << reg_off);
  always_comb begin
    for (int j = 0; j < Bytes; j++) begin
      byte_live[j] = vm || v0[BitW'((reg_idx<<(OffWS-ShW'(width)))+(VlW'(j)>>width))];
    end
  end
  assign reg_mask = in_beat & byte_live;

  // Store beat
  assign raddr = vd + AWIDTH'(reg_idx);
  assign mem_req = busy;
  assign mem_addr = addr;
  assign mem_wdata = (rdata << (8 * shift)) | (rdata >> (8 * (BytesV - VlW'(shift))));
  assign mem_wstrb = load ? '0 : Bytes'({reg_mask, reg_mask} >> (BytesV - VlW'(shift)));

  // Load beat
  assign wdata = (mem_rdata >> (8 * shift)) | (mem_rdata << (8 * (BytesV - VlW'(shift))));
  always_comb begin
    for (int j = 0; j < Bytes; j++) wstrb[j*8+:8] = {8{reg_mask[j]}};
  end
  assign wen = busy && load && mem_ready && (|reg_mask);

  // Register finished
  assign reg_done = busy && load && mem_ready &&
      ((next_elem == count) || ((next_elem >> (OffWS - ShW'(width))) != reg_idx));

  // Walk the beats
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      elem <= '0;
      addr <= '0;
      busy <= 1'b0;
      done <= 1'b0;
    end else if (core_en) begin
      done <= 1'b0;
      if (!busy) begin
        if (start) begin
          elem <= '0;
          addr <= base;
          if (count == '0) done <= 1'b1;
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
  logic [VlW-1:0] n_now;
  always_comb begin
    n_now = VlW'(1);
    if (unit) begin
      n_now = count - elem;
      if (((BytesV - VlW'(line_off)) >> width) < n_now) n_now = (BytesV - VlW'(line_off)) >> width;
      if (((BytesV - VlW'(reg_off)) >> width) < n_now) n_now = (BytesV - VlW'(reg_off)) >> width;
    end
  end
  assign dbg_n_ok = !busy || (n == n_now);
`endif

endmodule

`default_nettype wire
