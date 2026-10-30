#include "mamba3.h"

float u[DM], zx[NZX], dt[NH], A[NH], adt[NH], alpha[NH], lam[NH], beta[NH],
    gam[NH];
float bn[NS], cn[NS], kb[NH * NS], qb[NH * NS], th[NA], ang[NH * NA],
    sn[NH * NA], cs[NH * NA];
float kr[NH * NS], qr[NH * NS], kp[NH * NS], vp[DI], cb[DI], cg[DI],
    H[NH * P * NS];
float yp[DI], y[DI], out[DM], r1[DM], u2[DM], f[2 * DF], g[DF], m[DM], ro[DM],
    tmp[XN];

// Embed bin as symbol
#define BLOB(sym, file)                                                        \
    __asm__(".section .rodata\n.balign 16\n.globl " #sym "\n" #sym             \
            ":\n.incbin \"build/mamba3/" file "\"\n.previous");

BLOB(W_in, "w_in.bin")
BLOB(W_out, "w_out.bin")
BLOB(W_f1, "w_f1.bin")
BLOB(W_f2, "w_f2.bin")
BLOB(T_norm, "t_norm.bin")
BLOB(T_norm2, "t_norm2.bin")
BLOB(T_bnorm, "t_bnorm.bin")
BLOB(T_cnorm, "t_cnorm.bin")
BLOB(T_d, "t_d.bin")
BLOB(T_dtb, "t_dtb.bin")
BLOB(T_bb, "t_bb.bin")
BLOB(T_cb, "t_cb.bin")
BLOB(I_r, "i_r.bin")
BLOB(I_h, "i_h.bin")
BLOB(I_kp, "i_kp.bin")
BLOB(I_vp, "i_vp.bin")
BLOB(I_ang, "i_ang.bin")
