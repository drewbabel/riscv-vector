        .section .text
        .globl _start
_start:
        li      t0, 0x200
        csrs    mstatus, t0

        li      a0, 4
        vsetvli t0, a0, e32, m1, ta, ma
        li      t1, 0x12345678
        vmv.v.x v1, t1
        li      t2, 0x0F0F0F0F
        vmv.v.x v2, t2
        vadd.vv v3, v1, v2
        vsub.vv v4, v1, v2
        vand.vv v5, v1, v2
        vor.vv  v6, v1, v2
        vxor.vv v7, v1, v2
        vadd.vx v8, v1, t2
        vrsub.vx v9, v1, t2
        vadd.vi v10, v1, 13
        vadd.vi v11, v1, -16
        vsll.vi v12, v1, 3
        vsrl.vi v13, v1, 5
        vsra.vi v14, v1, 5
        vminu.vv v15, v1, v2
        vmin.vv v16, v1, v2
        vmaxu.vv v17, v1, v2
        vmax.vv v18, v1, v2

        li      a0, 8
        vsetvli t0, a0, e16, m1, ta, ma
        li      t3, 0x8001
        vmv.v.x v19, t3
        vadd.vv v20, v19, v19
        vsra.vi v21, v19, 2
        vsrl.vi v22, v19, 2

        li      a0, 16
        vsetvli t0, a0, e8, m1, ta, ma
        li      t4, 0x81
        vmv.v.x v23, t4
        vsra.vi v24, v23, 1
        vmax.vv v25, v23, v1

        li      a0, 3
        vsetvli t0, a0, e32, m1, ta, ma
        vadd.vv v26, v1, v2

        li      a0, 8
        vsetvli t0, a0, e32, m2, ta, ma
        vadd.vv v28, v2, v2

        li      a0, 4
        vsetvli t0, a0, e32, m1, ta, ma
        li      t5, 0xA
        vmv.v.x v0, t5
        vadd.vv v29, v1, v2, v0.t
        vsub.vv v30, v1, v2, v0.t
        vadc.vvm v31, v1, v2, v0
        vmerge.vvm v27, v1, v2, v0
        vmv.v.i v26, 7
        vadd.vi v25, v26, -1, v0.t

        li      a0, 5
        vsetvli t0, a0, e8, m1, ta, ma
        vadd.vv v24, v1, v2, v0.t

Ldone:  beq     x0, x0, Ldone
