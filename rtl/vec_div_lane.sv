`default_nettype none

module vec_div_lane
  import vec_pkg::*, muldiv_pkg::*;
#(
    parameter int ELEN = arch_pkg::ELEN
) (
    input  wire                     clk,
    input  wire                     rst_n,
    input  wire                     core_en,
    input  wire                     start,
    input  wire vec_op_e            op,
    input  wire          [     2:0] vsew,
    input  wire          [ELEN-1:0] a,
    input  wire          [ELEN-1:0] b,
    output logic         [ELEN-1:0] result,
    output logic                    busy,
    output logic                    done
);

  logic is_signed;
  muldiv_op_e md_op;
  logic [ELEN-1:0] a_ext;
  logic [ELEN-1:0] b_ext;
  logic [ELEN-1:0] md_result;
  logic [2:0] sew_q;

  function automatic logic [ELEN-1:0] extend(input logic [ELEN-1:0] x, input logic [2:0] sew,
                                             input logic sgn);
    case (sew)
      3'd0: extend = sgn ? ELEN'($signed(x[7:0])) : ELEN'(x[7:0]);
      3'd1: extend = sgn ? ELEN'($signed(x[15:0])) : ELEN'(x[15:0]);
      default: extend = x;
    endcase
  endfunction

  assign is_signed = (op == VEC_DIV) || (op == VEC_REM);

  always_comb begin
    case (op)
      VEC_DIVU: md_op = MD_DIVU;
      VEC_DIV:  md_op = MD_DIV;
      VEC_REMU: md_op = MD_REMU;
      VEC_REM:  md_op = MD_REM;
      default:  md_op = MD_DIVU;
    endcase
  end

  assign a_ext = extend(a, vsew, is_signed);
  assign b_ext = extend(b, vsew, is_signed);

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      sew_q <= '0;
    end else if (core_en) begin
      if (start && !busy && !done) sew_q <= vsew;
    end
  end

  muldiv #(
      .XLEN(ELEN)
  ) u_muldiv (
      .clk(clk),
      .rst_n(rst_n),
      .core_en(core_en),
      .start(start),
      .op(md_op),
      .a(a_ext),
      .b(b_ext),
      .busy(busy),
      .done(done),
      .result(md_result)
  );

  assign result = extend(md_result, sew_q, 1'b0);
endmodule

`default_nettype wire
