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
        vadd.vi v5, v2, -2
        vdivu.vv v6, v4, v5
        vdiv.vv v7, v4, v5
        vremu.vv v8, v4, v5
        vrem.vv v9, v4, v5
        li      t3, 7
        vdivu.vx v10, v4, t3
        vdiv.vx v11, v4, t3
        vremu.vx v12, v4, t3
        vrem.vx v13, v4, t3
        vdivu.vx v14, v4, x0
        vdiv.vx v15, v4, x0
        vremu.vx v16, v4, x0
        vrem.vx v17, v4, x0
        li      t4, -1
        li      t5, 0x80000000
        vmv.v.x v18, t5
        vdiv.vx v19, v18, t4
        vrem.vx v20, v18, t4
        vdiv.vv v21, v18, v5
        vrem.vv v22, v18, v5
        vdivu.vv v23, v18, v5

        li      a0, 8
        vsetvli t0, a0, e16, m1, ta, ma
        vdivu.vv v6, v4, v3
        vdiv.vv v7, v4, v5
        vremu.vv v8, v4, v5
        vrem.vv v9, v3, v5
        vdiv.vx v10, v4, t3
        vremu.vx v11, v4, x0
        li      t5, 0x80008000
        vmv.v.x v18, t5
        vdiv.vv v19, v18, v5
        vrem.vv v20, v18, v5
        vdiv.vx v21, v18, t4

        li      a0, 16
        vsetvli t0, a0, e8, m1, ta, ma
        vdivu.vv v6, v4, v3
        vdiv.vv v7, v4, v5
        vremu.vv v8, v4, v5
        vrem.vv v9, v3, v5
        vdivu.vx v10, v4, t3
        vrem.vx v11, v4, t4
        li      t5, 0x80
        vmv.v.x v18, t5
        vdiv.vv v19, v18, v5
        vrem.vx v20, v18, t4
        li      t6, 0xA5A5
        vmv.v.x v0, t6
        vdiv.vv v28, v4, v5, v0.t
        vremu.vx v29, v4, t3, v0.t

        li      a0, 7
        vsetvli t0, a0, e32, m2, ta, ma
        vdivu.vv v24, v4, v2
        vrem.vv v26, v4, v2
        vdiv.vv v30, v26, v24
        vadd.vv v22, v30, v24

Ldone:  beq     x0, x0, Ldone
