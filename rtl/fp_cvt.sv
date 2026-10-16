`default_nettype none

module fp_cvt (
    input  wire         to_int,
    input  wire         is_unsigned,
    input  wire  [ 2:0] iw,
    input  wire  [ 2:0] rm,
    input  wire  [31:0] a,
    output logic [31:0] result,
    output logic [ 4:0] fflags
);

  localparam logic [2:0] Rne = 3'd0;
  localparam logic [2:0] Rtz = 3'd1;
  localparam logic [2:0] Rdn = 3'd2;
  localparam logic [2:0] Rup = 3'd3;
  localparam logic [2:0] Rmm = 3'd4;

  localparam logic [4:0] FlagNv = 5'b10000;
  localparam logic [4:0] FlagNx = 5'b00001;

  logic w16;
  assign w16 = (iw == 3'd1);

  // Rounding increment
  function automatic logic round_up(input logic [2:0] mode, input logic neg, input logic lsb,
                                    input logic guard, input logic sticky);
    case (mode)
      Rne: round_up = guard && (sticky || lsb);
      Rtz: round_up = 1'b0;
      Rdn: round_up = neg && (guard || sticky);
      Rup: round_up = !neg && (guard || sticky);
      Rmm: round_up = guard;
      default: round_up = 1'b0;
    endcase
  endfunction

  // Float to integer
  logic        f_sign;
  logic [ 7:0] f_exp;
  logic [22:0] f_frac;
  logic [23:0] f_sig;
  logic        f_nan;
  logic        f_big;
  logic        f_tiny;
  logic [55:0] f_fix;
  logic [31:0] f_int;
  logic        f_guard;
  logic        f_sticky;
  logic        f_inc;
  logic [32:0] f_mag;
  logic [31:0] f_pos_max;
  logic [31:0] f_neg_max;
  logic        f_nv;
  logic [31:0] f_full;
  logic [31:0] f_res;
  logic [ 4:0] f_flags;

  assign f_sign = a[31];
  assign f_exp = a[30:23];
  assign f_frac = a[22:0];
  assign f_sig = {f_exp != 8'd0, f_frac};
  assign f_nan = (f_exp == 8'hFF) && (f_frac != '0);

  // Overflows 32 bits
  assign f_big = f_exp >= 8'd159;
  // Below one half
  assign f_tiny = f_exp < 8'd126;

  // Fixed point value
  assign f_fix = f_tiny ? '0 : (56'(f_sig) << 6'(f_exp - 8'd126));
  assign f_int = f_fix[55:24];
  assign f_guard = f_fix[23];
  assign f_sticky = (f_fix[22:0] != '0) || (f_tiny && (a[30:0] != '0));

  assign f_inc = round_up(rm, f_sign, f_int[0], f_guard, f_sticky);
  assign f_mag = {1'b0, f_int} + 33'(f_inc);

  // Destination bounds
  assign f_pos_max = is_unsigned ? (w16 ? 32'h0000_FFFF : 32'hFFFF_FFFF) :
      (w16 ? 32'h0000_7FFF : 32'h7FFF_FFFF);
  assign f_neg_max = is_unsigned ? '0 : (w16 ? 32'h0000_8000 : 32'h8000_0000);

  assign f_nv = f_nan || f_big || (f_mag > {1'b0, f_sign ? f_neg_max : f_pos_max});

  // Clip or negate
  assign f_full = f_nv ? ((f_nan || !f_sign) ? f_pos_max : f_neg_max) :
      (f_sign ? -f_mag[31:0] : f_mag[31:0]);
  assign f_res = w16 ? {16'd0, f_full[15:0]} : f_full;

  assign f_flags = f_nv ? FlagNv : ((f_guard || f_sticky) ? FlagNx : '0);

  // Integer to float
  logic [31:0] i_val;
  logic        i_sign;
  logic [31:0] i_mag;
  logic [31:0] i_norm;
  logic [ 4:0] i_lz;
  logic        i_guard;
  logic        i_sticky;
  logic        i_inc;
  logic [30:0] i_body;
  logic [31:0] i_res;
  logic [ 4:0] i_flags;

  assign i_val  = w16 ? {{16{a[15] && !is_unsigned}}, a[15:0]} : a;
  assign i_sign = !is_unsigned && i_val[31];
  assign i_mag  = i_sign ? -i_val : i_val;

  // Normalize leading one
  always_comb begin
    i_norm = i_mag;
    i_lz   = '0;
    for (int s = 4; s >= 0; s--) begin
      if ((i_norm >> (32 - (1 << s))) == '0) begin
        i_norm = i_norm << (1 << s);
        i_lz   = i_lz | 5'(1 << s);
      end
    end
  end

  assign i_guard = i_norm[7];
  assign i_sticky = i_norm[6:0] != '0;

  // Pack and round
  assign i_inc = round_up(rm, i_sign, i_norm[8], i_guard, i_sticky);
  assign i_body = {8'd158 - 8'(i_lz), i_norm[30:8]} + 31'(i_inc);

  assign i_res = (i_mag == '0) ? '0 : {i_sign, i_body};
  assign i_flags = (i_guard || i_sticky) ? FlagNx : '0;

  assign result = to_int ? f_res : i_res;
  assign fflags = to_int ? f_flags : i_flags;

endmodule

`default_nettype wire
