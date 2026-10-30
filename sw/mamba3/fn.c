#include <math.h>

#include "mamba3.h"

#define TWO_PI 6.28318530717958647692f

void expv(const float *x, float *y, int n) {
    for (int i = 0; i < n; ++i)
        y[i] = expf(x[i]);
}

void sigmoidv(const float *x, float *y, int n) {
    for (int i = 0; i < n; ++i)
        y[i] = 1.0f / (1.0f + expf(-x[i]));
}

void tanhv(const float *x, float *y, int n) {
    for (int i = 0; i < n; ++i)
        y[i] = tanhf(x[i]);
}

void softplusv(const float *x, float *y, int n) {
    for (int i = 0; i < n; ++i)
        y[i] = log1pf(expf(-fabsf(x[i]))) + fmaxf(x[i], 0.0f);
}

// Mamba3 A parametrization
void heavyneg(const float *x, float *y, int n, float fl) {
    for (int i = 0; i < n; ++i) {
        float h = fmaxf(x[i], 0.0f) + 1.0f / (1.0f - fminf(x[i], 0.0f));
        y[i] = fminf(-h, -fl);
    }
}

// Advance angle mod 2pi
void phase(float *a, const float *t, float d, int n) {
    for (int i = 0; i < n; ++i) {
        float v = a[i] + t[i] * (float)M_PI * d;
        a[i] = v - TWO_PI * floorf(v / TWO_PI);
    }
}

void sincosv(const float *a, float *s, float *c, int n) {
    for (int i = 0; i < n; ++i) {
        s[i] = sinf(a[i]);
        c[i] = cosf(a[i]);
    }
}
