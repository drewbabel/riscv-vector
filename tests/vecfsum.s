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
        li      a0, 4
        vsetvli t0, a0, e32, m1, tu, mu
        li      t1, 0x3f800000
        vmv.v.x v1, t1
        vmv.v.x v26, t1
        li      t1, 1
        vmv.v.x v0, t1
        li      t1, 0x4b800000
        vmerge.vxm v1, v1, t1, v0
        li      t1, 8
        vmv.v.x v0, t1
        li      t1, 0xcb800000
        vmerge.vxm v1, v1, t1, v0
        vmv.v.x v6, x0
        li      t1, 0x7f800001
        vmv.v.x v24, t1
        li      t1, 0x7fc0abcd
        vmv.v.x v25, t1
        li      t1, 0x7f7fffff
        vmv.v.x v2, t1
        vmv.v.x v27, t1
        li      t1, 0xa
        vmv.v.x v0, t1
        li      t1, 0x7f800000
        vmv.v.x v3, t1
        li      s0, 0x80000000
        vxor.vx v3, v3, s0, v0.t

        vfredosum.vs v30, v1, v6
        vfredusum.vs v31, v1, v6
        csrwi   frm, 1
        vfredosum.vs v30, v1, v6
        vfredusum.vs v31, v1, v6
        csrwi   frm, 2
        vfredosum.vs v30, v1, v6
        vfredusum.vs v31, v1, v6
        csrwi   frm, 3
        vfredosum.vs v30, v1, v6
        vfredusum.vs v31, v1, v6
        csrwi   frm, 4
        vfredosum.vs v30, v1, v6
        vfredusum.vs v31, v1, v6
        csrr    a1, fflags
        csrwi   fflags, 0
        csrwi   frm, 0

        vmv.v.x v0, x0
        vfredusum.vs v30, v1, v24, v0.t
        csrr    a2, fflags
        csrwi   fflags, 0
        vfredosum.vs v31, v1, v24, v0.t
        vfredusum.vs v30, v1, v25, v0.t
        vfredosum.vs v31, v1, v25, v0.t
        vfredusum.vs v30, v1, v26, v0.t
        csrr    a3, fflags
        csrwi   fflags, 0

        li      a0, 0
        vsetvli t0, a0, e32, m1, tu, mu
        vfredosum.vs v30, v1, v24
        vfredusum.vs v31, v1, v24
        csrr    a4, fflags
        li      a0, 4
        vsetvli t0, a0, e32, m1, tu, mu

        vfredosum.vs v30, v2, v27
        csrr    a5, fflags
        csrwi   fflags, 0
        csrwi   frm, 1
        vfredusum.vs v31, v2, v27
        csrwi   frm, 0
        vfredosum.vs v30, v3, v6
        csrr    a6, fflags
        csrwi   fflags, 0
        li      t1, 0x5
        vmv.v.x v0, t1
        vfredusum.vs v31, v3, v26, v0.t
        csrr    a7, fflags
        csrwi   fflags, 0

        li      a0, 32
        vsetvli t0, a0, e32, m8, tu, mu
        vid.v   v8
        vsll.vi v8, v8, 21
        li      t1, 0x3d2ab3c5
        vadd.vx v8, v8, t1
        li      t1, 0x96692c4d
        vmv.s.x v0, t1
        vxor.vx v8, v8, s0, v0.t
        vmv.v.v v16, v8
        li      t1, 0x00010000
        vmv.s.x v0, t1
        li      t1, 0x7f800003
        vmerge.vxm v16, v16, t1, v0

        li      a0, 4
        vsetvli t0, a0, e32, m1, tu, mu
        vfredosum.vs v30, v8, v26
        vfredusum.vs v31, v8, v6
        li      a0, 3
        vsetvli t0, a0, e32, m1, tu, mu
        vfredosum.vs v30, v9, v26
        csrr    s1, fflags
        csrwi   fflags, 0

        csrwi   frm, 2
        li      a0, 8
        vsetvli t0, a0, e32, m2, tu, mu
        vfredosum.vs v30, v8, v26
        vfredusum.vs v31, v10, v6
        li      a0, 5
        vsetvli t0, a0, e32, m2, tu, mu
        vfredusum.vs v30, v12, v26
        csrr    s2, fflags
        csrwi   fflags, 0

        csrwi   frm, 3
        li      a0, 16
        vsetvli t0, a0, e32, m4, tu, mu
        vfredosum.vs v30, v8, v26
        vfredusum.vs v31, v12, v6
        li      a0, 13
        vsetvli t0, a0, e32, m4, tu, mu
        vfredosum.vs v30, v16, v26
        csrr    s3, fflags
        csrwi   fflags, 0

        csrwi   frm, 4
        li      a0, 32
        vsetvli t0, a0, e32, m8, tu, mu
        vfredosum.vs v30, v8, v26
        vfredusum.vs v31, v8, v6
        li      a0, 29
        vsetvli t0, a0, e32, m8, tu, mu
        vfredosum.vs v30, v16, v26
        csrr    s4, fflags
        csrwi   fflags, 0

        csrwi   frm, 1
        li      t1, 0xff7effde
        vmv.s.x v0, t1
        li      a0, 32
        vsetvli t0, a0, e32, m8, tu, mu
        vfredosum.vs v30, v8, v26, v0.t
        vfredusum.vs v31, v16, v6, v0.t
        csrr    s5, fflags
        csrwi   fflags, 0
        csrwi   frm, 0

        vfredosum.vs v30, v8, v26
        vfredusum.vs v31, v8, v30
        vfredmin.vs v30, v8, v31
        vredsum.vs v31, v8, v30
        vfredosum.vs v30, v8, v31
        vfredmax.vs v31, v16, v30
        vfredusum.vs v30, v16, v31
        vfredosum.vs v29, v8, v26
        vfredmin.vs v28, v16, v6
        vredsum.vs v27, v8, v6
        vfredusum.vs v5, v16, v26
        vfredmax.vs v4, v8, v6
        csrr    s6, fflags
        csrwi   fflags, 0

        li      a0, 8
        vsetvli t0, a0, e16, m1, tu, mu
        csrwi   vstart, 1
        jal     ra, T1
        j       R1
T1:     vredsum.vs v30, v8, v6
R1:     jal     ra, T2
        j       R2
T2:     vwredsum.vs v30, v8, v6
R2:     li      a0, 4
        vsetvli t0, a0, e32, m1, tu, mu
        csrwi   vstart, 2
        jal     ra, T3
        j       R3
T3:     vfredosum.vs v30, v8, v6
R3:     jal     ra, T4
        j       R4
T4:     vfredusum.vs v30, v8, v6
R4:     jal     ra, T5
        j       R5
T5:     vfredmin.vs v30, v8, v6
R5:     jal     ra, T6
        j       R6
T6:     vredmaxu.vs v30, v8, v6
R6:     csrr    s7, vstart
        csrwi   vstart, 0
        vfredosum.vs v31, v8, v26
        csrr    s8, fflags

        csrwi   frm, 5
        jal     ra, T7
        j       R7
T7:     vfredosum.vs v30, v8, v6
R7:     csrwi   frm, 0
        li      a0, 8
        vsetvli t0, a0, e16, m1, tu, mu
        jal     ra, T8
        j       R8
T8:     vfredusum.vs v30, v8, v6
R8:     csrr    s9, mcause

Ldone:  beq     x0, x0, Ldone

handler:
        csrr    t3, mcause
        csrw    mepc, ra
        mret
