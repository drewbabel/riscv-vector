`default_nettype none

module muldiv_formal
  import muldiv_pkg::*;
#(
    parameter bit DIVIDE = 1'b0
) ();

  localparam int XLEN = arch_pkg::XLEN;

  logic                                    clk;

  (* anyseq *)logic                                    core_en;
  (* anyseq *)logic                                    rst_n;
  (* anyseq *)logic                                    start;
  (* anyseq *)muldiv_pkg::muldiv_op_e                  op;
  (* anyseq *)logic                   [      XLEN-1:0] a;
  (* anyseq *)logic                   [      XLEN-1:0] b;

  logic                   [      XLEN-1:0] result;
  logic                                    busy;
  logic                                    done;
  logic                   [           1:0] dbg_state;
  logic                   [      XLEN-1:0] dbg_stored_a;
  logic                   [      XLEN-1:0] dbg_stored_b;
  muldiv_pkg::muldiv_op_e                  dbg_stored_op;
  logic                   [      XLEN-1:0] dbg_quotient;
  logic                   [      XLEN-1:0] dbg_remainder;
  logic                   [      XLEN-1:0] dbg_div_n;
  logic                   [      XLEN-1:0] dbg_div_d;
  logic                   [$clog2(XLEN):0] dbg_cycle_count;
  logic                                    dbg_quot_neg;
  logic                                    dbg_rem_neg;

  muldiv #(
      .XLEN(XLEN)
  ) dut (
      .dbg_state      (dbg_state),
      .dbg_stored_a   (dbg_stored_a),
      .dbg_stored_b   (dbg_stored_b),
      .dbg_stored_op  (dbg_stored_op),
      .dbg_quotient   (dbg_quotient),
      .dbg_remainder  (dbg_remainder),
      .dbg_div_n      (dbg_div_n),
      .dbg_div_d      (dbg_div_d),
      .dbg_cycle_count(dbg_cycle_count),
      .dbg_quot_neg   (dbg_quot_neg),
      .dbg_rem_neg    (dbg_rem_neg),
      .clk            (clk),
      .core_en        (core_en),
      .rst_n          (rst_n),
      .start          (start),
      .op             (op),
      .a              (a),
      .b              (b),
      .result         (result),
      .busy           (busy),
      .done           (done)
  );

  logic f_past_valid = 1'b0;
  always @(posedge clk) f_past_valid <= 1'b1;

  // Reset first cycle
  always_comb if (!f_past_valid) assume (!rst_n);

  logic f_accept;
  assign f_accept = rst_n && core_en && start && !busy && !done;

  // Capture the accepted operands
  muldiv_pkg::muldiv_op_e            ref_op;
  logic                   [XLEN-1:0] ref_a;
  logic                   [XLEN-1:0] ref_b;
  always @(posedge clk)
    if (f_accept) begin
      ref_op <= op;
      ref_a  <= a;
      ref_b  <= b;
    end

  // Golden high and low products from the spec
  logic signed [  XLEN-1:0] sa;
  logic signed [  XLEN-1:0] sb;
  logic        [2*XLEN-1:0] prod_ss;
  logic        [2*XLEN-1:0] prod_su;
  logic        [2*XLEN-1:0] prod_uu;
  assign sa      = dbg_stored_a;
  assign sb      = dbg_stored_b;
  assign prod_ss = $signed((2 * XLEN)'(sa)) * $signed((2 * XLEN)'(sb));
  assign prod_su = $signed((2 * XLEN)'(sa)) * $signed({{XLEN{1'b0}}, dbg_stored_b});
  assign prod_uu = {{XLEN{1'b0}}, dbg_stored_a} * {{XLEN{1'b0}}, dbg_stored_b};

  logic [XLEN-1:0] mul_exp;
  always_comb begin
    case (dbg_stored_op)
      MD_MUL:    mul_exp = dbg_stored_a * dbg_stored_b;
      MD_MULH:   mul_exp = prod_ss[2*XLEN-1:XLEN];
      MD_MULHSU: mul_exp = prod_su[2*XLEN-1:XLEN];
      MD_MULHU:  mul_exp = prod_uu[2*XLEN-1:XLEN];
      default:   mul_exp = 'x;
    endcase
  end

  logic [XLEN-1:0] int_min;
  assign int_min = {1'b1, {(XLEN - 1) {1'b0}}};

  logic overflow;
  assign overflow = (ref_a == int_min) && (&ref_b);

  logic is_mul;
  assign is_mul = (ref_op == MD_MUL) || (ref_op == MD_MULH) || (ref_op == MD_MULHSU) ||
      (ref_op == MD_MULHU);

  logic f_started = 1'b0;
  always @(posedge clk)
    if (!rst_n) f_started <= 1'b0;
    else if (f_accept) f_started <= 1'b1;

  localparam logic [1:0] Idle = 2'd0;
  localparam logic [1:0] Exec = 2'd1;
  localparam logic [1:0] Done = 2'd2;

  // Operands held until done
  always @(posedge clk)
    if (rst_n) begin
      assert (dbg_state != 2'd3);
      assert (busy == (dbg_state == Exec));
      assert (done == (dbg_state == Done));
      if (dbg_state != Idle) begin
        assert (f_started);
        assert (dbg_stored_op == ref_op);
        assert (dbg_stored_a == ref_a);
        assert (dbg_stored_b == ref_b);
      end
      if (done) begin
        assert ($past(dbg_stored_op) == ref_op);
        assert ($past(dbg_stored_a) == ref_a);
        assert ($past(dbg_stored_b) == ref_b);
      end
    end

  // Multiply and special cases
  always @(posedge clk)
    if (rst_n) begin
      assert (!(busy && done));
      if (f_started && done) begin
        if (is_mul && !$past(done)) assert (result == $past(mul_exp));
        if ($past(done)) assert (result == $past(result));
        if ((ref_op == MD_DIV) && (ref_b == '0)) assert (&result);
        if ((ref_op == MD_DIV) && overflow) assert (result == int_min);
        if ((ref_op == MD_DIVU) && (ref_b == '0)) assert (&result);
        if ((ref_op == MD_REM) && (ref_b == '0)) assert (result == ref_a);
        if ((ref_op == MD_REM) && overflow) assert (result == '0);
        if ((ref_op == MD_REMU) && (ref_b == '0)) assert (result == ref_a);
      end
    end

  logic is_signed;
  assign is_signed = (ref_op == MD_DIV) || (ref_op == MD_REM);

  // General divide task only
  if (DIVIDE) begin : g_divide
    (* anyconst *) logic [XLEN-1:0] f_a;
    (* anyconst *) logic [XLEN-1:0] f_b;
    logic f_pick;
    assign f_pick = (ref_a == f_a) && (ref_b == f_b);

    // Spec quotient and remainder
    logic [XLEN-1:0] div_exp;
    always_comb begin
      case (ref_op)
        MD_DIVU: div_exp = f_a / f_b;
        MD_REMU: div_exp = f_a % f_b;
        MD_DIV:  div_exp = $signed(f_a) / $signed(f_b);
        MD_REM:  div_exp = $signed(f_a) % $signed(f_b);
        default: div_exp = 'x;
      endcase
    end

    logic [XLEN-1:0] mag_a;
    logic [XLEN-1:0] mag_b;
    logic [XLEN-1:0] abs_a;
    logic [XLEN-1:0] abs_b;
    assign mag_a = f_a[XLEN-1] ? -f_a : f_a;
    assign mag_b = f_b[XLEN-1] ? -f_b : f_b;
    assign abs_a = is_signed ? mag_a : f_a;
    assign abs_b = is_signed ? mag_b : f_b;

    // Long division stages
    logic [XLEN-1:0] u_in[XLEN+1];
    logic [XLEN-1:0] s_in[XLEN+1];
    logic [XLEN-1:0] u_q;
    logic [XLEN-1:0] s_q;
    assign u_in[0] = f_a;
    assign s_in[0] = mag_a;
    for (genvar i = 0; i < XLEN; i++) begin : g_stage
      localparam int Pad = XLEN - (i + 1);
      assign u_q[Pad]  = (XLEN + Pad)'(u_in[i]) >= {f_b, {Pad{1'b0}}};
      assign u_in[i+1] = u_q[Pad] ? XLEN'((XLEN + Pad)'(u_in[i]) - {f_b, {Pad{1'b0}}}) : u_in[i];
      assign s_q[Pad]  = (XLEN + Pad)'(s_in[i]) >= {mag_b, {Pad{1'b0}}};
      assign s_in[i+1] = s_q[Pad] ? XLEN'((XLEN + Pad)'(s_in[i]) - {mag_b, {Pad{1'b0}}}) : s_in[i];
    end

    logic [$clog2(XLEN):0] steps;
    assign steps = dbg_cycle_count;

    always @(posedge clk)
      if (rst_n && (dbg_state != Idle) && f_pick) begin
        assert (dbg_div_d == abs_b);
        assert (dbg_quot_neg == (is_signed && (ref_a[XLEN-1] ^ ref_b[XLEN-1])));
        assert (dbg_rem_neg == (is_signed && ref_a[XLEN-1]));
        assert (steps <= ($bits(steps))'(XLEN));
      end

    for (genvar k = 0; k <= XLEN; k++) begin : g_step
      logic [XLEN-1:0] stage_in;
      logic [XLEN-1:0] stage_q;
      assign stage_in = is_signed ? s_in[k] : u_in[k];
      assign stage_q  = is_signed ? s_q : u_q;
      always @(posedge clk)
        if (rst_n && (dbg_state != Idle) && f_pick && (steps == k)) begin
          assert (dbg_div_n == (abs_a << k));
          assert (dbg_quotient == (stage_q >> (XLEN - k)));
          assert (dbg_remainder == (stage_in >> (XLEN - k)));
        end
    end

    always @(posedge clk)
      if (rst_n && f_started && done && f_pick && !is_mul && (ref_b != '0) &&
          !(is_signed && overflow))
        assert (result == div_exp);
  end

  logic f_b2b;
  always @(posedge clk)
    if (!rst_n) f_b2b <= 1'b0;
    else if (f_accept) f_b2b <= $past(rst_n && done);

  always @(posedge clk)
    if (rst_n && done) begin
      cover (is_mul);
      cover (!is_mul && (ref_b != '0) && !(is_signed && overflow));
      cover (!is_mul && (ref_b == '0));
      cover (is_signed && overflow);
      cover (f_b2b);
    end

endmodule

`default_nettype wire
