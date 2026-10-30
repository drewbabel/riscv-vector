#include <riscv_vector.h>
#include <stddef.h>

#include "mamba3.h"

typedef vfloat32m4_t V;
typedef vuint32m4_t U;
#define SETVL(n) __riscv_vsetvl_e32m4(n)
#define VLMAX __riscv_vsetvlmax_e32m4()
#define LD(p) __riscv_vle32_v_f32m4(p, vl)
#define ST(p, v) __riscv_vse32_v_f32m4(p, v, vl)
// Every other float
#define LDS(p) __riscv_vlse32_v_f32m4(p, 8, vl)
#define STS(p, v) __riscv_vsse32_v_f32m4(p, 8, v, vl)
#define MUL(a, b) __riscv_vfmul_vv_f32m4(a, b, vl)
#define MAC(acc, a, b) __riscv_vfmacc_vv_f32m4_tu(acc, a, b, vl)
#define AS_F(u) __riscv_vreinterpret_v_u32m4_f32m4(u)
// Strip mining loop
#define FOR(n)                                                                 \
    for (size_t i = 0, vl; i < (size_t)(n); i += vl)                           \
        if ((vl = SETVL((n) - i)), 1)

static float sum(V acc) {
    vfloat32m1_t z = __riscv_vfmv_s_f_f32m1(0.0f, 1);
    return __riscv_vfmv_f_s_f32m1_f32(
        __riscv_vfredusum_vs_f32m4_f32m1(acc, z, VLMAX));
}

static V zero(void) { return __riscv_vfmv_v_f_f32m4(0.0f, VLMAX); }

static float dot(const float *a, const float *b, int n) {
    V acc = zero();
    FOR(n) acc = MAC(acc, LD(a + i), LD(b + i));
    return sum(acc);
}

void mv_v(const wt_t *w, const float *x, float *y, int rows, int cols) {
#if WBF16
    // Packed bf16 pairs
    int h = cols / 2;
    float *xe = tmp, *xo = tmp + h;
    FOR(h) {
        ST(xe + i, LDS(x + 2 * i));
        ST(xo + i, LDS(x + 2 * i + 1));
    }
    for (int r = 0; r < rows; ++r) {
        const uint32_t *row = (const uint32_t *)(w + r * cols);
        V acc = zero();
        FOR(h) {
            U p = __riscv_vle32_v_u32m4(row + i, vl);
            acc = MAC(acc, AS_F(__riscv_vsll_vx_u32m4(p, 16, vl)), LD(xe + i));
            acc = MAC(acc, AS_F(__riscv_vand_vx_u32m4(p, 0xFFFF0000u, vl)),
                      LD(xo + i));
        }
        y[r] = sum(acc);
    }
#else
    for (int r = 0; r < rows; ++r)
        y[r] = dot(w + r * cols, x, cols);
#endif
}

void rmsnorm_v(const float *x, const float *g, float *y, int n) {
    float s = 1.0f / __builtin_sqrtf(dot(x, x, n) / n + EPS);
    FOR(n) ST(y + i, MUL(__riscv_vfmul_vf_f32m4(LD(x + i), s, vl), LD(g + i)));
}

void add_v(const float *a, const float *b, float *y, int n) {
    FOR(n) ST(y + i, __riscv_vfadd_vv_f32m4(LD(a + i), LD(b + i), vl));
}

void sub_v(const float *a, const float *b, float *y, int n) {
    FOR(n) ST(y + i, __riscv_vfsub_vv_f32m4(LD(a + i), LD(b + i), vl));
}

void mul_v(const float *a, const float *b, float *y, int n) {
    FOR(n) ST(y + i, MUL(LD(a + i), LD(b + i)));
}

void scale_v(const float *a, float s, float *y, int n) {
    FOR(n) ST(y + i, __riscv_vfmul_vf_f32m4(LD(a + i), s, vl));
}

void silugate_v(const float *a, const float *z, float *y, int n) {
    sigmoidv(z, y, n);
    FOR(n) ST(y + i, MUL(MUL(LD(a + i), LD(z + i)), LD(y + i)));
}

void rotary_v(const float *t, const float *s, const float *c, float *y,
              int npair, int n) {
    FOR(npair) {
        V a = LDS(t + 2 * i), b = LDS(t + 2 * i + 1), cv = LD(c + i),
          sv = LD(s + i);
        STS(y + 2 * i, __riscv_vfnmsac_vv_f32m4(MUL(a, cv), b, sv, vl));
        STS(y + 2 * i + 1, __riscv_vfmacc_vv_f32m4(MUL(a, sv), b, cv, vl));
    }
    int k = 2 * npair;
    FOR(n - k) ST(y + k + i, LD(t + k + i));
}

void ssmupd_v(float *h, int rows, int n, float a, const float *cb,
              const float *kp, const float *cg, const float *kr) {
    for (int r = 0; r < rows; ++r) {
        float *hr = h + r * n;
        FOR(n) {
            V v = __riscv_vfmul_vf_f32m4(LD(hr + i), a, vl);
            v = __riscv_vfmacc_vf_f32m4(v, cb[r], LD(kp + i), vl);
            ST(hr + i, __riscv_vfmacc_vf_f32m4(v, cg[r], LD(kr + i), vl));
        }
    }
}

void ssmread_v(const float *h, int rows, int n, const float *q, float *y) {
    for (int r = 0; r < rows; ++r)
        y[r] = dot(h + r * n, q, n);
}
