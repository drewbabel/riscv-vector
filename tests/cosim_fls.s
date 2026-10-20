        .section .text
        .globl _start
_start:
        jal     t0, Lvec
        j       handler
Lvec:   csrw    mtvec, t0

        li      t0, 0x2200
        csrs    mstatus, t0
        lui     s0, 0x80008
        li      t0, 64
        mv      t1, s0
Lclear: sw      zero, 0(t1)
        addi    t1, t1, 4
        addi    t0, t0, -1
        bnez    t0, Lclear
        li      t1, 0x3f800000
        sw      t1, 0(s0)
        li      t1, 0x40400000
        sw      t1, 4(s0)
        li      t1, 0xbfc00000
        sw      t1, 8(s0)
        li      t1, 0x7fc00000
        sw      t1, 12(s0)
        addi    t1, s0, 4
        sw      t1, 32(s0)

        # Load use distances
        flw     f1, 0(s0)
        fadd.s  f2, f1, f1
        flw     f3, 4(s0)
        nop
        fmul.s  f4, f3, f1
        flw     f5, 8(s0)
        nop
        nop
        fsub.s  f6, f5, f3
        flw     f7, 12(s0)
        fmadd.s f8, f1, f3, f7
        flw     f9, 8(s0)
        fmadd.s f10, f3, f1, f9
        fmv.x.w a0, f2
        fmv.x.w a1, f10

        # Store a fresh result
        fadd.s  f11, f1, f3
        fsw     f11, 16(s0)
        fmadd.s f12, f3, f3, f1
        fsw     f12, 20(s0)
        fdiv.s  f13, f1, f3
        fsw     f13, 24(s0)
        flw     f14, 4(s0)
        fsw     f14, 28(s0)
        lw      t2, 16(s0)
        lw      t3, 20(s0)
        lw      t4, 24(s0)
        lw      t5, 28(s0)

        # Write after write
        fdiv.s  f15, f1, f3
        flw     f15, 0(s0)
        fsw     f15, 36(s0)
        lw      t6, 36(s0)
        flw     f16, 4(s0)
        fadd.s  f16, f1, f1
        fmv.x.w a2, f16

        # Shared register index
        flw     f10, 4(s0)
        addi    a0, a0, 1
        flw     f11, 8(s0)
        add     a3, a1, a1

        # Integer address chain
        lw      a4, 32(s0)
        flw     f17, 0(a4)
        fsw     f17, 40(a4)
        flw     f18, 40(a4)
        fmv.x.w a5, f18
        addi    s1, s0, 64
        flw     f19, -60(s1)
        fsw     f19, -16(s1)
        lw      a6, 48(s0)

        # Store then load
        fsw     f8, 52(s0)
        flw     f20, 52(s0)
        fadd.s  f21, f20, f20
        fmv.x.w a7, f21

        # Misaligned traps
        jal     ra, T1
        j       R1
T1:     flw     f22, 2(s0)
R1:     mv      s2, t3
        csrr    t4, mtval
        jal     ra, T2
        j       R2
T2:     fsw     f1, 1(s0)
R2:     mv      s3, t3
        csrr    t5, mtval
        lw      s4, 0(s0)

        # Illegal widths
        jal     ra, T3
        j       R3
T3:     .word   0x00043087
R3:     mv      s5, t3
        jal     ra, T4
        j       R4
T4:     .word   0x00143027
R4:     mv      s6, t3

        # Vector memory mix
        li      a0, 4
        vsetvli t0, a0, e32, m1, tu, mu
        vle32.v v1, (s0)
        flw     f23, 4(s0)
        addi    a1, s0, 128
        vse32.v v1, (a1)
        flw     f24, 132(s0)
        fsw     f24, 144(s0)
        addi    a2, s0, 144
        vle32.v v2, (a2)
        fsw     f2, 148(s0)
        vse32.v v2, (a1)
        flw     f25, 128(s0)
        flw     f26, 148(s0)
        fmv.x.w s7, f26

        # Float state field
        li      t0, 0x6000
        csrc    mstatus, t0
        jal     ra, T5
        j       R5
T5:     flw     f27, 0(s0)
R5:     mv      s8, t3
        jal     ra, T6
        j       R6
T6:     fsw     f1, 56(s0)
R6:     mv      s9, t3
        li      t0, 0x4000
        csrs    mstatus, t0
        fsw     f1, 56(s0)
        csrr    t1, mstatus
        srli    t1, t1, 13
        andi    s10, t1, 3
        flw     f28, 56(s0)
        csrr    t1, mstatus
        srli    t1, t1, 13
        andi    s11, t1, 3
        fmv.x.w a0, f28

done:   beq     x0, x0, done

handler:
        csrr    t3, mcause
        csrw    mepc, ra
        mret
