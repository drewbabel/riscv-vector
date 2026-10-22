`default_nettype none

module vec_compress #(
    parameter  int AWIDTH   = arch_pkg::RegAddrW,
    parameter  int VLEN     = arch_pkg::VLEN,
    localparam int VLW      = $clog2(VLEN + 1),
    localparam int MAXELEMS = VLEN / 8,
    localparam int WIDTHS   = $clog2(arch_pkg::ELEN / 8) + 1,
    localparam int SELW     = $clog2(WIDTHS),
    localparam int CNTW     = $clog2(MAXELEMS + 1)
) (
    input logic clk,
    input logic rst_n,
    input logic core_en,

    input logic              start,
    input logic [AWIDTH-1:0] vs1,
    input logic [AWIDTH-1:0] vs2,
    input logic [AWIDTH-1:0] vd,
    input logic [   VLW-1:0] vl,
    input logic [       2:0] vsew,

    // Register file
    input  logic [  VLEN-1:0] rdata_mask,
    input  logic [  VLEN-1:0] rdata_src,
    output logic [AWIDTH-1:0] raddr_mask,
    output logic [AWIDTH-1:0] raddr_src,
    output logic              wen,
    output logic [AWIDTH-1:0] waddr,
    output logic [  VLEN-1:0] wstrb,
    output logic [  VLEN-1:0] wdata,

    output logic busy,
    output logic done
);

  typedef enum logic [1:0] {
    S_IDLE,
    S_RUN,
    S_FLUSH
  } state_e;

  state_e              state_q;

  logic   [AWIDTH-1:0] vs1_q;
  logic   [AWIDTH-1:0] vs2_q;
  logic   [AWIDTH-1:0] vd_q;
  logic   [   VLW-1:0] vl_q;
  logic   [       2:0] vsew_q;

  logic   [AWIDTH-1:0] src_q;
  logic   [AWIDTH-1:0] dst_q;
  logic   [     VLW:0] ebase_q;

  logic   [  VLEN-1:0] partial_q;
  logic   [  CNTW-1:0] fill_q;

  logic   [  SELW-1:0] wsel;
  assign wsel = (32'(vsew_q) < WIDTHS) ? SELW'(vsew_q) : SELW'(WIDTHS - 1);

  logic [VLEN-1:0] mslice;
  assign mslice = rdata_mask >> ebase_q;

  // Pack by width
  logic [2*VLEN-1:0] combo_w[WIDTHS];
  logic [    CNTW:0] total_w[WIDTHS];

  for (genvar g = 0; g < WIDTHS; g++) begin : g_w
    localparam int W = 8 << g;
    localparam int N = VLEN / W;

    always_comb begin
      logic [CNTW:0] pos;
      combo_w[g] = (2 * VLEN)'(partial_q);
      pos        = (CNTW + 1)'(fill_q);
      for (int e = 0; e < N; e++) begin
        if (mslice[e] && ((ebase_q + (VLW + 1)'(e)) < (VLW + 1)'(vl_q))) begin
          combo_w[g][pos*W+:W] = rdata_src[e*W+:W];
          pos = pos + 1'b1;
        end
      end
      total_w[g] = pos;
    end
  end

  logic [2*VLEN-1:0] combo;
  logic [    CNTW:0] total;
  always_comb begin
    combo = '0;
    total = '0;
    for (int g = 0; g < WIDTHS; g++) begin
      if (wsel == SELW'(g)) begin
        combo = combo_w[g];
        total = total_w[g];
      end
    end
  end

  logic [VLEN-1:0] combo_lo;
  logic [VLEN-1:0] combo_hi;
  assign combo_lo = combo[VLEN-1:0];
  assign combo_hi = combo[2*VLEN-1:VLEN];

  logic [CNTW:0] nelem;
  logic          full;
  logic          last;

  assign nelem = (CNTW + 1)'(MAXELEMS >> wsel);
  assign full  = (total >= nelem);
  assign last  = ((ebase_q + (VLW + 1)'(nelem)) >= (VLW + 1)'(vl_q));

  logic [VLEN-1:0] fill_strb;
  assign fill_strb  = ~({VLEN{1'b1}} << (32'(fill_q) << (wsel + 3)));

  assign raddr_src  = vs2_q + src_q;
  assign raddr_mask = vs1_q;
  assign waddr      = vd_q + dst_q;
  assign busy       = (state_q != S_IDLE);
  assign done       = (state_q == S_FLUSH);

  always_comb begin
    wen   = 1'b0;
    wdata = '0;
    wstrb = '0;
    case (state_q)
      S_RUN: begin
        wen   = full;
        wdata = combo_lo;
        wstrb = full ? {VLEN{1'b1}} : '0;
      end
      S_FLUSH: begin
        wen   = (fill_q != '0);
        wdata = partial_q;
        wstrb = fill_strb;
      end
      default: ;
    endcase
  end

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      state_q   <= S_IDLE;
      vs1_q     <= '0;
      vs2_q     <= '0;
      vd_q      <= '0;
      vl_q      <= '0;
      vsew_q    <= '0;
      src_q     <= '0;
      dst_q     <= '0;
      ebase_q   <= '0;
      partial_q <= '0;
      fill_q    <= '0;
    end else if (core_en) begin
      case (state_q)
        S_IDLE: begin
          if (start) begin
            vs1_q     <= vs1;
            vs2_q     <= vs2;
            vd_q      <= vd;
            vl_q      <= vl;
            vsew_q    <= vsew;
            src_q     <= '0;
            dst_q     <= '0;
            ebase_q   <= '0;
            partial_q <= '0;
            fill_q    <= '0;
            if (vl == '0) state_q <= S_FLUSH;
            else state_q <= S_RUN;
          end
        end
        S_RUN: begin
          if (full) begin
            partial_q <= combo_hi;
            fill_q    <= CNTW'(total - nelem);
            dst_q     <= dst_q + 1'b1;
          end else begin
            partial_q <= combo_lo;
            fill_q    <= CNTW'(total);
          end
          src_q   <= src_q + 1'b1;
          ebase_q <= ebase_q + (VLW + 1)'(nelem);
          if (last) state_q <= S_FLUSH;
        end
        default: state_q <= S_IDLE;
      endcase
    end
  end

endmodule

`default_nettype wire
