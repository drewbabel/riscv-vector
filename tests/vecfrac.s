        .section .text
        .globl _start
_start:
        li      t0, 0x2200
        csrs    mstatus, t0
        csrwi   fflags, 0

        li      a0, 4
        vsetvli t0, a0, e32, m1, ta, ma
        vid.v   v4
        li      t1, 0x01234567
        vadd.vx v4, v4, t1
        li      t1, 0x7F3E2D1C
        vmv.v.x v6, t1
        vmul.vv v6, v6, v4
        li      t1, 0x3F800000
        vmv.v.x v20, t1
        li      t1, 0x33D6BF95
        vmv.v.x v21, t1

        li      a0, 4
        vsetvli t0, a0, e16, mf2, ta, ma
        vwadd.vv v8, v4, v6
        vmul.vv v9, v4, v6
        vadd.vv v10, v9, v4
        vmv.x.s a1, v9
        vwmulu.vv v12, v4, v6
        vmul.vv v13, v6, v6
        vmv.x.s a2, v13
        vnsrl.wi v14, v6, 3
        vmul.vv v15, v6, v4
        vmv.x.s a3, v15

        li      a0, 4
        vsetvli t0, a0, e8, mf4, ta, ma
        vwmul.vv v16, v4, v6
        vmul.vv v17, v4, v6
        vadd.vv v18, v17, v6
        vmv.x.s a4, v17
        vnsra.wi v22, v6, 2
        vmul.vv v23, v6, v4
        vmv.x.s a5, v23

        li      a0, 4
        vsetvli t0, a0, e16, mf2, ta, ma
        vwmulu.vv v24, v4, v6
        vsetvli t0, a0, e32, m1, ta, ma
        vfadd.vv v25, v20, v21
        csrr    a6, fflags
        csrwi   fflags, 0

        vsetvli t0, a0, e8, mf4, ta, ma
        vwmulu.vv v26, v4, v6
        vsetvli t0, a0, e32, m1, ta, ma
        vfadd.vv v27, v20, v21
        csrr    a7, fflags

Ldone:  beq     x0, x0, Ldone
