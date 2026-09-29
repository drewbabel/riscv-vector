`default_nettype none

module vec_sequencer
  import vec_pkg::*;
#(
    parameter int AWIDTH = arch_pkg::RegAddrW,
    parameter int VLEN = arch_pkg::VLEN,
    parameter int ELEN = arch_pkg::ELEN,
    parameter int MUL_LANES = arch_pkg::MulLanes,
    localparam int MaxElems = VLEN / 8,
    localparam int Widths = $clog2(ELEN / 8) + 1,
    localparam int SelW = $clog2(Widths),
    localparam int VlW = $clog2(VLEN + 1),
    localparam int OffW = $clog2(VLEN),
    localparam int CntW = $clog2(MaxElems + 1)
) (
    input wire                clk,
    input wire                rst_n,
    input wire                core_en,
    input wire                start,
    input wire [  AWIDTH-1:0] vs1,
    input wire [  AWIDTH-1:0] vs2,
    input wire [  AWIDTH-1:0] vd,
    input wire                reads_vd,
    input wire [     VlW-1:0] vl,
    input wire [         2:0] vsew,
    input wire [         2:0] vlmul,
    input wire                vm,
    input wire [MaxElems-1:0] mask_bits,
    input wire [    VLEN-1:0] v0_bits,

    // Element geometry
    input wire vec_rel_e d_rel,
    input wire vec_rel_e s1_rel,
    input wire vec_rel_e s2_rel,
    input wire           mul_rate,
    input wire           single_write,
    input wire           mask_dest,
    input wire           mask_whole,
    input wire           mask_src,

    // Register ports
    output logic [AWIDTH-1:0] raddr1,
    output logic [AWIDTH-1:0] raddr2,
    output logic [AWIDTH-1:0] raddr3,
    output logic [AWIDTH-1:0] waddr,
    output logic [  VLEN-1:0] wstrb,
    output logic              wen,

    // Element slices
    output logic [    OffW-1:0] s1_off,
    output logic [    OffW-1:0] s2_off,
    output logic [    OffW-1:0] d_off,
    output logic [     VlW-1:0] elem_base,
    output logic [    CntW-1:0] elem_count,
    output logic [MaxElems-1:0] elem_active,

    output logic last,
    output logic reg_done,
    output logic busy,
    output logic done
);

  localparam int LnW   = $clog2(OffW + 1);
  localparam int MulLn = $clog2(MUL_LANES);
  localparam int ProdW = VlW + $clog2(ELEN);
  localparam int DbW   = $clog2(ELEN + 1);
  localparam int DiffW = VlW + 1;

  // Element widths
  logic [    2:0] lsew;
  logic [    2:0] ld;
  logic [    2:0] ls1;
  logic [    2:0] ls2;
  logic [    2:0] lmax;
  logic [LnW-1:0] ln;

  assign lsew = vsew + 3'd3;

  assign ld   = vec_rel_log2(d_rel, lsew);
  assign ls1  = vec_rel_log2(s1_rel, lsew);
  assign ls2  = vec_rel_log2(s2_rel, lsew);

  // Widest port
  always_comb begin
    if (mask_whole) begin
      lmax = lsew;
    end else if (single_write) begin
      lmax = ls2;
    end else if (mask_dest) begin
      lmax = ls2;
      if (ls1 > lmax) lmax = ls1;
    end else if (mask_src) begin
      lmax = ld;
    end else begin
      lmax = ld;
      if (ls1 > lmax) lmax = ls1;
      if (ls2 > lmax) lmax = ls2;
    end
  end

  // Elements per phase
  always_comb begin
    ln = LnW'(OffW) - LnW'(lmax);
    if (mul_rate && (ln > LnW'(MulLn))) ln = LnW'(MulLn);
  end

  assign elem_count = mask_whole ? CntW'(1) : CntW'(CntW'(1) << ln);

  // Group geometry
  logic [    4:0] regs_per_group;
  logic [VlW-1:0] total_elems;

  assign regs_per_group = vlmul[2] ? 5'd1 : 5'(5'd1 << vlmul[1:0]);
  assign total_elems = mask_whole ? VlW'(1) : (VlW'(regs_per_group) << (LnW'(OffW) - LnW'(lsew)));

  // Element counter
  logic [VlW-1:0] elem_q;
  logic [VlW-1:0] elem_next;

  assign elem_base = elem_q;
  assign elem_next = elem_q + VlW'(elem_count);
  assign last = (elem_next >= total_elems);

  // Port offsets
  logic [ProdW-1:0] prod1;
  logic [ProdW-1:0] prod2;
  logic [ProdW-1:0] prodd;

  assign prod1  = (single_write || mask_src) ? '0 : (ProdW'(elem_base) << ls1);
  assign prod2  = mask_src ? '0 : (ProdW'(elem_base) << ls2);
  assign prodd  = single_write ? '0 : (mask_dest ? ProdW'(elem_base) : (ProdW'(elem_base) << ld));

  assign s1_off = prod1[OffW-1:0];
  assign s2_off = prod2[OffW-1:0];
  assign d_off  = prodd[OffW-1:0];

  assign raddr1 = vs1 + AWIDTH'(prod1[ProdW-1:OffW]);
  assign raddr2 = vs2 + AWIDTH'(prod2[ProdW-1:OffW]);
  assign raddr3 = reads_vd ? (vd + AWIDTH'(prodd[ProdW-1:OffW])) : '0;
  assign waddr  = vd + AWIDTH'(prodd[ProdW-1:OffW]);

  // Register finished
  logic [ProdW-1:0] prodd_next;
  assign
      prodd_next = single_write ? '0 : (mask_dest ? ProdW'(elem_next) : (ProdW'(elem_next) << ld));
  assign reg_done = busy && (last || (prodd_next[ProdW-1:OffW] != prodd[ProdW-1:OffW]));
  assign wen = busy && (wstrb != '0);

  // Destination bits
  logic [DbW-1:0] dbits;
  assign dbits = mask_dest ? DbW'(1) : DbW'(DbW'(1) << ld);

  // The live prefix
  logic [VLEN-1:0] vl_mask;
  assign vl_mask = VLEN'({VLEN{1'b1}} >> (DiffW'(VLEN) - DiffW'(vl)));

  // Live elements
  always_comb begin
    for (int e = 0; e < MaxElems; e++) begin
      elem_active[e] = (CntW'(e) < elem_count) && ((elem_base + VlW'(e)) < vl) &&
          (vm || mask_bits[e]);
    end
  end

  // One element wide
  logic [VLEN-1:0] unit_mask;
  assign unit_mask = VLEN'({ELEN{1'b1}} >> (DbW'(ELEN) - dbits));

  // Active elements spread
  logic [VLEN-1:0] spread_w[Widths];
  logic [VLEN-1:0] spread;
  logic [SelW-1:0] dsel;

  for (genvar g = 0; g < Widths; g++) begin : g_w
    localparam int W = 8 << g;
    for (genvar e = 0; e < VLEN / W; e++) begin : g_e
      assign spread_w[g][e*W+:W] = {W{elem_active[e]}};
    end
  end

  assign dsel = (ld >= 3'd3 && 32'(ld - 3'd3) < Widths) ? SelW'(ld - 3'd3) : SelW'(Widths - 1);
  always_comb begin
    spread = mask_dest ? VLEN'(elem_active) : '0;
    for (int g = 0; g < Widths; g++) begin
      if (!mask_dest && (dsel == SelW'(g))) spread = spread_w[g];
    end
  end

  // Tail plus mask
  always_comb begin
    wstrb = '0;
    if (single_write) begin
      if (last) wstrb = unit_mask;
    end else if (mask_whole) begin
      if (last) wstrb = vl_mask & (vm ? {VLEN{1'b1}} : v0_bits);
    end else begin
      wstrb = spread << d_off;
    end
  end

  // Walk the group
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      elem_q <= '0;
      busy   <= 1'b0;
      done   <= 1'b0;
    end else if (core_en) begin
      done <= 1'b0;
      if (!busy) begin
        if (start) begin
          elem_q <= '0;
          if (vl == '0) done <= 1'b1;
          else busy <= 1'b1;
        end
      end else begin
        if (last) begin
          busy <= 1'b0;
          done <= 1'b1;
        end else begin
          elem_q <= elem_next;
        end
      end
    end
  end

endmodule

`default_nettype wire
