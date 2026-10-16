`default_nettype none

module fp_rec7 (
    input  wire         sqrt,
    input  wire  [ 2:0] rm,
    input  wire  [31:0] a,
    output logic [31:0] result,
    output logic [ 4:0] fflags
);

  localparam int Bias = 127;
  localparam logic [8:0] RsqBase = 9'(3 * Bias - 1);
  localparam logic [7:0] RecBase = 8'(2 * Bias - 1);
  localparam logic [31:0] CanonNan = 32'h7FC0_0000;
  localparam logic [2:0] RmRtz = 3'd1;
  localparam logic [2:0] RmRdn = 3'd2;
  localparam logic [2:0] RmRup = 3'd3;
  localparam logic [4:0] FlagNv = 5'b10000;
  localparam logic [4:0] FlagDz = 5'b01000;
  localparam logic [4:0] FlagOf = 5'b00100;
  localparam logic [4:0] FlagNx = 5'b00001;

  logic        sign;
  logic [ 7:0] exp_in;
  logic [22:0] frac;
  logic        is_nan;
  logic        is_snan;
  logic        is_inf;
  logic        is_zero;
  logic        is_sub;
  logic [ 4:0] lz;
  logic [ 6:0] norm_top;
  logic        norm_exp_lsb;
  logic [ 6:0] rsq_idx;
  logic [ 6:0] rec_lut;
  logic [ 6:0] rsq_lut;
  logic [ 7:0] rsq_exp;
  logic [ 7:0] rec_exp;
  logic        rec_ovf;
  logic        rec_den;
  logic [22:0] rec_den_sig;
  logic        rec_max;

  assign sign = a[31];
  assign exp_in = a[30:23];
  assign frac = a[22:0];

  assign is_nan = (exp_in == 8'hFF) && (frac != '0);
  assign is_snan = is_nan && !frac[22];
  assign is_inf = (exp_in == 8'hFF) && (frac == '0);
  assign is_zero = (exp_in == '0) && (frac == '0);
  assign is_sub = (exp_in == '0) && (frac != '0);

  always_comb begin
    lz = '0;
    for (int i = 0; i < 23; i++) begin
      if (frac[i]) lz = 5'(22 - i);
    end
  end

  assign norm_top = is_sub ? 7'({frac, 7'b0} >> (5'd22 - lz)) : frac[22:16];
  assign norm_exp_lsb = is_sub ? lz[0] : exp_in[0];
  assign rsq_idx = {norm_exp_lsb, norm_top[6:1]};

  assign rsq_exp = is_sub ? 8'((RsqBase + 9'(lz)) >> 1) : 8'((RsqBase - 9'(exp_in)) >> 1);

  assign rec_exp = is_sub ? (RecBase + 8'(lz)) : (RecBase - exp_in);
  assign rec_ovf = is_sub && (frac[22:21] == 2'b00);
  assign rec_den = !is_sub && (exp_in >= RecBase);
  assign rec_den_sig = (exp_in == 8'(2 * Bias)) ? {2'b01, rec_lut, 14'b0} : {1'b1, rec_lut, 15'b0};
  assign rec_max = (rm == RmRtz) || ((rm == RmRdn) && !sign) || ((rm == RmRup) && sign);

  always_comb begin
    case (norm_top)
      7'd0: rec_lut = 7'd127;
      7'd1: rec_lut = 7'd125;
      7'd2: rec_lut = 7'd123;
      7'd3: rec_lut = 7'd121;
      7'd4: rec_lut = 7'd119;
      7'd5: rec_lut = 7'd117;
      7'd6: rec_lut = 7'd116;
      7'd7: rec_lut = 7'd114;
      7'd8: rec_lut = 7'd112;
      7'd9: rec_lut = 7'd110;
      7'd10: rec_lut = 7'd109;
      7'd11: rec_lut = 7'd107;
      7'd12: rec_lut = 7'd105;
      7'd13: rec_lut = 7'd104;
      7'd14: rec_lut = 7'd102;
      7'd15: rec_lut = 7'd100;
      7'd16: rec_lut = 7'd99;
      7'd17: rec_lut = 7'd97;
      7'd18: rec_lut = 7'd96;
      7'd19: rec_lut = 7'd94;
      7'd20: rec_lut = 7'd93;
      7'd21: rec_lut = 7'd91;
      7'd22: rec_lut = 7'd90;
      7'd23: rec_lut = 7'd88;
      7'd24: rec_lut = 7'd87;
      7'd25: rec_lut = 7'd85;
      7'd26: rec_lut = 7'd84;
      7'd27: rec_lut = 7'd83;
      7'd28: rec_lut = 7'd81;
      7'd29: rec_lut = 7'd80;
      7'd30: rec_lut = 7'd79;
      7'd31: rec_lut = 7'd77;
      7'd32: rec_lut = 7'd76;
      7'd33: rec_lut = 7'd75;
      7'd34: rec_lut = 7'd74;
      7'd35: rec_lut = 7'd72;
      7'd36: rec_lut = 7'd71;
      7'd37: rec_lut = 7'd70;
      7'd38: rec_lut = 7'd69;
      7'd39: rec_lut = 7'd68;
      7'd40: rec_lut = 7'd66;
      7'd41: rec_lut = 7'd65;
      7'd42: rec_lut = 7'd64;
      7'd43: rec_lut = 7'd63;
      7'd44: rec_lut = 7'd62;
      7'd45: rec_lut = 7'd61;
      7'd46: rec_lut = 7'd60;
      7'd47: rec_lut = 7'd59;
      7'd48: rec_lut = 7'd58;
      7'd49: rec_lut = 7'd57;
      7'd50: rec_lut = 7'd56;
      7'd51: rec_lut = 7'd55;
      7'd52: rec_lut = 7'd54;
      7'd53: rec_lut = 7'd53;
      7'd54: rec_lut = 7'd52;
      7'd55: rec_lut = 7'd51;
      7'd56: rec_lut = 7'd50;
      7'd57: rec_lut = 7'd49;
      7'd58: rec_lut = 7'd48;
      7'd59: rec_lut = 7'd47;
      7'd60: rec_lut = 7'd46;
      7'd61: rec_lut = 7'd45;
      7'd62: rec_lut = 7'd44;
      7'd63: rec_lut = 7'd43;
      7'd64: rec_lut = 7'd42;
      7'd65: rec_lut = 7'd41;
      7'd66: rec_lut = 7'd40;
      7'd67: rec_lut = 7'd40;
      7'd68: rec_lut = 7'd39;
      7'd69: rec_lut = 7'd38;
      7'd70: rec_lut = 7'd37;
      7'd71: rec_lut = 7'd36;
      7'd72: rec_lut = 7'd35;
      7'd73: rec_lut = 7'd35;
      7'd74: rec_lut = 7'd34;
      7'd75: rec_lut = 7'd33;
      7'd76: rec_lut = 7'd32;
      7'd77: rec_lut = 7'd31;
      7'd78: rec_lut = 7'd31;
      7'd79: rec_lut = 7'd30;
      7'd80: rec_lut = 7'd29;
      7'd81: rec_lut = 7'd28;
      7'd82: rec_lut = 7'd28;
      7'd83: rec_lut = 7'd27;
      7'd84: rec_lut = 7'd26;
      7'd85: rec_lut = 7'd25;
      7'd86: rec_lut = 7'd25;
      7'd87: rec_lut = 7'd24;
      7'd88: rec_lut = 7'd23;
      7'd89: rec_lut = 7'd23;
      7'd90: rec_lut = 7'd22;
      7'd91: rec_lut = 7'd21;
      7'd92: rec_lut = 7'd21;
      7'd93: rec_lut = 7'd20;
      7'd94: rec_lut = 7'd19;
      7'd95: rec_lut = 7'd19;
      7'd96: rec_lut = 7'd18;
      7'd97: rec_lut = 7'd17;
      7'd98: rec_lut = 7'd17;
      7'd99: rec_lut = 7'd16;
      7'd100: rec_lut = 7'd15;
      7'd101: rec_lut = 7'd15;
      7'd102: rec_lut = 7'd14;
      7'd103: rec_lut = 7'd14;
      7'd104: rec_lut = 7'd13;
      7'd105: rec_lut = 7'd12;
      7'd106: rec_lut = 7'd12;
      7'd107: rec_lut = 7'd11;
      7'd108: rec_lut = 7'd11;
      7'd109: rec_lut = 7'd10;
      7'd110: rec_lut = 7'd9;
      7'd111: rec_lut = 7'd9;
      7'd112: rec_lut = 7'd8;
      7'd113: rec_lut = 7'd8;
      7'd114: rec_lut = 7'd7;
      7'd115: rec_lut = 7'd7;
      7'd116: rec_lut = 7'd6;
      7'd117: rec_lut = 7'd5;
      7'd118: rec_lut = 7'd5;
      7'd119: rec_lut = 7'd4;
      7'd120: rec_lut = 7'd4;
      7'd121: rec_lut = 7'd3;
      7'd122: rec_lut = 7'd3;
      7'd123: rec_lut = 7'd2;
      7'd124: rec_lut = 7'd2;
      7'd125: rec_lut = 7'd1;
      7'd126: rec_lut = 7'd1;
      7'd127: rec_lut = 7'd0;
      default: rec_lut = 7'd0;
    endcase
  end

  always_comb begin
    case (rsq_idx)
      7'd0: rsq_lut = 7'd52;
      7'd1: rsq_lut = 7'd51;
      7'd2: rsq_lut = 7'd50;
      7'd3: rsq_lut = 7'd48;
      7'd4: rsq_lut = 7'd47;
      7'd5: rsq_lut = 7'd46;
      7'd6: rsq_lut = 7'd44;
      7'd7: rsq_lut = 7'd43;
      7'd8: rsq_lut = 7'd42;
      7'd9: rsq_lut = 7'd41;
      7'd10: rsq_lut = 7'd40;
      7'd11: rsq_lut = 7'd39;
      7'd12: rsq_lut = 7'd38;
      7'd13: rsq_lut = 7'd36;
      7'd14: rsq_lut = 7'd35;
      7'd15: rsq_lut = 7'd34;
      7'd16: rsq_lut = 7'd33;
      7'd17: rsq_lut = 7'd32;
      7'd18: rsq_lut = 7'd31;
      7'd19: rsq_lut = 7'd30;
      7'd20: rsq_lut = 7'd30;
      7'd21: rsq_lut = 7'd29;
      7'd22: rsq_lut = 7'd28;
      7'd23: rsq_lut = 7'd27;
      7'd24: rsq_lut = 7'd26;
      7'd25: rsq_lut = 7'd25;
      7'd26: rsq_lut = 7'd24;
      7'd27: rsq_lut = 7'd23;
      7'd28: rsq_lut = 7'd23;
      7'd29: rsq_lut = 7'd22;
      7'd30: rsq_lut = 7'd21;
      7'd31: rsq_lut = 7'd20;
      7'd32: rsq_lut = 7'd19;
      7'd33: rsq_lut = 7'd19;
      7'd34: rsq_lut = 7'd18;
      7'd35: rsq_lut = 7'd17;
      7'd36: rsq_lut = 7'd16;
      7'd37: rsq_lut = 7'd16;
      7'd38: rsq_lut = 7'd15;
      7'd39: rsq_lut = 7'd14;
      7'd40: rsq_lut = 7'd14;
      7'd41: rsq_lut = 7'd13;
      7'd42: rsq_lut = 7'd12;
      7'd43: rsq_lut = 7'd12;
      7'd44: rsq_lut = 7'd11;
      7'd45: rsq_lut = 7'd10;
      7'd46: rsq_lut = 7'd10;
      7'd47: rsq_lut = 7'd9;
      7'd48: rsq_lut = 7'd9;
      7'd49: rsq_lut = 7'd8;
      7'd50: rsq_lut = 7'd7;
      7'd51: rsq_lut = 7'd7;
      7'd52: rsq_lut = 7'd6;
      7'd53: rsq_lut = 7'd6;
      7'd54: rsq_lut = 7'd5;
      7'd55: rsq_lut = 7'd4;
      7'd56: rsq_lut = 7'd4;
      7'd57: rsq_lut = 7'd3;
      7'd58: rsq_lut = 7'd3;
      7'd59: rsq_lut = 7'd2;
      7'd60: rsq_lut = 7'd2;
      7'd61: rsq_lut = 7'd1;
      7'd62: rsq_lut = 7'd1;
      7'd63: rsq_lut = 7'd0;
      7'd64: rsq_lut = 7'd127;
      7'd65: rsq_lut = 7'd125;
      7'd66: rsq_lut = 7'd123;
      7'd67: rsq_lut = 7'd121;
      7'd68: rsq_lut = 7'd119;
      7'd69: rsq_lut = 7'd118;
      7'd70: rsq_lut = 7'd116;
      7'd71: rsq_lut = 7'd114;
      7'd72: rsq_lut = 7'd113;
      7'd73: rsq_lut = 7'd111;
      7'd74: rsq_lut = 7'd109;
      7'd75: rsq_lut = 7'd108;
      7'd76: rsq_lut = 7'd106;
      7'd77: rsq_lut = 7'd105;
      7'd78: rsq_lut = 7'd103;
      7'd79: rsq_lut = 7'd102;
      7'd80: rsq_lut = 7'd100;
      7'd81: rsq_lut = 7'd99;
      7'd82: rsq_lut = 7'd97;
      7'd83: rsq_lut = 7'd96;
      7'd84: rsq_lut = 7'd95;
      7'd85: rsq_lut = 7'd93;
      7'd86: rsq_lut = 7'd92;
      7'd87: rsq_lut = 7'd91;
      7'd88: rsq_lut = 7'd90;
      7'd89: rsq_lut = 7'd88;
      7'd90: rsq_lut = 7'd87;
      7'd91: rsq_lut = 7'd86;
      7'd92: rsq_lut = 7'd85;
      7'd93: rsq_lut = 7'd84;
      7'd94: rsq_lut = 7'd83;
      7'd95: rsq_lut = 7'd82;
      7'd96: rsq_lut = 7'd80;
      7'd97: rsq_lut = 7'd79;
      7'd98: rsq_lut = 7'd78;
      7'd99: rsq_lut = 7'd77;
      7'd100: rsq_lut = 7'd76;
      7'd101: rsq_lut = 7'd75;
      7'd102: rsq_lut = 7'd74;
      7'd103: rsq_lut = 7'd73;
      7'd104: rsq_lut = 7'd72;
      7'd105: rsq_lut = 7'd71;
      7'd106: rsq_lut = 7'd70;
      7'd107: rsq_lut = 7'd70;
      7'd108: rsq_lut = 7'd69;
      7'd109: rsq_lut = 7'd68;
      7'd110: rsq_lut = 7'd67;
      7'd111: rsq_lut = 7'd66;
      7'd112: rsq_lut = 7'd65;
      7'd113: rsq_lut = 7'd64;
      7'd114: rsq_lut = 7'd63;
      7'd115: rsq_lut = 7'd63;
      7'd116: rsq_lut = 7'd62;
      7'd117: rsq_lut = 7'd61;
      7'd118: rsq_lut = 7'd60;
      7'd119: rsq_lut = 7'd59;
      7'd120: rsq_lut = 7'd59;
      7'd121: rsq_lut = 7'd58;
      7'd122: rsq_lut = 7'd57;
      7'd123: rsq_lut = 7'd56;
      7'd124: rsq_lut = 7'd56;
      7'd125: rsq_lut = 7'd55;
      7'd126: rsq_lut = 7'd54;
      7'd127: rsq_lut = 7'd53;
      default: rsq_lut = 7'd0;
    endcase
  end

  always_comb begin
    result = '0;
    fflags = '0;
    if (is_nan) begin
      result = CanonNan;
      fflags = is_snan ? FlagNv : 5'b0;
    end else if (is_zero) begin
      result = {sign, 8'hFF, 23'b0};
      fflags = FlagDz;
    end else if (sqrt) begin
      if (sign) begin
        result = CanonNan;
        fflags = FlagNv;
      end else if (!is_inf) begin
        result = {1'b0, rsq_exp, rsq_lut, 16'b0};
      end
    end else if (is_inf) begin
      result = {sign, 31'b0};
    end else if (rec_ovf) begin
      result = rec_max ? {sign, 8'hFE, 23'h7F_FFFF} : {sign, 8'hFF, 23'b0};
      fflags = FlagOf | FlagNx;
    end else if (rec_den) begin
      result = {sign, 8'h00, rec_den_sig};
    end else begin
      result = {sign, rec_exp, rec_lut, 16'b0};
    end
  end

endmodule

`default_nettype wire
