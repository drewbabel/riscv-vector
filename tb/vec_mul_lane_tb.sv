`default_nettype none

module vec_mul_lane_tb
  import vec_pkg::*;
();

  localparam int ELEN = 32;
  localparam int NumTestCases = 12;


  //input logic
  vec_op_e op;
  logic [2:0] vsew;
  logic [ELEN-1:0] a, b;

  //output logic
  logic [ELEN-1:0] result;
  logic [2*ELEN-1:0] product;


  int checks = 0;
  int error_count = 0;
  int i;

  typedef struct packed {
    //input
    vec_op_e op;
    logic [2:0] vsew;
    logic [ELEN-1:0] a, b;

    //output
    logic [ELEN-1:0]   exp_result;
    logic [2*ELEN-1:0] exp_product;
  } test_vector_t;


  test_vector_t test_vec[NumTestCases];


  task automatic set_tv;
    input int idx;
    input vec_op_e tv_op;
    input logic [2:0] tv_vsew;
    input logic [ELEN-1:0] tv_a;
    input logic [ELEN-1:0] tv_b;
    input logic [ELEN-1:0] tv_exp_result;
    input logic [2*ELEN-1:0] tv_exp_product;

    begin
      //setting inputs
      test_vec[idx].op = tv_op;
      test_vec[idx].vsew = tv_vsew;
      test_vec[idx].a = tv_a;
      test_vec[idx].b = tv_b;

      //setting expected outputs
      test_vec[idx].exp_result = tv_exp_result;
      test_vec[idx].exp_product = tv_exp_product;

    end
  endtask

  task automatic run_tv(input int idx);
    begin
      op = test_vec[idx].op;
      vsew = test_vec[idx].vsew;
      a = test_vec[idx].a;
      b = test_vec[idx].b;

      #1;  // let DUT settle before sampling outputs

      checks++;

      if ((result !== test_vec[idx].exp_result) || (product !== test_vec[idx].exp_product)) begin

        error_count++;
        $display({"FAIL idx=%0d op=%0d vsew=%b a=%h b=%h exp_result=%h result=%h",
                  " exp_product=%h product=%h"}, idx, op, vsew, a, b, test_vec[idx].exp_result,
                   result, test_vec[idx].exp_product, product);

      end else begin
        $display("PASS idx=%0d op=%0d vsew=%b", idx, op, vsew);
      end

    end
  endtask

  //instantiation
  vec_mul_lane #(
      .ELEN(ELEN)
  ) DUT (
      .op(op),
      .vsew(vsew),
      .a(a),
      .b(b),
      .c('0),
      .result(result),
      .product(product)
  );

  initial begin
    // ---------------- SEW 8 ----------------

    // VMUL: -2 * 3 = -6
    // 16-bit product = FFFA, low 8 bits = FA
    set_tv(0, VEC_MUL, 3'b000, 32'h0000_00FE, 32'h0000_0003, 32'h0000_00FA,
           64'h0000_0000_0000_FFFA);

    // VMULH: -1 * -1 = 1
    // high 8 bits = 00
    set_tv(1, VEC_MULH, 3'b000, 32'h0000_00FF, 32'h0000_00FF, 32'h0000_0000,
           64'h0000_0000_0000_0001);

    // VMULHU: 255 * 2 = 510 = 01FE
    set_tv(2, VEC_MULHU, 3'b000, 32'h0000_00FF, 32'h0000_0002, 32'h0000_0001,
           64'h0000_0000_0000_01FE);

    // VMULHSU: -2 * 2 = -4 = FFFC
    set_tv(3, VEC_MULHSU, 3'b000, 32'h0000_00FE, 32'h0000_0002, 32'h0000_00FF,
           64'h0000_0000_0000_FFFC);


    // ---------------- SEW 16 ----------------

    // VMUL: -2 * 3 = -6
    set_tv(4, VEC_MUL, 3'b001, 32'h0000_FFFE, 32'h0000_0003, 32'h0000_FFFA,
           64'h0000_0000_FFFF_FFFA);

    // VMULH: -1 * -1 = 1
    set_tv(5, VEC_MULH, 3'b001, 32'h0000_FFFF, 32'h0000_FFFF, 32'h0000_0000,
           64'h0000_0000_0000_0001);

    // VMULHU: 65535 * 2 = 0001_FFFE
    set_tv(6, VEC_MULHU, 3'b001, 32'h0000_FFFF, 32'h0000_0002, 32'h0000_0001,
           64'h0000_0000_0001_FFFE);

    // VMULHSU: -2 * 2 = FFFF_FFFC
    set_tv(7, VEC_MULHSU, 3'b001, 32'h0000_FFFE, 32'h0000_0002, 32'h0000_FFFF,
           64'h0000_0000_FFFF_FFFC);


    // ---------------- SEW 32 ----------------

    // VMUL: -2 * 3 = -6
    set_tv(8, VEC_MUL, 3'b010, 32'hFFFF_FFFE, 32'h0000_0003, 32'hFFFF_FFFA,
           64'hFFFF_FFFF_FFFF_FFFA);

    // VMULH: -1 * -1 = 1
    set_tv(9, VEC_MULH, 3'b010, 32'hFFFF_FFFF, 32'hFFFF_FFFF, 32'h0000_0000,
           64'h0000_0000_0000_0001);

    // VMULHU: 0xFFFFFFFF * 2
    set_tv(10, VEC_MULHU, 3'b010, 32'hFFFF_FFFF, 32'h0000_0002, 32'h0000_0001,
           64'h0000_0001_FFFF_FFFE);

    // VMULHSU: -2 * 2 = -4
    set_tv(11, VEC_MULHSU, 3'b010, 32'hFFFF_FFFE, 32'h0000_0002, 32'hFFFF_FFFF,
           64'hFFFF_FFFF_FFFF_FFFC);

    for (i = 0; i < NumTestCases; i++) begin
      run_tv(i);
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
