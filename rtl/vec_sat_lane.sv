`default_nettype none

module vec_sat_lane
  import vec_pkg::*;
#(
    parameter int ELEN = arch_pkg::ELEN
) (
    input  wire                       clk,
    input  wire                       core_en,
    input  wire vec_op_e              op,
    input  wire          [       2:0] vsew,
    input  wire          [       1:0] vxrm,
    input  wire          [  ELEN-1:0] a,
    input  wire          [  ELEN-1:0] b,
    input  wire          [2*ELEN-1:0] product,
    output logic         [  ELEN-1:0] result,
    output logic                      sat
);

  localparam int XW = ELEN + 2;
  localparam int PW = 2 * ELEN + 1;
  localparam int DW = $clog2(ELEN);
  localparam int IW = $clog2(XW);
  localparam logic [2:0] SewTop = 3'($clog2(ELEN / 8));

  logic    [    DW:0] w;
  logic    [  DW+1:0] w2;
  logic    [ELEN-1:0] wmask;
  logic    [  XW-1:0] m2;
  logic    [  PW-1:0] pm;
  logic    [ELEN-1:0] smax;
  logic    [ELEN-1:0] smin;
  logic    [  DW-1:0] shamt;
  logic    [  DW-1:0] shamt2;
  logic    [  DW-1:0] top2;

  logic    [  XW-1:0] ua;
  logic    [  XW-1:0] ub;
  logic    [  XW-1:0] sa;
  logic    [  XW-1:0] sb;
  logic    [  XW-1:0] ua2;
  logic    [  XW-1:0] sa2;
  logic    [  PW-1:0] pu;
  logic    [  PW-1:0] ps;
  logic    [  PW-1:0] psh;

  logic    [  XW-1:0] v;
  logic    [  XW-1:0] shifted;
  logic    [  DW-1:0] d;
  logic               r;
  logic    [  XW-1:0] sum1;
  logic               borrow1;

  // Second stage registers
  vec_op_e            op_q;
  logic    [     2:0] vsew_q;
  logic    [    DW:0] w_q;
  logic    [ELEN-1:0] wmask_q;
  logic    [ELEN-1:0] smax_q;
  logic    [ELEN-1:0] smin_q;
  logic    [  XW-1:0] sum_q;
  logic               borrow_q;
  logic    [  XW-1:0] shifted_q;
  logic               r_q;
  logic    [  PW-1:0] psh_q;
  logic    [ELEN-1:0] res;

  // Element width
  assign w = (DW + 1)'(8) << vsew;
  assign w2 = (DW + 2)'(w) << 1;
  assign wmask = ELEN'((XW'(1) << w) - XW'(1));
  assign m2 = (XW'(1) << w2) - XW'(1);
  assign pm = (PW'(1) << w2) - PW'(1);
  assign smax = wmask >> 1;
  assign smin = wmask ^ smax;
  assign shamt = DW'(b & ELEN'(w - (DW + 1)'(1)));
  assign shamt2 = DW'(b & ELEN'(w2 - (DW + 2)'(1)));
  assign top2 = DW'(w2 - (DW + 2)'(1));

  // Extended operands
  assign ua = XW'(a & wmask);
  assign ub = XW'(b & wmask);
  assign sa = a[w-1] ? (ua | ~XW'(wmask)) : ua;
  assign sb = b[w-1] ? (ub | ~XW'(wmask)) : ub;

  // Double-width source
  assign ua2 = XW'(a) & m2;
  assign sa2 = a[top2] ? (ua2 | ~m2) : ua2;

  // Full product
  assign pu = PW'(product) & pm;
  assign ps = product[w2-1] ? (pu | ~pm) : pu;
  assign psh = $signed(ps) >>> d;

  // Rounding increment
  function automatic logic round_inc(input logic [XW-1:0] val, input logic [DW-1:0] dd,
                                     input logic [1:0] mode);
    logic [XW-1:0] below;
    logic [XW-1:0] under;
    below = (XW'(1) << dd) - XW'(1);
    under = below >> 1;
    case (mode)
      2'd0: round_inc = (dd != '0) && val[dd-1];
      2'd1: round_inc = (dd != '0) && val[dd-1] && (((val & under) != '0) || val[IW'(dd)]);
      2'd2: round_inc = 1'b0;
      default: round_inc = !val[IW'(dd)] && ((val & below) != '0);
    endcase
  endfunction

  // Pre-rounding value
  always_comb begin
    case (op)
      VEC_AADDU: v = ua + ub;
      VEC_AADD: v = sa + sb;
      VEC_ASUBU: v = ua - ub;
      VEC_ASUB: v = sa - sb;
      VEC_SSRA: v = sa;
      VEC_NCLIPU: v = ua2;
      VEC_NCLIP: v = sa2;
      VEC_SMUL: v = XW'(ps);
      default: v = ua;
    endcase
  end

  // Rounding position
  always_comb begin
    case (op)
      VEC_SSRL, VEC_SSRA:    d = shamt;
      VEC_NCLIPU, VEC_NCLIP: d = shamt2;
      VEC_SMUL:              d = DW'(w - (DW + 1)'(1));
      default:               d = DW'(1);
    endcase
  end

  assign shifted = ((op == VEC_SSRA) || (op == VEC_NCLIP)) ? XW'($signed(v) >>> d) : (v >> d);
  assign r = round_inc(v, d, vxrm);

  // Saturating sum
  always_comb begin
    case (op)
      VEC_SADDU: sum1 = ua + ub;
      VEC_SSUBU: sum1 = ua - ub;
      VEC_SADD:  sum1 = sa + sb;
      VEC_SSUB:  sum1 = sa - sb;
      default:   sum1 = '0;
    endcase
  end
  assign borrow1 = ua < ub;

  always_ff @(posedge clk) begin
    if (core_en) begin
      op_q      <= op;
      vsew_q    <= vsew;
      w_q       <= w;
      wmask_q   <= wmask;
      smax_q    <= smax;
      smin_q    <= smin;
      sum_q     <= sum1;
      borrow_q  <= borrow1;
      shifted_q <= shifted;
      r_q       <= r;
      psh_q     <= psh;
    end
  end

  // One element
  always_comb begin
    logic [XW-1:0] sum;
    logic [XW-1:0] hi;
    logic [PW-1:0] wide;
    logic [PW-1:0] whi;
    sum  = '0;
    hi   = '0;
    wide = '0;
    whi  = '0;
    sat  = 1'b0;
    case (op_q)
      VEC_SADDU: begin
        sat = sum_q[w_q];
        res = sat ? wmask_q : ELEN'(sum_q);
      end
      VEC_SSUBU: begin
        sat = borrow_q;
        res = sat ? '0 : ELEN'(sum_q);
      end
      VEC_SADD, VEC_SSUB: begin
        sat = sum_q[w_q] != sum_q[w_q-1];
        if (!sat) res = ELEN'(sum_q);
        else if (sum_q[w_q]) res = smin_q;
        else res = smax_q;
      end
      VEC_AADDU, VEC_AADD, VEC_ASUBU, VEC_ASUB, VEC_SSRL, VEC_SSRA: begin
        res = ELEN'(shifted_q) + ELEN'(r_q);
      end
      VEC_SMUL: begin
        wide = psh_q + PW'(r_q);
        whi  = $signed(wide) >>> (w_q - (DW + 1)'(1));
        sat  = (whi != '0) && (whi != '1);
        res  = sat ? smax_q : ELEN'(wide);
      end
      VEC_NCLIPU: begin
        sum = shifted_q + XW'(r_q);
        sat = (vsew_q < SewTop) && ((sum >> w_q) != '0);
        if (vsew_q >= SewTop) res = '0;
        else if (sat) res = wmask_q;
        else res = ELEN'(sum);
      end
      VEC_NCLIP: begin
        sum = shifted_q + XW'(r_q);
        hi  = $signed(sum) >>> (w_q - (DW + 1)'(1));
        sat = (vsew_q < SewTop) && (hi != '0) && (hi != '1);
        if (vsew_q >= SewTop) res = '0;
        else if (!sat) res = ELEN'(sum);
        else if (sum[XW-1]) res = smin_q;
        else res = smax_q;
      end
      default: res = '0;
    endcase
  end

  assign result = res & wmask_q;

endmodule

`default_nettype wire
