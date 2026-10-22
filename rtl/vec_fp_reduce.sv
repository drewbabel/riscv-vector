`default_nettype none

module vec_fp_reduce
  import vec_pkg::*;
  import fp_pkg::Funct5Fminmax, fp_pkg::Funct3Fmin, fp_pkg::Funct3Fmax;
#(
    parameter  int DLEN   = arch_pkg::VLEN,
    localparam int FpW    = 32,
    localparam int Elems  = DLEN / FpW,
    localparam int Levels = $clog2(Elems),
    localparam int Cut    = Levels / 2,
    localparam int Half   = Elems >> Cut
) (
    input wire clk,
    input wire rst_n,
    input wire core_en,

    input wire vec_fop_e             op,
    input wire                       first,
    input wire                       step,
    input wire           [ DLEN-1:0] vs2_data,
    input wire           [ DLEN-1:0] vs1_data,
    input wire           [Elems-1:0] elem_active,

    output logic [DLEN-1:0] result,
    output logic [     4:0] fflags
);

  if ((Elems < 2) || (Elems != (1 << Levels))) begin : g_elems
    $error("DLEN must hold a power of two float elements, at least two");
  end

  function automatic logic [2:0] pick(input vec_fop_e kind);
    pick = (kind == VEC_FMAX) ? Funct3Fmax : Funct3Fmin;
  endfunction

  logic [FpW-1:0] lo_val [2*Elems];
  logic           lo_live[2*Elems];
  logic [    4:0] lo_flag[2*Elems];

  for (genvar n = 0; n < Half; n++) begin : g_lo_unused
    assign lo_val[n]  = '0;
    assign lo_live[n] = 1'b0;
    assign lo_flag[n] = '0;
  end

  for (genvar e = 0; e < Elems; e++) begin : g_leaf
    assign lo_val[Elems+e]  = vs2_data[e*FpW+:FpW];
    assign lo_live[Elems+e] = elem_active[e];
    assign lo_flag[Elems+e] = '0;
  end

  // Lower tree
  for (genvar n = Half; n < Elems; n++) begin : g_lo
    logic [FpW-1:0] cmp_res;
    logic [    4:0] cmp_flags;
    logic           both;

    fp_misc #(
        .ExpW (8),
        .FracW(23)
    ) u_cmp (
        .funct5(Funct5Fminmax),
        .funct3(pick(op)),
        .a(lo_val[2*n]),
        .b(lo_val[2*n+1]),
        .result(cmp_res),
        .fflags(cmp_flags)
    );

    // Dead side copies
    assign both = lo_live[2*n] && lo_live[2*n+1];
    assign lo_val[n] = both ? cmp_res : (lo_live[2*n] ? lo_val[2*n] : lo_val[2*n+1]);
    assign lo_live[n] = lo_live[2*n] || lo_live[2*n+1];
    assign lo_flag[n] = lo_flag[2*n] | lo_flag[2*n+1] | (both ? cmp_flags : '0);
  end

  // Mid tree cut
  logic     [FpW-1:0] cut_val_q [Half];
  logic               cut_live_q[Half];
  logic     [    4:0] cut_flag_q[Half];
  logic     [FpW-1:0] seed_q;
  vec_fop_e           op_q;
  logic               first_q;
  logic               step_q;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      step_q <= 1'b0;
    end else if (core_en) begin
      for (int n = 0; n < Half; n++) begin
        cut_val_q[n]  <= lo_val[Half+n];
        cut_live_q[n] <= lo_live[Half+n];
        cut_flag_q[n] <= lo_flag[Half+n];
      end
      seed_q  <= vs1_data[FpW-1:0];
      op_q    <= op;
      first_q <= first;
      step_q  <= step;
    end
  end

  logic [FpW-1:0] hi_val [2*Half];
  logic           hi_live[2*Half];
  logic [    4:0] hi_flag[2*Half];

  assign hi_val[0]  = '0;
  assign hi_live[0] = 1'b0;
  assign hi_flag[0] = '0;

  for (genvar n = 0; n < Half; n++) begin : g_cut
    assign hi_val[Half+n]  = cut_val_q[n];
    assign hi_live[Half+n] = cut_live_q[n];
    assign hi_flag[Half+n] = cut_flag_q[n];
  end

  // Upper tree
  for (genvar n = 1; n < Half; n++) begin : g_hi
    logic [FpW-1:0] cmp_res;
    logic [    4:0] cmp_flags;
    logic           both;

    fp_misc #(
        .ExpW (8),
        .FracW(23)
    ) u_cmp (
        .funct5(Funct5Fminmax),
        .funct3(pick(op_q)),
        .a(hi_val[2*n]),
        .b(hi_val[2*n+1]),
        .result(cmp_res),
        .fflags(cmp_flags)
    );

    assign both = hi_live[2*n] && hi_live[2*n+1];
    assign hi_val[n] = both ? cmp_res : (hi_live[2*n] ? hi_val[2*n] : hi_val[2*n+1]);
    assign hi_live[n] = hi_live[2*n] || hi_live[2*n+1];
    assign hi_flag[n] = hi_flag[2*n] | hi_flag[2*n+1] | (both ? cmp_flags : '0);
  end

  // Carried accumulator
  logic [FpW-1:0] acc_q;
  logic [FpW-1:0] base;
  logic [FpW-1:0] acc_res;
  logic [    4:0] acc_flags;
  logic [FpW-1:0] acc_next;

  assign base = first_q ? seed_q : acc_q;

  fp_misc #(
      .ExpW (8),
      .FracW(23)
  ) u_acc (
      .funct5(Funct5Fminmax),
      .funct3(pick(op_q)),
      .a(base),
      .b(hi_val[1]),
      .result(acc_res),
      .fflags(acc_flags)
  );

  // Scalar kept alone
  assign acc_next = hi_live[1] ? acc_res : base;

  always_ff @(posedge clk) begin
    if (!rst_n) acc_q <= '0;
    else if (core_en && step_q) acc_q <= acc_next;
  end

  assign result = DLEN'(acc_next);
  assign fflags = (step_q && hi_live[1]) ? (hi_flag[1] | acc_flags) : '0;

endmodule

`default_nettype wire
