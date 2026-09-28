`default_nettype none

module vec_issue
  import vec_pkg::*;
#(
    parameter int AWIDTH = 5
) (
    input wire clk,
    input wire rst_n,
    input wire core_en,

    // Execute stage
    input wire                        instr_valid,
    input wire                        cancel,
    input wire vec_op_e               op,
    input wire vec_src_e              src,
    input wire vec_eew_e              eew,
    input wire                        writes_xreg,
    input wire           [AWIDTH-1:0] vs1,
    input wire           [AWIDTH-1:0] vs2,
    input wire           [AWIDTH-1:0] vd,
    input wire                        vm,
    input wire                        reads_vd,
    input wire           [       4:0] simm,
    input wire           [      31:0] xdata,
    input wire           [      31:0] xstride,

    // Register groups
    input wire [  AWIDTH:0] wr_regs,
    input wire [AWIDTH-1:0] rd1,
    input wire [  AWIDTH:0] rd1_regs,
    input wire [  AWIDTH:0] rd2_regs,

    // Write finished
    input wire              clear,
    input wire [AWIDTH-1:0] clear_addr,

    // Live configuration
    input wire [7:0] vl,
    input wire [2:0] vsew,
    input wire [2:0] vlmul,
    input wire [1:0] vxrm,

    // Sequencer status
    input wire seq_busy,
    input wire seq_done,

    // Sequencer command
    output logic                  seq_start,
    output vec_op_e               seq_op,
    output vec_src_e              seq_src,
    output vec_eew_e              seq_eew,
    output logic     [AWIDTH-1:0] seq_vs1,
    output logic     [AWIDTH-1:0] seq_vs2,
    output logic     [AWIDTH-1:0] seq_vd,
    output logic                  seq_vm,
    output logic                  seq_reads_vd,
    output logic     [       4:0] seq_simm,
    output logic     [      31:0] seq_xdata,
    output logic     [      31:0] seq_xstride,
    output logic     [       7:0] seq_vl,
    output logic     [       2:0] seq_vsew,
    output logic     [       2:0] seq_vlmul,
    output logic     [       1:0] seq_vxrm,

    // Pipeline handshake
    output logic vec_hold,
    output logic vec_idle,
    output logic load_pending,
    output logic store_pending
);

  // Queue slot
  logic                  q_valid;
  vec_op_e               q_op;
  vec_src_e              q_src;
  vec_eew_e              q_eew;
  logic                  q_xreg;
  logic     [AWIDTH-1:0] q_vs1;
  logic     [AWIDTH-1:0] q_vs2;
  logic     [AWIDTH-1:0] q_vd;
  logic                  q_vm;
  logic                  q_reads_vd;
  logic     [       4:0] q_simm;
  logic     [      31:0] q_xdata;
  logic     [      31:0] q_xstride;
  logic     [       7:0] q_vl;
  logic     [       2:0] q_vsew;
  logic     [       2:0] q_vlmul;
  logic     [       1:0] q_vxrm;
  logic     [  AWIDTH:0] q_wr_regs;
  logic     [AWIDTH-1:0] q_rd1;
  logic     [  AWIDTH:0] q_rd1_regs;
  logic     [  AWIDTH:0] q_rd2_regs;

  // Executing slot
  logic                  e_valid;
  logic                  e_load;
  logic                  e_store;
  logic                  e_xreg;

  logic                  accept;
  logic                  launch;
  logic                  x_wait;
  logic                  x_spent;
  logic                  x_hold;
  logic                  regs_ready;

  vec_busy_bits #(
      .NREGS(1 << AWIDTH)
  ) u_busy (
      .clk(clk),
      .rst_n(rst_n),
      .core_en(core_en),
      .start(launch),
      .vd(q_vd),
      .vd_regs(q_wr_regs),
      .vs1(q_rd1),
      .vs1_regs(q_rd1_regs),
      .vs2(q_vs2),
      .vs2_regs(q_rd2_regs),
      .masked(!q_vm),
      .clear(clear),
      .clear_addr(clear_addr),
      .ready(regs_ready)
  );

  assign launch = q_valid && !e_valid && regs_ready;
  assign x_wait = (q_valid && q_xreg) || (e_valid && e_xreg);
  assign accept = instr_valid && !cancel && !x_wait && !x_spent && (!q_valid || launch);
  assign x_hold = instr_valid && (x_wait || writes_xreg) && !x_spent;
  assign vec_hold = x_hold || (instr_valid && q_valid && !launch);
  assign vec_idle = !q_valid && !e_valid && !seq_busy;

  // Pending memory work
  assign load_pending = (q_valid && q_op == VEC_LOAD) || (e_valid && e_load);
  assign store_pending = (q_valid && q_op == VEC_STORE) || (e_valid && e_store);

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      q_valid   <= 1'b0;
      e_valid   <= 1'b0;
      seq_start <= 1'b0;
      x_spent   <= 1'b0;
    end else if (core_en) begin
      seq_start <= 1'b0;
      x_spent   <= seq_done && e_valid && e_xreg;

      // Drain the slot
      if (launch) begin
        seq_start    <= 1'b1;
        e_valid      <= 1'b1;
        e_load       <= (q_op == VEC_LOAD);
        e_store      <= (q_op == VEC_STORE);
        e_xreg       <= q_xreg;
        seq_op       <= q_op;
        seq_src      <= q_src;
        seq_eew      <= q_eew;
        seq_vs1      <= q_vs1;
        seq_vs2      <= q_vs2;
        seq_vd       <= q_vd;
        seq_vm       <= q_vm;
        seq_reads_vd <= q_reads_vd;
        seq_simm     <= q_simm;
        seq_xdata    <= q_xdata;
        seq_xstride  <= q_xstride;
        seq_vl       <= q_vl;
        seq_vsew     <= q_vsew;
        seq_vlmul    <= q_vlmul;
        seq_vxrm     <= q_vxrm;
        q_valid      <= 1'b0;
      end

      // Snapshot on entry
      if (accept) begin
        q_valid    <= 1'b1;
        q_op       <= op;
        q_src      <= src;
        q_eew      <= eew;
        q_xreg     <= writes_xreg;
        q_vs1      <= vs1;
        q_vs2      <= vs2;
        q_vd       <= vd;
        q_vm       <= vm;
        q_reads_vd <= reads_vd;
        q_simm     <= simm;
        q_xdata    <= xdata;
        q_xstride  <= xstride;
        q_vl       <= vl;
        q_vsew     <= vsew;
        q_vlmul    <= vlmul;
        q_vxrm     <= vxrm;
        q_wr_regs  <= wr_regs;
        q_rd1      <= rd1;
        q_rd1_regs <= rd1_regs;
        q_rd2_regs <= rd2_regs;
      end

      // Retire instruction
      if (seq_done) e_valid <= 1'b0;
    end
  end

endmodule

`default_nettype wire
