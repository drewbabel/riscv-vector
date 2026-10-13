`default_nettype none

module vec_mul_lane_tb
  import vec_pkg::*;
();

  localparam int ELEN = 32;

  localparam logic [2:0] SEW8 = 3'b000;
  localparam logic [2:0] SEW16 = 3'b001;
  localparam logic [2:0] SEW32 = 3'b010;

  vec_op_e op;
  logic [2:0] vsew;
  logic [ELEN-1:0] a, b;

  logic [ELEN-1:0] result;
  logic [2*ELEN-1:0] product;

  int checks = 0;
  int error_count = 0;

  int op_idx;
  int sew_idx;
  int rand_idx;

  vec_op_e rand_op;
  logic [2:0] rand_vsew;


  vec_mul_lane #(
      .ELEN(ELEN)
  ) dut (
      .op(op),
      .vsew(vsew),
      .a(a),
      .b(b),
      .c('0),
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
            VEC_MUL, VEC_MULH: begin
              ref_a = {{(ELEN + 1 - 8) {a_in[7]}}, a_in[7:0]};
              ref_b = {{(ELEN + 1 - 8) {b_in[7]}}, b_in[7:0]};
            end

            VEC_MULHU: begin
              ref_a = {{(ELEN + 1 - 8) {1'b0}}, a_in[7:0]};
              ref_b = {{(ELEN + 1 - 8) {1'b0}}, b_in[7:0]};
            end

            VEC_MULHSU: begin
              ref_a = {{(ELEN + 1 - 8) {a_in[7]}}, a_in[7:0]};
              ref_b = {{(ELEN + 1 - 8) {1'b0}}, b_in[7:0]};
            end

            default: begin
            end
          endcase

          ref_full = ref_a * ref_b;
          product_ref[15:0] = ref_full[15:0];
        end


        SEW16: begin
          case (op_in)
            VEC_MUL, VEC_MULH: begin
              ref_a = {{(ELEN + 1 - 16) {a_in[15]}}, a_in[15:0]};
              ref_b = {{(ELEN + 1 - 16) {b_in[15]}}, b_in[15:0]};
            end

            VEC_MULHU: begin
              ref_a = {{(ELEN + 1 - 16) {1'b0}}, a_in[15:0]};
              ref_b = {{(ELEN + 1 - 16) {1'b0}}, b_in[15:0]};
            end

            VEC_MULHSU: begin
              ref_a = {{(ELEN + 1 - 16) {a_in[15]}}, a_in[15:0]};
              ref_b = {{(ELEN + 1 - 16) {1'b0}}, b_in[15:0]};
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

            VEC_MULHU: begin
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
                                                 input logic [2*ELEN-1:0] product_in);

    begin
      result_ref = '0;

      case (vsew_in)

        SEW8: begin
          if (op_in == VEC_MUL) result_ref[7:0] = product_in[7:0];
          else result_ref[7:0] = product_in[15:8];
        end

        SEW16: begin
          if (op_in == VEC_MUL) result_ref[15:0] = product_in[15:0];
          else result_ref[15:0] = product_in[31:16];
        end

        SEW32: begin
          if (op_in == VEC_MUL) result_ref[31:0] = product_in[31:0];
          else result_ref[31:0] = product_in[63:32];
        end

        default: begin
          result_ref = '0;
        end

      endcase
    end
  endfunction


  task automatic check_case(input vec_op_e op_in, input logic [2:0] vsew_in,
                            input logic [ELEN-1:0] a_in, input logic [ELEN-1:0] b_in);

    logic [  ELEN-1:0] exp_result;
    logic [2*ELEN-1:0] exp_product;

    begin
      op = op_in;
      vsew = vsew_in;
      a = a_in;
      b = b_in;

      #1;

      exp_product = product_ref(op_in, vsew_in, a_in, b_in);
      exp_result  = result_ref(op_in, vsew_in, exp_product);

      checks++;

      if ((result !== exp_result) || (product !== exp_product)) begin
        error_count++;

        $display("FAIL op=%0d vsew=%b a=%h b=%h exp_result=%h result=%h exp_product=%h product=%h",
                 op, vsew, a, b, exp_result, result, exp_product, product);
      end
    end
  endtask


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


    if (error_count == 0) begin
      $display("PASS: %0d tests, %0d mismatches", checks, error_count);
    end else begin
      $fatal(1, "FAIL: %0d mismatches, %0d tests", error_count, checks);
    end

    $finish;
  end

endmodule

`default_nettype wire
