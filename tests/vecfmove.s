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

        fmv.w.x f12, zero
        li      t1, 0x7fc0abcd
        fmv.w.x f13, t1
        vfmv.v.f v16, f1
        csrrwi  a1, fflags, 0
        vfmv.v.f v17, f4
        csrrwi  a1, fflags, 0
        vfmv.v.f v18, f13
        csrrwi  a1, fflags, 0
        vfmv.v.f v19, f6
        csrrwi  a1, fflags, 0
        vfmv.s.f v20, f3
        csrrwi  a1, fflags, 0
        vfmv.s.f v21, f7
        csrrwi  a1, fflags, 0
        vfmv.f.s f14, v10
        csrrwi  a1, fflags, 0
        vfmv.f.s f15, v11
        csrrwi  a1, fflags, 0
        vfmv.f.s f16, v13
        csrrwi  a1, fflags, 0
        vfmv.f.s f17, v9
        csrrwi  a1, fflags, 0
        li      t1, 0x6
        vmv.s.x v0, t1
        vfmerge.vfm v22, v8, f4, v0
        csrrwi  a1, fflags, 0
        vfmerge.vfm v23, v10, f13, v0
        csrrwi  a1, fflags, 0
        li      t1, 0x9
        vmv.s.x v0, t1
        vfmerge.vfm v24, v12, f6, v0
        csrrwi  a1, fflags, 0
        li      t1, 0x0
        vmv.s.x v0, t1
        vfmerge.vfm v25, v9, f5, v0
        csrrwi  a1, fflags, 0
        fadd.s  f18, f14, f2
        vfmv.v.f v26, f18
        csrrwi  a1, fflags, 0
        vfmv.f.s f19, v26
        csrrwi  a1, fflags, 0
        fmul.s  f20, f19, f19
        vfmv.s.f v27, f20
        csrrwi  a1, fflags, 0

        li      a0, 8
        vsetvli t0, a0, e32, m2, tu, mu
        vfmv.v.f v16, f2
        csrrwi  a1, fflags, 0
        vfmv.s.f v18, f4
        csrrwi  a1, fflags, 0
        vfmv.f.s f21, v12
        csrrwi  a1, fflags, 0
        li      t1, 0xa6
        vmv.s.x v0, t1
        vfmerge.vfm v20, v8, f3, v0
        csrrwi  a1, fflags, 0
        vfmerge.vfm v22, v14, f9, v0
        csrrwi  a1, fflags, 0
        li      a0, 3
        vsetvli t0, a0, e32, m2, tu, mu
        vfmv.v.f v24, f6
        csrrwi  a1, fflags, 0
        vfmerge.vfm v26, v10, f7, v0
        csrrwi  a1, fflags, 0
        li      a0, 0
        vsetvli t0, a0, e32, m1, tu, mu
        vfmv.v.f v16, f1
        csrrwi  a1, fflags, 0
        vfmv.s.f v17, f1
        csrrwi  a1, fflags, 0
        vfmv.f.s f22, v10
        csrrwi  a1, fflags, 0
        vfmerge.vfm v18, v8, f1, v0
        csrrwi  a1, fflags, 0

        li      a0, 4
        vsetvli t0, a0, e32, mf2, tu, mu
        csrr    a2, vtype
        csrr    a3, vl
        jal     ra, T1
        j       R1
T1:     vfadd.vv v16, v8, v9
R1:     csrrwi  a1, fflags, 0
        jal     ra, T2
        j       R2
T2:     vfmv.v.f v16, f1
R2:     csrrwi  a1, fflags, 0
        jal     ra, T3
        j       R3
T3:     vfmv.f.s f23, v8
R3:     csrrwi  a1, fflags, 0
        jal     ra, T4
        j       R4
T4:     vfredusum.vs v16, v8, v9
R4:     csrrwi  a1, fflags, 0
        li      a0, 4
        vsetvli t0, a0, e16, mf2, tu, mu
        jal     ra, T5
        j       R5
T5:     vfmul.vv v16, v8, v9
R5:     csrrwi  a1, fflags, 0
        jal     ra, T6
        j       R6
T6:     vfmerge.vfm v16, v8, f1, v0
R6:     csrrwi  a1, fflags, 0
        li      a0, 4
        vsetvli t0, a0, e8, mf4, tu, mu
        jal     ra, T7
        j       R7
T7:     vmfeq.vv v1, v8, v9
R7:     csrrwi  a1, fflags, 0
        li      a0, 4
        vsetvli t0, a0, e32, m1, tu, mu
        vfadd.vv v16, v8, v9
        csrrwi  a1, fflags, 0

Ldone:  beq     x0, x0, Ldone

handler:
        csrr    t3, mcause
        csrw    mepc, ra
        mret
