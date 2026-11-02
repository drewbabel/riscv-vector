`default_nettype none

module hazard_unit_tb
  import opcode_pkg::*;
();

  localparam int RegAddrW = arch_pkg::RegAddrW;
  localparam int NRegs = arch_pkg::NumRegs;
  localparam int MinChecks = 300000;
  localparam int Pool = 4;
  localparam int FieldW = 2;

  int checks = 0;
  int errors = 0;
  int max_errors = 0;

  logic [RegAddrW-1:0] rs1_id;
  logic [RegAddrW-1:0] rs2_id;
  logic [RegAddrW-1:0] rs1_ex;
  logic [RegAddrW-1:0] rs2_ex;
  logic [RegAddrW-1:0] rd_id;
  logic [RegAddrW-1:0] rd_ex;
  logic [RegAddrW-1:0] rd_mem;
  logic [RegAddrW-1:0] rd_wb;
  logic reg_write_ex;
  logic reg_write_mem;
  logic reg_write_wb;
  logic [ResSrcW-1:0] result_src_ex;
  logic fp_op_id;
  logic frs1_read_id;
  logic frs2_read_id;
  logic frs3_read_id;
  logic frd_write_id;
  logic [RegAddrW-1:0] rs3_id;
  logic [NRegs-1:0] fp_busy;
  logic frd_write_ex;
  logic frd_write_mem;
  logic frm_write_ex;
  logic stall;
  logic [FwdW-1:0] forward_a;
  logic [FwdW-1:0] forward_b;

  hazard_unit dut (
      .rs1_id(rs1_id),
      .rs2_id(rs2_id),
      .rs1_ex(rs1_ex),
      .rs2_ex(rs2_ex),
      .rd_id(rd_id),
      .rd_ex(rd_ex),
      .rd_mem(rd_mem),
      .rd_wb(rd_wb),
      .reg_write_ex(reg_write_ex),
      .reg_write_mem(reg_write_mem),
      .reg_write_wb(reg_write_wb),
      .result_src_ex(result_src_ex),
      .fp_op_id(fp_op_id),
      .frs1_read_id(frs1_read_id),
      .frs2_read_id(frs2_read_id),
      .frs3_read_id(frs3_read_id),
      .frd_write_id(frd_write_id),
      .rs3_id(rs3_id),
      .fp_busy(fp_busy),
      .frd_write_ex(frd_write_ex),
      .frd_write_mem(frd_write_mem),
      .frm_write_ex(frm_write_ex),
      .stall(stall),
      .forward_a(forward_a),
      .forward_b(forward_b)
  );

  initial void'($value$plusargs("max_errors=%d", max_errors));

  task automatic check(input string name, input logic [FieldW-1:0] got,
                       input logic [FieldW-1:0] exp);
    checks++;
    if (got !== exp) begin
      errors++;
      $display("FAIL %s: got %h, expected %h", name, got, exp);
      if (errors == max_errors) $fatal(1, "TB STOPPED: %0d mismatches", errors);
    end
  endtask  // Automatic

  function automatic logic [RegAddrW-1:0] pick(input logic [RegAddrW-1:0] base);
    if ($urandom_range(3) == 0) return RegAddrW'($urandom);
    return base + RegAddrW'($urandom_range(Pool - 1));
  endfunction

  task automatic drive(input logic [RegAddrW-1:0] base);
    rs1_id = pick(base);
    rs2_id = pick(base);
    rs3_id = pick(base);
    rs1_ex = pick(base);
    rs2_ex = pick(base);
    rd_id = pick(base);
    rd_ex = pick(base);
    rd_mem = pick(base);
    rd_wb = pick(base);
    reg_write_ex = 1'($urandom);
    reg_write_mem = 1'($urandom);
    reg_write_wb = 1'($urandom);
    result_src_ex = ResSrcW'($urandom);
    fp_op_id = 1'($urandom);
    frs1_read_id = 1'($urandom);
    frs2_read_id = 1'($urandom);
    frs3_read_id = 1'($urandom);
    frd_write_id = 1'($urandom);
    fp_busy = '0;
    if ($urandom_range(3) == 0) fp_busy = NRegs'(1) << pick(base);
    else if ($urandom_range(3) == 0) fp_busy = NRegs'({32'($urandom), 32'($urandom)});
    frd_write_ex  = 1'($urandom);
    frd_write_mem = 1'($urandom);
    frm_write_ex  = $urandom_range(7) == 0;
  endtask  // Automatic

  task automatic check_now();
    string tag;
    #1;
    tag = $sformatf(
        "rs %0d %0d %0d ex %0d %0d rd %0d %0d %0d %0d",
        rs1_id,
        rs2_id,
        rs3_id,
        rs1_ex,
        rs2_ex,
        rd_id,
        rd_ex,
        rd_mem,
        rd_wb
    );
    check({tag, " stall"}, FieldW'(stall), FieldW'(stall_ref()));
    check({tag, " forward_a"}, forward_a, fwd_ref(rs1_ex));
    check({tag, " forward_b"}, forward_b, fwd_ref(rs2_ex));
  endtask  // Automatic

  task automatic random_sweep(input int n);
    repeat (n) begin
      drive(RegAddrW'($urandom));
      check_now();
    end
  endtask  // Automatic

  task automatic zero_sweep(input int n);
    repeat (n) begin
      drive('0);
      check_now();
    end
  endtask  // Automatic

  task automatic test_fp_regs();
    for (int r = 0; r < NRegs; r++) begin
      for (int src = 0; src < 7; src++) begin
        drive(RegAddrW'(r + 8));
        fp_op_id = 1'b1;
        frm_write_ex = 1'b0;
        {frs1_read_id, frs2_read_id, frs3_read_id, frd_write_id} = 4'(1 << (src % 4));
        {frd_write_ex, frd_write_mem} = 2'b00;
        fp_busy = '0;
        case (src)
          0, 1, 2, 3: fp_busy = NRegs'(1) << r;
          4: begin
            frd_write_ex = 1'b1;
            rd_ex = RegAddrW'(r);
          end
          default: begin
            frd_write_mem = 1'b1;
            rd_mem = RegAddrW'(r);
          end
        endcase
        case (src % 4)
          0: rs1_id = RegAddrW'(r);
          1: rs2_id = RegAddrW'(r);
          2: rs3_id = RegAddrW'(r);
          default: rd_id = RegAddrW'(r);
        endcase
        check_now();
      end
    end
  endtask  // Automatic

  task automatic test_int_regs();
    for (int r = 0; r < NRegs; r++) begin
      drive(RegAddrW'(r + 8));
      fp_op_id = 1'b0;
      result_src_ex = ResMem;
      reg_write_ex = 1'b1;
      rd_ex = RegAddrW'(r);
      rs1_id = RegAddrW'(r);
      check_now();
      rs1_id = RegAddrW'(r + 1);
      rs2_id = RegAddrW'(r);
      check_now();
      reg_write_mem = 1'b1;
      reg_write_wb = 1'b1;
      rd_mem = RegAddrW'(r);
      rd_wb = RegAddrW'(r);
      rs1_ex = RegAddrW'(r);
      rs2_ex = RegAddrW'(r);
      check_now();
      reg_write_mem = 1'b0;
      check_now();
    end
  endtask  // Automatic

  task automatic do_verdict();
    if (checks < MinChecks)
      $fatal(1, "TB UNDER-RAN: %0d checks, expected at least %0d", checks, MinChecks);
    if (errors == 0) $display("PASS: %0d checks, %0d mismatches", checks, errors);
    else $fatal(1, "FAIL: %0d mismatches, %0d checks", errors, checks);
    $finish;
  endtask  // Automatic

  task automatic do_reset();
    drive('0);
    #1;
  endtask  // Automatic

  initial begin
    $dumpfile("hazard_unit_tb.vcd");
    $dumpvars(0, hazard_unit_tb);
    do_reset();

    test_int_regs();
    test_fp_regs();
    zero_sweep(20000);
    random_sweep(80000);

    do_verdict();
  end

  // Golden reference
  function automatic logic busy_ref(input logic [RegAddrW-1:0] r);
    return fp_busy[r] || (frd_write_ex && rd_ex == r) || (frd_write_mem && rd_mem == r);
  endfunction

  function automatic logic stall_ref();
    logic load_use;
    logic fp_wait;
    load_use = result_src_ex == ResMem && reg_write_ex && rd_ex != 0 &&
        (rd_ex == rs1_id || rd_ex == rs2_id);
    fp_wait = (frs1_read_id && busy_ref(rs1_id)) || (frs2_read_id && busy_ref(rs2_id)) ||
        (frs3_read_id && busy_ref(rs3_id)) || (frd_write_id && busy_ref(rd_id)) || frm_write_ex;
    return load_use || (fp_op_id && fp_wait);
  endfunction

  function automatic logic [FwdW-1:0] fwd_ref(input logic [RegAddrW-1:0] rs);
    if (reg_write_mem && rd_mem != 0 && rd_mem == rs) return FwdMem;
    if (reg_write_wb && rd_wb != 0 && rd_wb == rs) return FwdWb;
    return FwdNone;
  endfunction

endmodule

`default_nettype wire
