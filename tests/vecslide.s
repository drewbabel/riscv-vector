        .section .text
        .globl _start
_start:
        jal     t0, Lvec
        j       handler
Lvec:   csrw    mtvec, t0

        li      t0, 0x2200
        csrs    mstatus, t0
        li      a0, 128
        vsetvli t0, a0, e8, m8, ta, ma
        vid.v   v8
        li      t1, 37
        vmul.vx v8, v8, t1
        vadd.vi v8, v8, 5
        vid.v   v16
        li      t1, 0xA3
        vxor.vx v16, v16, t1
        li      a0, 4
        vsetvli t0, a0, e32, m1, ta, ma
        li      t1, 0x5A3C96E1
        vmv.v.x v0, t1
        li      t1, 0x0F0F1234
        vmv.v.x v24, t1
        vmv.v.x v25, t1
        vmv.v.x v26, t1
        vmv.v.x v27, t1

        li      a0, 16
        vsetvli t0, a0, e8, m1, ta, ma
        li      t2, 3
        vslideup.vx   v1, v8, t2
        vslidedown.vx v2, v8, t2
        vslideup.vi   v3, v9, 0
        vslidedown.vi v4, v9, 31
        li      t3, 0x1F3
        vslide1up.vx   v5, v10, t3
        vslide1down.vx v6, v10, t3
        vslideup.vi    v7, v11, 7, v0.t
        vslidedown.vx  v24, v11, t2, v0.t

        li      a0, 11
        vsetvli t0, a0, e16, m2, ta, ma
        li      t2, 5
        vslideup.vx    v26, v8, t2
        vslidedown.vx  v28, v8, t2
        vslide1up.vx   v30, v12, t3, v0.t
        vslide1down.vx v2, v12, t3

        li      a0, 128
        vsetvli t0, a0, e8, m8, ta, ma
        li      t2, 21
        vslidedown.vx v16, v16, t2
        li      t2, 77
        vslideup.vx   v24, v8, t2
        vslide1down.vx v8, v8, t3

        li      a0, 32
        vsetvli t0, a0, e32, m8, ta, ma
        li      t2, 9
        vslidedown.vx v24, v16, t2, v0.t
        vslideup.vx   v8, v16, t2
        li      t2, 40
        vslidedown.vx v16, v8, t2
        li      t2, -1
        vslidedown.vx v24, v8, t2
        vslideup.vx   v16, v24, t2

        li      a0, 8
        vsetvli t0, a0, e16, mf2, ta, ma
        li      t2, 2
        vslidedown.vx v1, v9, t2
        vslideup.vx   v2, v9, t2
        vslide1down.vx v3, v9, t3
        li      a0, 4
        vsetvli t0, a0, e8, mf4, ta, ma
        vslidedown.vi v4, v10, 1
        vslide1up.vx  v5, v10, t3

        li      a0, 0
        vsetvli t0, a0, e32, m1, ta, ma
        vslideup.vi    v6, v10, 1
        vslide1down.vx v7, v10, t3

        li      a0, 4
        vsetvli t0, a0, e32, m1, ta, ma
        li      t1, 0x3fc00000
        fmv.w.x f1, t1
        li      t1, 0xff800000
        fmv.w.x f2, t1
        vfslide1up.vf   v1, v9, f1
        vfslide1down.vf v2, v9, f2
        vfslide1up.vf   v3, v9, f2, v0.t
        li      a0, 13
        vsetvli t0, a0, e32, m4, ta, ma
        vfslide1down.vf v12, v16, f1
        vfslide1up.vf   v20, v16, f2
        vfslide1down.vf v16, v16, f1, v0.t
        vadd.vv v20, v20, v12
        vslidedown.vi v4, v20, 3
        vadd.vv v8, v4, v16

        li      a0, 4
        vsetvli t0, a0, e32, m1, ta, ma
        li      t2, 1
        jal     ra, T1
        j       R1
T1:     vslideup.vx v9, v9, t2
R1:     jal     ra, T2
        j       R2
T2:     vfslide1up.vf v10, v10, f1
R2:     vsetvli t0, a0, e16, m1, ta, ma
        jal     ra, T3
        j       R3
T3:     vfslide1down.vf v11, v12, f1
R3:     li      a0, 8
        vsetvli t0, a0, e32, m2, ta, ma
        jal     ra, T4
        j       R4
T4:     vslidedown.vi v12, v13, 1
R4:     vmv.x.s s1, v1
        vmv.x.s s2, v2

Ldone:  beq     x0, x0, Ldone

handler:
        csrr    t3, mcause
        csrw    mepc, ra
        mret
