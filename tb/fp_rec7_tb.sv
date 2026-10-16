`default_nettype none

module fp_rec7_tb ();

  localparam int MinChecks = 480000;

  int checks;
  int errors;
  int max_errors;

  fp_rec7_bench #(
      .EXP_W (8),
      .FRAC_W(23),
      .FMT   ("f32")
  ) f32_bench ();

  fp_rec7_bench #(
      .EXP_W (11),
      .FRAC_W(52),
      .FMT   ("f64")
  ) f64_bench ();

  fp_rec7_bench #(
      .EXP_W (5),
      .FRAC_W(10),
      .FMT   ("f16")
  ) f16_bench ();

  task automatic do_verdict();
    checks = f32_bench.checks + f64_bench.checks + f16_bench.checks;
    errors = f32_bench.errors + f64_bench.errors + f16_bench.errors;
    if (f32_bench.checks < MinChecks || f64_bench.checks < MinChecks ||
        f16_bench.checks < MinChecks)
      $fatal(
          1,
          "TB UNDER-RAN: %0d, %0d and %0d checks, expected at least %0d each",
          f32_bench.checks,
          f64_bench.checks,
          f16_bench.checks,
          MinChecks
      );
    if (errors != 0) $fatal(1, "FAIL: %0d mismatches, %0d checks", errors, checks);
    $display("PASS: %0d checks", checks);
    $finish;
  endtask  // Automatic

  initial begin
    $dumpfile("fp_rec7_tb.vcd");
    $dumpvars(0, f32_bench);
    wait (f32_bench.done && f64_bench.done && f16_bench.done);
    do_verdict();
  end

  initial begin
    if ($value$plusargs("max_errors=%d", max_errors) && max_errors > 0) begin
      wait (f32_bench.errors + f64_bench.errors + f16_bench.errors >= max_errors);
      $fatal(1, "TB STOPPED: %0d mismatches",
             f32_bench.errors + f64_bench.errors + f16_bench.errors);
    end
  end

endmodule

module fp_rec7_bench
  import fp_pkg::RmRne, fp_pkg::RmRtz, fp_pkg::RmRdn, fp_pkg::RmRup;
  import fp_pkg::FlagNv, fp_pkg::FlagDz, fp_pkg::FlagOf, fp_pkg::FlagNx;
#(
    parameter  int    EXP_W  = 8,
    parameter  int    FRAC_W = 23,
    parameter  string FMT    = "f32",
    localparam int    FLEN   = 1 + EXP_W + FRAC_W
) ();

  localparam int Bias = (1 << (EXP_W - 1)) - 1;
  localparam int RandomN = 200000;
  localparam int ShowErrors = 20;
  localparam int FillW = FRAC_W - 7;
  localparam logic [FLEN-1:0] CanonNan = {1'b0, {EXP_W{1'b1}}, 1'b1, {(FRAC_W - 1) {1'b0}}};
  localparam logic [FLEN-1:0] One = {2'b00, {(EXP_W - 1) {1'b1}}, {FRAC_W{1'b0}}};
  localparam logic [FLEN-2:0] InfMag = {{EXP_W{1'b1}}, {FRAC_W{1'b0}}};
  localparam logic [FLEN-2:0] MaxMag = {{(EXP_W - 1) {1'b1}}, 1'b0, {FRAC_W{1'b1}}};

  int checks = 0;
  int errors = 0;
  int sec_start = 0;
  logic done = 1'b0;

  logic sqrt;
  logic [2:0] rm;
  logic [FLEN-1:0] a;
  logic [FLEN-1:0] result;
  logic [4:0] fflags;

  int rec_exps[12] = '{
      1,
      2,
      3,
      Bias / 2,
      Bias - 1,
      Bias,
      Bias + 1,
      Bias + Bias / 2,
      2 * Bias - 3,
      2 * Bias - 2,
      2 * Bias - 1,
      2 * Bias
  };
  int rsq_exps[6] = '{2, 4, Bias - 1, Bias + 1, 2 * (3 * Bias / 4), 2 * Bias};

  fp_rec7 #(
      .ExpW (EXP_W),
      .FracW(FRAC_W)
  ) dut (
      .sqrt(sqrt),
      .rm(rm),
      .a(a),
      .result(result),
      .fflags(fflags)
  );

  function automatic logic [6:0] rec_table(input logic [6:0] idx);
    case (idx)
      7'd0: rec_table = 7'd127;
      7'd1: rec_table = 7'd125;
      7'd2: rec_table = 7'd123;
      7'd3: rec_table = 7'd121;
      7'd4: rec_table = 7'd119;
      7'd5: rec_table = 7'd117;
      7'd6: rec_table = 7'd116;
      7'd7: rec_table = 7'd114;
      7'd8: rec_table = 7'd112;
      7'd9: rec_table = 7'd110;
      7'd10: rec_table = 7'd109;
      7'd11: rec_table = 7'd107;
      7'd12: rec_table = 7'd105;
      7'd13: rec_table = 7'd104;
      7'd14: rec_table = 7'd102;
      7'd15: rec_table = 7'd100;
      7'd16: rec_table = 7'd99;
      7'd17: rec_table = 7'd97;
      7'd18: rec_table = 7'd96;
      7'd19: rec_table = 7'd94;
      7'd20: rec_table = 7'd93;
      7'd21: rec_table = 7'd91;
      7'd22: rec_table = 7'd90;
      7'd23: rec_table = 7'd88;
      7'd24: rec_table = 7'd87;
      7'd25: rec_table = 7'd85;
      7'd26: rec_table = 7'd84;
      7'd27: rec_table = 7'd83;
      7'd28: rec_table = 7'd81;
      7'd29: rec_table = 7'd80;
      7'd30: rec_table = 7'd79;
      7'd31: rec_table = 7'd77;
      7'd32: rec_table = 7'd76;
      7'd33: rec_table = 7'd75;
      7'd34: rec_table = 7'd74;
      7'd35: rec_table = 7'd72;
      7'd36: rec_table = 7'd71;
      7'd37: rec_table = 7'd70;
      7'd38: rec_table = 7'd69;
      7'd39: rec_table = 7'd68;
      7'd40: rec_table = 7'd66;
      7'd41: rec_table = 7'd65;
      7'd42: rec_table = 7'd64;
      7'd43: rec_table = 7'd63;
      7'd44: rec_table = 7'd62;
      7'd45: rec_table = 7'd61;
      7'd46: rec_table = 7'd60;
      7'd47: rec_table = 7'd59;
      7'd48: rec_table = 7'd58;
      7'd49: rec_table = 7'd57;
      7'd50: rec_table = 7'd56;
      7'd51: rec_table = 7'd55;
      7'd52: rec_table = 7'd54;
      7'd53: rec_table = 7'd53;
      7'd54: rec_table = 7'd52;
      7'd55: rec_table = 7'd51;
      7'd56: rec_table = 7'd50;
      7'd57: rec_table = 7'd49;
      7'd58: rec_table = 7'd48;
      7'd59: rec_table = 7'd47;
      7'd60: rec_table = 7'd46;
      7'd61: rec_table = 7'd45;
      7'd62: rec_table = 7'd44;
      7'd63: rec_table = 7'd43;
      7'd64: rec_table = 7'd42;
      7'd65: rec_table = 7'd41;
      7'd66: rec_table = 7'd40;
      7'd67: rec_table = 7'd40;
      7'd68: rec_table = 7'd39;
      7'd69: rec_table = 7'd38;
      7'd70: rec_table = 7'd37;
      7'd71: rec_table = 7'd36;
      7'd72: rec_table = 7'd35;
      7'd73: rec_table = 7'd35;
      7'd74: rec_table = 7'd34;
      7'd75: rec_table = 7'd33;
      7'd76: rec_table = 7'd32;
      7'd77: rec_table = 7'd31;
      7'd78: rec_table = 7'd31;
      7'd79: rec_table = 7'd30;
      7'd80: rec_table = 7'd29;
      7'd81: rec_table = 7'd28;
      7'd82: rec_table = 7'd28;
      7'd83: rec_table = 7'd27;
      7'd84: rec_table = 7'd26;
      7'd85: rec_table = 7'd25;
      7'd86: rec_table = 7'd25;
      7'd87: rec_table = 7'd24;
      7'd88: rec_table = 7'd23;
      7'd89: rec_table = 7'd23;
      7'd90: rec_table = 7'd22;
      7'd91: rec_table = 7'd21;
      7'd92: rec_table = 7'd21;
      7'd93: rec_table = 7'd20;
      7'd94: rec_table = 7'd19;
      7'd95: rec_table = 7'd19;
      7'd96: rec_table = 7'd18;
      7'd97: rec_table = 7'd17;
      7'd98: rec_table = 7'd17;
      7'd99: rec_table = 7'd16;
      7'd100: rec_table = 7'd15;
      7'd101: rec_table = 7'd15;
      7'd102: rec_table = 7'd14;
      7'd103: rec_table = 7'd14;
      7'd104: rec_table = 7'd13;
      7'd105: rec_table = 7'd12;
      7'd106: rec_table = 7'd12;
      7'd107: rec_table = 7'd11;
      7'd108: rec_table = 7'd11;
      7'd109: rec_table = 7'd10;
      7'd110: rec_table = 7'd9;
      7'd111: rec_table = 7'd9;
      7'd112: rec_table = 7'd8;
      7'd113: rec_table = 7'd8;
      7'd114: rec_table = 7'd7;
      7'd115: rec_table = 7'd7;
      7'd116: rec_table = 7'd6;
      7'd117: rec_table = 7'd5;
      7'd118: rec_table = 7'd5;
      7'd119: rec_table = 7'd4;
      7'd120: rec_table = 7'd4;
      7'd121: rec_table = 7'd3;
      7'd122: rec_table = 7'd3;
      7'd123: rec_table = 7'd2;
      7'd124: rec_table = 7'd2;
      7'd125: rec_table = 7'd1;
      7'd126: rec_table = 7'd1;
      7'd127: rec_table = 7'd0;
      default: rec_table = 7'd0;
    endcase
  endfunction

  function automatic logic [6:0] rsq_table(input logic [6:0] idx);
    case (idx)
      7'd0: rsq_table = 7'd52;
      7'd1: rsq_table = 7'd51;
      7'd2: rsq_table = 7'd50;
      7'd3: rsq_table = 7'd48;
      7'd4: rsq_table = 7'd47;
      7'd5: rsq_table = 7'd46;
      7'd6: rsq_table = 7'd44;
      7'd7: rsq_table = 7'd43;
      7'd8: rsq_table = 7'd42;
      7'd9: rsq_table = 7'd41;
      7'd10: rsq_table = 7'd40;
      7'd11: rsq_table = 7'd39;
      7'd12: rsq_table = 7'd38;
      7'd13: rsq_table = 7'd36;
      7'd14: rsq_table = 7'd35;
      7'd15: rsq_table = 7'd34;
      7'd16: rsq_table = 7'd33;
      7'd17: rsq_table = 7'd32;
      7'd18: rsq_table = 7'd31;
      7'd19: rsq_table = 7'd30;
      7'd20: rsq_table = 7'd30;
      7'd21: rsq_table = 7'd29;
      7'd22: rsq_table = 7'd28;
      7'd23: rsq_table = 7'd27;
      7'd24: rsq_table = 7'd26;
      7'd25: rsq_table = 7'd25;
      7'd26: rsq_table = 7'd24;
      7'd27: rsq_table = 7'd23;
      7'd28: rsq_table = 7'd23;
      7'd29: rsq_table = 7'd22;
      7'd30: rsq_table = 7'd21;
      7'd31: rsq_table = 7'd20;
      7'd32: rsq_table = 7'd19;
      7'd33: rsq_table = 7'd19;
      7'd34: rsq_table = 7'd18;
      7'd35: rsq_table = 7'd17;
      7'd36: rsq_table = 7'd16;
      7'd37: rsq_table = 7'd16;
      7'd38: rsq_table = 7'd15;
      7'd39: rsq_table = 7'd14;
      7'd40: rsq_table = 7'd14;
      7'd41: rsq_table = 7'd13;
      7'd42: rsq_table = 7'd12;
      7'd43: rsq_table = 7'd12;
      7'd44: rsq_table = 7'd11;
      7'd45: rsq_table = 7'd10;
      7'd46: rsq_table = 7'd10;
      7'd47: rsq_table = 7'd9;
      7'd48: rsq_table = 7'd9;
      7'd49: rsq_table = 7'd8;
      7'd50: rsq_table = 7'd7;
      7'd51: rsq_table = 7'd7;
      7'd52: rsq_table = 7'd6;
      7'd53: rsq_table = 7'd6;
      7'd54: rsq_table = 7'd5;
      7'd55: rsq_table = 7'd4;
      7'd56: rsq_table = 7'd4;
      7'd57: rsq_table = 7'd3;
      7'd58: rsq_table = 7'd3;
      7'd59: rsq_table = 7'd2;
      7'd60: rsq_table = 7'd2;
      7'd61: rsq_table = 7'd1;
      7'd62: rsq_table = 7'd1;
      7'd63: rsq_table = 7'd0;
      7'd64: rsq_table = 7'd127;
      7'd65: rsq_table = 7'd125;
      7'd66: rsq_table = 7'd123;
      7'd67: rsq_table = 7'd121;
      7'd68: rsq_table = 7'd119;
      7'd69: rsq_table = 7'd118;
      7'd70: rsq_table = 7'd116;
      7'd71: rsq_table = 7'd114;
      7'd72: rsq_table = 7'd113;
      7'd73: rsq_table = 7'd111;
      7'd74: rsq_table = 7'd109;
      7'd75: rsq_table = 7'd108;
      7'd76: rsq_table = 7'd106;
      7'd77: rsq_table = 7'd105;
      7'd78: rsq_table = 7'd103;
      7'd79: rsq_table = 7'd102;
      7'd80: rsq_table = 7'd100;
      7'd81: rsq_table = 7'd99;
      7'd82: rsq_table = 7'd97;
      7'd83: rsq_table = 7'd96;
      7'd84: rsq_table = 7'd95;
      7'd85: rsq_table = 7'd93;
      7'd86: rsq_table = 7'd92;
      7'd87: rsq_table = 7'd91;
      7'd88: rsq_table = 7'd90;
      7'd89: rsq_table = 7'd88;
      7'd90: rsq_table = 7'd87;
      7'd91: rsq_table = 7'd86;
      7'd92: rsq_table = 7'd85;
      7'd93: rsq_table = 7'd84;
      7'd94: rsq_table = 7'd83;
      7'd95: rsq_table = 7'd82;
      7'd96: rsq_table = 7'd80;
      7'd97: rsq_table = 7'd79;
      7'd98: rsq_table = 7'd78;
      7'd99: rsq_table = 7'd77;
      7'd100: rsq_table = 7'd76;
      7'd101: rsq_table = 7'd75;
      7'd102: rsq_table = 7'd74;
      7'd103: rsq_table = 7'd73;
      7'd104: rsq_table = 7'd72;
      7'd105: rsq_table = 7'd71;
      7'd106: rsq_table = 7'd70;
      7'd107: rsq_table = 7'd70;
      7'd108: rsq_table = 7'd69;
      7'd109: rsq_table = 7'd68;
      7'd110: rsq_table = 7'd67;
      7'd111: rsq_table = 7'd66;
      7'd112: rsq_table = 7'd65;
      7'd113: rsq_table = 7'd64;
      7'd114: rsq_table = 7'd63;
      7'd115: rsq_table = 7'd63;
      7'd116: rsq_table = 7'd62;
      7'd117: rsq_table = 7'd61;
      7'd118: rsq_table = 7'd60;
      7'd119: rsq_table = 7'd59;
      7'd120: rsq_table = 7'd59;
      7'd121: rsq_table = 7'd58;
      7'd122: rsq_table = 7'd57;
      7'd123: rsq_table = 7'd56;
      7'd124: rsq_table = 7'd56;
      7'd125: rsq_table = 7'd55;
      7'd126: rsq_table = 7'd54;
      7'd127: rsq_table = 7'd53;
      default: rsq_table = 7'd0;
    endcase
  endfunction

  function automatic int lead_zeros(input logic [FRAC_W-1:0] f);
    lead_zeros = FRAC_W;
    for (int i = 0; i < FRAC_W; i++) if (f[i]) lead_zeros = FRAC_W - 1 - i;
  endfunction

  function automatic int norm_exp(input logic [FLEN-2:0] mag);
    if (mag[FLEN-2:FRAC_W] == '0) norm_exp = -lead_zeros(mag[FRAC_W-1:0]);
    else norm_exp = int'(mag[FLEN-2:FRAC_W]);
  endfunction

  function automatic logic [FRAC_W-1:0] norm_sig(input logic [FLEN-2:0] mag);
    if (mag[FLEN-2:FRAC_W] == '0) norm_sig = mag[FRAC_W-1:0] << (lead_zeros(mag[FRAC_W-1:0]) + 1);
    else norm_sig = mag[FRAC_W-1:0];
  endfunction

  function automatic logic [FLEN+4:0] ref_rec7(input logic [FLEN-1:0] x, input logic [2:0] mode);
    logic s;
    logic to_max;
    logic [FRAC_W-1:0] sig;
    logic [FRAC_W-1:0] osig;
    int oe;
    s = x[FLEN-1];
    to_max = (mode == RmRtz) || (mode == RmRdn && !s) || (mode == RmRup && s);
    if (x[FLEN-2:FRAC_W] == '1 && x[FRAC_W-1:0] != '0) begin
      ref_rec7 = {x[FRAC_W-1] ? 5'b0 : FlagNv, CanonNan};
    end else if (x[FLEN-2:FRAC_W] == '1) begin
      ref_rec7 = {5'b0, s, (FLEN - 1)'(0)};
    end else if (x[FLEN-2:0] == '0) begin
      ref_rec7 = {FlagDz, s, InfMag};
    end else begin
      sig  = norm_sig(x[FLEN-2:0]);
      oe   = 2 * Bias - 1 - norm_exp(x[FLEN-2:0]);
      osig = {rec_table(sig[FRAC_W-1-:7]), FillW'(0)};
      if (oe > 2 * Bias) ref_rec7 = {FlagOf | FlagNx, s, to_max ? MaxMag : InfMag};
      else if (oe <= 0) ref_rec7 = {5'b0, s, EXP_W'(0), FRAC_W'({1'b1, osig} >> (1 - oe))};
      else ref_rec7 = {5'b0, s, EXP_W'(oe), osig};
    end
  endfunction

  function automatic logic [FLEN+4:0] ref_rsqrt7(input logic [FLEN-1:0] x);
    logic [FRAC_W-1:0] sig;
    int ne;
    if (x[FLEN-2:FRAC_W] == '1 && x[FRAC_W-1:0] != '0) begin
      ref_rsqrt7 = {x[FRAC_W-1] ? 5'b0 : FlagNv, CanonNan};
    end else if (x[FLEN-2:0] == '0) begin
      ref_rsqrt7 = {FlagDz, x[FLEN-1], InfMag};
    end else if (x[FLEN-1]) begin
      ref_rsqrt7 = {FlagNv, CanonNan};
    end else if (x[FLEN-2:FRAC_W] == '1) begin
      ref_rsqrt7 = '0;
    end else begin
      sig = norm_sig(x[FLEN-2:0]);
      ne = norm_exp(x[FLEN-2:0]);
      ref_rsqrt7 = {
        5'b0, 1'b0, EXP_W'((3 * Bias - 1 - ne) / 2), rsq_table({ne[0], sig[FRAC_W-1-:6]}), FillW'(0)
      };
    end
  endfunction

  function automatic logic [31:0] rnd32();
    rnd32 = 32'($urandom);
  endfunction

  function automatic logic [FLEN-1:0] rnd_bits();
    rnd_bits = FLEN'({$urandom, $urandom});
  endfunction

  function automatic logic [FRAC_W-1:0] top_frac(input logic [22:0] p);
    top_frac = FRAC_W'({p, 64'b0} >> (87 - FRAC_W));
  endfunction

  function automatic logic [FRAC_W-1:0] sub_sig(input int lz, input logic [6:0] t);
    logic [FRAC_W-1:0] lead;
    logic [FRAC_W-1:0] tmask;
    logic [FRAC_W-1:0] f;
    lead = FRAC_W'(1) << (FRAC_W - 1 - lz);
    tmask = FRAC_W'({7'h7f, FRAC_W'(0)} >> (8 + lz));
    f = lead | (FRAC_W'(rnd_bits()) & (lead - FRAC_W'(1)));
    sub_sig = (f & ~tmask) | FRAC_W'({t, FRAC_W'(0)} >> (8 + lz));
  endfunction

  function automatic logic [FLEN-1:0] special_val(input int k);
    case (k)
      0: special_val = '0;
      1: special_val = {1'b1, (FLEN - 1)'(0)};
      2: special_val = {1'b0, InfMag};
      3: special_val = {1'b1, InfMag};
      4: special_val = CanonNan;
      5: special_val = {1'b1, CanonNan[FLEN-2:0]};
      6: special_val = {1'b0, {(FLEN - 1) {1'b1}}};
      7: special_val = {1'(rnd32()), {EXP_W{1'b1}}, 1'b1, (FRAC_W - 1)'(rnd_bits())};
      8: special_val = {1'b0, InfMag} | FLEN'(1);
      9: special_val = {1'b1, InfMag} | FLEN'(1);
      10: special_val = {1'b0, {EXP_W{1'b1}}, 1'b0, {(FRAC_W - 1) {1'b1}}};
      11:
      special_val = {
        1'(rnd32()), {EXP_W{1'b1}}, 1'b0, (FRAC_W - 1)'(rnd_bits()) | (FRAC_W - 1)'(1)
      };
      12: special_val = {1'b1, (FLEN - 1)'(1)};
      13: special_val = {1'b1, EXP_W'(0), {FRAC_W{1'b1}}};
      14: special_val = {1'b1, EXP_W'(0), FRAC_W'(rnd_bits()) | FRAC_W'(1)};
      15: special_val = {1'b1, EXP_W'(1), FRAC_W'(0)};
      16: special_val = {1'b1, MaxMag};
      17: special_val = {1'b1, EXP_W'(1 + rnd32() % (2 * Bias)), FRAC_W'(rnd_bits())};
      18: special_val = FLEN'(1);
      19: special_val = {1'b0, EXP_W'(0), 2'b00, {(FRAC_W - 2) {1'b1}}};
      20: special_val = {1'b1, EXP_W'(0), 2'b00, {(FRAC_W - 2) {1'b1}}};
      21:
      special_val = {1'(rnd32()), EXP_W'(0), 2'b00, (FRAC_W - 2)'(rnd_bits()) | (FRAC_W - 2)'(1)};
      22: special_val = {1'b0, EXP_W'(0), 2'b01, (FRAC_W - 2)'(0)};
      23: special_val = {1'b1, EXP_W'(0), 2'b01, (FRAC_W - 2)'(0)};
      24: special_val = {1'b0, EXP_W'(0), 2'b01, {(FRAC_W - 2) {1'b1}}};
      25: special_val = {1'b0, EXP_W'(0), 1'b1, (FRAC_W - 1)'(0)};
      26: special_val = {1'b0, EXP_W'(0), {FRAC_W{1'b1}}};
      27: special_val = {1'b0, EXP_W'(1), FRAC_W'(0)};
      28: special_val = {1'b0, MaxMag};
      29: special_val = {1'b1, MaxMag};
      30: special_val = {1'b0, EXP_W'(2 * Bias), FRAC_W'(0)};
      31: special_val = {1'b0, EXP_W'(2 * Bias - 1), FRAC_W'(0)};
      32: special_val = {1'b0, EXP_W'(2 * Bias - 2), {FRAC_W{1'b1}}};
      33: special_val = One;
      34: special_val = {1'b1, One[FLEN-2:0]};
      35: special_val = {1'b0, EXP_W'(0), top_frac(23'h71_8abc)};
      36: special_val = {1'b0, EXP_W'(2 * Bias), top_frac(23'h76_5432)};
      default: special_val = {1'(rnd32()), EXP_W'(2 * Bias - 1 + rnd32() % 2), FRAC_W'(rnd_bits())};
    endcase
  endfunction

  function automatic logic [FLEN-1:0] rand_input();
    logic [2:0] r;
    r = 3'(rnd32());
    if (r[1:0] != 2'b00) rand_input = rnd_bits();
    else if (r[2]) rand_input = special_val(int'(rnd32() % 38));
    else rand_input = {1'(rnd32()), EXP_W'(0), sub_sig(int'(rnd32() % FRAC_W), 7'(rnd32()))};
  endfunction

  task automatic check(input string sec, input logic op, input logic [2:0] mode,
                       input logic [FLEN-1:0] x);
    logic [FLEN+4:0] want;
    sqrt = op;
    rm = mode;
    a = x;
    #1;
    want = op ? ref_rsqrt7(x) : ref_rec7(x, mode);
    checks++;
    if (result !== want[FLEN-1:0] || fflags !== want[FLEN+4:FLEN]) begin
      errors++;
      if (errors <= ShowErrors)
        $display(
            "FAIL %s %s %s a=%h rm=%0d exp %h/%b got %h/%b",
            FMT,
            sec,
            op ? "vfrsqrt7" : "vfrec7",
            x,
            mode,
            want[FLEN-1:0],
            want[FLEN+4:FLEN],
            result,
            fflags
        );
    end
  endtask  // Automatic

  task automatic section_done(input string sec);
    $display("%s %s: %0d checks", FMT, sec, checks - sec_start);
    sec_start = checks;
  endtask  // Automatic

  task automatic ref_selftest();
    if (ref_rsqrt7(
            FLEN'(32'h0071_8abc)
        ) !== (FLEN + 5)'({5'b0, 32'h5f08_0000}) || ref_rsqrt7(
            FLEN'(32'h7f76_5432)
        ) !== (FLEN + 5)'({5'b0, 32'h1f82_0000}) || ref_rec7(
            FLEN'(32'h0071_8abc), RmRne
        ) !== (FLEN + 5)'({5'b0, 32'h7e90_0000}) || ref_rec7(
            FLEN'(32'h7f76_5432), RmRne
        ) !== (FLEN + 5)'({5'b0, 32'h0021_4000}))
      $fatal(1, "TB REFERENCE BROKEN: spec examples disagree");
  endtask  // Automatic

  task automatic table_rec7();
    logic [FillW-1:0] fill;
    for (int i = 0; i < 128; i++)
      for (int e = 0; e < 12; e++)
        for (int k = 0; k < 3; k++)
          for (int s = 0; s < 2; s++)
            for (int m = 0; m < 5; m++) begin
              case (k)
                0: fill = '0;
                1: fill = '1;
                default: fill = FillW'(rnd_bits());
              endcase
              check("table_rec7", 1'b0, 3'(m), {1'(s), EXP_W'(rec_exps[e]), 7'(i), fill});
            end
    section_done("table_rec7");
  endtask  // Automatic

  task automatic table_rsqrt7();
    logic [  FillW:0] fill;
    logic [EXP_W-1:0] ex;
    for (int i = 0; i < 128; i++)
      for (int e = 0; e < 6; e++)
        for (int k = 0; k < 3; k++)
          for (int m = 0; m < 5; m++) begin
            case (k)
              0: fill = '0;
              1: fill = '1;
              default: fill = (FillW + 1)'(rnd_bits());
            endcase
            ex = EXP_W'(rsq_exps[e] - ((i >= 64) ? 1 : 0));
            check("table_rsqrt7", 1'b1, 3'(m), {1'b0, ex, 6'(i), fill});
          end
    section_done("table_rsqrt7");
  endtask  // Automatic

  task automatic specials();
    for (int k = 0; k < 38; k++)
      for (int r = 0; r < 16; r++)
        for (int op = 0; op < 2; op++)
          for (int m = 0; m < 5; m++) check("specials", 1'(op), 3'(m), special_val(k));
    section_done("specials");
  endtask  // Automatic

  task automatic subnormals();
    for (int lz = 0; lz < FRAC_W; lz++)
      for (int t = 0; t < 128; t++)
        for (int op = 0; op < 2; op++)
          for (int s = 0; s < 2; s++)
            for (int m = 0; m < 5; m++)
              check("subnormals", 1'(op), 3'(m), {1'(s), EXP_W'(0), sub_sig(lz, 7'(t))});
    section_done("subnormals");
  endtask  // Automatic

  task automatic random_sweep(input logic op);
    for (int i = 0; i < RandomN; i++)
      check(op ? "random_rsqrt7" : "random_rec7", op, 3'(rnd32() % 5), rand_input());
    section_done(op ? "random_rsqrt7" : "random_rec7");
  endtask  // Automatic

  initial begin
    if (EXP_W == 8 && FRAC_W == 23) ref_selftest();

    table_rec7();
    table_rsqrt7();

    specials();

    subnormals();

    random_sweep(1'b0);
    random_sweep(1'b1);

    done = 1'b1;
  end

endmodule

`default_nettype wire
