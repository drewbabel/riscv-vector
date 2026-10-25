        .section .text
        .globl _start
_start:
        jal     t0, Lvec
        j       handler
Lvec:   csrw    mtvec, t0
        li      t1, 0x55
        csrw    mscratch, t1
        li      t5, 0x77
        li      t3, 0

        # Reserved SYSTEM funct3
        jal     ra, T1
        j       R1
T1:     .word   0x340042f3
R1:     mv      t4, t3
        mv      t6, t5
        li      t3, 0
        jal     ra, T2
        j       R2
T2:     .word   0x340f4f73
R2:     mv      t4, t3
        mv      t6, t5
        li      t3, 0
        jal     ra, T3
        j       R3
T3:     .word   0x3000c2f3
R3:     mv      t4, t3
        mv      t6, t5
        li      t3, 0
        jal     ra, T4
        j       R4
T4:     .word   0xc00042f3
R4:     mv      t4, t3
        csrr    t6, mscratch
Ldone:  beq     x0, x0, Ldone

handler:
        csrr    t3, mcause
        csrw    mepc, ra
        mret
