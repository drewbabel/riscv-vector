`default_nettype none

module vec_alu_lane_formal
  import vec_pkg::*;
();

  localparam int ELEN   = arch_pkg::ELEN;
  localparam int Widths = $clog2(ELEN / 8) + 1;

  logic               clk;

  (* anyseq *)vec_op_e            op;
  (* anyseq *)logic               vm;
  (* anyseq *)logic               mask_bit;
  (* anyseq *)logic    [ELEN-1:0] a;
  (* anyseq *)logic    [ELEN-1:0] b;

  function automatic logic is_alu(input vec_op_e o);
    return (o == VEC_ADD) || (o == VEC_SUB) || (o == VEC_RSUB) || (o == VEC_AND) ||
        (o == VEC_OR) || (o == VEC_XOR) || (o == VEC_SLL) || (o == VEC_SRL) || (o == VEC_SRA) ||
        (o == VEC_MINU) || (o == VEC_MIN) || (o == VEC_MAXU) || (o == VEC_MAX) ||
        (o == VEC_ADC) || (o == VEC_SBC) || (o == VEC_MERGE) || (o == VEC_MVNRR);
  endfunction

  // Lane per SEW
  for (genvar w = 0; w < Widths; w++) begin : g_sew
    localparam int S  = 8 << w;
    localparam int Lg = $clog2(S);

    logic [S-1:0] ea;
    logic [S-1:0] eb;
    logic [S-1:0] result;

    assign ea = a[S-1:0];
    assign eb = b[S-1:0];

    vec_alu_lane #(
        .W(S)
    ) dut (
        .op      (op),
        .vm      (vm),
        .mask_bit(mask_bit),
        .a       (ea),
        .b       (eb),
        .result  (result)
    );

    // Bitwise shifts
    function automatic logic [S-1:0] shl(input logic [S-1:0] x, input int sh);
      logic [S-1:0] y;
      y = '0;
      for (int i = 0; i < S; i++) for (int j = 0; j < S; j++) if (j + sh == i) y[i] = x[j];
      return y;
    endfunction

    function automatic logic [S-1:0] shr(input logic [S-1:0] x, input int sh, input logic fill);
      logic [S-1:0] y;
      y = {S{fill}};
      for (int i = 0; i < S; i++) for (int j = 0; j < S; j++) if (i + sh == j) y[i] = x[j];
      return y;
    endfunction

    // Signed order
    function automatic logic slt(input logic [S-1:0] x, input logic [S-1:0] y);
      return (x ^ (S'(1) << (S - 1))) < (y ^ (S'(1) << (S - 1)));
    endfunction

    // Reference element
    int           sh;
    logic [S-1:0] exp_res;

    assign sh = int'(eb[Lg-1:0]);

    always_comb begin
      exp_res = '0;
      if (op == VEC_ADD) exp_res = ea + eb;
      else if (op == VEC_SUB) exp_res = ea + ~eb + S'(1);
      else if (op == VEC_RSUB) exp_res = eb + ~ea + S'(1);
      else if (op == VEC_AND) exp_res = ea & eb;
      else if (op == VEC_OR) exp_res = ea | eb;
      else if (op == VEC_XOR) exp_res = ea ^ eb;
      else if (op == VEC_SLL) exp_res = shl(ea, sh);
      else if (op == VEC_SRL) exp_res = shr(ea, sh, 1'b0);
      else if (op == VEC_SRA) exp_res = shr(ea, sh, ea[S-1]);
      else if (op == VEC_MINU) exp_res = (eb < ea) ? eb : ea;
      else if (op == VEC_MIN) exp_res = slt(eb, ea) ? eb : ea;
      else if (op == VEC_MAXU) exp_res = (ea < eb) ? eb : ea;
      else if (op == VEC_MAX) exp_res = slt(ea, eb) ? eb : ea;
      else if (op == VEC_ADC) exp_res = ea + eb + S'(mask_bit);
      else if (op == VEC_SBC) exp_res = ea + ~eb + S'(!mask_bit);
      else if (op == VEC_MERGE) exp_res = (!vm && !mask_bit) ? ea : eb;
      else if (op == VEC_MVNRR) exp_res = ea;
    end

    always @(posedge clk) begin
      if (is_alu(op)) assert (result == exp_res);
    end

    // Covers
    always @(posedge clk) begin
      cover (op == VEC_ADD && result < ea);
      cover (op == VEC_RSUB && result != '0);
      cover (op == VEC_SLL && sh == S - 1 && result[S-1]);
      cover (op == VEC_SRA && ea[S-1] && sh != 0 && result[S-1]);
      cover (op == VEC_SRL && sh != 0 && ea[S-1] && !result[S-1]);
      cover (op == VEC_MIN && ea[S-1] != eb[S-1] && result == ea);
      cover (op == VEC_MAXU && ea[S-1] != eb[S-1] && result == eb);
      cover (op == VEC_ADC && mask_bit && result == '0);
      cover (op == VEC_SBC && mask_bit && result == '1);
      cover (op == VEC_MERGE && !vm && !mask_bit && ea != eb);
      cover (op == VEC_MERGE && vm && !mask_bit && result == eb && ea != eb);
    end
  end

endmodule

`default_nettype wire
