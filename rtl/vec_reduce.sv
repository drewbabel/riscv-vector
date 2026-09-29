`default_nettype none

module vec_reduce
  import vec_pkg::*;
#(
    parameter  int DLEN     = 128,
    localparam int MaxElems = DLEN / 8
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
  logic [5:0] sew_bits;
  logic [5:0] acc_bits;
  assign sew_bits = 6'(6'd8 << vsew);
  assign acc_bits = widen ? 6'(sew_bits << 1) : sew_bits;

  function automatic logic [31:0] widen_val(input logic sgn, input logic [31:0] raw,
                                            input logic [5:0] bits);
    logic [31:0] masked;
    logic        sign;
    masked = raw & (32'hFFFF_FFFF >> (6'd32 - bits));
    sign   = raw[5'(bits-6'd1)];
    widen_val = (sgn && sign) ? (masked | ~(32'hFFFF_FFFF >> (6'd32 - bits))) : masked;
  endfunction

  function automatic logic [31:0] combine(input vec_op_e kind, input logic [31:0] x,
                                          input logic [31:0] y);
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
  logic [31:0] identity;
  always_comb begin
    case (op)
      VEC_REDAND, VEC_REDMINU: identity = 32'hFFFF_FFFF;
      VEC_REDMIN:              identity = 32'h7FFF_FFFF;
      VEC_REDMAX:              identity = 32'h8000_0000;
      default:                 identity = 32'd0;
    endcase
  end

  // Lanes per register
  logic [4:0] live;
  assign live = 5'(MaxElems >> vsew);

  // Lane values
  logic [31:0] val[MaxElems];
  always_comb begin
    for (int e = 0; e < MaxElems; e++) begin
      logic [31:0] raw;
      raw = 32'd0;
      case (vsew)
        3'd0: raw = 32'(vs2_data[8*e+:8]);
        3'd1: raw = (e < MaxElems / 2) ? 32'(vs2_data[16*(e % (MaxElems / 2))+:16]) : 32'd0;
        default: raw = (e < MaxElems / 4) ? vs2_data[32*(e % (MaxElems / 4))+:32] : 32'd0;
      endcase
      val[e] = (elem_active[e] && (5'(e) < live)) ? widen_val(sign_ext, raw, sew_bits) : identity;
    end
  end

  // Fold tree
  localparam int Levels = $clog2(MaxElems);
  localparam int Cut = Levels / 2;
  localparam int Half = MaxElems >> Cut;
  logic [31:0] node[Cut+1][MaxElems];

  always_comb begin
    for (int e = 0; e < MaxElems; e++) node[0][e] = val[e];
    for (int l = 1; l <= Cut; l++) begin
      for (int e = 0; e < MaxElems; e++) begin
        node[l][e] = (e < (MaxElems >> l)) ? combine(op, node[l-1][2*e], node[l-1][2*e+1]) : 32'd0;
      end
    end
  end

  // Mid tree cut
  logic    [31:0] half_q     [Half];
  logic    [31:0] seed_q;
  vec_op_e        op_q;
  logic    [ 5:0] acc_bits_q;
  logic           first_q;
  logic           step_q;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      step_q <= 1'b0;
    end else if (core_en) begin
      for (int e = 0; e < Half; e++) half_q[e] <= node[Cut][e];
      seed_q     <= widen_val(sign_ext, vs1_data[31:0], acc_bits);
      op_q       <= op;
      acc_bits_q <= acc_bits;
      first_q    <= first;
      step_q     <= step;
    end
  end

  // Rest of tree
  logic [31:0] rest[Levels-Cut+1][Half];
  logic [31:0] folded;

  always_comb begin
    for (int e = 0; e < Half; e++) rest[0][e] = half_q[e];
    for (int l = 1; l <= Levels - Cut; l++) begin
      for (int e = 0; e < Half; e++) begin
        rest[l][e] = (e < (Half >> l)) ? combine(op_q, rest[l-1][2*e], rest[l-1][2*e+1]) : 32'd0;
      end
    end
  end

  assign folded = rest[Levels-Cut][0];

  // Carried accumulator
  logic [31:0] acc_q;
  logic [31:0] acc_next;

  assign acc_next = first_q ? combine(op_q, seed_q, folded) : combine(op_q, acc_q, folded);

  always_ff @(posedge clk) begin
    if (!rst_n) acc_q <= 32'd0;
    else if (core_en && step_q) acc_q <= acc_next;
  end

  assign result = DLEN'(32'(acc_next & (32'hFFFF_FFFF >> (6'd32 - acc_bits_q))));

endmodule

`default_nettype wire
