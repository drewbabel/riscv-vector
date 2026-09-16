        .section .text
        .globl _start
_start:
        li      t0, 0x200
        csrs    mstatus, t0
        lui     s0, 0x80008

        # Fill the source
        li      t0, 100
        mv      t1, s0
        li      t2, 7
Lfill:  sb      t2, 0(t1)
        addi    t2, t2, 13
        addi    t1, t1, 1
        addi    t0, t0, -1
        bnez    t0, Lfill

        # Vector copy
        addi    a0, s0, 128
        mv      a1, s0
        li      a2, 100
Lcopy:  vsetvli t0, a2, e8, m1, ta, ma
        vle8.v  v1, (a1)
        vse8.v  v1, (a0)
        add     a1, a1, t0
        add     a0, a0, t0
        sub     a2, a2, t0
        bnez    a2, Lcopy

        # Compare bytes
        li      t0, 100
        mv      t1, s0
        addi    t2, s0, 128
        li      x28, 1
Lchk:   lbu     t3, 0(t1)
        lbu     t4, 0(t2)
        beq     t3, t4, Lok
        li      x28, 0
Lok:    addi    t1, t1, 1
        addi    t2, t2, 1
        addi    t0, t0, -1
        bnez    t0, Lchk
Ldone:  beq     x0, x0, Ldone
