        .section .text
        .globl _start
_start:
        jal     t0, Lvec
        j       handler
Lvec:   csrw    mtvec, t0

        li      t0, 0x2200
        csrs    mstatus, t0
        csrwi   fcsr, 0
        lui     s0, 0x80008
        sw      zero, 64(s0)
        sw      zero, 84(s0)
        li      t1, 0x00000001
        sw      t1, 12(s0)
        sw      t1, 92(s0)
        li      t1, 0x00400000
        sw      t1, 120(s0)
        li      t1, 0x00800000
        sw      t1, 72(s0)
        li      t1, 0x0d800000
        sw      t1, 124(s0)
        li      t1, 0x33800000
        sw      t1, 108(s0)
        li      t1, 0x3eaaaaab
        sw      t1, 4(s0)
        li      t1, 0x3effffff
        sw      t1, 116(s0)
        li      t1, 0x3f800000
        sw      t1, 0(s0)
        sw      t1, 52(s0)
        li      t1, 0x3f800001
        sw      t1, 112(s0)
        li      t1, 0x3fffffff
        sw      t1, 96(s0)
        li      t1, 0x40490fdb
        sw      t1, 16(s0)
        li      t1, 0x4b000001
        sw      t1, 100(s0)
        li      t1, 0x7f7fffff
        sw      t1, 8(s0)
        sw      t1, 24(s0)
        li      t1, 0x7f800000
        sw      t1, 40(s0)
        sw      t1, 48(s0)
        sw      t1, 60(s0)
        li      t1, 0x7f800001
        sw      t1, 36(s0)
        li      t1, 0x7fc00000
        sw      t1, 32(s0)
        li      t1, 0x80000000
        sw      t1, 68(s0)
        sw      t1, 80(s0)
        li      t1, 0x80000003
        sw      t1, 28(s0)
        li      t1, 0x807fffff
        sw      t1, 76(s0)
        li      t1, 0x80800000
        sw      t1, 88(s0)
        li      t1, 0xbf800000
        sw      t1, 20(s0)
        li      t1, 0xcb7fffff
        sw      t1, 104(s0)
        li      t1, 0xff800000
        sw      t1, 44(s0)
        sw      t1, 56(s0)
        li      a0, 32
        vsetvli t0, a0, e32, m8, tu, mu
        vle32.v v8, (s0)
        flw     f1, 4(s0)
        flw     f2, 16(s0)
        flw     f3, 32(s0)
        flw     f4, 36(s0)
        flw     f5, 40(s0)
        flw     f6, 52(s0)
        flw     f7, 12(s0)
        flw     f8, 8(s0)
        flw     f9, 20(s0)
        flw     f10, 120(s0)
        flw     f11, 0(s0)
        li      a0, 4
        vsetvli t0, a0, e32, m1, tu, mu

        vfadd.vv v16, v8, v9
        csrrwi  a1, fflags, 0
        vfadd.vv v17, v10, v11
        csrrwi  a1, fflags, 0
        vfadd.vv v18, v12, v13
        csrrwi  a1, fflags, 0
        vfadd.vv v19, v14, v15
        csrrwi  a1, fflags, 0
        vfadd.vv v20, v12, v15
        csrrwi  a1, fflags, 0
        vfadd.vf v21, v8, f1
        csrrwi  a1, fflags, 0
        vfadd.vf v22, v10, f4
        csrrwi  a1, fflags, 0
        vfadd.vf v23, v12, f6
        csrrwi  a1, fflags, 0
        vfadd.vf v24, v11, f5
        csrrwi  a1, fflags, 0
        vfsub.vv v16, v8, v9
        csrrwi  a1, fflags, 0
        vfsub.vv v17, v11, v10
        csrrwi  a1, fflags, 0
        vfsub.vv v18, v12, v12
        csrrwi  a1, fflags, 0
        vfsub.vv v19, v14, v15
        csrrwi  a1, fflags, 0
        vfsub.vv v20, v13, v12
        csrrwi  a1, fflags, 0
        vfsub.vf v21, v9, f8
        csrrwi  a1, fflags, 0
        vfsub.vf v22, v11, f5
        csrrwi  a1, fflags, 0
        vfsub.vf v23, v13, f6
        csrrwi  a1, fflags, 0
        vfrsub.vf v16, v8, f2
        csrrwi  a1, fflags, 0
        vfrsub.vf v17, v10, f3
        csrrwi  a1, fflags, 0
        vfrsub.vf v18, v12, f6
        csrrwi  a1, fflags, 0
        vfrsub.vf v19, v11, f5
        csrrwi  a1, fflags, 0
        vfmul.vv v16, v8, v9
        csrrwi  a1, fflags, 0
        vfmul.vv v17, v10, v12
        csrrwi  a1, fflags, 0
        vfmul.vv v18, v11, v12
        csrrwi  a1, fflags, 0
        vfmul.vv v19, v14, v15
        csrrwi  a1, fflags, 0
        vfmul.vv v20, v12, v15
        csrrwi  a1, fflags, 0
        vfmul.vv v21, v13, v9
        csrrwi  a1, fflags, 0
        vfmul.vf v22, v8, f7
        csrrwi  a1, fflags, 0
        vfmul.vf v23, v15, f8
        csrrwi  a1, fflags, 0
        vfmul.vf v24, v12, f5
        csrrwi  a1, fflags, 0
        vfmul.vf v25, v9, f10
        csrrwi  a1, fflags, 0

        li      t1, 0x3
        vmv.s.x v0, t1
        vfmul.vv v16, v8, v9, v0.t
        csrrwi  a1, fflags, 0
        li      t1, 0x1
        vmv.s.x v0, t1
        vfadd.vf v17, v10, f1, v0.t
        csrrwi  a1, fflags, 0
        li      t1, 0x5
        vmv.s.x v0, t1
        vfadd.vv v18, v10, v11, v0.t
        csrrwi  a1, fflags, 0
        vfsub.vv v19, v12, v13, v0.t
        csrrwi  a1, fflags, 0
        li      t1, 0xa
        vmv.s.x v0, t1
        vfsub.vf v20, v8, f8, v0.t
        csrrwi  a1, fflags, 0
        vfrsub.vf v21, v12, f6, v0.t
        csrrwi  a1, fflags, 0
        vfmul.vf v22, v15, f7, v0.t
        csrrwi  a1, fflags, 0
        li      t1, 0x9
        vmv.s.x v0, t1
        vfmul.vv v23, v11, v12, v0.t
        csrrwi  a1, fflags, 0

        li      a0, 8
        vsetvli t0, a0, e32, m2, tu, mu
        vfadd.vv v16, v8, v10
        csrrwi  a1, fflags, 0
        vfadd.vf v18, v12, f1
        csrrwi  a1, fflags, 0
        vfsub.vv v20, v14, v12
        csrrwi  a1, fflags, 0
        vfsub.vf v22, v10, f5
        csrrwi  a1, fflags, 0
        vfrsub.vf v24, v8, f8
        csrrwi  a1, fflags, 0
        vfmul.vv v26, v8, v14
        csrrwi  a1, fflags, 0
        vfmul.vf v28, v12, f10
        csrrwi  a1, fflags, 0
        li      t1, 0xa5
        vmv.s.x v0, t1
        vfadd.vv v16, v10, v12, v0.t
        csrrwi  a1, fflags, 0
        vfsub.vf v18, v8, f4, v0.t
        csrrwi  a1, fflags, 0
        vfrsub.vf v20, v14, f2, v0.t
        csrrwi  a1, fflags, 0
        vfmul.vv v22, v8, v8, v0.t
        csrrwi  a1, fflags, 0
        li      t1, 0x5a
        vmv.s.x v0, t1
        vfmul.vf v24, v10, f6, v0.t
        csrrwi  a1, fflags, 0
        li      a0, 7
        vsetvli t0, a0, e32, m2, tu, mu
        vfadd.vv v26, v8, v14
        csrrwi  a1, fflags, 0
        vfmul.vv v28, v12, v14, v0.t
        csrrwi  a1, fflags, 0
        li      a0, 3
        vsetvli t0, a0, e32, m1, tu, mu
        vfsub.vv v16, v10, v11
        csrrwi  a1, fflags, 0
        vfmul.vf v17, v9, f8
        csrrwi  a1, fflags, 0
        li      a0, 0
        vsetvli t0, a0, e32, m1, tu, mu
        vfadd.vv v18, v10, v11
        csrrwi  a1, fflags, 0
        vfmul.vf v19, v10, f4
        csrrwi  a1, fflags, 0

Ldone:  beq     x0, x0, Ldone

handler:
        csrr    t3, mcause
        csrw    mepc, ra
        mret
