`default_nettype none

module vec_config_formal ();

  localparam int XLEN = 32;
  localparam int VLEN = 128;
  localparam int ELEN = 32;

  localparam logic [6:0] OpcodeOpV = 7'b1010111;
  localparam logic [2:0] Funct3Opcfg = 3'b111;
  localparam logic [2:0] Vsew32 = 3'b010;
  localparam logic [2:0] VlmulReserved = 3'b100;
  localparam logic [31:0] Poison = 32'h8000_0000;

  logic            clk;
  logic [XLEN-1:0] instr;
  logic [XLEN-1:0] rs1_data;
  logic [XLEN-1:0] rs2_data;
  logic [     7:0] vl_q;
  logic [XLEN-1:0] vtype_q;
  logic            is_vset;
  logic [     7:0] vl_d;
  logic [XLEN-1:0] vtype_d;

  vec_config #(
      .XLEN(XLEN),
      .VLEN(VLEN)
  ) dut (
      .instr   (instr),
      .rs1_data(rs1_data),
      .rs2_data(rs2_data),
      .vl_q    (vl_q),
      .vtype_q (vtype_q),
      .is_vset (is_vset),
      .vl_d    (vl_d),
      .vtype_d (vtype_d)
  );

  function automatic logic is_opcfg(input logic [31:0] i);
    return i[6:0] == OpcodeOpV && i[14:12] == Funct3Opcfg;
  endfunction

  function automatic logic is_vsetvli(input logic [31:0] i);
    return is_opcfg(i) && i[31] == 1'b0;
  endfunction

  function automatic logic is_vsetivli(input logic [31:0] i);
    return is_opcfg(i) && i[31:30] == 2'b11;
  endfunction

  function automatic logic is_vsetvl(input logic [31:0] i);
    return is_opcfg(i) && i[31:25] == 7'b1000000;
  endfunction

  function automatic logic is_cfg(input logic [31:0] i);
    return is_vsetvli(i) || is_vsetivli(i) || is_vsetvl(i);
  endfunction

  function automatic logic is_keep(input logic [31:0] i);
    return (is_vsetvli(i) || is_vsetvl(i)) && i[19:15] == 5'b0 && i[11:7] == 5'b0;
  endfunction

  function automatic logic [31:0] req_vtype(input logic [31:0] i, input logic [31:0] r2);
    if (is_vsetvli(i)) return {21'b0, i[30:20]};
    else if (is_vsetivli(i)) return {22'b0, i[29:20]};
    else return r2;
  endfunction

  function automatic logic [31:0] req_avl(input logic [31:0] i, input logic [31:0] r1,
                                          input logic [7:0] vlq);
    if (is_vsetivli(i)) return {27'b0, i[19:15]};
    else if (i[19:15] != 5'b0) return r1;
    else if (i[11:7] != 5'b0) return 32'hFFFF_FFFF;
    else return {24'b0, vlq};
  endfunction

  function automatic int sew_of(input logic [31:0] vt);
    return 8 << vt[5:3];
  endfunction

  function automatic int lmul_num(input logic [31:0] vt);
    case (vt[2:0])
      3'b001:  return 2;
      3'b010:  return 4;
      3'b011:  return 8;
      default: return 1;
    endcase
  endfunction

  function automatic int lmul_den(input logic [31:0] vt);
    case (vt[2:0])
      3'b101:  return 8;
      3'b110:  return 4;
      3'b111:  return 2;
      default: return 1;
    endcase
  endfunction

  function automatic int vmax_of(input logic [31:0] vt);
    return (lmul_num(vt) * VLEN) / (lmul_den(vt) * sew_of(vt));
  endfunction

  function automatic logic ratio_bad(input logic [31:0] vt);
    return (sew_of(vt) * lmul_den(vt)) / lmul_num(vt) > ELEN;
  endfunction

  function automatic logic req_bad(input logic [31:0] i, input logic [31:0] r2,
                                   input logic [31:0] vtq);
    logic [31:0] vt;
    logic        b;
    vt = req_vtype(i, r2);
    b = (vt[5:3] > Vsew32) || (vt[2:0] == VlmulReserved) || ratio_bad(vt) || (vt[30:8] != '0) ||
        vt[31];
    if (is_keep(i)) b = b || vtq[31] || (vmax_of(vt) != vmax_of(vtq));
    return b;
  endfunction

  logic [31:0] want_vtype;  // Requested setup
  logic [31:0] want_avl;  // Elements requested
  int          want_vmax;  // Elements per group

  assign want_vtype = req_vtype(instr, rs2_data);
  assign want_avl   = req_avl(instr, rs1_data, vl_q);
  assign want_vmax  = vmax_of(want_vtype);

  always @(posedge clk) begin
    assert (is_vset == is_cfg(instr));

    // Reachable current setup
    assume (vtype_q == Poison || (vtype_q[31:8] == '0 && vtype_q[5:3] <= Vsew32 &&
                                  vtype_q[2:0] != VlmulReserved && !ratio_bad(
        vtype_q
    )));

    if (!is_vset) begin
      assert (vl_d == vl_q);
      assert (vtype_d == vtype_q);
    end

    // Answer domain
    if (is_vset) begin
      assert (vtype_d == Poison || vtype_d[31:8] == '0);
      assert (vl_d <= 8'd128);
      assert ((vtype_d == Poison) == req_bad(instr, rs2_data, vtype_q));
    end

    if (is_vset && vtype_d == Poison) begin
      assert (vl_d == 8'b0);
    end

    // Legal answer
    if (is_vset && vtype_d != Poison) begin
      assert (vtype_d == {24'b0, want_vtype[7:0]});
      assert (32'(vl_d) <= want_vmax);
      assert (32'(vl_d) * sew_of(want_vtype) * lmul_den(want_vtype) <= lmul_num(want_vtype) * VLEN);
      if (want_avl >= 32'(want_vmax)) begin
        assert (32'(vl_d) == want_vmax);
      end else begin
        assert (32'(vl_d) == want_avl);
      end
    end

    // Reachability
    cover (!is_vset);
    cover (is_vsetvli(instr));
    cover (is_vsetivli(instr));
    cover (is_vsetvl(instr));
    cover (is_opcfg(instr) && !is_cfg(instr));
    cover (is_vset && vtype_d == Poison);
    cover (is_vset && vtype_d != Poison);
    cover (is_keep(instr) && vtype_q[31]);
    cover (is_keep(instr) && !vtype_q[31] && vtype_d == Poison);
    cover (is_keep(instr) && vtype_d != Poison);
    cover (is_vset && vtype_d != Poison && vl_d == 8'd0);
    cover (is_vset && vtype_d != Poison && vl_d == 8'd128);
    cover (is_vset && vtype_d != Poison && 32'(vl_d) == want_avl);
    cover (is_vset && vtype_d != Poison && 32'(vl_d) < want_avl);
    cover (is_vsetvli(instr) && instr[19:15] == 5'b0 && instr[11:7] != 5'b0);
  end

endmodule

`default_nettype wire
