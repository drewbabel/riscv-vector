        .section .text
        .globl _start

        .macro  vset4 vr, a, b, c, d
        li      t1, \a
        vmv.v.x \vr, t1
        li      t1, 2
        vmv.v.x v0, t1
        li      t1, \b
        vmerge.vxm \vr, \vr, t1, v0
        li      t1, 4
        vmv.v.x v0, t1
        li      t1, \c
        vmerge.vxm \vr, \vr, t1, v0
        li      t1, 8
        vmv.v.x v0, t1
        li      t1, \d
        vmerge.vxm \vr, \vr, t1, v0
        .endm

        .macro  wnall
        vfwcvt.f.x.v v18, v5
        vfwcvt.f.xu.v v20, v4
        vfncvt.x.f.w v22, v2
        vfncvt.xu.f.w v23, v2
        vfncvt.x.f.w v24, v6
        vfncvt.xu.f.w v25, v6
        .endm

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

        vset4   v2, 0x7fc00000, 0xff800000, 0x3f000000, 0x80000001
        vset4   v3, 0x477fff80, 0x46ffff00, 0xc7000080, 0xbf000000
        vset4   v4, 0x00000007, 0xffffffff, 0x80000000, 0x7fffffff
        vset4   v5, 0x0001ffff, 0x8000ffff, 0x12348001, 0x00007fff
        vset4   v6, 0x40400000, 0xbfc00000, 0x7f800001, 0x4b000001
        vset4   v7, 0x3effffff, 0xc6fffe00, 0x4f000000, 0x00000000

        li      a0, 8
        vsetvli t0, a0, e16, m1, tu, mu
        csrwi   frm, 0
        wnall
        csrr    s2, fflags
        csrwi   fflags, 0
        csrwi   frm, 2
        wnall
        csrr    s3, fflags
        csrwi   fflags, 0
        csrwi   frm, 4
        wnall
        vfncvt.rtz.x.f.w v26, v2
        vfncvt.rtz.xu.f.w v27, v6
        csrr    s4, fflags
        csrwi   fflags, 0

        li      t1, 0x0055
        vmv.s.x v0, t1
        vfwcvt.f.x.v v28, v5, v0.t
        vfncvt.x.f.w v30, v2, v0.t
        vfncvt.rtz.xu.f.w v31, v6, v0.t
        vmv.v.v v12, v2
        vmv.v.v v13, v3
        vfncvt.xu.f.w v12, v12
        csrr    s5, fflags
        csrwi   fflags, 0

        li      a0, 13
        vsetvli t0, a0, e16, m2, tu, mu
        vfncvt.x.f.w v8, v4
        vfwcvt.f.x.v v24, v4, v0.t
        li      a0, 4
        vsetvli t0, a0, e16, mf2, tu, mu
        vfwcvt.f.xu.v v10, v5
        vfncvt.xu.f.w v12, v3
        csrr    s6, fflags
        csrwi   fflags, 0

        li      a0, 0
        vsetvli t0, a0, e16, m1, tu, mu
        vfncvt.x.f.w v10, v2
        vfwcvt.f.x.v v10, v4
        csrr    s7, fflags

        li      a0, 4
        vsetvli t0, a0, e8, m1, tu, mu
        jal     ra, T1
        j       R1
T1:     vfwcvt.f.x.v v10, v1
R1:     jal     ra, T2
        j       R2
T2:     vfncvt.x.f.w v10, v2
R2:     li      a0, 4
        vsetvli t0, a0, e32, m1, tu, mu
        jal     ra, T3
        j       R3
T3:     vfwcvt.f.x.v v10, v1
R3:     jal     ra, T4
        j       R4
T4:     vfncvt.x.f.w v10, v2
R4:     li      a0, 4
        vsetvli t0, a0, e16, m1, tu, mu
        jal     ra, T5
        j       R5
T5:     vfwcvt.x.f.v v10, v1
R5:     jal     ra, T6
        j       R6
T6:     vfncvt.f.x.w v10, v2
R6:     jal     ra, T7
        j       R7
T7:     vfwcvt.f.f.v v10, v1
R7:     jal     ra, T8
        j       R8
T8:     vfncvt.f.f.w v10, v2
R8:     jal     ra, T9
        j       R9
T9:     vfncvt.rod.f.f.w v10, v2
R9:     jal     ra, T10
        j       R10
T10:    vfwcvt.f.x.v v8, v8
R10:    jal     ra, T11
        j       R11
T11:    vfncvt.x.f.w v9, v8
R11:    jal     ra, T12
        j       R12
T12:    vfwcvt.f.x.v v9, v4
R12:    csrwi   frm, 5
        jal     ra, T13
        j       R13
T13:    vfwcvt.f.x.v v10, v1
R13:    jal     ra, T14
        j       R14
T14:    vfncvt.rtz.x.f.w v10, v2
R14:    csrwi   frm, 0
        csrr    s8, fflags
        csrr    s1, mcause

Ldone:  beq     x0, x0, Ldone

handler:
        csrr    t3, mcause
        csrw    mepc, ra
        mret
