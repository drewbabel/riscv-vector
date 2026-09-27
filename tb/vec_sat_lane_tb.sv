`default_nettype none

module vec_sat_lane_tb
  import vec_pkg::*;
();

  localparam int ELEN = 32;

  int checks = 0;
  int errors = 0;

  vec_op_e op;
  logic [2:0] vsew;
  logic [1:0] vxrm;
  logic [ELEN-1:0] a;
  logic [ELEN-1:0] b;
  logic [2*ELEN-1:0] product;
  logic [ELEN-1:0] result;
  logic sat;

  vec_sat_lane #(
      .ELEN(ELEN)
  ) dut (
      .op(op),
      .vsew(vsew),
      .vxrm(vxrm),
      .a(a),
      .b(b),
      .product(product),
      .result(result),
      .sat(sat)
  );

  vec_op_e ops[13] = '{
      VEC_SADDU,
      VEC_SADD,
      VEC_SSUBU,
      VEC_SSUB,
      VEC_AADDU,
      VEC_AADD,
      VEC_ASUBU,
      VEC_ASUB,
      VEC_SSRL,
      VEC_SSRA,
      VEC_SMUL,
      VEC_NCLIPU,
      VEC_NCLIP
  };

  // Width helpers
  function automatic longint umask(input int w);
    umask = (64'sd1 <<< w) - 64'sd1;
  endfunction

  function automatic longint uval(input logic [31:0] x, input int w);
    uval = longint'({32'd0, x}) & umask(w);
  endfunction

  function automatic longint sval(input logic [31:0] x, input int w);
    longint u;
    u = uval(x, w);
    sval = u[w-1] ? (u - (64'sd1 <<< w)) : u;
  endfunction

  // Floor then round
  function automatic longint roundoff(input longint v, input int d, input logic [1:0] mode);
    longint q;
    longint rem;
    longint half;
    q = v >>> d;
    rem = v - (q <<< d);
    half = (d > 0) ? (64'sd1 <<< (d - 1)) : 64'sd0;
    case (mode)
      2'd0: roundoff = q + ((d > 0 && rem >= half) ? 1 : 0);
      2'd1: roundoff = q + ((d > 0 && (rem > half || (rem == half && q[0]))) ? 1 : 0);
      2'd2: roundoff = q;
      default: roundoff = (rem != 0) ? (q | 64'sd1) : q;
    endcase
  endfunction

  // Reference model
  task automatic ref_lane(input vec_op_e o, input int w, input logic [31:0] x, input logic [31:0] y,
                          input logic [1:0] mode, output logic [31:0] res, output logic s);
    longint ux;
    longint uy;
    longint sx;
    longint sy;
    longint smax;
    longint smin;
    longint t;
    ux = uval(x, w);
    uy = uval(y, w);
    sx = sval(x, w);
    sy = sval(y, w);
    smax = (64'sd1 <<< (w - 1)) - 1;
    smin = -(64'sd1 <<< (w - 1));
    s = 1'b0;
    case (o)
      VEC_SADDU: begin
        t = ux + uy;
        if (t > umask(w)) begin
          t = umask(w);
          s = 1'b1;
        end
      end
      VEC_SSUBU: begin
        t = ux - uy;
        if (t < 0) begin
          t = 0;
          s = 1'b1;
        end
      end
      VEC_SADD, VEC_SSUB: begin
        t = (o == VEC_SADD) ? sx + sy : sx - sy;
        if (t > smax) begin
          t = smax;
          s = 1'b1;
        end else if (t < smin) begin
          t = smin;
          s = 1'b1;
        end
      end
      VEC_AADDU: t = roundoff(ux + uy, 1, mode);
      VEC_AADD:  t = roundoff(sx + sy, 1, mode);
      VEC_ASUBU: t = roundoff(ux - uy, 1, mode);
      VEC_ASUB:  t = roundoff(sx - sy, 1, mode);
      VEC_SSRL:  t = roundoff(ux, int'(uy) & (w - 1), mode);
      VEC_SSRA:  t = roundoff(sx, int'(uy) & (w - 1), mode);
      VEC_SMUL: begin
        t = roundoff(sx * sy, w - 1, mode);
        if (t > smax) begin
          t = smax;
          s = 1'b1;
        end else if (t < smin) begin
          t = smin;
          s = 1'b1;
        end
      end
      VEC_NCLIPU: begin
        t = roundoff(uval(x, 2 * w), int'(y) & (2 * w - 1), mode);
        if (t > umask(w)) begin
          t = umask(w);
          s = 1'b1;
        end
      end
      default: begin
        t = roundoff(sval(x, 2 * w), int'(y) & (2 * w - 1), mode);
        if (t > smax) begin
          t = smax;
          s = 1'b1;
        end else if (t < smin) begin
          t = smin;
          s = 1'b1;
        end
      end
    endcase
    if ((o == VEC_NCLIPU || o == VEC_NCLIP) && w == 32) begin
      t = 0;
      s = 1'b0;
    end
    res = 32'(t & umask(w));
  endtask

  // Product with junk
  function automatic logic [63:0] full_product(input logic [31:0] x, input logic [31:0] y,
                                               input int w);
    logic [63:0] keep;
    logic [63:0] prod;
    keep = (w == 32) ? '1 : 64'(umask(2 * w));
    prod = 64'(sval(x, w) * sval(y, w));
    full_product = (prod & keep) | ({$urandom, $urandom} & ~keep);
  endfunction

  // One check
  task automatic check(input vec_op_e o, input logic [2:0] sew, input logic [1:0] mode,
                       input logic [31:0] x, input logic [31:0] y);
    logic [31:0] exp_res;
    logic exp_sat;
    op = o;
    vsew = sew;
    vxrm = mode;
    a = x;
    b = y;
    product = full_product(x, y, 8 << sew);
    #1;
    ref_lane(o, 8 << sew, x, y, mode, exp_res, exp_sat);
    checks++;
    if (result !== exp_res || sat !== exp_sat) begin
      errors++;
      if (errors <= 10)
        $display(
            "FAIL %s sew=%0d vxrm=%0d a=%h b=%h got %h/%b exp %h/%b",
            o.name(),
            8 << sew,
            mode,
            x,
            y,
            result,
            sat,
            exp_res,
            exp_sat
        );
    end
  endtask

  // Every byte pair
  task automatic sweep8();
    for (int k = 0; k < $size(ops); k++)
      for (int m = 0; m < 4; m++)
        for (int i = 0; i < 256; i++)
          for (int j = 0; j < 256; j++)
            check(ops[k], 3'd0, 2'(m), {$urandom} << 8 | 32'(i), {$urandom} << 8 | 32'(j));
  endtask

  // Narrowing sources
  task automatic sweep_clip8();
    for (int k = 11; k < 13; k++)
      for (int m = 0; m < 4; m++)
        for (int sh = 0; sh < 32; sh++)
          for (int i = 0; i < 4096; i++)
            check(ops[k], 3'd0, 2'(m), {$urandom} << 16 | 32'(i << 4) | 32'($urandom & 15),
                  {$urandom} << 5 | 32'(sh));
  endtask

  // Edge values
  function automatic logic [31:0] edge_val(input int idx, input int w);
    longint m;
    m = umask(w);
    case (idx)
      0: edge_val = 32'(0);
      1: edge_val = 32'(1);
      2: edge_val = 32'(2);
      3: edge_val = 32'(m);
      4: edge_val = 32'(m - 1);
      5: edge_val = 32'(m >> 1);
      6: edge_val = 32'((m >> 1) + 1);
      7: edge_val = 32'((m >> 1) - 1);
      8: edge_val = 32'((m >> 1) + 2);
      9: edge_val = 32'(w - 1);
      10: edge_val = 32'(3);
      default: edge_val = 32'(m >> 2);
    endcase
  endfunction

  task automatic edges(input logic [2:0] sew);
    for (int k = 0; k < $size(ops); k++)
      for (int m = 0; m < 4; m++)
        for (int i = 0; i < 12; i++)
          for (int j = 0; j < 12; j++)
            check(ops[k], sew, 2'(m), edge_val(i, 8 << sew), edge_val(j, 8 << sew));
  endtask

  task automatic random_cases(input logic [2:0] sew, input int n);
    for (int k = 0; k < $size(ops); k++)
      for (int m = 0; m < 4; m++)
        for (int i = 0; i < n; i++) check(ops[k], sew, 2'(m), $urandom, $urandom);
  endtask

  task automatic verdict();
    $display("vec_sat_lane: %0d checks, %0d errors", checks, errors);
    if (errors != 0) $fatal(1, "vec_sat_lane FAILED");
    $finish;
  endtask

  initial begin
    // Exhaustive bytes
    sweep8();

    sweep_clip8();

    // Halfword and word edges
    edges(3'd1);
    edges(3'd2);

    // Random operands
    random_cases(3'd1, 5000);
    random_cases(3'd2, 5000);

    verdict();
  end

endmodule

`default_nettype wire
