        .section .text
        .globl _start
_start:
        jal     t0, Lvec
        j       handler
Lvec:   csrw    mtvec, t0

        li      t0, 0x2200
        csrs    mstatus, t0
        csrwi   fcsr, 0
        lui     s0, 0x80008
        sw      zero, 64(s0)
        sw      zero, 84(s0)
        li      t1, 0x00000001
        sw      t1, 12(s0)
        sw      t1, 92(s0)
        li      t1, 0x00400000
        sw      t1, 120(s0)
        li      t1, 0x00800000
        sw      t1, 72(s0)
        li      t1, 0x0d800000
        sw      t1, 124(s0)
        li      t1, 0x33800000
        sw      t1, 108(s0)
        li      t1, 0x3eaaaaab
        sw      t1, 4(s0)
        li      t1, 0x3effffff
        sw      t1, 116(s0)
        li      t1, 0x3f800000
        sw      t1, 0(s0)
        sw      t1, 52(s0)
        li      t1, 0x3f800001
        sw      t1, 112(s0)
        li      t1, 0x3fffffff
        sw      t1, 96(s0)
        li      t1, 0x40490fdb
        sw      t1, 16(s0)
        li      t1, 0x4b000001
        sw      t1, 100(s0)
        li      t1, 0x7f7fffff
        sw      t1, 8(s0)
        sw      t1, 24(s0)
        li      t1, 0x7f800000
        sw      t1, 40(s0)
        sw      t1, 48(s0)
        sw      t1, 60(s0)
        li      t1, 0x7f800001
        sw      t1, 36(s0)
        li      t1, 0x7fc00000
        sw      t1, 32(s0)
        li      t1, 0x80000000
        sw      t1, 68(s0)
        sw      t1, 80(s0)
        li      t1, 0x80000003
        sw      t1, 28(s0)
        li      t1, 0x807fffff
        sw      t1, 76(s0)
        li      t1, 0x80800000
        sw      t1, 88(s0)
        li      t1, 0xbf800000
        sw      t1, 20(s0)
        li      t1, 0xcb7fffff
        sw      t1, 104(s0)
        li      t1, 0xff800000
        sw      t1, 44(s0)
        sw      t1, 56(s0)
        li      a0, 32
        vsetvli t0, a0, e32, m8, tu, mu
        vle32.v v8, (s0)
        flw     f1, 4(s0)
        flw     f2, 16(s0)
        flw     f3, 32(s0)
        flw     f4, 36(s0)
        flw     f5, 40(s0)
        flw     f6, 52(s0)
        flw     f7, 12(s0)
        flw     f8, 8(s0)
        flw     f9, 20(s0)
        flw     f10, 120(s0)
        flw     f11, 0(s0)
        li      a0, 4
        vsetvli t0, a0, e32, m1, tu, mu

        li      t1, 0x3f800000
        fmv.w.x f12, t1
        csrwi   frm, 5
        jal     ra, T1
        j       R1
T1:     vfadd.vv v16, v8, v9
R1:     csrrwi  a1, fflags, 0
        jal     ra, T2
        j       R2
T2:     vfmv.v.f v17, f1
R2:     csrrwi  a1, fflags, 0
        jal     ra, T3
        j       R3
T3:     vfmerge.vfm v18, v8, f1, v0
R3:     csrrwi  a1, fflags, 0
        jal     ra, T4
        j       R4
T4:     vfsgnj.vv v19, v8, v9
R4:     csrrwi  a1, fflags, 0
        jal     ra, T5
        j       R5
T5:     vmfeq.vv v1, v8, v10
R5:     csrrwi  a1, fflags, 0
        jal     ra, T6
        j       R6
T6:     vfmin.vv v20, v8, v10
R6:     csrrwi  a1, fflags, 0
        jal     ra, T7
        j       R7
T7:     vfredmax.vs v21, v8, v9
R7:     csrrwi  a1, fflags, 0
        jal     ra, T8
        j       R8
T8:     vfmv.f.s f24, v8
R8:     csrrwi  a1, fflags, 0
        jal     ra, T9
        j       R9
T9:     vfmv.s.f v22, f1
R9:     csrrwi  a1, fflags, 0
        jal     ra, T10
        j       R10
T10:    vfmacc.vf v23, f1, v9
R10:    csrrwi  a1, fflags, 0
        csrwi   frm, 6
        jal     ra, T11
        j       R11
T11:    vfadd.vv v16, v8, v9
R11:    csrrwi  a1, fflags, 0
        jal     ra, T12
        j       R12
T12:    vfmv.v.f v17, f1
R12:    csrrwi  a1, fflags, 0
        jal     ra, T13
        j       R13
T13:    vfmerge.vfm v18, v8, f1, v0
R13:    csrrwi  a1, fflags, 0
        jal     ra, T14
        j       R14
T14:    vfsgnj.vv v19, v8, v9
R14:    csrrwi  a1, fflags, 0
        jal     ra, T15
        j       R15
T15:    vmfeq.vv v1, v8, v10
R15:    csrrwi  a1, fflags, 0
        jal     ra, T16
        j       R16
T16:    vfmin.vv v20, v8, v10
R16:    csrrwi  a1, fflags, 0
        jal     ra, T17
        j       R17
T17:    vfredmax.vs v21, v8, v9
R17:    csrrwi  a1, fflags, 0
        csrwi   frm, 7
        jal     ra, T18
        j       R18
T18:    vfadd.vv v16, v8, v9
R18:    csrrwi  a1, fflags, 0
        jal     ra, T19
        j       R19
T19:    vfmv.v.f v17, f1
R19:    csrrwi  a1, fflags, 0
        jal     ra, T20
        j       R20
T20:    vfmerge.vfm v18, v8, f1, v0
R20:    csrrwi  a1, fflags, 0
        jal     ra, T21
        j       R21
T21:    vfsgnj.vv v19, v8, v9
R21:    csrrwi  a1, fflags, 0
        jal     ra, T22
        j       R22
T22:    vmfeq.vv v1, v8, v10
R22:    csrrwi  a1, fflags, 0
        jal     ra, T23
        j       R23
T23:    vfmin.vv v20, v8, v10
R23:    csrrwi  a1, fflags, 0
        jal     ra, T24
        j       R24
T24:    vfredmax.vs v21, v8, v9
R24:    csrrwi  a1, fflags, 0
        csrwi   frm, 0

        vfadd.vv v16, v8, v9
        csrr    a3, fflags
        vfmul.vv v17, v9, v9
        csrr    a3, fflags
        vfmin.vv v18, v8, v10
        csrr    a3, fflags
        vfmul.vf v19, v15, f10
        csrr    a3, fflags
        vfredusum.vs v20, v10, v8
        csrr    a3, fcsr
        csrwi   fflags, 0
        fadd.s  f13, f1, f2
        vfsgnj.vv v21, v8, v10
        csrr    a3, fflags
        vmfeq.vv v1, v10, v10
        csrr    a3, fflags
        vmflt.vv v2, v10, v8
        csrr    a3, fflags
        fdiv.s  f14, f2, f12
        vfmacc.vf v22, f14, v12
        csrr    a3, fflags
        csrwi   fflags, 0x1f
        vfadd.vv v23, v8, v8
        csrr    a3, fflags
        csrwi   fflags, 0
        li      t1, 0x2
        vmv.s.x v0, t1
        vfadd.vv v24, v8, v8, v0.t
        csrr    a3, fflags

Ldone:  beq     x0, x0, Ldone

handler:
        csrr    t3, mcause
        csrw    mepc, ra
        mret
