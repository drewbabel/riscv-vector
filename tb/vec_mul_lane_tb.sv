`default_nettype none

module vec_mul_lane_tb
  import vec_pkg::*;
();

  localparam int ELEN = 32;
  localparam int MinChecks = 26500;
  localparam int MinHold = 5000;
  localparam int MixN = 20000;

  localparam logic [2:0] SEW8 = 3'b000;
  localparam logic [2:0] SEW16 = 3'b001;
  localparam logic [2:0] SEW32 = 3'b010;

  logic clk = 1'b0;
  always #5 clk = ~clk;

  logic core_en = 1'b1;
  vec_op_e op = VEC_MUL;
  logic [2:0] vsew = '0;
  logic [ELEN-1:0] a = '0;
  logic [ELEN-1:0] b = '0;
  logic [ELEN-1:0] c = '0;

  logic [ELEN-1:0] result;
  logic [2*ELEN-1:0] product;

  int checks = 0;
  int hold_checks = 0;
  int error_count = 0;
  int max_errors = 0;

  vec_op_e ops[15] = '{
      VEC_MUL,
      VEC_MULH,
      VEC_MULHU,
      VEC_MULHSU,
      VEC_MACC,
      VEC_NMSAC,
      VEC_MADD,
      VEC_NMSUB,
      VEC_WMUL,
      VEC_WMULU,
      VEC_WMULSU,
      VEC_WMACC,
      VEC_WMACCU,
      VEC_WMACCSU,
      VEC_WMACCUS
  };

  logic stalling = 1'b0;
  logic in_valid = 1'b0;
  logic [ELEN-1:0] in_result = '0;
  logic [2*ELEN-1:0] in_product = '0;
  logic out_valid = 1'b0;
  logic out_held = 1'b0;
  logic [ELEN-1:0] out_result = '0;
  logic [2*ELEN-1:0] out_product = '0;
  vec_op_e out_op = VEC_MUL;
  logic [2:0] out_vsew = '0;
  logic [ELEN-1:0] out_a = '0;
  logic [ELEN-1:0] out_b = '0;
  logic [ELEN-1:0] out_c = '0;

  int op_idx;
  int sew_idx;
  int rand_idx;

  vec_op_e rand_op;
  logic [2:0] rand_vsew;


  vec_mul_lane #(
      .ELEN(ELEN)
  ) dut (
      .clk(clk),
      .core_en(core_en),
      .op(op),
      .vsew(vsew),
      .a(a),
      .b(b),
      .c(c),
      .result(result),
      .product(product)
  );


  function automatic logic [2*ELEN-1:0] product_ref(input vec_op_e op_in, input logic [2:0] vsew_in,
                                                    input logic [ELEN-1:0] a_in,
                                                    input logic [ELEN-1:0] b_in);

    logic signed [ELEN:0] ref_a;
    logic signed [ELEN:0] ref_b;
    logic signed [2*ELEN+1:0] ref_full;

    begin
      ref_a = '0;
      ref_b = '0;
      ref_full = '0;
      product_ref = '0;

      case (vsew_in)

        SEW8: begin
          case (op_in)
            VEC_MUL, VEC_MULH, VEC_WMUL, VEC_WMACC: begin
              ref_a = {{(ELEN + 1 - 8) {a_in[7]}}, a_in[7:0]};
              ref_b = {{(ELEN + 1 - 8) {b_in[7]}}, b_in[7:0]};
            end

            VEC_MULHU, VEC_MACC, VEC_NMSAC, VEC_MADD, VEC_NMSUB, VEC_WMULU, VEC_WMACCU: begin
              ref_a = {{(ELEN + 1 - 8) {1'b0}}, a_in[7:0]};
              ref_b = {{(ELEN + 1 - 8) {1'b0}}, b_in[7:0]};
            end

            VEC_MULHSU, VEC_WMULSU, VEC_WMACCUS: begin
              ref_a = {{(ELEN + 1 - 8) {a_in[7]}}, a_in[7:0]};
              ref_b = {{(ELEN + 1 - 8) {1'b0}}, b_in[7:0]};
            end

            VEC_WMACCSU: begin
              ref_a = {{(ELEN + 1 - 8) {1'b0}}, a_in[7:0]};
              ref_b = {{(ELEN + 1 - 8) {b_in[7]}}, b_in[7:0]};
            end

            default: begin
            end
          endcase

          ref_full = ref_a * ref_b;
          product_ref[15:0] = ref_full[15:0];
        end


        SEW16: begin
          case (op_in)
            VEC_MUL, VEC_MULH, VEC_WMUL, VEC_WMACC: begin
              ref_a = {{(ELEN + 1 - 16) {a_in[15]}}, a_in[15:0]};
              ref_b = {{(ELEN + 1 - 16) {b_in[15]}}, b_in[15:0]};
            end

            VEC_MULHU, VEC_MACC, VEC_NMSAC, VEC_MADD, VEC_NMSUB, VEC_WMULU, VEC_WMACCU: begin
              ref_a = {{(ELEN + 1 - 16) {1'b0}}, a_in[15:0]};
              ref_b = {{(ELEN + 1 - 16) {1'b0}}, b_in[15:0]};
            end

            VEC_MULHSU, VEC_WMULSU, VEC_WMACCUS: begin
              ref_a = {{(ELEN + 1 - 16) {a_in[15]}}, a_in[15:0]};
              ref_b = {{(ELEN + 1 - 16) {1'b0}}, b_in[15:0]};
            end

            VEC_WMACCSU: begin
              ref_a = {{(ELEN + 1 - 16) {1'b0}}, a_in[15:0]};
              ref_b = {{(ELEN + 1 - 16) {b_in[15]}}, b_in[15:0]};
            end

            default: begin
            end
          endcase

          ref_full = ref_a * ref_b;
          product_ref[31:0] = ref_full[31:0];
        end


        SEW32: begin
          case (op_in)
            VEC_MUL, VEC_MULH: begin
              ref_a = {a_in[31], a_in[31:0]};
              ref_b = {b_in[31], b_in[31:0]};
            end

            VEC_MULHU, VEC_MACC, VEC_NMSAC, VEC_MADD, VEC_NMSUB: begin
              ref_a = {1'b0, a_in[31:0]};
              ref_b = {1'b0, b_in[31:0]};
            end

            VEC_MULHSU: begin
              ref_a = {a_in[31], a_in[31:0]};
              ref_b = {1'b0, b_in[31:0]};
            end

            default: begin
            end
          endcase

          ref_full = ref_a * ref_b;
          product_ref[63:0] = ref_full[63:0];
        end


        default: begin
          product_ref = '0;
        end

      endcase
    end
  endfunction


  function automatic logic [ELEN-1:0] result_ref(input vec_op_e op_in, input logic [2:0] vsew_in,
                                                 input logic [2*ELEN-1:0] product_in,
                                                 input logic [ELEN-1:0] c_in);

    begin
      result_ref = '0;

      case (vsew_in)

        SEW8: begin
          case (op_in)
            VEC_MUL: result_ref[7:0] = product_in[7:0];
            VEC_MACC, VEC_MADD: result_ref[7:0] = product_in[7:0] + c_in[7:0];
            VEC_NMSAC, VEC_NMSUB: result_ref[7:0] = c_in[7:0] - product_in[7:0];
            VEC_WMUL, VEC_WMULU, VEC_WMULSU: result_ref[15:0] = product_in[15:0];
            VEC_WMACC, VEC_WMACCU, VEC_WMACCSU, VEC_WMACCUS:
            result_ref[15:0] = product_in[15:0] + c_in[15:0];
            default: result_ref[7:0] = product_in[15:8];
          endcase
        end

        SEW16: begin
          case (op_in)
            VEC_MUL: result_ref[15:0] = product_in[15:0];
            VEC_MACC, VEC_MADD: result_ref[15:0] = product_in[15:0] + c_in[15:0];
            VEC_NMSAC, VEC_NMSUB: result_ref[15:0] = c_in[15:0] - product_in[15:0];
            VEC_WMUL, VEC_WMULU, VEC_WMULSU: result_ref[31:0] = product_in[31:0];
            VEC_WMACC, VEC_WMACCU, VEC_WMACCSU, VEC_WMACCUS:
            result_ref[31:0] = product_in[31:0] + c_in[31:0];
            default: result_ref[15:0] = product_in[31:16];
          endcase
        end

        SEW32: begin
          case (op_in)
            VEC_MUL: result_ref[31:0] = product_in[31:0];
            VEC_MACC, VEC_MADD: result_ref[31:0] = product_in[31:0] + c_in[31:0];
            VEC_NMSAC, VEC_NMSUB: result_ref[31:0] = c_in[31:0] - product_in[31:0];
            VEC_WMUL, VEC_WMULU, VEC_WMULSU, VEC_WMACC, VEC_WMACCU, VEC_WMACCSU, VEC_WMACCUS:
            result_ref = '0;
            default: result_ref[31:0] = product_in[63:32];
          endcase
        end

        default: begin
          result_ref = '0;
        end

      endcase
    end
  endfunction


  // Clock enable drops
  task automatic stall();
    while (stalling && 1'($urandom)) begin
      @(posedge clk);
      core_en <= 1'b0;
      in_valid <= 1'b0;
      op <= ops[$urandom_range(14)];
      vsew <= 3'($urandom);
      a <= $urandom;
      b <= $urandom;
      c <= $urandom;
    end
  endtask

  task automatic check_case_c(input vec_op_e op_in, input logic [2:0] vsew_in,
                              input logic [ELEN-1:0] a_in, input logic [ELEN-1:0] b_in,
                              input logic [ELEN-1:0] c_in);

    logic [  ELEN-1:0] exp_result;
    logic [2*ELEN-1:0] exp_product;

    begin
      stall();

      exp_product = product_ref(op_in, vsew_in, a_in, b_in);
      exp_result  = result_ref(op_in, vsew_in, exp_product, c_in);

      @(posedge clk);
      core_en <= 1'b1;
      op <= op_in;
      vsew <= vsew_in;
      a <= a_in;
      b <= b_in;
      c <= c_in;
      in_valid <= 1'b1;
      in_result <= exp_result;
      in_product <= exp_product;
    end
  endtask

  task automatic check_case(input vec_op_e op_in, input logic [2:0] vsew_in,
                            input logic [ELEN-1:0] a_in, input logic [ELEN-1:0] b_in);
    check_case_c(op_in, vsew_in, a_in, b_in, $urandom);
  endtask

  always @(posedge clk) begin
    out_held <= !core_en;
    if (core_en) begin
      out_valid <= in_valid;
      out_result <= in_result;
      out_product <= in_product;
      out_op <= op;
      out_vsew <= vsew;
      out_a <= a;
      out_b <= b;
      out_c <= c;
    end
  end

  always @(negedge clk) begin
    if (out_valid) begin
      if (out_held) hold_checks++;
      else checks++;

      if ((result !== out_result) || (product !== out_product)) begin
        error_count++;

        $display("FAIL op=%s held=%0b vsew=%b a=%h b=%h c=%h exp %h/%h got %h/%h", out_op.name(),
                 out_held, out_vsew, out_a, out_b, out_c, out_result, out_product, result, product);
        if (error_count == max_errors) $fatal(1, "TB STOPPED: %0d mismatches", error_count);
      end
    end
  end


  initial void'($value$plusargs("max_errors=%d", max_errors));

  initial begin

    // Directed cases

    check_case(VEC_MUL, SEW8, 32'h0000_00FE, 32'h0000_0003);

    check_case(VEC_MULH, SEW8, 32'h0000_00FF, 32'h0000_00FF);

    check_case(VEC_MULHU, SEW8, 32'h0000_00FF, 32'h0000_0002);

    check_case(VEC_MULHSU, SEW8, 32'h0000_00FE, 32'h0000_0002);


    check_case(VEC_MUL, SEW16, 32'h0000_FFFE, 32'h0000_0003);

    check_case(VEC_MULH, SEW16, 32'h0000_FFFF, 32'h0000_FFFF);

    check_case(VEC_MULHU, SEW16, 32'h0000_FFFF, 32'h0000_0002);

    check_case(VEC_MULHSU, SEW16, 32'h0000_FFFE, 32'h0000_0002);


    check_case(VEC_MUL, SEW32, 32'hFFFF_FFFE, 32'h0000_0003);

    check_case(VEC_MULH, SEW32, 32'hFFFF_FFFF, 32'hFFFF_FFFF);

    check_case(VEC_MULHU, SEW32, 32'hFFFF_FFFF, 32'h0000_0002);

    check_case(VEC_MULHSU, SEW32, 32'hFFFF_FFFE, 32'h0000_0002);


    // Sign corners

    check_case(VEC_MULH, SEW8, 32'h0000_0080, 32'h0000_0080);

    check_case(VEC_MULHSU, SEW8, 32'h0000_0080, 32'h0000_00FF);

    check_case(VEC_MULHU, SEW8, 32'h0000_00FF, 32'h0000_00FF);


    check_case(VEC_MULH, SEW16, 32'h0000_8000, 32'h0000_8000);

    check_case(VEC_MULHSU, SEW16, 32'h0000_8000, 32'h0000_FFFF);

    check_case(VEC_MULHU, SEW16, 32'h0000_FFFF, 32'h0000_FFFF);


    check_case(VEC_MULH, SEW32, 32'h8000_0000, 32'h8000_0000);

    check_case(VEC_MULHSU, SEW32, 32'h8000_0000, 32'hFFFF_FFFF);

    check_case(VEC_MULHU, SEW32, 32'hFFFF_FFFF, 32'hFFFF_FFFF);


    // Widening sign corners

    check_case(VEC_WMUL, SEW8, 32'h0000_0080, 32'h0000_0080);
    check_case(VEC_WMULU, SEW8, 32'h0000_00FF, 32'h0000_00FF);
    check_case(VEC_WMULSU, SEW8, 32'h0000_0080, 32'h0000_00FF);

    check_case(VEC_WMUL, SEW16, 32'h0000_8000, 32'h0000_8000);
    check_case(VEC_WMULU, SEW16, 32'h0000_FFFF, 32'h0000_FFFF);
    check_case(VEC_WMULSU, SEW16, 32'h0000_8000, 32'h0000_FFFF);


    // Widening directed cases

    check_case(VEC_WMUL, SEW8, 32'h0000_00FE, 32'h0000_0003);
    check_case(VEC_WMULU, SEW8, 32'h0000_00FF, 32'h0000_0002);
    check_case(VEC_WMULSU, SEW8, 32'h0000_00FE, 32'h0000_00FF);

    check_case(VEC_WMUL, SEW16, 32'h0000_FFFE, 32'h0000_0003);
    check_case(VEC_WMULU, SEW16, 32'h0000_FFFF, 32'h0000_0002);
    check_case(VEC_WMULSU, SEW16, 32'h0000_FFFE, 32'h0000_FFFF);


    // Accumulate sign corners

    check_case_c(VEC_WMACC, SEW8, 32'h0000_0080, 32'h0000_0080, 32'h0000_0001);
    check_case_c(VEC_WMACCU, SEW8, 32'h0000_00FF, 32'h0000_00FF, 32'h0000_0001);
    check_case_c(VEC_WMACCSU, SEW8, 32'h0000_00FF, 32'h0000_0080, 32'h0000_0001);
    check_case_c(VEC_WMACCUS, SEW8, 32'h0000_0080, 32'h0000_00FF, 32'h0000_0001);

    check_case_c(VEC_WMACC, SEW16, 32'h0000_8000, 32'h0000_8000, 32'h0000_0001);
    check_case_c(VEC_WMACCU, SEW16, 32'h0000_FFFF, 32'h0000_FFFF, 32'h0000_0001);
    check_case_c(VEC_WMACCSU, SEW16, 32'h0000_FFFF, 32'h0000_8000, 32'h0000_0001);
    check_case_c(VEC_WMACCUS, SEW16, 32'h0000_8000, 32'h0000_FFFF, 32'h0000_0001);


    // Accumulate directed cases

    check_case_c(VEC_WMACC, SEW8, 32'h0000_00FE, 32'h0000_0003, 32'h0000_0005);
    check_case_c(VEC_WMACCU, SEW8, 32'h0000_00FF, 32'h0000_0002, 32'h0000_0001);
    check_case_c(VEC_WMACCSU, SEW8, 32'h0000_00FF, 32'h0000_00FE, 32'h0000_0003);
    check_case_c(VEC_WMACCUS, SEW8, 32'h0000_00FE, 32'h0000_00FF, 32'h0000_0004);

    check_case_c(VEC_WMACC, SEW16, 32'h0000_FFFE, 32'h0000_0003, 32'h0000_0005);
    check_case_c(VEC_WMACCU, SEW16, 32'h0000_FFFF, 32'h0000_0002, 32'h0000_0001);
    check_case_c(VEC_WMACCSU, SEW16, 32'h0000_FFFF, 32'h0000_FFFE, 32'h0000_0003);
    check_case_c(VEC_WMACCUS, SEW16, 32'h0000_FFFE, 32'h0000_FFFF, 32'h0000_0004);


    // Accumulate carries out
    check_case_c(VEC_WMACCU, SEW8, 32'h0000_00FF, 32'h0000_00FF, 32'h0000_0200);
    check_case_c(VEC_WMACCU, SEW16, 32'h0000_FFFF, 32'h0000_FFFF, 32'h0002_0000);


    // Widening past ELEN
    check_case(VEC_WMUL, SEW32, 32'h1234_5678, 32'h0000_0002);
    check_case_c(VEC_WMACC, SEW32, 32'h1234_5678, 32'h0000_0002, 32'hFFFF_FFFF);


    // Randomized sweep:
    // 3 SEWs * 4 operations * 250 random inputs = 3000 tests

    for (sew_idx = 0; sew_idx < 3; sew_idx++) begin

      case (sew_idx)
        0: rand_vsew = SEW8;
        1: rand_vsew = SEW16;
        2: rand_vsew = SEW32;
        default: rand_vsew = SEW8;
      endcase

      for (op_idx = 0; op_idx < 4; op_idx++) begin

        case (op_idx)
          0: rand_op = VEC_MUL;
          1: rand_op = VEC_MULH;
          2: rand_op = VEC_MULHU;
          3: rand_op = VEC_MULHSU;
          default: rand_op = VEC_MUL;
        endcase

        for (rand_idx = 0; rand_idx < 250; rand_idx++) begin
          check_case(rand_op, rand_vsew, $urandom, $urandom);
        end

      end
    end


    // Widening sweep

    for (sew_idx = 0; sew_idx < 2; sew_idx++) begin

      rand_vsew = (sew_idx == 0) ? SEW8 : SEW16;

      for (op_idx = 0; op_idx < 7; op_idx++) begin

        rand_op = ops[8+op_idx];

        for (rand_idx = 0; rand_idx < 250; rand_idx++) begin
          check_case(rand_op, rand_vsew, $urandom, $urandom);
        end

      end
    end


    // Neighbours differ
    stalling = 1'b1;
    for (rand_idx = 0; rand_idx < MixN; rand_idx++) begin
      check_case(ops[$urandom_range(14)], 3'($urandom_range(2)), $urandom, $urandom);
    end
    stalling = 1'b0;

    @(posedge clk);
    core_en  <= 1'b1;
    in_valid <= 1'b0;
    @(posedge clk);
    @(negedge clk);


    if (checks < MinChecks || hold_checks < MinHold) begin
      $fatal(1, "TB UNDER-RAN: %0d tests, %0d hold checks", checks, hold_checks);
    end else if (error_count == 0) begin
      $display("PASS: %0d tests, %0d hold checks, %0d mismatches", checks, hold_checks,
               error_count);
    end else begin
      $fatal(1, "FAIL: %0d mismatches, %0d tests", error_count, checks);
    end

    $finish;
  end

endmodule

`default_nettype wire
