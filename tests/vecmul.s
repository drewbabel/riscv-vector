        .section .text
        .globl _start
_start:
        li      t0, 0x200
        csrs    mstatus, t0

        li      a0, 4
        vsetvli t0, a0, e32, m1, ta, ma
        li      t1, 0x89ABCDEF
        vmv.v.x v1, t1
        vid.v   v2
        li      t2, 0x7FFF1234
        vmul.vx v3, v2, t2
        vxor.vv v4, v3, v1
        vmul.vv v5, v4, v3
        vmulh.vv v6, v4, v3
        vmulhu.vv v7, v4, v3
        vmulhsu.vv v8, v4, v3
        vmul.vx v9, v4, t1
        vmulh.vx v10, v4, t1
        vmulhu.vx v11, v4, t1
        vmulhsu.vx v12, v4, t1

        li      a0, 8
        vsetvli t0, a0, e16, m1, ta, ma
        vmul.vv v13, v4, v3
        vmulh.vv v14, v4, v3
        vmulhu.vv v15, v4, v3
        vmulhsu.vv v16, v4, v3
        vmulh.vx v17, v4, t1

        li      a0, 16
        vsetvli t0, a0, e8, m1, ta, ma
        vmul.vv v18, v4, v3
        vmulh.vv v19, v4, v3
        vmulhu.vv v20, v4, v3
        vmulhsu.vv v21, v4, v3
        vmulhsu.vx v22, v4, t1

        li      a0, 8
        vsetvli t0, a0, e32, m2, ta, ma
        vmul.vv v24, v4, v2
        vmulh.vv v26, v4, v2

        li      a0, 16
        vsetvli t0, a0, e8, m1, ta, ma
        li      t5, 0xA5A5
        vmv.v.x v0, t5
        vmul.vv v28, v4, v3, v0.t
        vmulhu.vx v29, v4, t1, v0.t

        li      a0, 5
        vsetvli t0, a0, e16, m1, ta, ma
        vmulh.vv v30, v4, v3

        li      a0, 4
        vsetvli t0, a0, e32, m1, ta, ma
        li      t3, 0x80000000
        vmv.v.x v31, t3
        vmulh.vv v31, v31, v31

        vmv.v.v v20, v3
        vmacc.vv v20, v4, v2
        vmv.v.v v21, v3
        vnmsac.vv v21, v4, v2
        vmv.v.v v22, v3
        vmadd.vv v22, v4, v2
        vmv.v.v v23, v3
        vnmsub.vv v23, v4, v2
        vmacc.vx v20, t1, v4
        vnmsac.vx v21, t1, v4
        vmadd.vx v22, t1, v4
        vnmsub.vx v23, t1, v4

        li      a0, 8
        vsetvli t0, a0, e16, m1, ta, ma
        vmacc.vv v20, v4, v3
        vnmsub.vx v21, t1, v4
        li      a0, 16
        vsetvli t0, a0, e8, m1, ta, ma
        vmadd.vv v22, v4, v3
        vnmsac.vx v23, t2, v4
        vmacc.vv v28, v4, v3, v0.t
        li      a0, 6
        vsetvli t0, a0, e32, m2, ta, ma
        vmacc.vv v24, v4, v2

Ldone:  beq     x0, x0, Ldone
