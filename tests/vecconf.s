        .section .text
        .globl _start
_start:
        li      t0, 0x200
        csrs    mstatus, t0
        li      a0, 16
        vsetvli t0, a0, e8, m1, ta, ma
        csrr    t1, vl
        csrr    t2, vtype
        csrr    t3, vlenb
        li      a0, 5
        vsetvli t0, a0, e32, m1, ta, ma
        csrr    t1, vl
        csrr    t2, vtype
        li      a0, 200
        vsetvli t0, a0, e16, m2, ta, ma
        csrr    t1, vl
        csrr    t2, vtype
        li      t4, 3
        csrw    vstart, t4
        csrr    t5, vstart
        csrsi   vstart, 4
        csrr    t5, vstart
        csrci   vstart, 1
        csrr    t5, vstart
        li      a0, 8
        vsetvli t0, a0, e8, m1, ta, ma
        csrr    t5, vstart
        csrr    t1, vl
Ldone:  beq     x0, x0, Ldone
