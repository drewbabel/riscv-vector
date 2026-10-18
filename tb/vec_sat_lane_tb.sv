`default_nettype none

module vec_sat_lane_tb
  import vec_pkg::*;
();

  localparam int ELEN = arch_pkg::ELEN;
  localparam int MinChecks = 5_000_000;
  localparam int MinHold = 10_000;
  localparam int ShowErrors = 20;
  localparam int MixN = 50_000;

  int   checks = 0;
  int   hold_checks = 0;
  int   errors = 0;
  int   max_errors = 0;

  logic clk = 1'b0;
  always #5 clk = ~clk;

  logic core_en = 1'b1;
  vec_op_e op = VEC_SADDU;
  logic [2:0] vsew = '0;
  logic [1:0] vxrm = '0;
  logic [ELEN-1:0] a = '0;
  logic [ELEN-1:0] b = '0;
  logic [2*ELEN-1:0] product = '0;
  logic [ELEN-1:0] result;
  logic sat;

  logic stalling = 1'b0;
  logic in_valid = 1'b0;
  logic [ELEN-1:0] in_res = '0;
  logic in_sat = 1'b0;
  logic out_valid = 1'b0;
  logic out_held = 1'b0;
  logic [ELEN-1:0] out_res = '0;
  logic out_sat = 1'b0;
  vec_op_e out_op = VEC_SADDU;
  logic [2:0] out_vsew = '0;
  logic [1:0] out_vxrm = '0;
  logic [ELEN-1:0] out_a = '0;
  logic [ELEN-1:0] out_b = '0;

  vec_sat_lane #(
      .ELEN(ELEN)
  ) dut (
      .clk(clk),
      .core_en(core_en),
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

  function automatic longint uval(input logic [ELEN-1:0] x, input int w);
    uval = longint'({32'd0, x}) & umask(w);
  endfunction

  function automatic longint sval(input logic [ELEN-1:0] x, input int w);
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
  task automatic ref_lane(input vec_op_e o, input int w, input logic [ELEN-1:0] x,
                          input logic [ELEN-1:0] y, input logic [1:0] mode,
                          output logic [ELEN-1:0] res, output logic s);
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
    if ((o == VEC_NCLIPU || o == VEC_NCLIP) && w == ELEN) begin
      t = 0;
      s = 1'b0;
    end
    res = ELEN'(t & umask(w));
  endtask

  // Product with junk
  function automatic logic [2*ELEN-1:0] full_product(input logic [ELEN-1:0] x,
                                                     input logic [ELEN-1:0] y, input int w);
    logic [2*ELEN-1:0] keep;
    logic [2*ELEN-1:0] prod;
    keep = (w == ELEN) ? '1 : (2 * ELEN)'(umask(2 * w));
    prod = (2 * ELEN)'(sval(x, w) * sval(y, w));
    full_product = (prod & keep) | ({$urandom, $urandom} & ~keep);
  endfunction

  // Clock enable drops
  task automatic stall();
    while (stalling && 1'($urandom)) begin
      @(posedge clk);
      core_en <= 1'b0;
      in_valid <= 1'b0;
      op <= ops[$urandom_range($size(ops)-1)];
      vsew <= 3'($urandom);
      vxrm <= 2'($urandom);
      a <= $urandom;
      b <= $urandom;
      product <= {$urandom, $urandom};
    end
  endtask

  // One op
  task automatic check(input vec_op_e o, input logic [2:0] sew, input logic [1:0] mode,
                       input logic [ELEN-1:0] x, input logic [ELEN-1:0] y);
    logic [ELEN-1:0] exp_res;
    logic exp_sat;
    stall();
    ref_lane(o, 8 << sew, x, y, mode, exp_res, exp_sat);
    @(posedge clk);
    core_en <= 1'b1;
    op <= o;
    vsew <= sew;
    vxrm <= mode;
    a <= x;
    b <= y;
    product <= full_product(x, y, 8 << sew);
    in_valid <= 1'b1;
    in_res <= exp_res;
    in_sat <= exp_sat;
  endtask

  task automatic drain();
    @(posedge clk);
    core_en  <= 1'b1;
    in_valid <= 1'b0;
    @(posedge clk);
    @(negedge clk);
  endtask

  always @(posedge clk) begin
    out_held <= !core_en;
    if (core_en) begin
      out_valid <= in_valid;
      out_res <= in_res;
      out_sat <= in_sat;
      out_op <= op;
      out_vsew <= vsew;
      out_vxrm <= vxrm;
      out_a <= a;
      out_b <= b;
    end
  end

  always @(negedge clk) begin
    if (out_valid) begin
      if (out_held) hold_checks++;
      else checks++;
      if (result !== out_res || sat !== out_sat) begin
        errors++;
        if (errors <= ShowErrors)
          $display(
              "FAIL %s held=%0b sew=%0d vxrm=%0d a=%h b=%h got %h/%b exp %h/%b",
              out_op.name(),
              out_held,
              8 << out_vsew,
              out_vxrm,
              out_a,
              out_b,
              result,
              sat,
              out_res,
              out_sat
          );
        if (errors == max_errors) $fatal(1, "TB STOPPED: %0d mismatches", errors);
      end
    end
  end

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
  function automatic logic [ELEN-1:0] edge_val(input int idx, input int w);
    longint m;
    m = umask(w);
    case (idx)
      0: edge_val = ELEN'(0);
      1: edge_val = ELEN'(1);
      2: edge_val = ELEN'(2);
      3: edge_val = ELEN'(m);
      4: edge_val = ELEN'(m - 1);
      5: edge_val = ELEN'(m >> 1);
      6: edge_val = ELEN'((m >> 1) + 1);
      7: edge_val = ELEN'((m >> 1) - 1);
      8: edge_val = ELEN'((m >> 1) + 2);
      9: edge_val = ELEN'(w - 1);
      10: edge_val = ELEN'(3);
      default: edge_val = ELEN'(m >> 2);
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

  // Neighbours differ
  task automatic random_mix(input int n);
    vec_op_e o;
    logic [2:0] sew;
    stalling = 1'b1;
    for (int i = 0; i < n; i++) begin
      o   = ops[$urandom_range($size(ops)-1)];
      sew = 3'($urandom_range(2));
      check(o, sew, 2'($urandom), $urandom, $urandom);
    end
    stalling = 1'b0;
  endtask

  task automatic do_verdict();
    if (checks < MinChecks || hold_checks < MinHold)
      $fatal(1, "TB UNDER-RAN: %0d checks, %0d hold checks", checks, hold_checks);
    if (errors != 0) $fatal(1, "FAIL: %0d mismatches, %0d checks", errors, checks);
    $display("PASS: %0d checks, %0d hold checks", checks, hold_checks);
    $finish;
  endtask

  initial void'($value$plusargs("max_errors=%d", max_errors));

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

    random_mix(MixN);
    drain();

    do_verdict();
  end

endmodule

`default_nettype wire
