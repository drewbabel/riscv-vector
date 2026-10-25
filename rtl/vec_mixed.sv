`default_nettype none

module vec_mixed
  import vec_pkg::*;
#(
    parameter  int DLEN   = arch_pkg::VLEN,
    parameter  int ELEN   = arch_pkg::ELEN,
    parameter  int XLEN   = arch_pkg::XLEN,
    localparam int Widths = $clog2(ELEN / 8) + 1,
    localparam int SelW   = $clog2(Widths)
) (
    input  wire vec_op_e                       op,
    input  wire vec_src_e                      src,
    input  wire vec_eew_e                      eew,
    input  wire           [vec_pkg::VsewW-1:0] vsew,
    input  wire           [          DLEN-1:0] vs2_data,
    input  wire           [          DLEN-1:0] vs1_data,
    input  wire           [          XLEN-1:0] xdata,
    input  wire           [               4:0] simm,
    output logic          [          DLEN-1:0] result
);

  if (ELEN != 32) begin : g_elen
    $error("ELEN must be 32 (Zve32f)");
  end

  logic [DLEN-1:0] res_w[Widths];

  logic [2*DLEN-1:0] vs2_pad;
  logic [2*DLEN-1:0] vs1_pad;

  assign vs2_pad = {{DLEN{1'b0}}, vs2_data};
  assign vs1_pad = {{DLEN{1'b0}}, vs1_data};

  logic is_narrow;
  logic is_ext;
  logic ext_signed;
  logic src_signed;
  logic quarter;
  logic wide_a;
  logic is_vv;

  assign is_narrow = (op == VEC_NSRL) || (op == VEC_NSRA);
  assign is_ext = (op == VEC_ZEXT2) || (op == VEC_ZEXT4) || (op == VEC_SEXT2) || (op == VEC_SEXT4);
  assign ext_signed = (op == VEC_SEXT2) || (op == VEC_SEXT4);
  assign src_signed = (op == VEC_WADD) || (op == VEC_WSUB);
  assign quarter = (op == VEC_ZEXT4) || (op == VEC_SEXT4);
  assign wide_a = (eew == VEC_EEW_WIDEN_W);
  assign is_vv = (src == VEC_SRC_VV);

  for (genvar g = 0; g < Widths; g++) begin : g_dw
    localparam int Dw = 8 << g;
    localparam int Half = (Dw > 8) ? (Dw / 2) : 1;
    localparam int Quart = (Dw > 16) ? (Dw / 4) : 1;
    localparam int Wide = Dw * 2;
    localparam int Shamt = $clog2(Wide);

    logic [DLEN-1:0] res;

    for (genvar e = 0; e < DLEN / Dw; e++) begin : g_e
      logic [   Dw-1:0] a;
      logic [   Dw-1:0] b;
      logic [ Wide-1:0] wsrc;
      logic [Shamt-1:0] shamt;
      logic [   Dw-1:0] shifted;
      logic [   Dw-1:0] extended;
      logic [ Half-1:0] b_half;
      logic [Quart-1:0] a_quart;
      logic [ Half-1:0] a_half;

      // Source slices
      assign b_half = is_vv ? vs1_pad[e*Half+:Half] : xdata[0+:Half];
      assign a_quart = vs2_pad[e*Quart+:Quart];
      assign a_half = vs2_pad[e*Half+:Half];
      assign wsrc = vs2_pad[e*Wide+:Wide];

      // Widened operands
      always_comb begin
        if (wide_a) a = vs2_pad[e*Dw+:Dw];
        else if (src_signed) a = Dw'($signed(a_half));
        else a = Dw'(a_half);
      end
      assign b = src_signed ? Dw'($signed(b_half)) : Dw'(b_half);

      // Shift amount
      always_comb begin
        if (is_vv) shamt = Shamt'(vs1_pad[e*Dw+:Dw]);
        else if (src == VEC_SRC_VI) shamt = Shamt'(simm);
        else shamt = Shamt'(xdata);
      end
      assign shifted = (op == VEC_NSRA) ? Dw'($signed(wsrc) >>> shamt) : Dw'(wsrc >> shamt);

      // Extended element
      always_comb begin
        if (quarter && ext_signed) extended = Dw'($signed(a_quart));
        else if (quarter) extended = Dw'(a_quart);
        else if (ext_signed) extended = Dw'($signed(a_half));
        else extended = Dw'(a_half);
      end

      // One element
      always_comb begin
        if (is_narrow) res[e*Dw+:Dw] = shifted;
        else if (is_ext) res[e*Dw+:Dw] = extended;
        else
          case (op)
            VEC_WADDU, VEC_WADD: res[e*Dw+:Dw] = a + b;
            VEC_WSUBU, VEC_WSUB: res[e*Dw+:Dw] = a - b;
            default:             res[e*Dw+:Dw] = '0;
          endcase
      end
    end

    assign res_w[g] = res;
  end

  // Destination width
  logic [SelW-1:0] dsel;
  assign dsel   = SelW'(vsew) + SelW'(!(is_narrow || is_ext));

  assign result = res_w[vec_sew_index(3'(dsel), Widths)];

endmodule

`default_nettype wire
