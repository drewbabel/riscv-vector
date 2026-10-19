`default_nettype none

module fp_div_sqrt
  import fp_pkg::RmRne, fp_pkg::RmRtz, fp_pkg::RmRdn, fp_pkg::RmRup, fp_pkg::RmRmm;
  import fp_pkg::FlagNv, fp_pkg::FlagDz, fp_pkg::FlagOf, fp_pkg::FlagUf, fp_pkg::FlagNx;
  import fp_pkg::fp_round_up, fp_pkg::fp_lzc, fp_pkg::FpLzcW;
#(
    parameter  int ExpW  = fp_pkg::ExpW,
    parameter  int FracW = fp_pkg::FracW,
    localparam int FLEN  = 1 + ExpW + FracW
) (
    input  wire             clk,
    input  wire             rst_n,
    input  wire             core_en,
    input  wire             start,
    input  wire             sqrt,
    input  wire  [     2:0] rm,
    input  wire  [FLEN-1:0] a,
    input  wire  [FLEN-1:0] b,
    output logic [FLEN-1:0] result,
    output logic [     4:0] fflags,
    output logic            busy,
    output logic            done
);

  localparam int SigW = FracW + 1;
  localparam int Bias = (1 << (ExpW - 1)) - 1;
  localparam int QuoW = FracW + 3;
  localparam int RemW = QuoW + 2;
  localparam int RadW = SigW + 2;
  localparam int CntW = $clog2(QuoW);
  localparam int IExpW = ExpW + 2;
  localparam int LzW = $clog2(SigW);
  localparam int ShW = $clog2(QuoW);
  localparam int ShCap = (1 << ShW) - 1;
  localparam int ShiftW = 2 * QuoW;

  localparam logic [CntW-1:0] LastIter = CntW'(QuoW - 1);
  localparam logic [IExpW-1:0] ExpInf = IExpW'((1 << ExpW) - 1);
  localparam logic [FLEN-1:0] CanonNan = {1'b0, {ExpW{1'b1}}, 1'b1, {(FracW - 1) {1'b0}}};
  localparam logic [FLEN-2:0] InfMag = {{ExpW{1'b1}}, {FracW{1'b0}}};
  localparam logic [FLEN-2:0] MaxMag = {{(ExpW - 1) {1'b1}}, 1'b0, {FracW{1'b1}}};

  typedef enum logic [2:0] {
    IDLE,
    PREP,
    ITER,
    ROUND,
    DONE
  } state_t;
  state_t state;

  if (!((FracW < (1 << (ExpW - 1))) && (SigW <= FpLzcW))) begin : g_width_error
    $error("ExpW and FracW outside the supported range");
  end

  logic [FLEN-1:0] a_q;
  logic [FLEN-1:0] b_q;
  logic sqrt_q;
  logic [2:0] rm_q;

  logic sign_q;
  logic [IExpW-1:0] exp_q;
  logic [RemW-1:0] rem_q;
  logic [RadW-1:0] src_q;
  logic [QuoW-1:0] quo_q;
  logic [CntW-1:0] cnt_q;

  logic a_zero, a_inf, a_nan, a_snan;
  logic b_zero, b_inf, b_nan, b_snan;
  assign a_zero = a_q[FLEN-2:0] == '0;
  assign a_inf  = (&a_q[FLEN-2:FracW]) && (a_q[FracW-1:0] == '0);
  assign a_nan  = (&a_q[FLEN-2:FracW]) && (a_q[FracW-1:0] != '0);
  assign a_snan = a_nan && !a_q[FracW-1];
  assign b_zero = b_q[FLEN-2:0] == '0;
  assign b_inf  = (&b_q[FLEN-2:FracW]) && (b_q[FracW-1:0] == '0);
  assign b_nan  = (&b_q[FLEN-2:FracW]) && (b_q[FracW-1:0] != '0);
  assign b_snan = b_nan && !b_q[FracW-1];

  logic [SigW-1:0] a_man, b_man;
  logic [LzW-1:0] a_lz, b_lz;
  logic [SigW-1:0] a_sig, b_sig;
  logic [IExpW-1:0] a_exp, b_exp;
  assign a_man = {a_q[FLEN-2:FracW] != '0, a_q[FracW-1:0]};
  assign b_man = {b_q[FLEN-2:FracW] != '0, b_q[FracW-1:0]};
  assign a_lz  = LzW'(fp_lzc(FpLzcW'(a_man), SigW));
  assign b_lz  = LzW'(fp_lzc(FpLzcW'(b_man), SigW));
  assign a_sig = a_man << a_lz;
  assign b_sig = b_man << b_lz;
  assign a_exp = IExpW'(a_q[FLEN-2:FracW]) + IExpW'(a_q[FLEN-2:FracW] == '0) - IExpW'(a_lz);
  assign b_exp = IExpW'(b_q[FLEN-2:FracW]) + IExpW'(b_q[FLEN-2:FracW] == '0) - IExpW'(b_lz);

  // Special case results
  logic a_neg;
  logic sign_div;
  logic special;
  logic [FLEN-1:0] spec_result;
  logic [4:0] spec_flags;
  assign a_neg = a_q[FLEN-1];
  assign sign_div = a_neg ^ b_q[FLEN-1];

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
        spec_result = {sign_div, InfMag};
        spec_flags  = a_inf ? 5'd0 : FlagDz;
      end else if (a_zero || b_inf) spec_result = {sign_div, {(FLEN - 1) {1'b0}}};
      else special = 1'b0;
    end
  end

  // Divide setup
  logic sig_lt;
  logic [SigW:0] div_rem;
  logic [IExpW-1:0] div_exp;
  assign sig_lt  = a_sig < b_sig;
  assign div_rem = sig_lt ? {a_sig, 1'b0} : {1'b0, a_sig};
  assign div_exp = a_exp - b_exp + IExpW'(Bias) - IExpW'(sig_lt);

  // Square root setup
  logic [ RadW-1:0] sqrt_rad;
  logic [IExpW-1:0] sqrt_exp;
  assign sqrt_rad = a_exp[0] ? {1'b0, a_sig, 1'b0} : {a_sig, 2'b00};
  assign sqrt_exp = (a_exp + IExpW'(Bias - 1) + IExpW'(a_exp[0])) >> 1;

  // One result bit
  logic [RemW-1:0] sqrt_sh;
  logic [RemW-1:0] rem_sh;
  logic [RemW-1:0] trial;
  logic q_bit;
  logic [RemW-1:0] rem_nxt;
  assign sqrt_sh = {rem_q[RemW-3:0], src_q[RadW-1:RadW-2]};
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
  logic [IExpW-1:0] sh_full;
  logic [ShW-1:0] sh;
  logic [ShiftW-1:0] shifted;
  assign sticky = rem_q != '0;
  assign sub = exp_q[IExpW-1] || (exp_q == '0);
  assign sh_full = IExpW'(1) - exp_q;
  always_comb begin
    if (!sub) sh = '0;
    else if (sh_full > IExpW'(ShCap)) sh = ShW'(ShCap);
    else sh = sh_full[ShW-1:0];
  end
  assign shifted = {quo_q, {QuoW{1'b0}}} >> sh;

  // Rounding
  logic [SigW-1:0] mant;
  logic guard;
  logic st;
  logic inexact;
  logic [SigW:0] mant_r;
  logic [IExpW-1:0] e_pre;
  logic [IExpW-1:0] e_out;
  logic ovf;
  logic ovf_inf;
  assign mant = shifted[ShiftW-1:ShiftW-SigW];
  assign guard = shifted[ShiftW-SigW-1];
  assign st = (shifted[ShiftW-SigW-2:0] != '0) || sticky;
  assign inexact = guard || st;
  assign mant_r = {1'b0, mant} + (SigW + 1)'(fp_round_up(rm_q, sign_q, mant[0], guard, st));
  assign e_pre = sub ? '0 : exp_q - IExpW'(1);
  assign e_out = e_pre + IExpW'(mant_r[SigW:SigW-1]);
  assign ovf = !sub && (e_out >= ExpInf);
  assign ovf_inf = (rm_q == RmRne) || (rm_q == RmRmm) || ((rm_q == RmRdn) && sign_q) ||
      ((rm_q == RmRup) && !sign_q);

  // Tininess after rounding
  logic carry_sig;
  logic tiny;
  assign carry_sig = (&quo_q[QuoW-1:2]) && fp_round_up(
      rm_q, sign_q, quo_q[2], quo_q[1], quo_q[0] || sticky
  );
  assign tiny = exp_q[IExpW-1] || ((exp_q == '0) && !carry_sig);

  logic [FLEN-1:0] rnd_packed;
  logic [FLEN-1:0] rnd_result;
  logic [     4:0] rnd_flags;
  assign rnd_packed = {sign_q, e_out[ExpW-1:0], mant_r[FracW-1:0]};
  always_comb begin
    if (ovf) begin
      rnd_result = ovf_inf ? {sign_q, InfMag} : {sign_q, MaxMag};
      rnd_flags  = FlagOf | FlagNx;
    end else begin
      rnd_result = rnd_packed;
      rnd_flags  = '0;
      if (tiny && inexact) rnd_flags = rnd_flags | FlagUf;
      if (inexact) rnd_flags = rnd_flags | FlagNx;
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
        IDLE, DONE: begin
          busy  <= 1'b0;
          done  <= 1'b0;
          state <= IDLE;
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
            rem_q  <= sqrt_q ? '0 : RemW'(div_rem);
            src_q  <= sqrt_q ? sqrt_rad : {2'b00, b_sig};
            quo_q  <= '0;
            cnt_q  <= '0;
            state  <= ITER;
          end
        end
        ITER: begin
          rem_q <= sqrt_q ? rem_nxt : rem_nxt << 1;
          src_q <= sqrt_q ? src_q << 2 : src_q;
          quo_q <= {quo_q[QuoW-2:0], q_bit};
          cnt_q <= cnt_q + CntW'(1);
          if (cnt_q == LastIter) state <= ROUND;
        end
        ROUND: begin
          result <= rnd_result;
          fflags <= rnd_flags;
          busy   <= 1'b0;
          done   <= 1'b1;
          state  <= DONE;
        end
        default: state <= IDLE;
      endcase
    end
  end

endmodule

`default_nettype wire
