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
        vmv.v.x v15, t1
        li      t1, 0xa
        vmv.v.x v0, t1
        vfclass.v v15, v1, v0.t
        csrr    a2, fflags

        li      a0, 0
        vsetvli t0, a0, e32, m1, tu, mu
        vfclass.v v14, v2
        vfclass.v v15, v4
        li      a0, 4
        vsetvli t0, a0, e32, m1, tu, mu
        csrr    a3, fflags

        vmv.v.v v16, v1
        vmv.v.v v17, v2
        vmv.v.v v18, v3
        vmv.v.v v19, v4
        vmv.v.v v20, v3
        vmv.v.v v21, v2
        vmv.v.v v22, v1
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
        li      a0, 29
        vsetvli t0, a0, e32, m8, tu, mu
        vmv.v.x v8, x0
        vfclass.v v8, v16
        csrr    a4, fflags

        vfclass.v v16, v8
        vfadd.vv v24, v16, v8
        vfclass.v v8, v24
        csrr    a5, fflags
        csrwi   fflags, 0

        li      a0, 4
        vsetvli t0, a0, e32, m1, tu, mu
        csrwi   frm, 5
        jal     ra, T1
        j       R1
T1:     vfclass.v v10, v1
R1:     csrwi   frm, 0
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
