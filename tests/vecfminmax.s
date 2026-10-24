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

        vfmin.vv v16, v8, v10
        csrrwi  a1, fflags, 0
        vfmin.vv v17, v12, v13
        csrrwi  a1, fflags, 0
        vfmin.vv v18, v10, v10
        csrrwi  a1, fflags, 0
        vfmin.vv v19, v9, v12
        csrrwi  a1, fflags, 0
        vfmin.vf v20, v8, f3
        csrrwi  a1, fflags, 0
        vfmin.vf v21, v9, f4
        csrrwi  a1, fflags, 0
        vfmin.vf v22, v12, f6
        csrrwi  a1, fflags, 0
        vfmax.vv v16, v8, v10
        csrrwi  a1, fflags, 0
        vfmax.vv v17, v12, v13
        csrrwi  a1, fflags, 0
        vfmax.vv v18, v10, v10
        csrrwi  a1, fflags, 0
        vfmax.vv v19, v9, v12
        csrrwi  a1, fflags, 0
        vfmax.vf v20, v8, f3
        csrrwi  a1, fflags, 0
        vfmax.vf v21, v9, f4
        csrrwi  a1, fflags, 0
        vfmax.vf v22, v13, f6
        csrrwi  a1, fflags, 0
        vfsgnj.vv v16, v8, v9
        csrrwi  a1, fflags, 0
        vfsgnj.vv v17, v10, v13
        csrrwi  a1, fflags, 0
        vfsgnj.vf v18, v10, f6
        csrrwi  a1, fflags, 0
        vfsgnjn.vv v19, v12, v13
        csrrwi  a1, fflags, 0
        vfsgnjn.vv v20, v10, v10
        csrrwi  a1, fflags, 0
        vfsgnjn.vf v21, v9, f9
        csrrwi  a1, fflags, 0
        vfsgnjx.vv v22, v9, v13
        csrrwi  a1, fflags, 0
        vfsgnjx.vv v23, v10, v9
        csrrwi  a1, fflags, 0
        vfsgnjx.vf v24, v10, f9
        csrrwi  a1, fflags, 0

        vmfeq.vv v1, v8, v9
        csrrwi  a1, fflags, 0
        vmfeq.vv v2, v10, v10
        csrrwi  a1, fflags, 0
        vmfeq.vv v3, v12, v13
        csrrwi  a1, fflags, 0
        vmfeq.vf v4, v10, f3
        csrrwi  a1, fflags, 0
        vmfne.vv v1, v10, v10
        csrrwi  a1, fflags, 0
        vmfne.vv v2, v12, v13
        csrrwi  a1, fflags, 0
        vmfne.vf v3, v8, f4
        csrrwi  a1, fflags, 0
        vmflt.vv v1, v8, v9
        csrrwi  a1, fflags, 0
        vmflt.vv v2, v12, v13
        csrrwi  a1, fflags, 0
        vmflt.vv v3, v10, v11
        csrrwi  a1, fflags, 0
        vmflt.vf v4, v9, f8
        csrrwi  a1, fflags, 0
        vmfle.vv v1, v12, v13
        csrrwi  a1, fflags, 0
        vmfle.vv v2, v9, v8
        csrrwi  a1, fflags, 0
        vmfle.vf v3, v10, f5
        csrrwi  a1, fflags, 0
        vmfgt.vf v4, v8, f1
        csrrwi  a1, fflags, 0
        vmfgt.vf v5, v13, f6
        csrrwi  a1, fflags, 0
        vmfgt.vf v6, v11, f3
        csrrwi  a1, fflags, 0
        vmfge.vf v1, v8, f8
        csrrwi  a1, fflags, 0
        vmfge.vf v2, v12, f6
        csrrwi  a1, fflags, 0
        vmfge.vf v3, v9, f4
        csrrwi  a1, fflags, 0

        li      t1, 0x5
        vmv.s.x v0, t1
        vfmin.vv v16, v8, v10, v0.t
        csrrwi  a1, fflags, 0
        vfmax.vf v17, v9, f4, v0.t
        csrrwi  a1, fflags, 0
        vfsgnjn.vv v18, v10, v12, v0.t
        csrrwi  a1, fflags, 0
        vmfeq.vv v1, v8, v10, v0.t
        csrrwi  a1, fflags, 0
        vmflt.vv v2, v8, v10, v0.t
        csrrwi  a1, fflags, 0
        li      t1, 0x9
        vmv.s.x v0, t1
        vfmax.vv v19, v10, v13, v0.t
        csrrwi  a1, fflags, 0
        vfsgnjx.vf v20, v8, f9, v0.t
        csrrwi  a1, fflags, 0
        vmfne.vf v3, v10, f4, v0.t
        csrrwi  a1, fflags, 0
        vmfle.vv v4, v11, v10, v0.t
        csrrwi  a1, fflags, 0
        vmfge.vf v5, v14, f3, v0.t
        csrrwi  a1, fflags, 0

        li      a0, 8
        vsetvli t0, a0, e32, m2, tu, mu
        vfmin.vv v16, v8, v12
        csrrwi  a1, fflags, 0
        vfmax.vv v18, v10, v14
        csrrwi  a1, fflags, 0
        vfmin.vf v20, v10, f4
        csrrwi  a1, fflags, 0
        vfsgnj.vv v22, v12, v8
        csrrwi  a1, fflags, 0
        vfsgnjn.vf v24, v10, f6
        csrrwi  a1, fflags, 0
        vfsgnjx.vv v26, v8, v10
        csrrwi  a1, fflags, 0
        vmfeq.vv v1, v8, v10
        csrrwi  a1, fflags, 0
        vmflt.vv v2, v12, v14
        csrrwi  a1, fflags, 0
        vmfle.vf v3, v8, f8
        csrrwi  a1, fflags, 0
        vmfgt.vf v4, v10, f2
        csrrwi  a1, fflags, 0
        vmfne.vv v5, v10, v10
        csrrwi  a1, fflags, 0
        vmfge.vf v6, v12, f6
        csrrwi  a1, fflags, 0
        li      t1, 0xc3
        vmv.s.x v0, t1
        vfmax.vf v16, v8, f3, v0.t
        csrrwi  a1, fflags, 0
        vfsgnjx.vv v18, v10, v12, v0.t
        csrrwi  a1, fflags, 0
        vmflt.vf v1, v10, f5, v0.t
        csrrwi  a1, fflags, 0
        vmfeq.vv v2, v8, v12, v0.t
        csrrwi  a1, fflags, 0
        li      a0, 5
        vsetvli t0, a0, e32, m2, tu, mu
        vfmin.vv v20, v10, v8
        csrrwi  a1, fflags, 0
        vmfle.vv v3, v8, v14
        csrrwi  a1, fflags, 0
        li      a0, 0
        vsetvli t0, a0, e32, m1, tu, mu
        vfmin.vv v21, v10, v10
        csrrwi  a1, fflags, 0
        vmflt.vv v4, v10, v10
        csrrwi  a1, fflags, 0

Ldone:  beq     x0, x0, Ldone

handler:
        csrr    t3, mcause
        csrw    mepc, ra
        mret
