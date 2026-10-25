        .section .text
        .globl _start
_start:
        li      t0, 0x200
        csrs    mstatus, t0
        lui     s0, 0x80008
        li      t1, 0x5ac3e71d
        li      t2, 64
        mv      t3, s0
Lfill:  sw      t1, 0(t3)
        slli    t4, t1, 13
        xor     t1, t1, t4
        srli    t4, t1, 17
        xor     t1, t1, t4
        slli    t4, t1, 5
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
        vmxor.mm v4, v4, v4
        vmxnor.mm v5, v5, v5

        vcompress.vm v8, v2, v1
        vcompress.vm v9, v2, v4
        vcompress.vm v10, v2, v5
        vcompress.vm v11, v3, v0
        li      a0, 11
        vsetvli t0, a0, e8, m1, tu, mu
        vcompress.vm v12, v3, v1

        li      a0, 8
        vsetvli t0, a0, e16, m1, tu, mu
        vcompress.vm v8, v2, v1
        vcompress.vm v9, v3, v4
        vcompress.vm v10, v3, v5
        li      a0, 5
        vsetvli t0, a0, e16, m1, tu, mu
        vcompress.vm v11, v2, v1

        li      a0, 4
        vsetvli t0, a0, e32, m1, tu, mu
        vcompress.vm v8, v3, v1
        vcompress.vm v9, v2, v4
        vcompress.vm v10, v2, v5
        li      a0, 3
        vsetvli t0, a0, e32, m1, tu, mu
        vcompress.vm v11, v3, v1

        li      a0, 32
        vsetvli t0, a0, e8, m2, tu, mu
        addi    t3, s0, 48
        vle8.v  v16, (t3)
        addi    t3, s0, 80
        vle8.v  v18, (t3)
        vcompress.vm v20, v16, v1
        vcompress.vm v22, v18, v4
        vcompress.vm v24, v18, v5
        li      a0, 19
        vsetvli t0, a0, e8, m2, tu, mu
        vcompress.vm v26, v16, v3

        li      a0, 16
        vsetvli t0, a0, e16, m2, tu, mu
        vcompress.vm v20, v18, v2
        vcompress.vm v22, v16, v5
        li      a0, 8
        vsetvli t0, a0, e32, m2, tu, mu
        vcompress.vm v24, v16, v2
        vcompress.vm v26, v18, v4
        li      a0, 6
        vsetvli t0, a0, e32, m2, tu, mu
        vcompress.vm v28, v18, v5

        vadd.vv v30, v24, v28
        vcompress.vm v20, v30, v1
        vxor.vv v24, v20, v18

        li      a0, 0
        vsetvli t0, a0, e8, m1, tu, mu
        vcompress.vm v13, v2, v5
Ldone:  beq     x0, x0, Ldone
