`default_nettype none

module fp_rec7_tb
  import fp_pkg::FLEN;
  import fp_pkg::RmRne, fp_pkg::RmRtz, fp_pkg::RmRdn, fp_pkg::RmRup;
  import fp_pkg::FlagNv, fp_pkg::FlagDz, fp_pkg::FlagOf, fp_pkg::FlagNx;
();

  localparam int Bias = 127;
  localparam int MinChecks = 400000;
  localparam int RandomN = 200000;
  localparam logic [31:0] CanonNan = 32'h7fc0_0000;

  int checks = 0;
  int errors = 0;
  int max_errors = 0;
  int sec_start = 0;

  logic sqrt;
  logic [2:0] rm;
  logic [FLEN-1:0] a;
  logic [FLEN-1:0] result;
  logic [4:0] fflags;

  int rec_exps[12] = '{1, 2, 3, 64, 126, 127, 128, 200, 251, 252, 253, 254};
  int rsq_exps[6] = '{2, 4, 126, 128, 200, 254};

  fp_rec7 dut (
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

  function automatic int lead_zeros(input logic [22:0] f);
    lead_zeros = 23;
    for (int i = 0; i < 23; i++) if (f[i]) lead_zeros = 22 - i;
  endfunction

  function automatic int norm_exp(input logic [30:0] mag);
    norm_exp = (mag[30:23] == 8'h00) ? -lead_zeros(mag[22:0]) : int'(mag[30:23]);
  endfunction

  function automatic logic [22:0] norm_sig(input logic [30:0] mag);
    norm_sig = (mag[30:23] == 8'h00) ? mag[22:0] << (lead_zeros(mag[22:0]) + 1) : mag[22:0];
  endfunction

  function automatic logic [36:0] ref_rec7(input logic [31:0] x, input logic [2:0] mode);
    logic s;
    logic to_max;
    logic [22:0] sig;
    logic [22:0] osig;
    int oe;
    s = x[31];
    to_max = (mode == RmRtz) || (mode == RmRdn && !s) || (mode == RmRup && s);
    if (x[30:23] == 8'hff && x[22:0] != '0) begin
      ref_rec7 = {x[22] ? 5'b0 : FlagNv, CanonNan};
    end else if (x[30:23] == 8'hff) begin
      ref_rec7 = {5'b0, s, 31'h0};
    end else if (x[30:0] == '0) begin
      ref_rec7 = {FlagDz, s, 31'h7f80_0000};
    end else begin
      sig  = norm_sig(x[30:0]);
      oe   = 2 * Bias - 1 - norm_exp(x[30:0]);
      osig = {rec_table(7'(sig >> 16)), 16'h0};
      if (oe > 2 * Bias) ref_rec7 = {FlagOf | FlagNx, s, to_max ? 31'h7f7f_ffff : 31'h7f80_0000};
      else if (oe <= 0) ref_rec7 = {5'b0, s, 8'h00, 23'({1'b1, osig} >> (1 - oe))};
      else ref_rec7 = {5'b0, s, 8'(oe), osig};
    end
  endfunction

  function automatic logic [36:0] ref_rsqrt7(input logic [31:0] x);
    logic [22:0] sig;
    int ne;
    if (x[30:23] == 8'hff && x[22:0] != '0) begin
      ref_rsqrt7 = {x[22] ? 5'b0 : FlagNv, CanonNan};
    end else if (x[30:0] == '0) begin
      ref_rsqrt7 = {FlagDz, x[31], 31'h7f80_0000};
    end else if (x[31]) begin
      ref_rsqrt7 = {FlagNv, CanonNan};
    end else if (x[30:23] == 8'hff) begin
      ref_rsqrt7 = 37'h0;
    end else begin
      sig = norm_sig(x[30:0]);
      ne = norm_exp(x[30:0]);
      ref_rsqrt7 = {
        5'b0, 1'b0, 8'((3 * Bias - 1 - ne) / 2), rsq_table({ne[0], 6'(sig >> 17)}), 16'h0
      };
    end
  endfunction

  function automatic logic [31:0] rnd32();
    rnd32 = 32'($urandom);
  endfunction

  function automatic logic [22:0] sub_sig(input int lz, input logic [6:0] t);
    logic [22:0] lead;
    logic [22:0] tmask;
    logic [22:0] f;
    lead = 23'd1 << (22 - lz);
    tmask = 23'({7'h7f, 23'h0} >> (8 + lz));
    f = lead | (23'(rnd32()) & (lead - 23'd1));
    sub_sig = (f & ~tmask) | 23'({t, 23'h0} >> (8 + lz));
  endfunction

  function automatic logic [31:0] special_val(input int k);
    case (k)
      0: special_val = 32'h0000_0000;
      1: special_val = 32'h8000_0000;
      2: special_val = 32'h7f80_0000;
      3: special_val = 32'hff80_0000;
      4: special_val = 32'h7fc0_0000;
      5: special_val = 32'hffc0_0000;
      6: special_val = 32'h7fff_ffff;
      7: special_val = {1'(rnd32()), 8'hff, 1'b1, 22'(rnd32())};
      8: special_val = 32'h7f80_0001;
      9: special_val = 32'hff80_0001;
      10: special_val = 32'h7fbf_ffff;
      11: special_val = {1'(rnd32()), 8'hff, 1'b0, 22'(rnd32()) | 22'd1};
      12: special_val = 32'h8000_0001;
      13: special_val = 32'h807f_ffff;
      14: special_val = {1'b1, 8'h00, 23'(rnd32()) | 23'd1};
      15: special_val = 32'h8080_0000;
      16: special_val = 32'hff7f_ffff;
      17: special_val = {1'b1, 8'(1 + rnd32() % 254), 23'(rnd32())};
      18: special_val = 32'h0000_0001;
      19: special_val = 32'h001f_ffff;
      20: special_val = 32'h801f_ffff;
      21: special_val = {1'(rnd32()), 8'h00, 2'b00, 21'(rnd32()) | 21'd1};
      22: special_val = 32'h0020_0000;
      23: special_val = 32'h8020_0000;
      24: special_val = 32'h003f_ffff;
      25: special_val = 32'h0040_0000;
      26: special_val = 32'h007f_ffff;
      27: special_val = 32'h0080_0000;
      28: special_val = 32'h7f7f_ffff;
      29: special_val = 32'hff7f_ffff;
      30: special_val = 32'h7f00_0000;
      31: special_val = 32'h7e80_0000;
      32: special_val = 32'h7e7f_ffff;
      33: special_val = 32'h3f80_0000;
      34: special_val = 32'hbf80_0000;
      35: special_val = 32'h0071_8abc;
      36: special_val = 32'h7f76_5432;
      default: special_val = {1'(rnd32()), 8'(253 + rnd32() % 2), 23'(rnd32())};
    endcase
  endfunction

  function automatic logic [31:0] rand_input();
    logic [2:0] r;
    r = 3'(rnd32());
    if (r[1:0] != 2'b00) rand_input = rnd32();
    else if (r[2]) rand_input = special_val(int'(rnd32() % 38));
    else rand_input = {1'(rnd32()), 8'h00, sub_sig(int'(rnd32() % 23), 7'(rnd32()))};
  endfunction

  task automatic check(input string sec, input logic op, input logic [2:0] mode,
                       input logic [31:0] x);
    logic [36:0] want;
    sqrt = op;
    rm = mode;
    a = x;
    #1;
    want = op ? ref_rsqrt7(x) : ref_rec7(x, mode);
    checks++;
    if (result !== want[31:0] || fflags !== want[36:32]) begin
      errors++;
      if (errors <= 20)
        $display(
            "FAIL %s %s a=%h rm=%0d exp %h/%b got %h/%b",
            sec,
            op ? "vfrsqrt7" : "vfrec7",
            x,
            mode,
            want[31:0],
            want[36:32],
            result,
            fflags
        );
      if (errors == max_errors) $fatal(1, "TB STOPPED: %0d mismatches", errors);
    end
  endtask

  task automatic section_done(input string sec);
    $display("%s: %0d checks", sec, checks - sec_start);
    sec_start = checks;
  endtask

  task automatic dump_setup();
    string dump_arg;
    if ($value$plusargs("DUMP%s", dump_arg)) begin
      $dumpfile({"fp_rec7_tb", dump_arg, ".vcd"});
      $dumpvars(0, fp_rec7_tb);
    end
  endtask

  task automatic ref_selftest();
    if (ref_rsqrt7(
            32'h0071_8abc
        ) !== {5'b0, 32'h5f08_0000} || ref_rsqrt7(
            32'h7f76_5432
        ) !== {5'b0, 32'h1f82_0000} || ref_rec7(
            32'h0071_8abc, RmRne
        ) !== {5'b0, 32'h7e90_0000} || ref_rec7(
            32'h7f76_5432, RmRne
        ) !== {5'b0, 32'h0021_4000})
      $fatal(1, "TB REFERENCE BROKEN: spec examples disagree");
  endtask

  task automatic table_rec7();
    logic [15:0] fill;
    for (int i = 0; i < 128; i++)
      for (int e = 0; e < 12; e++)
        for (int k = 0; k < 3; k++)
          for (int s = 0; s < 2; s++)
            for (int m = 0; m < 5; m++) begin
              fill = (k == 0) ? 16'h0000 : (k == 1) ? 16'hffff : 16'(rnd32());
              check("table_rec7", 1'b0, 3'(m), {1'(s), 8'(rec_exps[e]), 7'(i), fill});
            end
    section_done("table_rec7");
  endtask

  task automatic table_rsqrt7();
    logic [16:0] fill;
    logic [ 7:0] ex;
    for (int i = 0; i < 128; i++)
      for (int e = 0; e < 6; e++)
        for (int k = 0; k < 3; k++)
          for (int m = 0; m < 5; m++) begin
            fill = (k == 0) ? 17'h0 : (k == 1) ? 17'h1ffff : 17'(rnd32());
            ex   = 8'(rsq_exps[e] - ((i >= 64) ? 1 : 0));
            check("table_rsqrt7", 1'b1, 3'(m), {1'b0, ex, 6'(i), fill});
          end
    section_done("table_rsqrt7");
  endtask

  task automatic specials();
    for (int k = 0; k < 38; k++)
      for (int r = 0; r < 16; r++)
        for (int op = 0; op < 2; op++)
          for (int m = 0; m < 5; m++) check("specials", 1'(op), 3'(m), special_val(k));
    section_done("specials");
  endtask

  task automatic subnormals();
    for (int lz = 0; lz < 23; lz++)
      for (int t = 0; t < 128; t++)
        for (int op = 0; op < 2; op++)
          for (int s = 0; s < 2; s++)
            for (int m = 0; m < 5; m++)
              check("subnormals", 1'(op), 3'(m), {1'(s), 8'h00, sub_sig(lz, 7'(t))});
    section_done("subnormals");
  endtask

  task automatic random_sweep(input logic op);
    for (int i = 0; i < RandomN; i++)
      check(op ? "random_rsqrt7" : "random_rec7", op, 3'(rnd32() % 5), rand_input());
    section_done(op ? "random_rsqrt7" : "random_rec7");
  endtask

  task automatic do_verdict();
    if (checks < MinChecks)
      $fatal(1, "TB UNDER-RAN: %0d checks, expected at least %0d", checks, MinChecks);
    if (errors != 0) $fatal(1, "FAIL: %0d mismatches, %0d checks", errors, checks);
    $display("PASS: %0d checks", checks);
    $finish;
  endtask

  initial void'($value$plusargs("max_errors=%d", max_errors));

  initial begin
    dump_setup();
    ref_selftest();

    table_rec7();
    table_rsqrt7();

    specials();

    subnormals();

    random_sweep(1'b0);
    random_sweep(1'b1);

    do_verdict();
  end

endmodule

`default_nettype wire
