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

        vmv.v.v v16, v10
        vfmacc.vv v16, v11, v12
        csrrwi  a1, fflags, 0
        vmv.v.v v17, v14
        vfnmacc.vv v17, v8, v9
        csrrwi  a1, fflags, 0
        vmv.v.v v18, v13
        vfmsac.vv v18, v12, v12
        csrrwi  a1, fflags, 0
        vmv.v.v v19, v10
        vfnmsac.vv v19, v11, v12
        csrrwi  a1, fflags, 0
        vmv.v.v v20, v14
        vfmadd.vv v20, v8, v9
        csrrwi  a1, fflags, 0
        vmv.v.v v21, v13
        vfnmadd.vv v21, v12, v12
        csrrwi  a1, fflags, 0
        vmv.v.v v22, v10
        vfmsub.vv v22, v11, v12
        csrrwi  a1, fflags, 0
        vmv.v.v v23, v14
        vfnmsub.vv v23, v8, v9
        csrrwi  a1, fflags, 0
        vmv.v.v v24, v14
        vfmacc.vf v24, f5, v9
        csrrwi  a1, fflags, 0
        vmv.v.v v25, v13
        vfnmacc.vf v25, f1, v12
        csrrwi  a1, fflags, 0
        vmv.v.v v26, v10
        vfmsac.vf v26, f6, v12
        csrrwi  a1, fflags, 0
        vmv.v.v v27, v14
        vfnmsac.vf v27, f7, v9
        csrrwi  a1, fflags, 0
        vmv.v.v v28, v13
        vfmadd.vf v28, f4, v12
        csrrwi  a1, fflags, 0
        vmv.v.v v29, v10
        vfnmadd.vf v29, f8, v12
        csrrwi  a1, fflags, 0
        vmv.v.v v30, v14
        vfmsub.vf v30, f3, v9
        csrrwi  a1, fflags, 0
        vmv.v.v v31, v13
        vfnmsub.vf v31, f9, v12
        csrrwi  a1, fflags, 0
        vmv.v.v v16, v10
        vfmacc.vv v16, v11, v12
        csrrwi  a1, fflags, 0
        vmv.v.v v17, v12
        vfmadd.vv v17, v11, v10
        csrrwi  a1, fflags, 0
        vmv.v.v v18, v15
        vfnmsub.vf v18, f10, v12
        csrrwi  a1, fflags, 0
        vmv.v.v v19, v13
        vfmsac.vf v19, f11, v13
        csrrwi  a1, fflags, 0

        li      t1, 0x5
        vmv.s.x v0, t1
        vmv.v.v v16, v13
        vfmacc.vv v16, v12, v12, v0.t
        csrrwi  a1, fflags, 0
        vmv.v.v v17, v10
        vfnmacc.vf v17, f4, v12, v0.t
        csrrwi  a1, fflags, 0
        vmv.v.v v18, v14
        vfmsac.vv v18, v8, v9, v0.t
        csrrwi  a1, fflags, 0
        vmv.v.v v19, v13
        vfnmsac.vf v19, f8, v12, v0.t
        csrrwi  a1, fflags, 0
        li      t1, 0xa
        vmv.s.x v0, t1
        vmv.v.v v20, v10
        vfmadd.vv v20, v11, v12, v0.t
        csrrwi  a1, fflags, 0
        vmv.v.v v21, v14
        vfnmadd.vf v21, f3, v9, v0.t
        csrrwi  a1, fflags, 0
        vmv.v.v v22, v13
        vfmsub.vv v22, v12, v12, v0.t
        csrrwi  a1, fflags, 0
        vmv.v.v v23, v10
        vfnmsub.vf v23, f7, v12, v0.t
        csrrwi  a1, fflags, 0

        li      a0, 8
        vsetvli t0, a0, e32, m2, tu, mu
        vmv.v.v v16, v14
        vfmacc.vv v16, v8, v10
        csrrwi  a1, fflags, 0
        vmv.v.v v18, v12
        vfnmacc.vf v18, f1, v14
        csrrwi  a1, fflags, 0
        vmv.v.v v20, v8
        vfmsac.vv v20, v10, v12
        csrrwi  a1, fflags, 0
        vmv.v.v v22, v10
        vfnmsac.vf v22, f8, v8
        csrrwi  a1, fflags, 0
        vmv.v.v v24, v14
        vfmadd.vv v24, v8, v10
        csrrwi  a1, fflags, 0
        vmv.v.v v26, v12
        vfnmadd.vf v26, f6, v14
        csrrwi  a1, fflags, 0
        vmv.v.v v28, v8
        vfmsub.vv v28, v10, v12
        csrrwi  a1, fflags, 0
        vmv.v.v v30, v10
        vfnmsub.vf v30, f10, v8
        csrrwi  a1, fflags, 0
        li      t1, 0x96
        vmv.s.x v0, t1
        vfmacc.vv v16, v10, v12, v0.t
        csrrwi  a1, fflags, 0
        vfnmadd.vf v18, f8, v8, v0.t
        csrrwi  a1, fflags, 0
        vfmsub.vv v20, v14, v10, v0.t
        csrrwi  a1, fflags, 0
        vfnmsac.vf v22, f4, v12, v0.t
        csrrwi  a1, fflags, 0
        li      a0, 6
        vsetvli t0, a0, e32, m2, tu, mu
        vfmadd.vv v24, v8, v14
        csrrwi  a1, fflags, 0
        vfnmacc.vf v26, f2, v10, v0.t
        csrrwi  a1, fflags, 0
        li      a0, 0
        vsetvli t0, a0, e32, m1, tu, mu
        vfmacc.vv v16, v10, v11
        csrrwi  a1, fflags, 0
        vfnmsub.vf v17, f4, v10
        csrrwi  a1, fflags, 0

Ldone:  beq     x0, x0, Ldone

handler:
        csrr    t3, mcause
        csrw    mepc, ra
        mret
