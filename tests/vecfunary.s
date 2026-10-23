        .section .text
        .globl _start
_start:
        jal     t0, Lvec
        j       handler
Lvec:   csrw    mtvec, t0

        li      t0, 0x2200
        csrs    mstatus, t0
        csrwi   fflags, 0
        csrwi   frm, 0
        li      a0, 4
        vsetvli t0, a0, e32, m1, tu, mu

        li      t1, 0xff800000
        vmv.v.x v1, t1
        li      t1, 0x00000000
        vmv.v.x v2, t1
        li      t1, 0x7f800001
        vmv.v.x v3, t1
        li      t1, 0x00800000
        vmv.v.x v4, t1
        li      t1, 0x00718abc
        vmv.v.x v5, t1
        li      t1, 0x00200000
        vmv.v.x v9, t1

        li      t1, 2
        vmv.v.x v0, t1
        li      t1, 0xbf800000
        vmerge.vxm v1, v1, t1, v0
        li      t1, 0x007fffff
        vmerge.vxm v2, v2, t1, v0
        li      t1, 0x7fc00000
        vmerge.vxm v3, v3, t1, v0
        li      t1, 0x807fffff
        vmerge.vxm v4, v4, t1, v0
        li      t1, 0x7f765432
        vmerge.vxm v5, v5, t1, v0
        li      t1, 0x00400000
        vmerge.vxm v9, v9, t1, v0

        li      t1, 4
        vmv.v.x v0, t1
        li      t1, 0x80000001
        vmerge.vxm v1, v1, t1, v0
        li      t1, 0x7f7fffff
        vmerge.vxm v2, v2, t1, v0
        li      t1, 0xffc00001
        vmerge.vxm v3, v3, t1, v0
        li      t1, 0x7fbfffff
        vmerge.vxm v4, v4, t1, v0
        li      t1, 0x00000001
        vmerge.vxm v5, v5, t1, v0
        li      t1, 0x7f000000
        vmerge.vxm v9, v9, t1, v0

        li      t1, 8
        vmv.v.x v0, t1
        li      t1, 0x80000000
        vmerge.vxm v1, v1, t1, v0
        li      t1, 0x7f800000
        vmerge.vxm v2, v2, t1, v0
        li      t1, 0xff800001
        vmerge.vxm v3, v3, t1, v0
        li      t1, 0xff7fffff
        vmerge.vxm v4, v4, t1, v0
        li      t1, 0x80000001
        vmerge.vxm v5, v5, t1, v0
        li      t1, 0x7e800000
        vmerge.vxm v9, v9, t1, v0

        vfclass.v v10, v1
        vfclass.v v11, v2
        vfclass.v v12, v3
        vfclass.v v13, v4
        csrr    a1, fflags

        li      t1, 0xdeadbeef
        vmv.v.x v14, t1
        li      t1, 0x5
        vmv.v.x v0, t1
        vfclass.v v14, v3, v0.t
        vfrsqrt7.v v15, v1, v0.t
        csrr    a2, fflags
        csrwi   fflags, 0
        li      t1, 0xc
        vmv.v.x v0, t1
        vfrec7.v v12, v2, v0.t
        vfrsqrt7.v v13, v1, v0.t
        csrr    t4, fflags
        csrwi   fflags, 0

        li      a0, 0
        vsetvli t0, a0, e32, m1, tu, mu
        vfclass.v v14, v2
        vfrec7.v v15, v2
        vfrsqrt7.v v14, v1
        li      a0, 4
        vsetvli t0, a0, e32, m1, tu, mu
        csrr    a3, fflags

        csrwi   frm, 0
        vfrec7.v v10, v5
        vfrec7.v v11, v9
        vfrec7.v v12, v2
        csrr    s2, fflags
        csrwi   fflags, 0
        csrwi   frm, 1
        vfrec7.v v10, v5
        vfrec7.v v11, v9
        vfrec7.v v12, v2
        csrr    s3, fflags
        csrwi   fflags, 0
        csrwi   frm, 2
        vfrec7.v v10, v5
        vfrec7.v v11, v9
        vfrec7.v v12, v2
        csrr    s4, fflags
        csrwi   fflags, 0
        csrwi   frm, 3
        vfrec7.v v10, v5
        vfrec7.v v11, v9
        vfrec7.v v12, v2
        csrr    s5, fflags
        csrwi   fflags, 0
        csrwi   frm, 4
        vfrec7.v v10, v5
        vfrec7.v v11, v9
        vfrec7.v v12, v2
        csrr    s6, fflags
        csrwi   fflags, 0
        csrwi   frm, 0
        vfrec7.v v13, v1
        vfrec7.v v14, v3
        vfrec7.v v15, v4
        csrr    s7, fflags
        csrwi   fflags, 0
        vfrsqrt7.v v10, v1
        vfrsqrt7.v v11, v2
        vfrsqrt7.v v12, v3
        vfrsqrt7.v v13, v4
        vfrsqrt7.v v14, v5
        vfrsqrt7.v v15, v9
        csrr    s8, fflags
        csrwi   fflags, 0

        vmv.v.v v16, v1
        vmv.v.v v17, v2
        vmv.v.v v18, v3
        vmv.v.v v19, v4
        vmv.v.v v20, v5
        vmv.v.v v21, v9
        vmv.v.v v22, v3
        vmv.v.v v23, v4
        li      a0, 32
        vsetvli t0, a0, e32, m8, tu, mu
        vid.v   v24
        li      t1, 0x96692c4d
        vmv.s.x v0, t1
        li      t1, 0x80000000
        vxor.vx v16, v16, t1, v0.t

        vfclass.v v8, v16
        li      t1, 0x2d3c4b5a
        vmv.s.x v0, t1
        vfclass.v v24, v16, v0.t
        csrwi   frm, 2
        vfrec7.v v8, v16, v0.t
        csrr    s9, fflags
        csrwi   fflags, 0
        vfrsqrt7.v v24, v16
        csrr    s10, fflags
        csrwi   fflags, 0
        li      a0, 29
        vsetvli t0, a0, e32, m8, tu, mu
        csrwi   frm, 3
        vfrec7.v v8, v16
        vfrsqrt7.v v24, v16, v0.t
        csrr    s11, fflags
        csrwi   fflags, 0
        csrwi   frm, 0
        vmv.v.x v8, x0
        vfclass.v v8, v16
        csrr    a4, fflags

        vfrec7.v v16, v8
        vfrsqrt7.v v24, v16
        vfclass.v v8, v24
        csrr    a5, fflags
        csrwi   fflags, 0

        li      a0, 4
        vsetvli t0, a0, e32, m1, tu, mu
        csrwi   frm, 5
        jal     ra, T1
        j       R1
T1:     vfclass.v v10, v1
R1:     jal     ra, T4
        j       R4
T4:     vfrec7.v v10, v5
R4:     jal     ra, T5
        j       R5
T5:     vfrsqrt7.v v10, v5
R5:     csrwi   frm, 0
        li      a0, 8
        vsetvli t0, a0, e16, m1, tu, mu
        jal     ra, T2
        j       R2
T2:     vfclass.v v10, v2
R2:     li      a0, 4
        vsetvli t0, a0, e32, m1, tu, mu
        jal     ra, T3
        j       R3
T3:     .word   0x4e185557
R3:     csrr    s1, mcause

Ldone:  beq     x0, x0, Ldone

handler:
        csrr    t3, mcause
        csrw    mepc, ra
        mret
