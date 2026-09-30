        .section .text
        .globl _start
_start:
        li      t0, 0x200
        csrs    mstatus, t0
        lui     s0, 0x80008
        li      t1, 0x5bd1e995
        li      t2, 64
        mv      t3, s0
Lfill:  sw      t1, 0(t3)
        slli    t4, t1, 13
        xor     t1, t1, t4
        srli    t4, t1, 17
        xor     t1, t1, t4
        addi    t3, t3, 4
        addi    t2, t2, -1
        bnez    t2, Lfill

        li      a0, 16
        vsetvli t0, a0, e8, m1, tu, mu
        vle8.v  v1, (s0)
        addi    t3, s0, 16
        vle8.v  v2, (t3)
        addi    t3, s0, 32
        vle8.v  v3, (t3)
        addi    t3, s0, 48
        vle8.v  v4, (t3)

        vredsum.vs v5, v1, v2
        vmv.x.s    a1, v3
        vmv.x.s    a2, v4
        add        a3, a1, a2

        vredmaxu.vs v6, v2, v1
        vcpop.m    a4, v3
        vmv.x.s    a5, v1
        vfirst.m   a6, v4
        xor        a7, a4, a5

        vadd.vv    v7, v1, v2
        vmv.x.s    s1, v7
        vmv.x.s    s2, v2
        vcpop.m    s3, v1
        vcpop.m    s4, v2
        add        s5, s3, s4

        vwredsumu.vs v8, v3, v4
        vmv.x.s    s6, v8
        vfirst.m   s7, v2
        vmv.x.s    s8, v3
        sub        s9, s6, s8

        li      a0, 4
        vsetvli t0, a0, e32, m1, tu, mu
        vredsum.vs v9, v1, v2
        vmv.x.s    s10, v9
        vmv.x.s    s11, v1
        add        t5, s10, s11
Ldone:  beq     x0, x0, Ldone
