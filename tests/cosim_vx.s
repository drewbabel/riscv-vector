        .section .text
        .globl _start
_start:
        li      t0, 0x2200
        csrs    mstatus, t0
        li      t1, 0x3f920008
        fmv.w.x f2, t1
        li      t1, 0x3f800000
        fmv.w.x f1, t1
        fmv.w.x f0, zero
        lui     s0, 0x80080
        fmadd.s f3, f0, f1, f2
        fmadd.s f4, f1, f0, f2

        # Vector stores
        li      a0, 16
        vsetvli t0, a0, e8, m1, tu, mu
        vid.v   v1
        li      t2, 4
1:      vse8.v  v1, (s0)
        sw      t2, 20(s0)
        addi    a1, s0, 35
        vse8.v  v1, (a1)
        vadd.vi v1, v1, 3
        addi    s0, s0, 64
        addi    t2, t2, -1
        bnez    t2, 1b
        li      a0, 4
        vsetvli t0, a0, e32, m1, tu, mu
        vse32.v v1, (s0)
        vle8.v  v3, (s0)
Ldone:  beq     x0, x0, Ldone
