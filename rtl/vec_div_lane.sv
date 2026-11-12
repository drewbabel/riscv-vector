`default_nettype none

module vec_div_lane
  import vec_pkg::*;
#(
    parameter int ELEN = arch_pkg::ELEN
) (
    input  wire                               clk,
    input  wire                               rst_n,
    input  wire                               core_en,
    input  wire                               start,
    input  wire vec_op_e                      op,
    input  wire          [vec_pkg::VsewW-1:0] vsew,
    input  wire          [          ELEN-1:0] a,
    input  wire          [          ELEN-1:0] b,
    output logic         [          ELEN-1:0] result,
    output logic                              busy,
    output logic                              done
);

  localparam int CountW = $clog2(ELEN + 1);
  localparam logic [vec_pkg::VsewW-1:0] SewTop = vec_pkg::VsewW'($clog2(ELEN / 8));

  if (ELEN != 32) begin : g_elen
    $error("ELEN must be 32 (Zve32f)");
  end

  typedef enum logic [1:0] {
    IDLE,
    EXEC,
    DONE
  } state_t;

  state_t                       state;
  state_t                       next_state;
  logic    [        CountW-1:0] cycle_count;
  logic    [        CountW-1:0] target_iters;
  logic                         op_complete;

  // Operand preparation
  logic                         op_signed;
  logic    [          ELEN-1:0] a_ext;
  logic    [          ELEN-1:0] b_ext;
  logic    [          ELEN-1:0] a_mag;
  logic    [          ELEN-1:0] b_mag;
  logic    [          ELEN-1:0] stored_a;
  logic    [          ELEN-1:0] stored_b;
  vec_op_e                      stored_op;
  logic    [vec_pkg::VsewW-1:0] sew_q;
  logic                         is_div;
  logic    [          ELEN-1:0] min_signed;
  logic                         overflow;

  // Division state
  logic    [          ELEN-1:0] div_n;
  logic    [          ELEN-1:0] div_d;
  logic    [          ELEN-1:0] quotient;
  logic    [          ELEN-1:0] remainder;
  logic                         quot_neg;
  logic                         rem_neg;
  logic    [          ELEN-1:0] trial_rem;
  logic    [          ELEN-1:0] step_remainder;
  logic    [          ELEN-1:0] step_quotient;
  logic    [          ELEN-1:0] div_result;

  function automatic logic [ELEN-1:0] extend(input logic [ELEN-1:0] x,
                                             input logic [vec_pkg::VsewW-1:0] sew, input logic sgn);
    logic [ELEN-1:0] keep;
    keep = {ELEN{1'b1}} >> (ELEN - (8 << sew));
    if (sew >= SewTop) extend = x;
    else if (sgn && x[(8<<sew)-1]) extend = x | ~keep;
    else extend = x & keep;
  endfunction

  function automatic logic [CountW-1:0] sew_iters(input logic [vec_pkg::VsewW-1:0] sew);
    sew_iters = (sew >= SewTop) ? CountW'(ELEN) : CountW'(8 << sew);
  endfunction

  assign op_signed = (op == VEC_DIV) || (op == VEC_REM);
  assign a_ext     = extend(a, vsew, op_signed);
  assign b_ext     = extend(b, vsew, op_signed);
  assign b_mag     = (op_signed && b_ext[ELEN-1]) ? -b_ext : b_ext;

  always_comb begin
    a_mag = (op_signed && a_ext[ELEN-1]) ? -a_ext : a_ext;
    // Left aligned dividend
    a_mag = a_mag << (ELEN - int'(sew_iters(vsew)));
  end

  // Captured element width
  assign target_iters = sew_iters(sew_q);
  assign is_div       = (stored_op != VEC_REM) && (stored_op != VEC_REMU);

  always_comb begin
    case (sew_q)
      3'd0: min_signed = ELEN'($signed(8'h80));
      3'd1: min_signed = ELEN'($signed(16'h8000));
      default: min_signed = ELEN'($signed(32'h8000_0000));
    endcase
  end

  assign overflow = ((stored_op == VEC_DIV) || (stored_op == VEC_REM)) &&
                    (stored_a == min_signed) && (&stored_b);
  assign op_complete = (stored_b == '0) || overflow || (cycle_count == target_iters);

  // Restoring iteration
  assign trial_rem = {remainder[ELEN-2:0], div_n[ELEN-1]};
  always_comb begin
    step_remainder = trial_rem;
    step_quotient  = {quotient[ELEN-2:0], 1'b0};
    if (trial_rem >= div_d) begin
      step_remainder   = trial_rem - div_d;
      step_quotient[0] = 1'b1;
    end
  end

  always_comb begin
    if (stored_b == '0) div_result = is_div ? '1 : stored_a;
    else if (overflow) div_result = is_div ? stored_a : '0;
    else if (is_div) div_result = quot_neg ? -quotient : quotient;
    else div_result = rem_neg ? -remainder : remainder;
    div_result = extend(div_result, sew_q, 1'b0);
  end

  always_comb begin
    next_state = state;
    case (state)
      IDLE: if (start) next_state = EXEC;
      EXEC: if (op_complete) next_state = DONE;
      DONE: next_state = IDLE;
      default: next_state = IDLE;
    endcase
  end

  // Reset and enable
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      state       <= IDLE;
      result      <= '0;
      busy        <= 1'b0;
      done        <= 1'b0;
      cycle_count <= '0;
      stored_a    <= '0;
      stored_b    <= '0;
      stored_op   <= VEC_DIVU;
      sew_q       <= '0;
      div_n       <= '0;
      div_d       <= '0;
      quotient    <= '0;
      remainder   <= '0;
      quot_neg    <= 1'b0;
      rem_neg     <= 1'b0;
    end else if (core_en) begin
      state <= next_state;
      case (state)
        IDLE: begin
          busy <= 1'b0;
          done <= 1'b0;
          if (start) begin
            stored_a    <= a_ext;
            stored_b    <= b_ext;
            stored_op   <= op;
            sew_q       <= vsew;
            busy        <= 1'b1;
            cycle_count <= '0;
            quotient    <= '0;
            remainder   <= '0;
            div_n       <= a_mag;
            div_d       <= b_mag;
            quot_neg    <= op_signed && (a_ext[ELEN-1] ^ b_ext[ELEN-1]);
            rem_neg     <= op_signed && a_ext[ELEN-1];
          end
        end
        EXEC: begin
          // Completion cycle
          if (op_complete) begin
            result <= div_result;
            busy   <= 1'b0;
            done   <= 1'b1;
          end else begin
            cycle_count <= cycle_count + 1'b1;
            div_n       <= div_n << 1;
            remainder   <= step_remainder;
            quotient    <= step_quotient;
          end
        end
        DONE: done <= 1'b0;
        default: begin
          busy <= 1'b0;
          done <= 1'b0;
        end
      endcase
    end
  end

endmodule

`default_nettype wire
