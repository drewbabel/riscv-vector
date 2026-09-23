`default_nettype none

module vec_mixed
  import vec_pkg::*;
#(
    parameter int DLEN = 128
) (
    input  vec_op_e             op,
    input  vec_src_e            src,
    input  vec_eew_e            eew,
    input  logic     [     2:0] vsew,
    input  logic     [DLEN-1:0] vs2_data,
    input  logic     [DLEN-1:0] vs1_data,
    input  logic     [    31:0] xdata,
    input  logic     [     4:0] simm,
    output logic     [DLEN-1:0] result
);

  logic [DLEN-1:0] res8;
  logic [DLEN-1:0] res16;
  logic [DLEN-1:0] res32;

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

  assign is_narrow = (op == VEC_NSRL) || (op == VEC_NSRA);
  assign is_ext = (op == VEC_ZEXT2) || (op == VEC_ZEXT4) || (op == VEC_SEXT2) || (op == VEC_SEXT4);
  assign ext_signed = (op == VEC_SEXT2) || (op == VEC_SEXT4);
  assign src_signed = (op == VEC_WADD) || (op == VEC_WSUB);
  assign quarter = (op == VEC_ZEXT4) || (op == VEC_SEXT4);
  assign wide_a = (eew == VEC_EEW_WIDEN_W);

  for (genvar g = 0; g < 3; g++) begin : g_dw
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

      // Source slices
      assign b_half  = (src == VEC_SRC_VV) ? vs1_pad[e*Half+:Half] : xdata[0+:Half];
      assign a_quart = vs2_pad[e*Quart+:Quart];
      assign wsrc    = vs2_pad[e*Wide+:Wide];

      // Widened operands
      assign a = wide_a ? vs2_pad[e*Dw+:Dw]
          : (src_signed ? Dw'($signed(vs2_pad[e*Half+:Half])) : Dw'(vs2_pad[e*Half+:Half]));
      assign b = src_signed ? Dw'($signed(b_half)) : Dw'(b_half);

      // Shift amount
      assign shamt = (src == VEC_SRC_VV) ? Shamt'(vs1_pad[e*Dw+:Dw])
          : ((src == VEC_SRC_VI) ? Shamt'(simm) : Shamt'(xdata));
      assign shifted = (op == VEC_NSRA) ? Dw'($signed(wsrc) >>> shamt) : Dw'(wsrc >> shamt);

      // Extended element
      assign extended = quarter
          ? (ext_signed ? Dw'($signed(a_quart)) : Dw'(a_quart))
          : (ext_signed ? Dw'($signed(vs2_pad[e*Half+:Half]))
                        : Dw'(vs2_pad[e*Half+:Half]));

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

    if (Dw == 8) begin : g_w8
      assign res8 = res;
    end else if (Dw == 16) begin : g_w16
      assign res16 = res;
    end else begin : g_w32
      assign res32 = res;
    end
  end

  // Destination width
  logic [1:0] dsel;
  assign dsel = (is_narrow || is_ext) ? 2'(vsew[1:0]) : 2'(vsew[1:0] + 2'd1);

  always_comb begin
    case (dsel)
      2'd0:    result = res8;
      2'd1:    result = res16;
      default: result = res32;
    endcase
  end

endmodule

`default_nettype wire
