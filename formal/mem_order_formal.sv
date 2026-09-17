`default_nettype none

module mem_order_formal ();

  localparam int Xlen = 32;

  logic clk;

  // Free core inputs
  (* anyseq *)logic [Xlen-1:0] instr;
  (* anyseq *)logic [Xlen-1:0] read_data;
  (* anyseq *)logic            imem_ready;
  (* anyseq *)logic            dmem_ready;

  logic            dmem_req;
  logic [Xlen-1:0] pc;
  logic            mem_write;
  logic [Xlen-1:0] alu_result;
  logic [Xlen-1:0] write_data;
  logic [     3:0] store_wstrb;
  logic [Xlen-1:0] store_data;
  logic [Xlen-1:0] mem_addr;

  logic            ex_commit;
  logic [Xlen-1:0] ex_insn;
  logic            s_take;
  logic            v_take;
  logic            v_retire;

  logic            rst_n;
  logic [     1:0] t = 2'd0;
  logic            f_past_valid = 1'b0;

  initial assume (t == 2'd0);
  always @(posedge clk) begin
    t <= (t == 2'd3) ? 2'd3 : t + 2'd1;
    f_past_valid <= 1'b1;
  end
  assign rst_n = (t != 2'd0);

  riscv_pipelined #(
      .XLEN(Xlen)
  ) dut (
      .dbg_valid(),
      .dbg_insn(),
      .dbg_pc_rdata(),
      .dbg_pc_wdata(),
      .dbg_rs1_rdata(),
      .dbg_rs2_rdata(),
      .dbg_rd_wdata(),
      .dbg_reg_write(),
      .dbg_mem_addr(),
      .dbg_mem_wmask(),
      .dbg_mem_wdata(),
      .dbg_mem_rdata(),
      .dbg_trap(),
      .dbg_csr_wdata(),
      .dbg_mscratch(),
      .dbg_mstatus(),
      .dbg_mtvec(),
      .dbg_mepc(),
      .dbg_mcause(),
      .dbg_mtval(),
      .dbg_mie(),
      .dbg_mip(),
      .dbg_mcycle(),
      .dbg_minstret(),
      .dbg_mcycleh(),
      .dbg_minstreth(),
      .dbg_vl(),
      .dbg_vtype_bits(),
      .dbg_vtype_ill(),
      .dbg_vstart(),
      .dbg_vec_tag(),
      .dbg_vec_retire(v_retire),
      .dbg_vec_vd(),
      .dbg_vec_regs(),
      .dbg_vec_idle(),
      .dbg_ex_commit(ex_commit),
      .dbg_ex_insn(ex_insn),
      .dbg_s_take(s_take),
      .dbg_v_take(v_take),
      .clk(clk),
      .core_en(1'b1),
      .rst_n(rst_n),
      .instr(instr),
      .read_data(read_data),
      .timer_irq(1'b0),
      .ext_irq(1'b0),
      .imem_ready(imem_ready),
      .dmem_ready(dmem_ready),
      .dmem_req(dmem_req),
      .pc(pc),
      .mem_write(mem_write),
      .alu_result(alu_result),
      .write_data(write_data),
      .store_wstrb(store_wstrb),
      .store_data(store_data),
      .mem_addr(mem_addr)
  );

  // Program contract
  logic is_lw, is_sw, is_vle, is_vse, is_vset, is_addi, is_fence, is_csrs;

  assign is_lw = (instr[6:0] == 7'b0000011) && (instr[14:12] == 3'b010)
      && (instr[19:15] == 5'd0) && (instr[21:20] == 2'b00);
  assign is_sw = (instr[6:0] == 7'b0100011) && (instr[14:12] == 3'b010)
      && (instr[19:15] == 5'd0) && (instr[8:7] == 2'b00);
  assign is_vle = (instr[6:0] == 7'b0000111) && (instr[31:26] == 6'd0)
      && (instr[24:12] == 13'd0) && (instr[25] || instr[11:7] != 5'd0);
  assign is_vse = (instr[6:0] == 7'b0100111) && (instr[31:26] == 6'd0)
      && (instr[24:12] == 13'd0);
  assign is_vset = (instr[6:0] == 7'b1010111) && (instr[31:20] == 12'd0)
      && (instr[14:12] == 3'b111) && (instr[19:15] == 5'd1);
  assign is_addi = (instr[6:0] == 7'b0010011) && (instr[14:12] == 3'b000)
      && (instr[19:15] == 5'd0) && (instr[11:7] == 5'd1) && (instr[31:23] == 9'd0);
  assign is_fence = (instr == 32'h0000_000F);
  assign is_csrs = (instr == 32'h3000_A073);

  always @(posedge clk) begin
    assume (is_lw || is_sw || is_vle || is_vse || is_vset || is_addi || is_fence || is_csrs);
  end

  // Memory contract
  logic [2:0] imem_stall = 3'd0;
  logic [2:0] dmem_stall = 3'd0;

  always @(posedge clk) begin
    if (!rst_n || imem_ready) imem_stall <= 3'd0;
    else imem_stall <= imem_stall + 3'd1;
    if (!rst_n || dmem_ready || !dmem_req) dmem_stall <= 3'd0;
    else dmem_stall <= dmem_stall + 3'd1;
  end

  always @(posedge clk) begin
    assume (imem_stall < 3'd3);
    assume (dmem_stall < 3'd3);
  end

  // Commit order model
  logic [7:0] seq;
  logic       ex_sload;
  logic       ex_sstore;
  logic       ex_vload;
  logic       ex_vstore;
  logic       ex_fence;

  logic       s_pend;
  logic [7:0] s_seq;
  logic       s_store;

  logic [7:0] v_seq       [2];
  logic       v_store     [2];
  logic [1:0] v_cnt;

  assign ex_sload  = ex_commit && (ex_insn[6:0] == 7'b0000011);
  assign ex_sstore = ex_commit && (ex_insn[6:0] == 7'b0100011);
  assign ex_vload  = ex_commit && (ex_insn[6:0] == 7'b0000111);
  assign ex_vstore = ex_commit && (ex_insn[6:0] == 7'b0100111);
  assign ex_fence  = ex_commit && (ex_insn == 32'h0000_000F);

  always @(posedge clk) begin
    if (!rst_n) begin
      seq    <= 8'd0;
      s_pend <= 1'b0;
      v_cnt  <= 2'd0;
    end else begin
      if (ex_commit) seq <= seq + 8'd1;

      if (s_take) s_pend <= 1'b0;
      if (ex_sload || ex_sstore) begin
        s_pend  <= 1'b1;
        s_seq   <= seq;
        s_store <= ex_sstore;
      end

      if (v_retire && (ex_vload || ex_vstore)) begin
        if (v_cnt == 2'd1) begin
          v_seq[0]   <= seq;
          v_store[0] <= ex_vstore;
        end else begin
          v_seq[0]   <= v_seq[1];
          v_store[0] <= v_store[1];
          v_seq[1]   <= seq;
          v_store[1] <= ex_vstore;
        end
      end else if (v_retire) begin
        v_seq[0]   <= v_seq[1];
        v_store[0] <= v_store[1];
        v_cnt      <= v_cnt - 2'd1;
      end else if (ex_vload || ex_vstore) begin
        v_seq[v_cnt[0]]   <= seq;
        v_store[v_cnt[0]] <= ex_vstore;
        v_cnt             <= v_cnt + 2'd1;
      end
    end
  end

  // Store retire age
  logic [2:0] vs_age;
  always @(posedge clk) begin
    if (!rst_n) vs_age <= 3'd7;
    else if (v_retire && v_store[0]) vs_age <= 3'd0;
    else if (vs_age != 3'd7) vs_age <= vs_age + 3'd1;
  end

  // Model sanity
  always @(posedge clk)
    if (rst_n) begin
      assert (v_cnt <= 2'd2);
      if (v_retire) assert (v_cnt != 2'd0);
      if (ex_vload || ex_vstore) assert (v_cnt != 2'd2 || v_retire);
      if (s_take) assert (s_pend);
      if (ex_sload || ex_sstore) assert (!s_pend || s_take);
    end

  // Scalar never passes
  always @(posedge clk)
    if (rst_n && s_take) begin
      if (v_cnt >= 2'd1) assert (!(s_store || v_store[0]) || v_seq[0] > s_seq);
      if (v_cnt == 2'd2) assert (!(s_store || v_store[1]) || v_seq[1] > s_seq);
    end

  // Vector never passes
  always @(posedge clk)
    if (rst_n && v_take && s_pend && (s_store || v_store[0])) assert (v_seq[0] < s_seq);

  // Fence drains unit
  always @(posedge clk) if (rst_n && ex_fence) assert (v_cnt == 2'd0);

  // Covers
  always @(posedge clk)
    if (rst_n) begin
      cover (v_take);
      cover (s_take && !s_store && v_cnt != 2'd0 && !v_store[0]);
      cover (v_take && s_pend && !s_store && !v_store[0]);
      cover (s_take && !s_store && vs_age < 3'd6);
      cover (ex_fence && f_past_valid && $past(v_retire));
      cover (s_take && s_store && vs_age < 3'd6);
    end

endmodule

`default_nettype wire
