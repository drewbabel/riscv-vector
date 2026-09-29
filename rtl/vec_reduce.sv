`default_nettype none

module vec_reduce
  import vec_pkg::*;
#(
    parameter  int DLEN     = arch_pkg::VLEN,
    parameter  int ELEN     = arch_pkg::ELEN,
    localparam int MaxElems = DLEN / 8,
    localparam int BitsW    = $clog2(ELEN) + 1,
    localparam int IdxW     = $clog2(ELEN),
    localparam int LiveW    = $clog2(MaxElems + 1)
) (
    input wire clk,
    input wire rst_n,
    input wire core_en,

    input wire vec_op_e                op,
    input wire          [         2:0] vsew,
    input wire                         widen,
    input wire                         first,
    input wire                         step,
    input wire          [    DLEN-1:0] vs2_data,
    input wire          [    DLEN-1:0] vs1_data,
    input wire          [MaxElems-1:0] elem_active,

    output logic [DLEN-1:0] result
);

  logic sign_ext;
  assign sign_ext = (op == VEC_REDMIN) || (op == VEC_REDMAX) || (op == VEC_WREDSUM);

  // Element width
  localparam logic [BitsW-1:0] ElenBits = BitsW'(ELEN);

  logic [BitsW-1:0] sew_bits;
  logic [BitsW-1:0] acc_bits;
  assign sew_bits = BitsW'(BitsW'(8) << vsew);
  assign acc_bits = widen ? BitsW'(sew_bits << 1) : sew_bits;

  function automatic logic [ELEN-1:0] widen_val(input logic sgn, input logic [ELEN-1:0] raw,
                                                input logic [BitsW-1:0] bits);
    logic [ELEN-1:0] masked;
    logic            sign;
    masked = raw & ({ELEN{1'b1}} >> (ElenBits - bits));
    sign = raw[IdxW'(bits-BitsW'(1))];
    widen_val = (sgn && sign) ? (masked | ~({ELEN{1'b1}} >> (ElenBits - bits))) : masked;
  endfunction

  function automatic logic [ELEN-1:0] combine(input vec_op_e kind, input logic [ELEN-1:0] x,
                                              input logic [ELEN-1:0] y);
    case (kind)
      VEC_REDSUM, VEC_WREDSUM, VEC_WREDSUMU: combine = x + y;
      VEC_REDAND:                            combine = x & y;
      VEC_REDOR:                             combine = x | y;
      VEC_REDXOR:                            combine = x ^ y;
      VEC_REDMINU:                           combine = (x < y) ? x : y;
      VEC_REDMIN:                            combine = ($signed(x) < $signed(y)) ? x : y;
      VEC_REDMAXU:                           combine = (x > y) ? x : y;
      VEC_REDMAX:                            combine = ($signed(x) > $signed(y)) ? x : y;
      default:                               combine = x;
    endcase
  endfunction

  // Inactive element
  logic [ELEN-1:0] identity;
  always_comb begin
    case (op)
      VEC_REDAND, VEC_REDMINU: identity = {ELEN{1'b1}};
      VEC_REDMIN:              identity = {1'b0, {(ELEN - 1) {1'b1}}};
      VEC_REDMAX:              identity = {1'b1, {(ELEN - 1) {1'b0}}};
      default:                 identity = '0;
    endcase
  end

  // Lanes per register
  logic [LiveW-1:0] live;
  assign live = LiveW'(MaxElems >> vsew);

  // Lane values
  logic [ELEN-1:0] val[MaxElems];
  always_comb begin
    for (int e = 0; e < MaxElems; e++) begin
      logic [ELEN-1:0] raw;
      raw = '0;
      case (vsew)
        3'd0: raw = ELEN'(vs2_data[8*e+:8]);
        3'd1: raw = (e < MaxElems / 2) ? ELEN'(vs2_data[16*(e%(MaxElems/2))+:16]) : '0;
        default: raw = (e < MaxElems / 4) ? ELEN'(vs2_data[32*(e%(MaxElems/4))+:32]) : '0;
      endcase
      val[e] = (elem_active[e] && (LiveW'(e) < live)) ? widen_val(sign_ext, raw, sew_bits) :
          identity;
    end
  end

  // Fold tree
  localparam int Levels = $clog2(MaxElems);
  localparam int Cut = Levels / 2;
  localparam int Half = MaxElems >> Cut;
  logic [ELEN-1:0] node[Cut+1][MaxElems];

  always_comb begin
    for (int e = 0; e < MaxElems; e++) node[0][e] = val[e];
    for (int l = 1; l <= Cut; l++) begin
      for (int e = 0; e < MaxElems; e++) begin
        node[l][e] = (e < (MaxElems >> l)) ? combine(op, node[l-1][2*e], node[l-1][2*e+1]) : '0;
      end
    end
  end

  // Mid tree cut
  logic    [ ELEN-1:0] half_q     [Half];
  logic    [ ELEN-1:0] seed_q;
  vec_op_e             op_q;
  logic    [BitsW-1:0] acc_bits_q;
  logic                first_q;
  logic                step_q;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      step_q <= 1'b0;
    end else if (core_en) begin
      for (int e = 0; e < Half; e++) half_q[e] <= node[Cut][e];
      seed_q     <= widen_val(sign_ext, vs1_data[ELEN-1:0], acc_bits);
      op_q       <= op;
      acc_bits_q <= acc_bits;
      first_q    <= first;
      step_q     <= step;
    end
  end

  // Rest of tree
  logic [ELEN-1:0] rest[Levels-Cut+1][Half];
  logic [ELEN-1:0] folded;

  always_comb begin
    for (int e = 0; e < Half; e++) rest[0][e] = half_q[e];
    for (int l = 1; l <= Levels - Cut; l++) begin
      for (int e = 0; e < Half; e++) begin
        rest[l][e] = (e < (Half >> l)) ? combine(op_q, rest[l-1][2*e], rest[l-1][2*e+1]) : '0;
      end
    end
  end

  assign folded = rest[Levels-Cut][0];

  // Carried accumulator
  logic [ELEN-1:0] acc_q;
  logic [ELEN-1:0] acc_next;

  assign acc_next = first_q ? combine(op_q, seed_q, folded) : combine(op_q, acc_q, folded);

  always_ff @(posedge clk) begin
    if (!rst_n) acc_q <= '0;
    else if (core_en && step_q) acc_q <= acc_next;
  end

  assign result = DLEN'(ELEN'(acc_next & ({ELEN{1'b1}} >> (ElenBits - acc_bits_q))));

endmodule

`default_nettype wire
