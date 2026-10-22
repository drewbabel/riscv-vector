        .section .text
        .globl _start
_start:
        jal     t0, Lvec
        j       handler
Lvec:   csrw    mtvec, t0

        li      t0, 0x200
        csrs    mstatus, t0
        li      a0, 4
        vsetvli t0, a0, e32, m1, ta, ma
        vid.v   v2
        jal     ra, T1
        j       R1
T1:     vfmv.f.s f1, v2
R1:     jal     ra, T2
        j       R2
T2:     vfmv.v.f v4, f1

R2:     li      t0, 0x2000
        csrs    mstatus, t0
        csrwi   fflags, 0
        li      t0, 0x3f800000
        fmv.w.x f1, t0
        li      t0, 0xc0400000
        fmv.w.x f2, t0
        li      t0, 0x7f7fffff
        fmv.w.x f3, t0
        li      t0, 0x7f800001
        fmv.w.x f4, t0
        li      t0, 0x80000000
        fmv.w.x f5, t0

        vid.v   v3
        vsll.vi v3, v3, 23
        li      t1, 0x3faaaaab
        vadd.vx v1, v3, t1
        li      t1, 0x40490fdb
        vadd.vx v2, v3, t1
        li      t1, 0x7fc00000
        vmv.v.x v7, t1
        li      t1, 0xff800001
        vmv.s.x v7, t1
        li      t1, 0x5
        vmv.v.x v0, t1

        li      a0, 8
        vsetvli t0, a0, e16, m1, ta, ma
        jal     ra, T3
        j       R3
T3:     vfmerge.vfm v10, v1, f1, v0
R3:     jal     ra, T4
        j       R4
T4:     vfmv.v.f v10, f1
R4:     jal     ra, T5
        j       R5
T5:     vfmv.s.f v10, f1
R5:     jal     ra, T6
        j       R6
T6:     vfmv.f.s f6, v1
R6:     li      a0, 16
        vsetvli t0, a0, e8, m1, ta, ma
        jal     ra, T7
        j       R7
T7:     vfmv.f.s f6, v1

R7:     li      a0, 4
        vsetvli t0, a0, e32, m1, ta, ma
        csrwi   frm, 5
        jal     ra, T8
        j       R8
T8:     vfmerge.vfm v10, v1, f1, v0
R8:     csrwi   frm, 6
        jal     ra, T9
        j       R9
T9:     vfmv.f.s f6, v1
R9:     csrwi   frm, 7
        jal     ra, T10
        j       R10
T10:    vfmv.s.f v10, f1
R10:    jal     ra, T11
        j       R11
T11:    vfmv.v.f v10, f1
R11:    csrwi   frm, 0

        jal     ra, T12
        j       R12
T12:    .word   0x4000d257
R12:    jal     ra, T13
        j       R13
T13:    .word   0x402012d7
R13:    jal     ra, T14
        j       R14
T14:    .word   0x5e30d257
R14:    jal     ra, T15
        j       R15
T15:    .word   0x5c20d057
R15:    jal     ra, T16
        j       R16
T16:    .word   0x4220d257
R16:    jal     ra, T17
        j       R17
T17:    .word   0x422092d7

R17:    vfmerge.vfm v10, v1, f1, v0
        vfmerge.vfm v11, v7, f4, v0
        vfmv.v.f v12, f2
        vfmv.v.f v13, f4
        vmv.v.v v14, v2
        vfmv.s.f v14, f3
        vmv.v.v v15, v2
        vfmv.s.f v15, f5
        vfmv.v.f v0, f5
        li      t1, 0xa
        vmv.v.x v0, t1
        vfmerge.vfm v16, v16, f2, v0

        vfmv.f.s f6, v10
        fadd.s  f7, f6, f1
        vfmv.f.s f8, v11
        fmv.x.w a1, f8
        vfmv.f.s f9, v7
        fsgnj.s f10, f9, f9
        vfmv.f.s f11, v14
        fmul.s  f12, f11, f1
        vfmv.f.s f13, v12
        vfadd.vf v17, v1, f13
        vfadd.vv v18, v1, v2
        vfmv.f.s f14, v18
        feq.s   a2, f14, f14

        fdiv.s  f15, f2, f1
        vfmv.f.s f16, v10
        fadd.s  f17, f16, f15
        fdiv.s  f18, f1, f2
        vfmv.f.s f18, v12
        fmv.x.w a3, f18
        fsqrt.s f19, f1
        vfmerge.vfm v19, v1, f19, v0
        vfmv.f.s f20, v19

        li      a0, 3
        vsetvli t0, a0, e32, m1, ta, ma
        vfmerge.vfm v10, v2, f2, v0
        vfmv.v.f v11, f1
        vfmv.s.f v12, f1
        vfmv.f.s f21, v10

        li      a0, 0
        vsetvli t0, a0, e32, m1, ta, ma
        vfmerge.vfm v10, v1, f1, v0
        vfmv.v.f v11, f2
        vfmv.s.f v12, f3
        vfmv.f.s f22, v2
        fadd.s  f23, f22, f1

        li      t1, 0x5a5a
        li      a0, 4
        vsetvli t0, a0, e32, m1, ta, ma
        vmv.v.x v0, t1

        li      a0, 8
        vsetvli t0, a0, e32, m2, ta, ma
        vfmerge.vfm v20, v2, f2, v0
        vfmv.v.f v22, f3
        vfmv.s.f v25, f1
        vfmv.f.s f24, v21

        li      a0, 16
        vsetvli t0, a0, e32, m4, ta, ma
        vfmerge.vfm v8, v20, f1, v0
        vfmv.v.f v12, f4
        vfmv.s.f v17, f2
        vfmv.f.s f25, v9

        li      a0, 32
        vsetvli t0, a0, e32, m8, ta, ma
        vfmerge.vfm v16, v8, f5, v0
        vfmv.v.f v24, f2
        vfmv.s.f v3, f3
        vfmv.f.s f26, v19
        fmax.s  f27, f26, f25
        li      a0, 13
        vsetvli t0, a0, e32, m8, ta, ma
        vfmerge.vfm v24, v16, f1, v0
        vfmv.v.f v8, f3
        csrr    a4, fflags

        li      a0, 4
        vsetvli t0, a0, e32, m1, ta, ma
        li      t0, 0x6000
        csrc    mstatus, t0
        li      t0, 0x4000
        csrs    mstatus, t0
        csrr    s1, mstatus
        vfmerge.vfm v10, v1, f1, v0
        csrr    s2, mstatus
        vfmv.v.f v11, f1
        vfmv.s.f v12, f1
        csrr    s3, mstatus
        vfmv.f.s f28, v10
        csrr    s4, mstatus
        fmv.x.w s5, f28
        csrr    s6, fcsr

Ldone:  beq     x0, x0, Ldone

handler:
        csrr    t3, mcause
        csrw    mepc, ra
        mret
