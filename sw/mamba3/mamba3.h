#ifndef MAMBA3_H
#define MAMBA3_H

#include <stdint.h>

#include "../../build/mamba3/model.h"

#if WBF16
typedef uint16_t wt_t;
#else
typedef float wt_t;
#endif

// Scratch buffer length
#define XN (DM > DI ? (DM > DF ? DM : DF) : (DI > DF ? DI : DF))

extern const wt_t W_in[], W_out[], W_f1[], W_f2[];
extern const float T_norm[], T_norm2[], T_bnorm[], T_cnorm[], T_d[], T_dtb[],
    T_bb[], T_cb[];
extern const float I_r[], I_h[], I_kp[], I_vp[], I_ang[];

extern float u[DM], zx[NZX], dt[NH], A[NH], adt[NH], alpha[NH], lam[NH],
    beta[NH], gam[NH];
extern float bn[NS], cn[NS], kb[NH * NS], qb[NH * NS], th[NA], ang[NH * NA],
    sn[NH * NA], cs[NH * NA];
extern float kr[NH * NS], qr[NH * NS], kp[NH * NS], vp[DI], cb[DI], cg[DI],
    H[NH * P * NS];
extern float yp[DI], y[DI], out[DM], r1[DM], u2[DM], f[2 * DF], g[DF], m[DM],
    ro[DM], tmp[XN];

#define STEPS(X)                                                               \
    X(norm)                                                                    \
    X(inproj)                                                                  \
    X(dta)                                                                     \
    X(bcnorm)                                                                  \
    X(rotary)                                                                  \
    X(state)                                                                   \
    X(readout)                                                                 \
    X(gate)                                                                    \
    X(outproj)                                                                 \
    X(norm2)                                                                   \
    X(fc1)                                                                     \
    X(glu)                                                                     \
    X(fc2)
#define DECL(n)                                                                \
    void m3_##n##_s(void);                                                     \
    void m3_##n##_v(void);
STEPS(DECL)

#define OPS(X)                                                                 \
    void mv##X(const wt_t *w, const float *x, float *y, int rows, int cols);   \
    void rmsnorm##X(const float *x, const float *g, float *y, int n);          \
    void add##X(const float *a, const float *b, float *y, int n);              \
    void sub##X(const float *a, const float *b, float *y, int n);              \
    void mul##X(const float *a, const float *b, float *y, int n);              \
    void scale##X(const float *a, float s, float *y, int n);                   \
    void silugate##X(const float *a, const float *z, float *y, int n);         \
    void rotary##X(const float *t, const float *s, const float *c, float *y,   \
                   int npair, int n);                                          \
    void ssmupd##X(float *h, int rows, int n, float a, const float *cb,        \
                   const float *kp, const float *cg, const float *kr);         \
    void ssmread##X(const float *h, int rows, int n, const float *q, float *y);
OPS(_s)
OPS(_v)

void expv(const float *x, float *y, int n);
void sigmoidv(const float *x, float *y, int n);
void tanhv(const float *x, float *y, int n);
void softplusv(const float *x, float *y, int n);
void heavyneg(const float *x, float *y, int n, float fl);
void phase(float *a, const float *t, float d, int n);
void sincosv(const float *a, float *s, float *c, int n);

#endif
