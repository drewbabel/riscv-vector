        .section .text
        .globl _start

        .macro  trap op:vararg
        jal     ra, 1f
        j       2f
1:      \op
2:
        .endm

        .macro  ill set:vararg
        vsetvli t0, a0, e32, m1, tu, mu
        \set
        csrr    s2, vl
        csrr    s3, vtype
        trap    vadd.vv v8, v4, v4
        .endm

_start:
        jal     t0, Lvec
        j       handler
Lvec:   csrw    mtvec, t0

        li      t0, 0x2200
        csrs    mstatus, t0
        csrwi   fcsr, 0
        li      a0, 4

        ill     vsetvli t0, a0, e64, m1, tu, mu
        ill     vsetvli t0, a0, e64, m2, ta, mu
        ill     vsetvli t0, a0, e64, m4, tu, ma
        ill     vsetvli t0, a0, e64, m8, ta, ma
        ill     vsetvli t0, a0, e64, mf2, tu, mu
        ill     vsetvli t0, a0, e64, mf4, ta, ma
        ill     vsetvli t0, a0, e64, mf8, tu, mu
        ill     vsetvli t0, x0, e64, m1, tu, mu

        ill     vsetivli t0, 4, e64, m1, tu, mu
        ill     vsetivli t0, 1, e64, m2, ta, mu
        ill     vsetivli t0, 31, e64, m4, tu, ma
        ill     vsetivli t0, 4, e64, m8, ta, ma
        ill     vsetivli t0, 4, e64, mf2, tu, mu
        ill     vsetivli t0, 2, e64, mf4, ta, ma
        ill     vsetivli t0, 4, e64, mf8, tu, mu

        li      s4, 0x18
        ill     vsetvl t0, a0, s4
        li      s4, 0x59
        ill     vsetvl t0, a0, s4
        li      s4, 0x9a
        ill     vsetvl t0, a0, s4
        li      s4, 0xdb
        ill     vsetvl t0, a0, s4
        li      s4, 0x1f
        ill     vsetvl t0, a0, s4
        li      s4, 0x5e
        ill     vsetvl t0, a0, s4
        li      s4, 0x1d
        ill     vsetvl t0, a0, s4
        li      s4, 0x18
        ill     vsetvl t0, x0, s4

        vsetvli t0, a0, e32, m1, tu, mu
        csrr    s2, vl
        csrr    s3, vtype
        csrr    s1, mcause

Ldone:  beq     x0, x0, Ldone

handler:
        csrr    t3, mcause
        csrw    mepc, ra
        mret
