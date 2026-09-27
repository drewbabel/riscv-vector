`default_nettype none

module vec_sat_lane
  import vec_pkg::*;
#(
    parameter int ELEN = 32
) (
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
  localparam int DW = $clog2(ELEN);
  localparam int IW = $clog2(XW);

  logic [    DW:0] w;
  logic [ELEN-1:0] wmask;
  logic [ELEN-1:0] smax;
  logic [ELEN-1:0] smin;
  logic [  DW-1:0] shamt;

  logic [  XW-1:0] ua;
  logic [  XW-1:0] ub;
  logic [  XW-1:0] sa;
  logic [  XW-1:0] sb;

  logic [  XW-1:0] v;
  logic [  XW-1:0] shifted;
  logic [  DW-1:0] d;
  logic            r;
  logic [ELEN-1:0] res;

  // Element width
  assign w = (DW + 1)'(8) << vsew;
  assign wmask = ELEN'((XW'(1) << w) - XW'(1));
  assign smax = wmask >> 1;
  assign smin = wmask ^ smax;
  assign shamt = DW'(b & ELEN'(w - (DW + 1)'(1)));

  // Extended operands
  assign ua = XW'(a & wmask);
  assign ub = XW'(b & wmask);
  assign sa = a[w-1] ? (ua | ~XW'(wmask)) : ua;
  assign sb = b[w-1] ? (ub | ~XW'(wmask)) : ub;

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
      VEC_AADD:  v = sa + sb;
      VEC_ASUBU: v = ua - ub;
      VEC_ASUB:  v = sa - sb;
      VEC_SSRA:  v = sa;
      default:   v = ua;
    endcase
  end

  assign d = ((op == VEC_SSRL) || (op == VEC_SSRA)) ? shamt : DW'(1);
  assign shifted = (op == VEC_SSRA) ? XW'($signed(v) >>> d) : (v >> d);
  assign r = round_inc(v, d, vxrm);

  // One element
  always_comb begin
    logic [XW-1:0] sum;
    sum = '0;
    sat = 1'b0;
    case (op)
      VEC_SADDU: begin
        sum = ua + ub;
        sat = sum[w];
        res = sat ? wmask : ELEN'(sum);
      end
      VEC_SSUBU: begin
        sum = ua - ub;
        sat = ua < ub;
        res = sat ? '0 : ELEN'(sum);
      end
      VEC_SADD: begin
        sum = sa + sb;
        sat = sum[w] != sum[w-1];
        res = sat ? (sum[w] ? smin : smax) : ELEN'(sum);
      end
      VEC_SSUB: begin
        sum = sa - sb;
        sat = sum[w] != sum[w-1];
        res = sat ? (sum[w] ? smin : smax) : ELEN'(sum);
      end
      VEC_AADDU, VEC_AADD, VEC_ASUBU, VEC_ASUB, VEC_SSRL, VEC_SSRA: begin
        res = ELEN'(shifted) + ELEN'(r);
      end
      default: res = '0;
    endcase
  end

  assign result = res & wmask;

endmodule

`default_nettype wire
