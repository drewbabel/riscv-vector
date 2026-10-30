#include "mamba3.h"

// Widen weight to float
static inline float wf(wt_t w) {
#if WBF16
    union {
        uint32_t u;
        float f;
    } c = {.u = (uint32_t)w << 16};
    return c.f;
#else
    return w;
#endif
}

static float dot(const float *a, const float *b, int n) {
    float acc = 0.0f;
    for (int i = 0; i < n; ++i)
        acc += a[i] * b[i];
    return acc;
}

void mv_s(const wt_t *w, const float *x, float *y, int rows, int cols) {
    for (int r = 0; r < rows; ++r) {
        const wt_t *row = w + r * cols;
        float acc = 0.0f;
        for (int c = 0; c < cols; ++c)
            acc += wf(row[c]) * x[c];
        y[r] = acc;
    }
}

void rmsnorm_s(const float *x, const float *g, float *y, int n) {
    float s = 1.0f / __builtin_sqrtf(dot(x, x, n) / n + EPS);
    for (int i = 0; i < n; ++i)
        y[i] = x[i] * s * g[i];
}

void add_s(const float *a, const float *b, float *y, int n) {
    for (int i = 0; i < n; ++i)
        y[i] = a[i] + b[i];
}

void sub_s(const float *a, const float *b, float *y, int n) {
    for (int i = 0; i < n; ++i)
        y[i] = a[i] - b[i];
}

void mul_s(const float *a, const float *b, float *y, int n) {
    for (int i = 0; i < n; ++i)
        y[i] = a[i] * b[i];
}

void scale_s(const float *a, float s, float *y, int n) {
    for (int i = 0; i < n; ++i)
        y[i] = a[i] * s;
}

void silugate_s(const float *a, const float *z, float *y, int n) {
    sigmoidv(z, y, n);
    for (int i = 0; i < n; ++i)
        y[i] = a[i] * z[i] * y[i];
}

void rotary_s(const float *t, const float *s, const float *c, float *y,
              int npair, int n) {
    for (int i = 0; i < npair; ++i) {
        float a = t[2 * i], b = t[2 * i + 1];
        y[2 * i] = a * c[i] - b * s[i];
        y[2 * i + 1] = a * s[i] + b * c[i];
    }
    for (int i = 2 * npair; i < n; ++i)
        y[i] = t[i];
}

void ssmupd_s(float *h, int rows, int n, float a, const float *cb,
              const float *kp, const float *cg, const float *kr) {
    for (int r = 0; r < rows; ++r)
        for (int i = 0; i < n; ++i)
            h[r * n + i] = a * h[r * n + i] + cb[r] * kp[i] + cg[r] * kr[i];
}

void ssmread_s(const float *h, int rows, int n, const float *q, float *y) {
    for (int r = 0; r < rows; ++r)
        y[r] = dot(h + r * n, q, n);
}
