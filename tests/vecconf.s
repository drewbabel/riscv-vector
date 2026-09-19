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
        li      t4, 2
        csrw    vxrm, t4
        csrr    t5, vxrm
        csrr    t6, vcsr
        csrwi   vxsat, 1
        csrr    t5, vxsat
        csrr    t6, vcsr
        csrsi   vcsr, 4
        csrr    t5, vxrm
        csrr    t6, vxsat
        csrci   vcsr, 1
        csrr    t6, vcsr
        csrrw   t5, vxrm, x0
        csrr    t6, vcsr
        li      a0, 4
        vsetvli t0, a0, e16, m4, ta, ma
        vadd.vv v8, v16, v24
        csrr    t5, vcsr
Ldone:  beq     x0, x0, Ldone
