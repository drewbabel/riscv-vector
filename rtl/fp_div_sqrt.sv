`default_nettype none

module fp_div_sqrt (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         core_en,
    input  wire         start,
    input  wire         sqrt,
    input  wire  [ 2:0] rm,
    input  wire  [31:0] a,
    input  wire  [31:0] b,
    output logic [31:0] result,
    output logic [ 4:0] fflags,
    output logic        busy,
    output logic        done
);

  // Rounding modes
  localparam logic [2:0] Rne = 3'd0;
  localparam logic [2:0] Rtz = 3'd1;
  localparam logic [2:0] Rdn = 3'd2;
  localparam logic [2:0] Rup = 3'd3;
  localparam logic [2:0] Rmm = 3'd4;

  localparam logic [4:0] FlagNv = 5'b10000;
  localparam logic [4:0] FlagDz = 5'b01000;
  localparam logic [4:0] FlagOfNx = 5'b00101;

  localparam logic [31:0] CanonNan = 32'h7FC0_0000;

  localparam int SigW = 26;
  localparam logic [4:0] LastIter = 5'(SigW - 1);

  typedef enum logic [2:0] {
    IDLE,
    PREP,
    ITER,
    ROUND,
    DONE
  } state_t;
  state_t state;

  logic [31:0] a_q;
  logic [31:0] b_q;
  logic sqrt_q;
  logic [2:0] rm_q;

  logic sign_q;
  logic [9:0] exp_q;  // Biased result exponent
  logic [27:0] rem_q;
  logic [25:0] src_q;  // Divisor or radicand
  logic [SigW-1:0] quo_q;  // Quotient or root
  logic [4:0] cnt_q;

  function automatic logic [4:0] lzc24(input logic [23:0] x);
    lzc24 = 5'd0;
    for (int i = 0; i < 24; i++) begin
      if (x[i]) lzc24 = 5'(23 - i);
    end
  endfunction

  function automatic logic round_up(input logic [2:0] mode, input logic neg, input logic lsb,
                                    input logic g, input logic s);
    case (mode)
      Rne: round_up = g && (s || lsb);
      Rtz: round_up = 1'b0;
      Rdn: round_up = neg && (g || s);
      Rup: round_up = !neg && (g || s);
      Rmm: round_up = g;
      default: round_up = 1'b0;
    endcase
  endfunction

  logic a_zero, a_inf, a_nan, a_snan;
  logic b_zero, b_inf, b_nan, b_snan;
  assign a_zero = a_q[30:0] == 31'd0;
  assign a_inf  = (a_q[30:23] == 8'hFF) && (a_q[22:0] == 23'd0);
  assign a_nan  = (a_q[30:23] == 8'hFF) && (a_q[22:0] != 23'd0);
  assign a_snan = a_nan && !a_q[22];
  assign b_zero = b_q[30:0] == 31'd0;
  assign b_inf  = (b_q[30:23] == 8'hFF) && (b_q[22:0] == 23'd0);
  assign b_nan  = (b_q[30:23] == 8'hFF) && (b_q[22:0] != 23'd0);
  assign b_snan = b_nan && !b_q[22];

  logic [23:0] a_man, b_man;
  logic [4:0] a_lz, b_lz;
  logic [23:0] a_sig, b_sig;
  logic [9:0] a_exp, b_exp;
  assign a_man = {a_q[30:23] != 8'd0, a_q[22:0]};
  assign b_man = {b_q[30:23] != 8'd0, b_q[22:0]};
  assign a_lz  = lzc24(a_man);
  assign b_lz  = lzc24(b_man);
  assign a_sig = a_man << a_lz;
  assign b_sig = b_man << b_lz;
  assign a_exp = 10'(a_q[30:23]) + 10'(a_q[30:23] == 8'd0) - 10'(a_lz);
  assign b_exp = 10'(b_q[30:23]) + 10'(b_q[30:23] == 8'd0) - 10'(b_lz);

  // Special case results
  logic a_neg;
  logic sign_div;
  logic special;
  logic [31:0] spec_result;
  logic [4:0] spec_flags;
  assign a_neg = a_q[31];
  assign sign_div = a_neg ^ b_q[31];

  always_comb begin
    special = 1'b1;
    spec_result = CanonNan;
    spec_flags = 5'd0;
    if (sqrt_q) begin
      if (a_nan) spec_flags = a_snan ? FlagNv : 5'd0;
      else if (a_zero || (a_inf && !a_neg)) spec_result = a_q;
      else if (a_neg) spec_flags = FlagNv;
      else special = 1'b0;
    end else begin
      if (a_nan || b_nan) spec_flags = (a_snan || b_snan) ? FlagNv : 5'd0;
      else if ((a_inf && b_inf) || (a_zero && b_zero)) spec_flags = FlagNv;
      else if (a_inf || b_zero) begin
        spec_result = {sign_div, 8'hFF, 23'd0};
        spec_flags  = a_inf ? 5'd0 : FlagDz;
      end else if (a_zero || b_inf) spec_result = {sign_div, 31'd0};
      else special = 1'b0;
    end
  end

  // Divide setup
  logic sig_lt;
  logic [24:0] div_rem;
  logic [9:0] div_exp;
  assign sig_lt  = a_sig < b_sig;
  assign div_rem = sig_lt ? {a_sig, 1'b0} : {1'b0, a_sig};
  assign div_exp = a_exp - b_exp + 10'd127 - 10'(sig_lt);

  // Odd exponent shifts radicand
  logic [25:0] sqrt_rad;
  logic [ 9:0] sqrt_exp;
  assign sqrt_rad = a_exp[0] ? {1'b0, a_sig, 1'b0} : {a_sig, 2'b00};
  assign sqrt_exp = (a_exp + 10'd126 + 10'(a_exp[0])) >> 1;

  // One result bit
  logic [27:0] sqrt_sh;
  logic [27:0] rem_sh;
  logic [27:0] trial;
  logic q_bit;
  logic [27:0] rem_nxt;
  assign sqrt_sh = {rem_q[25:0], src_q[25:24]};
  always_comb begin
    if (sqrt_q) begin
      rem_sh = sqrt_sh;
      trial  = {quo_q, 2'b01};
    end else begin
      rem_sh = rem_q;
      trial  = {2'b00, src_q};
    end
    q_bit   = rem_sh >= trial;
    rem_nxt = q_bit ? rem_sh - trial : rem_sh;
  end

  // Subnormal shift
  logic sticky;
  logic sub;
  logic [9:0] sh_full;
  logic [4:0] sh;
  logic [51:0] shifted;
  assign sticky = rem_q != 28'd0;
  assign sub = exp_q[9] || (exp_q == 10'd0);
  assign sh_full = 10'd1 - exp_q;
  assign sh = !sub ? 5'd0 : (sh_full > 10'd31) ? 5'd31 : sh_full[4:0];
  assign shifted = {quo_q, 26'd0} >> sh;

  // Rounding
  logic [23:0] mant;
  logic guard;
  logic st;
  logic inexact;
  logic [24:0] mant_r;
  logic [9:0] e_pre;
  logic [9:0] e_out;
  logic ovf;
  logic ovf_inf;
  assign mant = shifted[51:28];
  assign guard = shifted[27];
  assign st = shifted[26] || (shifted[25:0] != 26'd0) || sticky;
  assign inexact = guard || st;
  assign mant_r = {1'b0, mant} + 25'(round_up(rm_q, sign_q, mant[0], guard, st));
  assign e_pre = sub ? 10'd0 : exp_q - 10'd1;
  assign e_out = e_pre + 10'(mant_r[24:23]);
  assign ovf = !sub && (e_out >= 10'd255);
  assign ovf_inf = (rm_q == Rne) || (rm_q == Rmm) || ((rm_q == Rdn) && sign_q) ||
      ((rm_q == Rup) && !sign_q);

  // Tininess after rounding
  logic carry24;
  logic tiny;
  assign carry24 = (&quo_q[25:2]) && round_up(rm_q, sign_q, quo_q[2], quo_q[1], quo_q[0] || sticky);
  assign tiny = exp_q[9] || ((exp_q == 10'd0) && !carry24);

  logic [31:0] rnd_packed;
  logic [31:0] rnd_result;
  logic [ 4:0] rnd_flags;
  assign rnd_packed = {sign_q, e_out[7:0], mant_r[22:0]};
  always_comb begin
    if (ovf) begin
      rnd_result = ovf_inf ? {sign_q, 8'hFF, 23'd0} : {sign_q, 8'hFE, 23'h7F_FFFF};
      rnd_flags  = FlagOfNx;
    end else begin
      rnd_result = rnd_packed;
      rnd_flags  = {3'b000, tiny && inexact, inexact};
    end
  end

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      state  <= IDLE;
      result <= '0;
      fflags <= '0;
      busy   <= 1'b0;
      done   <= 1'b0;
      a_q    <= '0;
      b_q    <= '0;
      sqrt_q <= 1'b0;
      rm_q   <= '0;
      sign_q <= 1'b0;
      exp_q  <= '0;
      rem_q  <= '0;
      src_q  <= '0;
      quo_q  <= '0;
      cnt_q  <= '0;
    end else if (core_en) begin
      case (state)
        IDLE: begin
          busy <= 1'b0;
          done <= 1'b0;
          if (start) begin
            a_q    <= a;
            b_q    <= b;
            sqrt_q <= sqrt;
            rm_q   <= rm;
            busy   <= 1'b1;
            state  <= PREP;
          end
        end
        PREP: begin
          if (special) begin
            result <= spec_result;
            fflags <= spec_flags;
            busy   <= 1'b0;
            done   <= 1'b1;
            state  <= DONE;
          end else begin
            sign_q <= !sqrt_q && sign_div;
            exp_q  <= sqrt_q ? sqrt_exp : div_exp;
            rem_q  <= sqrt_q ? 28'd0 : 28'(div_rem);
            src_q  <= sqrt_q ? sqrt_rad : {2'b00, b_sig};
            quo_q  <= '0;
            cnt_q  <= '0;
            state  <= ITER;
          end
        end
        ITER: begin
          rem_q <= sqrt_q ? rem_nxt : rem_nxt << 1;
          src_q <= sqrt_q ? src_q << 2 : src_q;
          quo_q <= {quo_q[SigW-2:0], q_bit};
          cnt_q <= cnt_q + 5'd1;
          if (cnt_q == LastIter) state <= ROUND;
        end
        ROUND: begin
          result <= rnd_result;
          fflags <= rnd_flags;
          busy   <= 1'b0;
          done   <= 1'b1;
          state  <= DONE;
        end
        DONE: begin
          done  <= 1'b0;
          state <= IDLE;
        end
        default: state <= IDLE;
      endcase
    end
  end

endmodule

`default_nettype wire
