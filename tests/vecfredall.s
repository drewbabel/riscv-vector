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

        vfredusum.vs v16, v8, v14
        csrrwi  a1, fflags, 0
        vfredosum.vs v17, v8, v14
        csrrwi  a1, fflags, 0
        vfredmax.vs v19, v8, v14
        csrrwi  a1, fflags, 0
        vfredusum.vs v16, v9, v12
        csrrwi  a1, fflags, 0
        vfredmin.vs v18, v9, v12
        csrrwi  a1, fflags, 0
        vfredmax.vs v19, v9, v12
        csrrwi  a1, fflags, 0
        vfredosum.vs v17, v10, v8
        csrrwi  a1, fflags, 0
        vfredmin.vs v18, v10, v8
        csrrwi  a1, fflags, 0
        vfredusum.vs v16, v11, v12
        csrrwi  a1, fflags, 0
        vfredosum.vs v17, v11, v12
        csrrwi  a1, fflags, 0
        vfredmax.vs v19, v11, v12
        csrrwi  a1, fflags, 0
        vfredusum.vs v16, v12, v13
        csrrwi  a1, fflags, 0
        vfredmin.vs v18, v12, v13
        csrrwi  a1, fflags, 0
        vfredmax.vs v19, v12, v13
        csrrwi  a1, fflags, 0
        vfredosum.vs v17, v13, v12
        csrrwi  a1, fflags, 0
        vfredmin.vs v18, v13, v12
        csrrwi  a1, fflags, 0
        vfredusum.vs v16, v14, v15
        csrrwi  a1, fflags, 0
        vfredosum.vs v17, v14, v15
        csrrwi  a1, fflags, 0
        vfredmax.vs v19, v14, v15
        csrrwi  a1, fflags, 0
        vfredusum.vs v16, v15, v11
        csrrwi  a1, fflags, 0
        vfredmin.vs v18, v15, v11
        csrrwi  a1, fflags, 0
        vfredmax.vs v19, v15, v11
        csrrwi  a1, fflags, 0
        vfredusum.vs v16, v8, v10
        csrrwi  a1, fflags, 0
        vfredosum.vs v17, v8, v10
        csrrwi  a1, fflags, 0
        vfredmin.vs v18, v8, v10
        csrrwi  a1, fflags, 0
        vfredmax.vs v19, v8, v10
        csrrwi  a1, fflags, 0

        li      t1, 0x5
        vmv.s.x v0, t1
        vfredusum.vs v20, v10, v8, v0.t
        csrrwi  a1, fflags, 0
        vfredusum.vs v21, v9, v14, v0.t
        csrrwi  a1, fflags, 0
        vfredosum.vs v20, v10, v8, v0.t
        csrrwi  a1, fflags, 0
        vfredosum.vs v21, v9, v14, v0.t
        csrrwi  a1, fflags, 0
        vfredmin.vs v20, v10, v8, v0.t
        csrrwi  a1, fflags, 0
        vfredmin.vs v21, v9, v14, v0.t
        csrrwi  a1, fflags, 0
        vfredmax.vs v20, v10, v8, v0.t
        csrrwi  a1, fflags, 0
        vfredmax.vs v21, v9, v14, v0.t
        csrrwi  a1, fflags, 0
        li      t1, 0x0
        vmv.s.x v0, t1
        vfredusum.vs v22, v10, v10, v0.t
        csrrwi  a1, fflags, 0
        vfredosum.vs v23, v8, v10, v0.t
        csrrwi  a1, fflags, 0
        vfredmin.vs v22, v8, v10, v0.t
        csrrwi  a1, fflags, 0
        vfredmax.vs v23, v8, v13, v0.t
        csrrwi  a1, fflags, 0

        li      a0, 8
        vsetvli t0, a0, e32, m2, tu, mu
        vfredusum.vs v24, v8, v14
        csrrwi  a1, fflags, 0
        vfredusum.vs v25, v12, v13
        csrrwi  a1, fflags, 0
        vfredusum.vs v26, v14, v12
        csrrwi  a1, fflags, 0
        vfredosum.vs v24, v8, v14
        csrrwi  a1, fflags, 0
        vfredosum.vs v25, v12, v13
        csrrwi  a1, fflags, 0
        vfredosum.vs v26, v14, v12
        csrrwi  a1, fflags, 0
        vfredmin.vs v24, v8, v14
        csrrwi  a1, fflags, 0
        vfredmin.vs v25, v12, v13
        csrrwi  a1, fflags, 0
        vfredmin.vs v26, v14, v12
        csrrwi  a1, fflags, 0
        vfredmax.vs v24, v8, v14
        csrrwi  a1, fflags, 0
        vfredmax.vs v25, v12, v13
        csrrwi  a1, fflags, 0
        vfredmax.vs v26, v14, v12
        csrrwi  a1, fflags, 0
        li      t1, 0x69
        vmv.s.x v0, t1
        vfredusum.vs v27, v8, v15, v0.t
        csrrwi  a1, fflags, 0
        vfredusum.vs v28, v10, v12, v0.t
        csrrwi  a1, fflags, 0
        vfredosum.vs v27, v8, v15, v0.t
        csrrwi  a1, fflags, 0
        vfredosum.vs v28, v10, v12, v0.t
        csrrwi  a1, fflags, 0
        vfredmin.vs v27, v8, v15, v0.t
        csrrwi  a1, fflags, 0
        vfredmin.vs v28, v10, v12, v0.t
        csrrwi  a1, fflags, 0
        vfredmax.vs v27, v8, v15, v0.t
        csrrwi  a1, fflags, 0
        vfredmax.vs v28, v10, v12, v0.t
        csrrwi  a1, fflags, 0
        li      a0, 5
        vsetvli t0, a0, e32, m2, tu, mu
        vfredusum.vs v29, v12, v8
        csrrwi  a1, fflags, 0
        vfredosum.vs v29, v12, v8
        csrrwi  a1, fflags, 0
        vfredmin.vs v29, v12, v8
        csrrwi  a1, fflags, 0
        vfredmax.vs v29, v12, v8
        csrrwi  a1, fflags, 0
        li      a0, 0
        vsetvli t0, a0, e32, m1, tu, mu
        vfredosum.vs v30, v10, v10
        csrrwi  a1, fflags, 0
        vfredmax.vs v31, v10, v10
        csrrwi  a1, fflags, 0

Ldone:  beq     x0, x0, Ldone

handler:
        csrr    t3, mcause
        csrw    mepc, ra
        mret
