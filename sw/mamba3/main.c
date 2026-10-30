#include <string.h>

#include "board.h"
#include "mamba3.h"

#ifndef SCALAR
#define SCALAR 1
#endif
#ifndef VECTOR
#define VECTOR 1
#endif

typedef void (*step_fn)(void);

#define PICK_S(n) m3_##n##_s,
#define PICK_V(n) m3_##n##_v,
#define NAME(n) #n,
static const step_fn scalar[] = {STEPS(PICK_S)};
static const step_fn vector[] = {STEPS(PICK_V)};
static const char *const names[] = {STEPS(NAME)};
#define NSTEP (sizeof names / sizeof names[0])

static float res[2][DM];

// Reload initial SSM state
static void restore(void) {
    memcpy(H, I_h, sizeof H);
    memcpy(kp, I_kp, sizeof kp);
    memcpy(vp, I_vp, sizeof vp);
    memcpy(ang, I_ang, sizeof ang);
}

static void line(const char *tag, const char *name, uint32_t v) {
    board_puts(tag);
    board_putc(' ');
    board_puts(name);
    board_putc(' ');
    board_putu(v);
    board_putc('\n');
}

static void run(const char *tag, const step_fn *steps, float *r) {
    restore();
    uint32_t total = 0;
    for (unsigned i = 0; i < NSTEP; ++i) {
        uint32_t a = read_cycles();
        steps[i]();
        uint32_t c = read_cycles() - a;
        total += c;
        line(tag, names[i], c);
    }
    line(tag, "total", total);
    memcpy(r, ro, sizeof ro);
}

static void dump(const char *tag, const float *r) {
    board_puts(tag);
    board_puts(" ro\n");
    for (int i = 0; i < DM; ++i) {
        uint32_t v;
        memcpy(&v, &r[i], 4);
        for (int k = 28; k >= 0; k -= 4)
            board_putc("0123456789abcdef"[(v >> k) & 15]);
        if (i % 8 == 7 || i == DM - 1)
            board_putc('\n');
    }
}

int main(void) {
    static const char *const tags[2] = {"scalar", "vector"};
    static const step_fn *const sets[2] = {scalar, vector};
    static const int on[2] = {SCALAR, VECTOR};
    board_puts(MODEL "\n");
    for (int b = 0; b < 2; ++b)
        if (on[b])
            run(tags[b], sets[b], res[b]);
    for (int b = 0; b < 2; ++b)
        if (on[b])
            dump(tags[b], res[b]);
    board_puts("END\n");
    return 0;
}
