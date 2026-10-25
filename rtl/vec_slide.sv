`default_nettype none

module vec_slide
  import vec_pkg::*;
#(
    parameter  int XLEN   = arch_pkg::XLEN,
    parameter  int AWIDTH = arch_pkg::RegAddrW,
    parameter  int VLEN   = arch_pkg::VLEN,
    localparam int VlW    = $clog2(VLEN + 1)
) (
    input wire clk,
    input wire rst_n,
    input wire core_en,

    // Issued instruction
    input wire                       start,
    input wire vec_op_e              op,
    input wire                       vm,
    input wire          [AWIDTH-1:0] vs2,
    input wire          [AWIDTH-1:0] vd,
    input wire          [   VlW-1:0] vl,
    input wire          [       2:0] vsew,
    input wire          [       2:0] vlmul,
    input wire          [  XLEN-1:0] offset,
    input wire          [  XLEN-1:0] scalar,

    // Register file
    input  wire  [  VLEN-1:0] v0,
    input  wire  [  VLEN-1:0] rdata_lo,
    input  wire  [  VLEN-1:0] rdata_hi,
    output logic [AWIDTH-1:0] raddr_lo,
    output logic [AWIDTH-1:0] raddr_hi,
    output logic              wen,
    output logic [AWIDTH-1:0] waddr,
    output logic [  VLEN-1:0] wstrb,
    output logic [  VLEN-1:0] wdata,

    output logic busy,
    output logic done
);

  localparam int Bytes = VLEN / 8;
  localparam int OffW = $clog2(Bytes);
  localparam int ShW = $clog2(OffW + 1);
  localparam int BitW = $clog2(VLEN);
  localparam int SumW = VlW + 1;
  localparam logic [ShW-1:0] OffWS = ShW'(OffW);
  localparam logic [SumW-1:0] VlenS = SumW'(VLEN);

  logic              up;
  logic              one;
  logic [  XLEN-1:0] amount;
  logic [  SumW-1:0] amt;
  logic [AWIDTH-1:0] q;
  logic [  OffW-1:0] m;
  logic [   ShW-1:0] elem_log2;
  logic [  SumW-1:0] vlmax;
  logic [AWIDTH-1:0] last_reg;
  logic [AWIDTH-1:0] r;
  logic [  SumW-1:0] base;

  // Slide amount
  assign up = (op == VEC_SLIDEUP) || (op == VEC_SLIDE1UP);
  assign one = (op == VEC_SLIDE1UP) || (op == VEC_SLIDE1DOWN);
  assign amount = one ? XLEN'(1) : offset;
  assign amt = (amount >= XLEN'(VLEN)) ? VlenS : SumW'(amount);
  assign elem_log2 = OffWS - ShW'(vsew);
  assign q = AWIDTH'(amount >> elem_log2);
  assign m = OffW'(amount << vsew);

  // Group geometry
  assign vlmax = SumW'(vec_group_elems(Bytes >> vsew, vlmul));
  assign last_reg = AWIDTH'(vec_group_regs(4'($signed(vlmul))) - 1);
  assign base = SumW'(r) << elem_log2;

  // Source registers
  assign raddr_lo = up ? (vs2 + r - q - AWIDTH'(1)) : (vs2 + r + q);
  assign raddr_hi = up ? (vs2 + r - q) : (vs2 + r + q + AWIDTH'(1));

  logic [2*VLEN-1:0] pair;
  logic [  VLEN-1:0] slid;
  logic [  VLEN-1:0] fill;

  assign pair = {rdata_hi, rdata_lo};
  assign slid = up ? VLEN'(pair >> (8 * (Bytes - int'(m)))) : VLEN'(pair >> (8 * int'(m)));

  always_comb begin
    for (int b = 0; b < Bytes; b++) fill[b*8+:8] = scalar[8*(b%(1<<vsew))+:8];
  end

  // Element writes
  logic [Bytes-1:0] keep;
  logic [Bytes-1:0] zero;
  logic [Bytes-1:0] put;

  always_comb begin
    for (int k = 0; k < Bytes; k++) begin
      logic [SumW-1:0] i;
      i = base + SumW'(k);
      keep[k] = (i < SumW'(vl)) && (vm || v0[BitW'(i)]);
      if (up) begin
        put[k]  = one && (i == '0);
        zero[k] = 1'b0;
        if (!put[k] && (i < amt)) keep[k] = 1'b0;
      end else begin
        put[k]  = one && (i == SumW'(vl) - SumW'(1));
        zero[k] = (i + amt) >= vlmax;
      end
    end
  end

  always_comb begin
    for (int b = 0; b < Bytes; b++) begin
      wstrb[b*8+:8] = {8{keep[b>>vsew]}};
      if (put[b>>vsew]) wdata[b*8+:8] = fill[b*8+:8];
      else if (zero[b>>vsew]) wdata[b*8+:8] = 8'h00;
      else wdata[b*8+:8] = slid[b*8+:8];
    end
  end

  assign wen   = busy && (|wstrb);
  assign waddr = vd + r;

  // Walk registers
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      r    <= '0;
      busy <= 1'b0;
      done <= 1'b0;
    end else if (core_en) begin
      done <= 1'b0;
      if (!busy) begin
        if (start) begin
          r <= '0;
          if (vl == '0) done <= 1'b1;
          else busy <= 1'b1;
        end
      end else begin
        r <= r + AWIDTH'(1);
        if (r == last_reg) begin
          busy <= 1'b0;
          done <= 1'b1;
        end
      end
    end
  end

endmodule

`default_nettype wire
