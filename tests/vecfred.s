        .section .text
        .globl _start
_start:
        jal     t0, Lvec
        j       handler
Lvec:   csrw    mtvec, t0

        li      t0, 0x2200
        csrs    mstatus, t0
        csrwi   fflags, 0
        li      s0, 0x80000000
        li      a0, 4
        vsetvli t0, a0, e32, m1, tu, mu
        li      t1, 0xa
        vmv.v.x v0, t1
        vmv.v.x v1, x0
        vxor.vx v1, v1, s0, v0.t
        li      t1, 0x3f800000
        vmv.v.x v2, t1
        vmv.v.x v26, t1
        li      t2, 0x7f800001
        vmerge.vxm v2, v2, t2, v0
        vmv.v.x v24, t2
        li      t1, 0x7fc01234
        vmv.v.x v3, t1
        li      t2, 0xff800001
        vmerge.vxm v3, v3, t2, v0
        li      t1, 0x7f800000
        vmv.v.x v4, t1
        vxor.vx v4, v4, s0, v0.t
        li      t1, 0xff800000
        vmv.v.x v27, t1
        li      t1, 1
        vmv.v.x v5, t1
        vxor.vx v5, v5, s0, v0.t
        vmv.v.x v6, x0
        vmv.v.x v7, s0
        li      t1, 0x7fc0abcd
        vmv.v.x v25, t1
        li      t1, 0x7fc00000
        vmv.v.x v28, t1
        li      t2, 0xffc0abcd
        vmerge.vxm v28, v28, t2, v0

        vfredmin.vs v29, v1, v6
        vfredmax.vs v30, v1, v7
        vfredmin.vs v31, v5, v6
        vfredmax.vs v29, v5, v7
        vfredmax.vs v30, v4, v26
        vfredmin.vs v31, v4, v27
        csrr    a1, fflags
        csrwi   fflags, 0

        vfredmin.vs v29, v2, v26
        csrr    a2, fflags
        csrwi   fflags, 0
        vfredmax.vs v30, v28, v25
        csrr    a3, fflags
        csrwi   fflags, 0
        vfredmin.vs v31, v3, v28
        vfredmax.vs v29, v4, v24
        csrr    a4, fflags
        csrwi   fflags, 0

        vfredmin.vs v30, v2, v26, v0.t
        csrr    a5, fflags
        csrwi   fflags, 0
        li      t1, 0x5
        vmv.v.x v0, t1
        vfredmax.vs v31, v2, v6, v0.t
        vmv.v.x v0, x0
        vfredmin.vs v29, v4, v24, v0.t
        vfredmax.vs v30, v4, v25, v0.t
        csrr    a6, fflags
        csrwi   fflags, 0

        li      a0, 0
        vsetvli t0, a0, e32, m1, tu, mu
        vfredmin.vs v31, v4, v24
        vfredmax.vs v29, v2, v26
        csrr    a7, fflags

        li      a0, 32
        vsetvli t0, a0, e32, m8, tu, mu
        vid.v   v16
        vsll.vi v16, v16, 22
        li      t1, 0x3e000000
        vadd.vx v16, v16, t1
        li      t1, 0x96692c4d
        vmv.s.x v0, t1
        vxor.vx v16, v16, s0, v0.t
        vmv.v.v v8, v16
        li      t1, 0x00420020
        vmv.s.x v0, t1
        li      t2, 0x7f800003
        vmerge.vxm v8, v8, t2, v0
        li      t1, 0x10000400
        vmv.s.x v0, t1
        li      t2, 0x7fc00000
        vmerge.vxm v8, v8, t2, v0
        li      t1, 0x00008001
        vmv.s.x v0, t1
        vmerge.vxm v8, v8, s0, v0
        csrwi   fflags, 0

        li      a0, 4
        vsetvli t0, a0, e32, m1, tu, mu
        vfredmin.vs v29, v16, v26
        vfredmax.vs v30, v8, v7
        li      a0, 3
        vsetvli t0, a0, e32, m1, tu, mu
        vfredmin.vs v31, v8, v25
        csrr    s1, fflags
        csrwi   fflags, 0

        li      a0, 8
        vsetvli t0, a0, e32, m2, tu, mu
        vfredmin.vs v29, v8, v6
        vfredmax.vs v30, v16, v26
        li      a0, 5
        vsetvli t0, a0, e32, m2, tu, mu
        vfredmax.vs v31, v8, v25
        csrr    s2, fflags
        csrwi   fflags, 0

        li      a0, 16
        vsetvli t0, a0, e32, m4, tu, mu
        vfredmin.vs v29, v16, v26
        vfredmax.vs v30, v8, v7
        li      a0, 13
        vsetvli t0, a0, e32, m4, tu, mu
        vfredmin.vs v31, v12, v25
        csrr    s3, fflags
        csrwi   fflags, 0

        li      a0, 32
        vsetvli t0, a0, e32, m8, tu, mu
        vfredmin.vs v29, v8, v6
        vfredmax.vs v30, v16, v27
        li      a0, 29
        vsetvli t0, a0, e32, m8, tu, mu
        vfredmax.vs v31, v8, v24
        csrr    s4, fflags
        csrwi   fflags, 0

        li      t1, 0xff7fffde
        vmv.s.x v0, t1
        li      a0, 32
        vsetvli t0, a0, e32, m8, tu, mu
        vfredmin.vs v29, v8, v24, v0.t
        vfredmax.vs v30, v8, v24, v0.t
        csrr    s5, fflags
        csrwi   fflags, 0
        li      t1, 0x00800021
        vmv.s.x v0, t1
        li      a0, 16
        vsetvli t0, a0, e32, m4, tu, mu
        vfredmin.vs v31, v8, v26, v0.t
        li      a0, 8
        vsetvli t0, a0, e32, m2, tu, mu
        vfredmax.vs v29, v10, v27, v0.t
        csrr    s6, fflags
        csrwi   fflags, 0

        li      a0, 32
        vsetvli t0, a0, e32, m8, tu, mu
        csrwi   frm, 1
        vfredmin.vs v29, v8, v6
        csrwi   frm, 2
        vfredmax.vs v30, v8, v7
        csrwi   frm, 3
        vfredmin.vs v31, v16, v27
        csrwi   frm, 4
        vfredmax.vs v29, v16, v4
        csrwi   frm, 0
        vfredmin.vs v16, v8, v16
        vfredmax.vs v8, v8, v26
        csrr    s7, fcsr
        csrwi   fflags, 0

        csrwi   frm, 5
        jal     ra, T1
        j       R1
T1:     vfredmin.vs v29, v16, v6
R1:     csrwi   frm, 7
        jal     ra, T2
        j       R2
T2:     vfredmax.vs v29, v16, v6
R2:     csrwi   frm, 0
        li      a0, 8
        vsetvli t0, a0, e16, m1, tu, mu
        jal     ra, T3
        j       R3
T3:     vfredmin.vs v29, v1, v6
R3:     li      a0, 8
        vsetvli t0, a0, e32, m2, tu, mu
        jal     ra, T4
        j       R4
T4:     vfredmax.vs v29, v17, v6
R4:     vfredmin.vs v30, v18, v6
        csrr    s8, fflags

        li      a0, 4
        vsetvli t0, a0, e32, m1, tu, mu
        jal     ra, T5
        j       R5
T5:     csrwi   frm, 6
        vfredmin.vs v29, v4, v6
R5:     csrwi   frm, 5
        csrwi   frm, 2
        vfredmax.vs v30, v4, v6
        csrwi   frm, 0
        li      t0, 0x6000
        csrc    mstatus, t0
        jal     ra, T6
        j       R6
T6:     vfredmin.vs v31, v4, v6
R6:     li      t0, 0x2000
        csrs    mstatus, t0

        li      a0, 4
        vsetvli t0, a0, e32, m1, tu, mu
        li      t0, 0x6000
        csrc    mstatus, t0
        li      t0, 0x4000
        csrs    mstatus, t0
        vfredmin.vs v29, v4, v6
        csrr    s9, mstatus
        vfredmax.vs v30, v2, v6
        csrr    s10, mstatus
        li      t0, 0x2000
        csrs    mstatus, t0
        csrr    s11, fflags

Ldone:  beq     x0, x0, Ldone

handler:
        csrr    t3, mcause
        csrw    mepc, ra
        mret
