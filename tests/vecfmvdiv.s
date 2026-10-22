        .section .text
        .globl _start
_start:
        li      t0, 0x2200
        csrs    mstatus, t0
        li      t0, 0x40400000
        fmv.w.x f2, t0
        li      t0, 0x3f800000
        fmv.w.x f1, t0
        li      a0, 4
        vsetvli t0, a0, e32, m1, ta, ma
        vid.v   v1
        vsll.vi v1, v1, 23
        li      t1, 0x3fc00000
        vadd.vx v1, v1, t1
        li      s1, 12
        li      s0, 0
L0:     fdiv.s  f3, f2, f1
        mv      t1, s0
D0:     beqz    t1, E0
        addi    t1, t1, -1
        j       D0
E0:
        vfmv.f.s f4, v1
        fadd.s  f5, f4, f3
        fmv.x.w a1, f5
        addi    s0, s0, 1
        blt     s0, s1, L0
        li      s0, 0
L1:     fdiv.s  f3, f2, f1
        mv      t1, s0
D1:     beqz    t1, E1
        addi    t1, t1, -1
        j       D1
E1:
        nop
        vfmv.f.s f4, v1
        fadd.s  f5, f4, f3
        fmv.x.w a1, f5
        addi    s0, s0, 1
        blt     s0, s1, L1
        li      s0, 0
L2:     fdiv.s  f3, f2, f1
        mv      t1, s0
D2:     beqz    t1, E2
        addi    t1, t1, -1
        j       D2
E2:
        nop
        nop
        vfmv.f.s f4, v1
        fadd.s  f5, f4, f3
        fmv.x.w a1, f5
        addi    s0, s0, 1
        blt     s0, s1, L2
        li      s0, 0
L3:     fdiv.s  f3, f2, f1
        mv      t1, s0
D3:     beqz    t1, E3
        addi    t1, t1, -1
        j       D3
E3:
        nop
        nop
        nop
        vfmv.f.s f4, v1
        fadd.s  f5, f4, f3
        fmv.x.w a1, f5
        addi    s0, s0, 1
        blt     s0, s1, L3
Ldone:  beq     x0, x0, Ldone
