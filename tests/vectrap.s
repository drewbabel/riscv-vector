        .section .text
        .globl _start
_start:
        jal     t0, Lvec
        j       handler
Lvec:   csrw    mtvec, t0
        li      t0, 0x200
        csrs    mstatus, t0
        lui     s0, 0x80008
        li      t1, 0x11223344
        sw      t1, 0(s0)
        sw      t1, 4(s0)
        sw      t1, 8(s0)
        sw      t1, 12(s0)

        # Illegal while vill
        jal     ra, T1
        j       R1
T1:     vle8.v  v1, (s0)
R1:     jal     ra, T2
        j       R2
T2:     vse8.v  v1, (s0)
R2:     .word   0x02840107

        # Group too wide
        li      a0, 4
        vsetvli t0, a0, e8, m8, tu, mu
        jal     ra, T3
        j       R3
T3:     vle32.v v2, (s0)

        # Reserved forms
R3:     li      a0, 4
        vsetvli t0, a0, e32, m1, tu, mu
        jal     ra, T5
        j       R5
T5:     .word   0x02047087
R5:     jal     ra, T6
        j       R6
T6:     .word   0x02845127
R6:     vle32.v v3, (s0)
        lw      t2, 0(s0)

        # Vector state off
        li      t0, 0x600
        csrc    mstatus, t0
        jal     ra, T7
        j       R7
T7:     vle32.v v4, (s0)
R7:     lw      t2, 4(s0)
Ldone:  beq     x0, x0, Ldone

handler:
        csrr    t3, mcause
        csrw    mepc, ra
        mret
