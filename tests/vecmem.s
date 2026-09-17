        .section .text
        .globl _start
_start:
        li      t0, 0x200
        csrs    mstatus, t0
        lui     s0, 0x80008
        li      t0, 64
        mv      t1, s0
Lclear: sw      zero, 0(t1)
        addi    t1, t1, 4
        addi    t0, t0, -1
        bnez    t0, Lclear
        li      t1, 0x11223344
        sw      t1, 0(s0)
        li      t1, 0x55667788
        sw      t1, 4(s0)
        li      t1, 0x99aabbcc
        sw      t1, 8(s0)
        li      t1, 0xddeeff00
        sw      t1, 12(s0)

        # Unit stride loads
        li      a0, 4
        vsetvli t0, a0, e32, m1, tu, mu
        vle32.v v1, (s0)
        li      a0, 8
        vsetvli t0, a0, e16, m1, tu, mu
        vle16.v v2, (s0)
        li      a0, 16
        vsetvli t0, a0, e8, m1, tu, mu
        vle8.v  v3, (s0)

        # Store then scalar load
        addi    a1, s0, 32
        vse8.v  v3, (a1)
        lw      t2, 32(s0)
        lbu     t3, 47(s0)

        # Write after write
        vse8.v  v1, (a1)
        sw      t1, 32(s0)
        vle8.v  v4, (a1)

        # Scalar store first
        sw      t2, 64(s0)
        addi    a2, s0, 64
        vle8.v  v5, (a2)

        # Two register group
        addi    a3, s0, 4
        vle16.v v6, (a3)

        # Strided both ways
        li      a0, 3
        vsetvli t0, a0, e16, m1, tu, mu
        addi    a4, s0, 20
        li      a5, -4
        vlse16.v v8, (a4), a5
        addi    a4, s0, 96
        li      a5, 6
        vsse16.v v8, (a4), a5
        lw      t4, 96(s0)
        lw      t5, 104(s0)

        # Masked moves
        li      a0, 8
        vsetvli t0, a0, e8, m1, tu, mu
        vle8.v  v0, (s0)
        vle8.v  v9, (s0), v0.t
        addi    a4, s0, 112
        vse8.v  v2, (a4), v0.t
        lw      t4, 112(s0)

        # Whole register moves
        .word   0x02845507
        addi    a4, s0, 116
        .word   0x02870127
        lw      t4, 116(s0)
        lw      t5, 128(s0)

        # Zero length
        li      a0, 0
        vsetvli t0, a0, e8, m1, tu, mu
        vle8.v  v11, (s0)
        vse8.v  v11, (a1)

        # Full queue forwarding
        li      a0, 16
        vsetvli t0, a0, e8, m1, tu, mu
        addi    a6, s0, 136
        vse8.v  v3, (a6)
        addi    a6, s0, 152
        vse8.v  v2, (a6)
        addi    a6, s0, 168
        vse8.v  v1, (a6)
        li      t6, 0x12345678
        sw      t6, 176(s0)
        fence
        lw      t4, 136(s0)
        lw      t5, 176(s0)

        # Held load onto base
        addi    a1, s0, 200
        vse8.v  v3, (a1)
        lw      a1, 0(a1)
        csrr    t4, minstret
Ldone:  beq     x0, x0, Ldone
