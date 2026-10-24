        .section .text
        .globl _start
_start:
        jal     t0, Lvec
        j       handler
Lvec:   csrw    mtvec, t0

        li      t0, 0x2200
        csrs    mstatus, t0
        csrwi   fflags, 0
        csrwi   frm, 0
        li      t0, 0x40400000
        fmv.w.x f1, t0
        li      t0, 0x3f800000
        fmv.w.x f2, t0
        li      t0, 0x7f800001
        fmv.w.x f3, t0
        li      t0, 0x00000000
        fmv.w.x f4, t0
        li      a0, 4
        vsetvli t0, a0, e32, m1, tu, mu

        li      t1, 0x3f800000
        vmv.v.x v1, t1
        li      t1, 0x40400000
        vmv.v.x v2, t1
        li      t1, 0x7f7fffff
        vmv.v.x v3, t1
        li      t1, 0x00800000
        vmv.v.x v4, t1
        li      t1, 0x00000000
        vmv.v.x v5, t1

        li      t1, 2
        vmv.v.x v0, t1
        li      t1, 0x00000000
        vmerge.vxm v1, v1, t1, v0
        vmerge.vxm v2, v2, t1, v0
        li      t1, 0xbf800000
        vmerge.vxm v3, v3, t1, v0
        li      t1, 0x7fc00000
        vmerge.vxm v4, v4, t1, v0
        li      t1, 0x00718abc
        vmerge.vxm v5, v5, t1, v0

        li      t1, 4
        vmv.v.x v0, t1
        li      t1, 0x7f800000
        vmerge.vxm v1, v1, t1, v0
        vmerge.vxm v2, v2, t1, v0
        li      t1, 0x00000001
        vmerge.vxm v3, v3, t1, v0
        li      t1, 0x4b000000
        vmerge.vxm v4, v4, t1, v0
        li      t1, 0xc0490fdb
        vmerge.vxm v5, v5, t1, v0

        li      t1, 8
        vmv.v.x v0, t1
        li      t1, 0x7f800001
        vmerge.vxm v1, v1, t1, v0
        li      t1, 0x3f800000
        vmerge.vxm v2, v2, t1, v0
        li      t1, 0x80000000
        vmerge.vxm v3, v3, t1, v0
        li      t1, 0x3f000000
        vmerge.vxm v4, v4, t1, v0
        li      t1, 0x7f000000
        vmerge.vxm v5, v5, t1, v0

        vfdiv.vv v10, v1, v2
        csrr    s1, fflags
        csrwi   fflags, 0
        vfdiv.vv v11, v3, v4
        csrr    s2, fflags
        csrwi   fflags, 0
        vfdiv.vv v12, v4, v3
        csrr    s3, fflags
        csrwi   fflags, 0
        vfdiv.vv v13, v1, v5
        csrr    s4, fflags
        csrwi   fflags, 0
        vfdiv.vf v14, v3, f1
        vfdiv.vf v15, v5, f4
        csrr    s5, fflags
        csrwi   fflags, 0
        vfrdiv.vf v16, v5, f2
        csrr    s6, fflags
        csrwi   fflags, 0
        vfrdiv.vf v17, v3, f3
        vfrdiv.vf v18, v4, f4
        csrr    s7, fflags
        csrwi   fflags, 0
        vfsqrt.v v19, v1
        csrr    s8, fflags
        csrwi   fflags, 0
        vfsqrt.v v20, v3
        csrr    s9, fflags
        csrwi   fflags, 0
        vfsqrt.v v21, v5
        vfsqrt.v v22, v4
        csrr    s10, fflags
        csrwi   fflags, 0

        vid.v   v6
        vsll.vi v6, v6, 21
        li      t1, 0x3fb504f3
        vadd.vx v6, v6, t1
        li      t1, 0x40e00000
        vmv.v.x v7, t1
        csrwi   frm, 0
        vfdiv.vv v10, v6, v7
        vfsqrt.v v11, v6
        vfrdiv.vf v12, v6, f1
        csrr    a1, fflags
        csrwi   frm, 1
        vfdiv.vv v13, v6, v7
        vfsqrt.v v14, v6
        vfrdiv.vf v15, v6, f1
        csrwi   frm, 2
        vfdiv.vv v16, v6, v7
        vfsqrt.v v17, v6
        vfrdiv.vf v18, v6, f1
        csrwi   frm, 3
        vfdiv.vv v19, v6, v7
        vfsqrt.v v20, v6
        vfrdiv.vf v21, v6, f1
        csrwi   frm, 4
        vfdiv.vv v22, v6, v7
        vfsqrt.v v23, v6
        vfrdiv.vf v24, v6, f1
        csrr    a2, fflags
        csrwi   fflags, 0
        csrwi   frm, 0

        li      t1, 0xdeadbeef
        vmv.v.x v20, t1
        vmv.v.x v21, t1
        vmv.v.x v22, t1
        li      t1, 0x5
        vmv.v.x v0, t1
        vfdiv.vv v20, v1, v2, v0.t
        vfsqrt.v v21, v3, v0.t
        vfrdiv.vf v22, v5, f4, v0.t
        csrr    a3, fflags
        csrwi   fflags, 0
        li      t1, 0xa
        vmv.v.x v0, t1
        vfsqrt.v v21, v3, v0.t
        vfrdiv.vf v22, v5, f4, v0.t
        csrr    a4, fflags
        csrwi   fflags, 0

        vfdiv.vv v10, v1, v2
        vadd.vv v11, v3, v4
        vfadd.vv v12, v10, v2
        vfsqrt.v v13, v3
        vor.vv  v14, v1, v2
        vfmul.vv v15, v13, v4
        vfrdiv.vf v16, v15, f1
        vxor.vv v17, v16, v3
        vfdiv.vv v18, v16, v12
        vmul.vv v19, v18, v1
        csrr    a5, fflags
        csrwi   fflags, 0

        li      a0, 0
        vsetvli t0, a0, e32, m1, tu, mu
        vfdiv.vv v10, v1, v2
        vfsqrt.v v11, v3
        vfrdiv.vf v12, v5, f4
        csrr    a6, fflags
        li      a0, 4
        vsetvli t0, a0, e32, m1, tu, mu

        vmv.v.v v24, v1
        vmv.v.v v25, v2
        vmv.v.v v26, v3
        vmv.v.v v27, v4
        vmv.v.v v28, v5
        vmv.v.v v29, v6
        vmv.v.v v30, v7
        vmv.v.v v31, v3
        li      a0, 32
        vsetvli t0, a0, e32, m8, tu, mu
        vid.v   v8
        vsll.vi v8, v8, 20
        li      t1, 0x3f800000
        vadd.vx v8, v8, t1
        vid.v   v16
        vsll.vi v16, v16, 22
        li      t1, 0x3e000000
        vadd.vx v16, v16, t1
        vfdiv.vv v0, v8, v16
        vfdiv.vv v16, v24, v8
        csrr    s11, fflags
        csrwi   fflags, 0
        li      a0, 29
        vsetvli t0, a0, e32, m8, tu, mu
        li      t1, 0x96692c4d
        vmv.s.x v0, t1
        csrwi   frm, 2
        vfsqrt.v v24, v8, v0.t
        vfrdiv.vf v16, v24, f1, v0.t
        csrwi   frm, 3
        vfdiv.vf v8, v16, f1
        csrr    t4, fflags
        csrwi   fflags, 0
        csrwi   frm, 0

        li      a0, 4
        vsetvli t0, a0, e32, m1, tu, mu
        csrwi   frm, 5
        jal     ra, T1
        j       R1
T1:     vfdiv.vv v10, v1, v2
R1:     jal     ra, T2
        j       R2
T2:     vfsqrt.v v10, v1
R2:     jal     ra, T3
        j       R3
T3:     vfrdiv.vf v10, v1, f1
R3:     csrwi   frm, 0
        li      a0, 8
        vsetvli t0, a0, e16, m1, tu, mu
        jal     ra, T4
        j       R4
T4:     vfdiv.vv v10, v1, v2
R4:     jal     ra, T5
        j       R5
T5:     vfsqrt.v v10, v1
R5:     li      a0, 4
        vsetvli t0, a0, e32, m1, tu, mu
        jal     ra, T6
        j       R6
T6:     .word   0x86209557
R6:     csrr    s1, mcause

Ldone:  beq     x0, x0, Ldone

handler:
        csrr    t3, mcause
        csrw    mepc, ra
        mret
