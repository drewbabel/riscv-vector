`default_nettype none

module fp_add (
    input  wire         sub,
    input  wire  [ 2:0] rm,
    input  wire  [31:0] a,
    input  wire  [31:0] b,
    output logic [31:0] result,
    output logic [ 4:0] fflags
);

  localparam logic [2:0] Rne = 3'd0;
  localparam logic [2:0] Rtz = 3'd1;
  localparam logic [2:0] Rdn = 3'd2;
  localparam logic [2:0] Rup = 3'd3;
  localparam logic [2:0] Rmm = 3'd4;

  localparam logic [31:0] CanonNan = 32'h7FC0_0000;
  localparam logic [30:0] InfMag = 31'h7F80_0000;
  localparam logic [30:0] MaxMag = 31'h7F7F_FFFF;

  logic        sa;
  logic        sb;
  logic [ 7:0] ea;
  logic [ 7:0] eb;
  logic [22:0] fa;
  logic [22:0] fb;
  logic        a_nan;
  logic        b_nan;
  logic        a_inf;
  logic        b_inf;
  logic        inf_clash;
  logic        nv;

  logic        swap;
  logic        sx;
  logic        eff_sub;
  logic [ 7:0] ex;
  logic [ 7:0] ey;
  logic [23:0] mx;
  logic [23:0] my;
  logic [ 7:0] d;
  logic [ 4:0] sh;

  logic [53:0] y_wide;
  logic [26:0] y_al;
  logic [27:0] sum;
  logic [26:0] limit;
  logic [26:0] lz_in;
  logic [ 4:0] lz;

  logic [26:0] n;
  logic [ 8:0] e;
  logic [ 8:0] e_field;
  logic        lsb;
  logic        g;
  logic        st;
  logic        inexact;
  logic        inc;
  logic        r_top;
  logic [30:0] r_mag;
  logic        ovf;
  logic        to_max;
  logic        uf;

  // Operand fields
  assign sa = a[31];
  assign sb = b[31] ^ sub;
  assign ea = a[30:23];
  assign eb = b[30:23];
  assign fa = a[22:0];
  assign fb = b[22:0];

  assign a_nan = (ea == 8'hFF) && (fa != 23'd0);
  assign b_nan = (eb == 8'hFF) && (fb != 23'd0);
  assign a_inf = (ea == 8'hFF) && (fa == 23'd0);
  assign b_inf = (eb == 8'hFF) && (fb == 23'd0);
  assign inf_clash = a_inf && b_inf && (sa != sb);
  assign nv = (a_nan && !fa[22]) || (b_nan && !fb[22]) || inf_clash;

  // Larger magnitude first
  assign swap = b[30:0] > a[30:0];
  assign sx = swap ? sb : sa;
  assign eff_sub = sa != sb;
  assign ex = swap ? (eb | 8'(eb == 8'd0)) : (ea | 8'(ea == 8'd0));
  assign ey = swap ? (ea | 8'(ea == 8'd0)) : (eb | 8'(eb == 8'd0));
  assign mx = swap ? {eb != 8'd0, fb} : {ea != 8'd0, fa};
  assign my = swap ? {ea != 8'd0, fa} : {eb != 8'd0, fb};
  assign d = ex - ey;
  assign sh = (d > 8'd27) ? 5'd27 : d[4:0];

  // Align with sticky
  assign y_wide = {my, 30'd0} >> sh;
  assign y_al = {y_wide[53:28], y_wide[27] | (y_wide[26:0] != 27'd0)};
  assign sum = eff_sub ? {1'b0, mx, 3'd0} - {1'b0, y_al} : {1'b0, mx, 3'd0} + {1'b0, y_al};

  // Subnormal shift cap
  assign limit = 27'h400_0000 >> (ex - 8'd1);
  assign lz_in = sum[26:0] | limit;

  always_comb begin
    lz = 5'd0;
    for (int i = 0; i < 27; i++) begin
      if (lz_in[i]) lz = 5'(26 - i);
    end
  end

  assign n = sum[27] ? {sum[27:2], sum[1] | sum[0]} : sum[26:0] << lz;
  assign e = sum[27] ? {1'b0, ex} + 9'd1 : {1'b0, ex} - {4'd0, lz};
  assign e_field = n[26] ? e : 9'd0;

  assign lsb = n[3];
  assign g = n[2];
  assign st = n[1] | n[0];
  assign inexact = g | st;

  always_comb begin
    case (rm)
      Rne: inc = g & (st | lsb);
      Rtz: inc = 1'b0;
      Rdn: inc = sx & inexact;
      Rup: inc = ~sx & inexact;
      Rmm: inc = g;
      default: inc = 1'b0;
    endcase
  end

  assign {r_top, r_mag} = {e_field, n[25:3]} + 32'(inc);
  assign ovf = {r_top, r_mag[30:23]} >= 9'd255;
  assign to_max = (rm == Rtz) || ((rm == Rdn) && !sx) || ((rm == Rup) && sx);
  assign uf = inexact && ({r_top, r_mag[30:23]} == 9'd0);

  always_comb begin
    if (a_nan || b_nan || inf_clash) begin
      result = CanonNan;
      fflags = {nv, 4'b0000};
    end else if (a_inf || b_inf) begin
      result = {a_inf ? sa : sb, InfMag};
      fflags = 5'b00000;
    end else if (sum == 28'd0) begin
      result = {eff_sub ? (rm == Rdn) : sx, 31'd0};
      fflags = 5'b00000;
    end else if (ovf) begin
      result = {sx, to_max ? MaxMag : InfMag};
      fflags = 5'b00101;
    end else begin
      result = {sx, r_mag};
      fflags = {3'b000, uf, inexact};
    end
  end

endmodule

`default_nettype wire
