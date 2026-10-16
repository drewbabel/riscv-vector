`default_nettype none

module fp_mul (
    input  wire  [ 2:0] rm,
    input  wire  [31:0] a,
    input  wire  [31:0] b,
    output logic [31:0] result,
    output logic [ 4:0] fflags
);

  localparam logic [2:0] RmRne = 3'd0;
  localparam logic [2:0] RmRtz = 3'd1;
  localparam logic [2:0] RmRdn = 3'd2;
  localparam logic [2:0] RmRup = 3'd3;
  localparam logic [2:0] RmRmm = 3'd4;

  localparam logic [4:0] FlagNv = 5'b10000;
  localparam logic [4:0] FlagOf = 5'b00100;
  localparam logic [4:0] FlagUf = 5'b00010;
  localparam logic [4:0] FlagNx = 5'b00001;

  localparam logic [31:0] CanonicalNan = 32'h7FC0_0000;
  localparam logic [4:0] MaxRshift = 5'd26;

  function automatic logic round_up(input logic [2:0] mode, input logic neg, input logic lsb,
                                    input logic half, input logic rest);
    case (mode)
      RmRne:   round_up = half && (rest || lsb);
      RmRtz:   round_up = 1'b0;
      RmRdn:   round_up = neg && (half || rest);
      RmRup:   round_up = !neg && (half || rest);
      RmRmm:   round_up = half;
      default: round_up = 1'b0;
    endcase
  endfunction

  logic sign_a, sign_b, sign;
  logic [7:0] exp_a, exp_b;
  logic [22:0] frac_a, frac_b;
  assign {sign_a, exp_a, frac_a} = a;
  assign {sign_b, exp_b, frac_b} = b;
  assign sign = sign_a ^ sign_b;

  logic zero_a, zero_b, inf_a, inf_b, nan_a, nan_b, snan_a, snan_b;
  assign zero_a = (exp_a == 8'h00) && (frac_a == 23'd0);
  assign zero_b = (exp_b == 8'h00) && (frac_b == 23'd0);
  assign inf_a  = (exp_a == 8'hFF) && (frac_a == 23'd0);
  assign inf_b  = (exp_b == 8'hFF) && (frac_b == 23'd0);
  assign nan_a  = (exp_a == 8'hFF) && (frac_a != 23'd0);
  assign nan_b  = (exp_b == 8'hFF) && (frac_b != 23'd0);
  assign snan_a = nan_a && !frac_a[22];
  assign snan_b = nan_b && !frac_b[22];

  logic invalid;
  assign invalid = snan_a || snan_b || (inf_a && zero_b) || (zero_a && inf_b);

  logic [7:0] eff_exp_a, eff_exp_b;
  logic [23:0] sig_a, sig_b;
  assign eff_exp_a = (exp_a == 8'h00) ? 8'd1 : exp_a;
  assign eff_exp_b = (exp_b == 8'h00) ? 8'd1 : exp_b;
  assign sig_a = {exp_a != 8'h00, frac_a};
  assign sig_b = {exp_b != 8'h00, frac_b};

  logic [47:0] prod;
  assign prod = {24'd0, sig_a} * {24'd0, sig_b};

  logic [5:0] lz;
  always_comb begin
    lz = 6'd0;
    for (int i = 0; i < 48; i++) begin
      if (prod[i]) lz = 6'(47 - i);
    end
  end

  logic [9:0] exp_top, exp_lz, rshift_full;
  assign exp_top     = {2'd0, eff_exp_a} + {2'd0, eff_exp_b} - 10'd126;
  assign exp_lz      = exp_top - {4'd0, lz};
  assign rshift_full = 10'd1 - exp_top;

  logic normal, partial_left;
  assign normal       = !exp_lz[9] && (exp_lz != 10'd0);
  assign partial_left = !exp_top[9] && (exp_top != 10'd0);

  logic [5:0] lshift;
  logic [4:0] rshift;
  logic [8:0] exp_norm;
  assign lshift = normal ? lz : (partial_left ? exp_top[5:0] - 6'd1 : 6'd0);
  assign rshift = (normal || partial_left) ? 5'd0
      : ((rshift_full > 10'(MaxRshift)) ? MaxRshift : rshift_full[4:0]);
  assign exp_norm = normal ? exp_lz[8:0] : 9'd1;

  logic [47:0] norm;
  logic [73:0] aligned;
  assign norm    = prod << lshift;
  assign aligned = {norm, 26'd0} >> rshift;

  logic [23:0] mant;
  logic guard, round, sticky;
  assign mant   = aligned[73:50];
  assign guard  = aligned[49];
  assign round  = aligned[48];
  assign sticky = |aligned[47:0];

  logic inc, inc_unbounded;
  assign inc = round_up(rm, sign, mant[0], guard, round || sticky);
  assign inc_unbounded = round_up(rm, sign, guard, round, sticky);

  logic [31:0] rounded, finite;
  assign rounded = {exp_norm - 9'd1, 23'd0} + {8'd0, mant} + {31'd0, inc};
  assign finite  = {sign, rounded[30:0]};

  logic inexact, overflow, tiny, overflow_to_inf;
  assign inexact  = guard || round || sticky;
  assign overflow = rounded[31:23] >= 9'd255;
  assign tiny     = !mant[23] && !((&mant[22:0]) && guard && inc_unbounded);

  always_comb begin
    case (rm)
      RmRtz:   overflow_to_inf = 1'b0;
      RmRdn:   overflow_to_inf = sign;
      RmRup:   overflow_to_inf = !sign;
      default: overflow_to_inf = 1'b1;
    endcase
  end

  always_comb begin
    result = finite;
    fflags = (tiny && inexact ? FlagUf : 5'd0) | (inexact ? FlagNx : 5'd0);
    if (nan_a || nan_b || invalid) begin
      result = CanonicalNan;
      fflags = invalid ? FlagNv : 5'd0;
    end else if (inf_a || inf_b) begin
      result = {sign, 8'hFF, 23'd0};
      fflags = 5'd0;
    end else if (zero_a || zero_b) begin
      result = {sign, 31'd0};
      fflags = 5'd0;
    end else if (overflow) begin
      result = overflow_to_inf ? {sign, 8'hFF, 23'd0} : {sign, 8'hFE, {23{1'b1}}};
      fflags = FlagOf | FlagNx;
    end
  end

endmodule

`default_nettype wire
