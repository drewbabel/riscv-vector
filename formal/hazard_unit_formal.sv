`default_nettype none

module hazard_unit_formal ();

  localparam int XLEN = arch_pkg::XLEN;

  localparam logic [1:0] FwdNone = 2'b00;
  localparam logic [1:0] FwdMem = 2'b01;
  localparam logic [1:0] FwdWb = 2'b10;
  localparam logic [1:0] ResMem = 2'd1;

  logic       clk;
  logic       core_en;
  logic       rst_n;
  logic [4:0] rs1_id;
  logic [4:0] rs2_id;
  logic [4:0] rs1_ex;
  logic [4:0] rs2_ex;
  logic [4:0] rd_id;
  logic [4:0] rd_ex;
  logic [4:0] rd_mem;
  logic [4:0] rd_wb;
  logic       reg_write_mem;
  logic       reg_write_wb;
  logic       mem_write_ex;
  logic [1:0] result_src_ex;
  logic [1:0] result_src_mem;
  logic [1:0] result_src_wb;
  logic       stall;
  logic [1:0] forward_a;
  logic [1:0] forward_b;

  localparam int FpRegs = arch_pkg::NumRegs;

  logic              fp_op_id;
  logic              frs1_read_id;
  logic              frs2_read_id;
  logic              frs3_read_id;
  logic              frd_write_id;
  logic [       4:0] rs3_id;
  logic [FpRegs-1:0] fp_busy;
  logic              frd_write_ex;
  logic              frm_write_ex;
  logic              load_use;
  logic              fp_dep;

  hazard_unit #(
      .XLEN(XLEN)
  ) dut (
      .clk           (clk),
      .core_en       (core_en),
      .rst_n         (rst_n),
      .rs1_id        (rs1_id),
      .rs2_id        (rs2_id),
      .rs1_ex        (rs1_ex),
      .rs2_ex        (rs2_ex),
      .rd_id         (rd_id),
      .rd_ex         (rd_ex),
      .rd_mem        (rd_mem),
      .rd_wb         (rd_wb),
      .reg_write_mem (reg_write_mem),
      .reg_write_wb  (reg_write_wb),
      .mem_write_ex  (mem_write_ex),
      .result_src_ex (result_src_ex),
      .result_src_mem(result_src_mem),
      .result_src_wb (result_src_wb),
      .fp_op_id      (fp_op_id),
      .frs1_read_id  (frs1_read_id),
      .frs2_read_id  (frs2_read_id),
      .frs3_read_id  (frs3_read_id),
      .frd_write_id  (frd_write_id),
      .rs3_id        (rs3_id),
      .fp_busy       (fp_busy),
      .frd_write_ex  (frd_write_ex),
      .frm_write_ex  (frm_write_ex),
      .stall         (stall),
      .forward_a     (forward_a),
      .forward_b     (forward_b)
  );

  always @(posedge clk) begin
    assert (forward_a !== 2'b11);
    assert (forward_b !== 2'b11);

    // MEM firing and priority
    if (reg_write_mem && (rd_mem != 0) && (rd_mem == rs1_ex)) begin
      assert (forward_a == FwdMem);
    end else if (reg_write_wb && (rd_wb != 0) && (rd_wb == rs1_ex)) begin
      assert (forward_a == FwdWb);
    end else begin
      assert (forward_a == FwdNone);
    end

    // x0 never forwarded
    if (rd_mem == 0) assert ((forward_a !== FwdMem) && (forward_b !== FwdMem));

    // Stall-only for load-use hazard
    if (stall && !fp_op_id) assert (result_src_ex == ResMem);

    // Correct stall firing
    if (load_use || fp_dep) begin
      assert (stall);
    end else begin
      assert (!stall);
    end
  end

  assign load_use = (result_src_ex == ResMem) && (rd_ex != 0) &&
      ((rd_ex == rs1_id) || (rd_ex == rs2_id));

  always_comb begin
    fp_dep = frm_write_ex;
    if (frs1_read_id && (fp_busy[rs1_id] || (frd_write_ex && (rd_ex == rs1_id)))) fp_dep = 1'b1;
    if (frs2_read_id && (fp_busy[rs2_id] || (frd_write_ex && (rd_ex == rs2_id)))) fp_dep = 1'b1;
    if (frs3_read_id && (fp_busy[rs3_id] || (frd_write_ex && (rd_ex == rs3_id)))) fp_dep = 1'b1;
    if (frd_write_id && (fp_busy[rd_id] || (frd_write_ex && (rd_ex == rd_id)))) fp_dep = 1'b1;
    fp_dep = fp_dep && fp_op_id;
  end

endmodule

`default_nettype wire
