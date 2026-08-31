`default_nettype none

module vec_config #(
    parameter int XLEN = 32,
    parameter int VLEN = 128
) (
    // Setting Request
    input  wire  [XLEN-1:0] instr,
    input  wire  [XLEN-1:0] rs1_data,
    input  wire  [XLEN-1:0] rs2_data,
    // Current setting
    input  wire  [     7:0] vl_q,
    input  wire  [XLEN-1:0] vtype_q,
    // Next setting
    output logic            is_vset,
    output logic [     7:0] vl_d,
    output logic [XLEN-1:0] vtype_d
);

  // Local until vector arithmetic unit implemented
  localparam logic [6:0] OpcodeOpV = 7'b1010111;
  localparam logic [2:0] Funct3Opcfg = 3'b111;
  // localparam logic [2:0] Vsew8 = 3'b000;
  // localparam logic [2:0] Vsew16 = 3'b001;
  localparam logic [2:0] Vsew32 = 3'b010;
  localparam logic [2:0] VlmulReserved = 3'b100;
  localparam int Elen = 32;

  logic [XLEN-1:0] vtype_arg;  // Requested setup
  logic [XLEN-1:0] avl;  // Elements left
  logic [     7:0] vlmax;  // Elements per group
  logic            vill;  // Request is nonsense
  logic            is_keep_vl;  // Keep across instrs

  function automatic logic [7:0] vlmax_of(input logic [5:0] vtype);
    return vtype[2] ? 8'((VLEN >> (3 + vtype[5:3])) >> (4 - vtype[1:0])) :
                      8'((VLEN >> (3 + vtype[5:3])) << vtype[1:0]);
  endfunction

  always_comb begin
    is_vset    = 1'b0;
    is_keep_vl = 1'b0;
    vtype_arg  = '0;
    avl        = '0;

    // Read request
    if (instr[6:0] == OpcodeOpV && instr[14:12] == Funct3Opcfg) begin
      casez (instr[31:25])
        7'b0??????: begin  // vsetvli
          is_vset   = 1'b1;
          vtype_arg = {{XLEN - 11{1'b0}}, instr[30:20]};
          if (instr[19:15] != 5'b0) avl = rs1_data;
          else if (instr[11:7] != 5'b0) avl = {XLEN{1'b1}};
          else begin
            avl = {{XLEN - 8{1'b0}}, vl_q};
            is_keep_vl = 1'b1;
          end
        end
        7'b11?????: begin  // vsetivli
          is_vset   = 1'b1;
          vtype_arg = {{XLEN - 10{1'b0}}, instr[29:20]};
          avl       = {{XLEN - 5{1'b0}}, instr[19:15]};
        end
        7'b1000000: begin  // vsetvl
          is_vset   = 1'b1;
          vtype_arg = rs2_data;
          if (instr[19:15] != 5'b0) avl = rs1_data;
          else if (instr[11:7] != 5'b0) avl = {XLEN{1'b1}};
          else begin
            avl = {{XLEN - 8{1'b0}}, vl_q};
            is_keep_vl = 1'b1;
          end
        end
        default: ;
      endcase
    end

    vlmax = vlmax_of(vtype_arg[5:0]);

    // Nonsense request
    vill = (vtype_arg[5:3] > Vsew32)  // Element too wide
    || (vtype_arg[2:0] == VlmulReserved)  // Undefined group
    || (vlmax < 8'(VLEN / Elen))  // Group underfilled
    || (vtype_arg[XLEN-2:8] != '0)  // Reserved bits set
    || (vtype_arg[XLEN-1])  // Request already poisoned
    || (is_keep_vl && (vtype_q[XLEN-1] || vlmax != vlmax_of(vtype_q[5:0])));  // Kept vl impossible

    // Answer
    if (!is_vset) begin
      vtype_d = vtype_q;
      vl_d    = vl_q;
    end else if (vill) begin
      vtype_d = {1'b1, {XLEN - 1{1'b0}}};
      vl_d    = 8'b0;
    end else begin
      vtype_d = {{XLEN - 8{1'b0}}, vtype_arg[7:0]};
      vl_d    = (avl < {{XLEN - 8{1'b0}}, vlmax}) ? avl[7:0] : vlmax;
    end
  end

endmodule

`default_nettype wire
