        .section .text
        .globl _start
_start:
        j       Lboot

        # Readbacks
Lmain:  csrw    mtvec, t0
        li      t1, 0x000a5a02
        csrw    mtvec, t1
        csrr    t2, mtvec
        csrw    mtvec, t0
        li      t1, 0x20024080
        csrrw   t2, mscratch, t1
        csrrs   t2, mscratch, t2
        csrrci  t2, mscratch, 0x1f
        li      t1, 0x12345674
        csrw    mepc, t1
        csrr    t2, mepc
        li      t1, 0x0002000a
        csrw    mcause, t1
        csrr    t2, mcause
        li      t1, 0x08020123
        csrw    mtval, t1
        csrr    t2, mtval
        csrr    t2, mie
        li      t1, -1
        csrw    mie, t1
        csrr    t2, mie
        li      t1, 0x888
        csrw    mie, t1
        csrr    t2, mie
        csrr    t2, mip

        # Trap sites
        jal     ra, 1f
        j       2f
1:      .word   0x00000000
2:      csrr    t3, mcause
        jal     ra, 1f
        j       2f
1:      .word   0x0000006d
2:      csrr    t3, mcause
        jal     ra, 1f
        j       2f
1:      .word   0x00000001
2:      jal     ra, 1f
        j       2f
1:      ecall
2:      csrr    t3, mcause
        jal     ra, 1f
        j       2f
1:      ebreak
2:      csrr    t3, mcause
        jal     ra, 1f
        j       2f
1:      csrr    t3, 0x7c0
2:      csrr    t3, mcause
        jal     ra, 1f
        j       2f
1:      csrrw   t3, 0xc30, t1
2:      csrr    t3, mcause
        csrr    t3, mhartid
        csrr    t3, mstatush
        csrr    t2, mstatus

        # Counters
        li      t1, 0x100
        csrw    mcycleh, t1
        csrr    t2, mcycleh
        li      t1, 0x00021f00
        csrw    mcycle, t1
        li      t1, -16
        csrw    minstret, t1
        csrsi   mstatus, 8
        lui     s0, 0x80008
        li      t4, 200
1:      sw      t4, 0(s0)
        lw      t5, 0(s0)
        addi    t4, t4, -1
        bnez    t4, 1b
        csrci   mstatus, 8
        csrr    t2, minstreth
        csrr    t2, mstatus
Ldone:  beq     x0, x0, Ldone

        .org    0x1fc
Lboot:  jal     t0, Lmain
        csrw    mepc, ra
        mret
