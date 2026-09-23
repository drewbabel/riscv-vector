`default_nettype none

module vec_mask
  import vec_pkg::*;
#(
    parameter  int DLEN     = 128,
    parameter  int ELEN     = 32,
    localparam int MaxElems = DLEN / 8,
    localparam int Widths   = $clog2(ELEN / 8) + 1,
    localparam int CntW     = $clog2(DLEN + 1),
    localparam int SelW     = $clog2(Widths)
) (
    input vec_op_e             op,
    input vec_src_e            src,
    input logic     [     2:0] vsew,
    input logic                vm,
    input logic     [DLEN-1:0] vs2_data,
    input logic     [DLEN-1:0] vs1_data,
    input logic     [DLEN-1:0] v0_bits,
    input logic     [    31:0] xdata,
    input logic     [     4:0] simm,
    input logic     [     7:0] elem_base,
    input logic     [     7:0] vl,

    output logic [DLEN-1:0] result,
    output logic [    31:0] xresult
);

  // Active mask bits
  logic [DLEN-1:0] live;
  logic [DLEN-1:0] active;

  assign live   = DLEN'({DLEN{1'b1}} >> (9'(DLEN) - 9'(vl)));
  assign active = live & (vm ? {DLEN{1'b1}} : v0_bits);

  // Signed comparison
  function automatic logic is_signed_cmp(input vec_op_e kind);
    case (kind)
      VEC_MSLT, VEC_MSLE, VEC_MSGT: is_signed_cmp = 1'b1;
      default:                      is_signed_cmp = 1'b0;
    endcase
  endfunction

  // Compare one pair
  function automatic logic cmp_bit(input vec_op_e kind, input logic [31:0] a, input logic [31:0] b);
    case (kind)
      VEC_MSEQ:  cmp_bit = (a == b);
      VEC_MSNE:  cmp_bit = (a != b);
      VEC_MSLTU: cmp_bit = (a < b);
      VEC_MSLT:  cmp_bit = ($signed(a) < $signed(b));
      VEC_MSLEU: cmp_bit = (a <= b);
      VEC_MSLE:  cmp_bit = ($signed(a) <= $signed(b));
      VEC_MSGTU: cmp_bit = (a > b);
      VEC_MSGT:  cmp_bit = ($signed(a) > $signed(b));
      default:   cmp_bit = 1'b0;
    endcase
  endfunction

  // Trim a value
  function automatic logic [31:0] sized(input logic [31:0] val, input logic [5:0] bits,
                                        input logic sgn);
    case (bits)
      6'd8:    sized = sgn ? {{24{val[7]}}, val[7:0]} : {24'd0, val[7:0]};
      6'd16:   sized = sgn ? {{16{val[15]}}, val[15:0]} : {16'd0, val[15:0]};
      default: sized = val;
    endcase
  endfunction

  // Count set bits
  function automatic logic [CntW-1:0] ones(input logic [DLEN-1:0] x);
    ones = '0;
    for (int i = 0; i < DLEN; i++) ones = ones + CntW'(x[i]);
  endfunction

  // Bitwise mask logic
  function automatic logic [DLEN-1:0] logic_of(input vec_op_e kind, input logic [DLEN-1:0] a,
                                               input logic [DLEN-1:0] b);
    case (kind)
      VEC_MAND:  logic_of = a & b;
      VEC_MNAND: logic_of = ~(a & b);
      VEC_MANDN: logic_of = a & ~b;
      VEC_MOR:   logic_of = a | b;
      VEC_MNOR:  logic_of = ~(a | b);
      VEC_MORN:  logic_of = a | ~b;
      VEC_MXOR:  logic_of = a ^ b;
      VEC_MXNOR: logic_of = ~(a ^ b);
      default:   logic_of = '0;
    endcase
  endfunction

  logic [5:0] ebits;
  assign ebits = 6'(6'd8 << vsew);

  // Width select
  logic [SelW-1:0] wsel;
  assign wsel = (32'(vsew) < Widths) ? SelW'(vsew) : SelW'(Widths - 1);

  // Elements by width
  logic [ELEN-1:0] a_w[Widths][MaxElems];
  logic [ELEN-1:0] b_w[Widths][MaxElems];

  for (genvar g = 0; g < Widths; g++) begin : g_w
    localparam int W = 8 << g;
    for (genvar e = 0; e < MaxElems; e++) begin : g_e
      if (e < DLEN / W) begin : g_in
        assign a_w[g][e] = ELEN'(vs2_data[e*W+:W]);
        assign b_w[g][e] = ELEN'(vs1_data[e*W+:W]);
      end else begin : g_out
        assign a_w[g][e] = '0;
        assign b_w[g][e] = '0;
      end
    end
  end

  // Live width elements
  logic [ELEN-1:0] a_sel[MaxElems];
  logic [ELEN-1:0] b_sel[MaxElems];
  always_comb begin
    for (int e = 0; e < MaxElems; e++) begin
      a_sel[e] = '0;
      b_sel[e] = '0;
      for (int g = 0; g < Widths; g++) begin
        if (wsel == SelW'(g)) begin
          a_sel[e] = a_w[g][e];
          b_sel[e] = b_w[g][e];
        end
      end
    end
  end

  // Second compare operand
  logic [31:0] scalar_b;
  always_comb begin
    case (src)
      VEC_SRC_VI: scalar_b = {{27{simm[4]}}, simm};
      default:    scalar_b = xdata;
    endcase
  end

  // Compare results
  logic [MaxElems-1:0] cmp_bits;
  always_comb begin
    cmp_bits = '0;
    for (int e = 0; e < MaxElems; e++) begin
      cmp_bits[e] = cmp_bit(op, sized(a_sel[e], ebits, is_signed_cmp(op)),
                            (src == VEC_SRC_VV)
                                ? sized(b_sel[e], ebits, is_signed_cmp(op))
                                : sized(scalar_b, ebits, is_signed_cmp(op)));
    end
  end

  // Set before first
  logic [DLEN-1:0] hits;
  logic [DLEN-1:0] before_first;
  logic [DLEN-1:0] at_first;

  assign hits = vs2_data & active;

  always_comb begin
    before_first    = '0;
    before_first[0] = 1'b1;
    for (int i = 1; i < DLEN; i++) begin
      before_first[i] = before_first[i-1] && !hits[i-1];
    end
    for (int i = 0; i < DLEN; i++) begin
      at_first[i] = hits[i] && before_first[i];
    end
  end

  // Set results
  logic [DLEN-1:0] set_bits;
  always_comb begin
    case (op)
      VEC_MSBF: set_bits = before_first & ~at_first;
      VEC_MSIF: set_bits = before_first;
      VEC_MSOF: set_bits = at_first;
      default:  set_bits = '0;
    endcase
  end

  // Running index count
  logic [CntW-1:0] below;
  logic [DLEN-1:0] window;
  logic [CntW-1:0] count[MaxElems];

  assign below  = ones(hits & ~({DLEN{1'b1}} << elem_base));
  assign window = hits >> elem_base;

  always_comb begin
    count[0] = below;
    for (int e = 1; e < MaxElems; e++) count[e] = count[e-1] + CntW'(window[e-1]);
  end

  // Index values
  logic [CntW-1:0] ival[MaxElems];
  logic [MaxElems-1:0] ion;
  always_comb begin
    for (int e = 0; e < MaxElems; e++) begin
      ion[e]  = (9'(elem_base) + 9'(e)) < 9'(DLEN);
      ival[e] = (op == VEC_ID) ? CntW'(elem_base + 8'(e)) : count[e];
    end
  end

  // Index results
  logic [DLEN-1:0] idx_w[Widths];
  logic [DLEN-1:0] index_data;

  for (genvar g = 0; g < Widths; g++) begin : g_iw
    localparam int W = 8 << g;
    for (genvar e = 0; e < DLEN / W; e++) begin : g_e
      assign idx_w[g][e*W+:W] = ion[e] ? W'(ival[e]) : '0;
    end
  end

  always_comb begin
    index_data = '0;
    for (int g = 0; g < Widths; g++) begin
      if (wsel == SelW'(g)) index_data = idx_w[g];
    end
  end

  // Scalar summaries
  logic [31:0] pop_count;
  logic [31:0] first_one;
  always_comb begin
    pop_count = 32'(ones(hits));
    first_one = 32'hFFFF_FFFF;
    for (int i = DLEN - 1; i >= 0; i--) begin
      if (hits[i]) first_one = 32'(i);
    end
  end

  assign xresult = (op == VEC_CPOP) ? pop_count : first_one;

  always_comb begin
    case (vec_class(op))
      VEC_CLS_CMP:  result = DLEN'(cmp_bits);
      VEC_CLS_MLOG: result = logic_of(op, vs2_data, vs1_data);
      VEC_CLS_MSET: result = set_bits;
      VEC_CLS_IOTA: result = index_data;
      default:      result = '0;
    endcase
  end

endmodule

`default_nettype wire
