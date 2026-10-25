#include <riscv_vector.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>

#include "board.h"

#define N 64

static int32_t a[N], b[N], c_scalar[N], c_vector[N];

static void report(const char *tag, uint32_t cycles) {
    board_puts(tag);
    board_putu(cycles);
    board_puts("\n");
}

int main(void) {
    board_puts("hello from the riscv-vector core\n");

    for (int i = 0; i < N; i++) {
        a[i] = 3 * i + 1;
        b[i] = 1000 - 7 * i;
    }

    uint32_t t0 = read_cycles();
    for (int i = 0; i < N; i++)
        c_scalar[i] = a[i] + b[i];
    uint32_t scalar_cycles = read_cycles() - t0;

    t0 = read_cycles();
    for (size_t i = 0; i < N;) {
        size_t vl = __riscv_vsetvl_e32m1(N - i);
        vint32m1_t va = __riscv_vle32_v_i32m1(&a[i], vl);
        vint32m1_t vb = __riscv_vle32_v_i32m1(&b[i], vl);
        __riscv_vse32_v_i32m1(&c_vector[i], __riscv_vadd_vv_i32m1(va, vb, vl),
                              vl);
        i += vl;
    }
    uint32_t vector_cycles = read_cycles() - t0;

    int ok = 1;
    for (int i = 0; i < N; i++)
        if (c_scalar[i] != c_vector[i])
            ok = 0;

    board_puts(ok ? "MATCH\n" : "MISMATCH\n");
    report("scalar cycles ", scalar_cycles);
    report("vector cycles ", vector_cycles);
    printf("printf lanes %d\n", (int)(N / 4));
    board_puts("END\n");
    return 0;
}
