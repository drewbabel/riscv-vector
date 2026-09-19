        .section .text
        .globl _start
_start:
        li      t0, 0x200
        csrs    mstatus, t0
        lui     s0, 0x80008
        li      t1, 0x91a2b3c4
        li      t2, 64
        mv      t3, s0
Lfill:  sw      t1, 0(t3)
        slli    t4, t1, 13
        xor     t1, t1, t4
        srli    t4, t1, 17
        xor     t1, t1, t4
        addi    t3, t3, 4
        addi    t2, t2, -1
        bnez    t2, Lfill

        li      a0, 16
        vsetvli t0, a0, e8, m1, tu, mu
        vle8.v  v1, (s0)
        addi    t3, s0, 16
        vle8.v  v2, (t3)
        addi    t3, s0, 32
        vle8.v  v0, (t3)

        vmseq.vv   v3, v1, v2
        vmsne.vv   v4, v1, v2
        vmsltu.vv  v5, v1, v2
        vmslt.vv   v6, v1, v2
        vmsleu.vv  v7, v1, v2
        vmsle.vv   v8, v1, v2
        li      t1, 0x40
        vmsgtu.vx  v9, v1, t1
        vmsgt.vx   v10, v1, t1
        vmseq.vi   v11, v1, 5
        vmsle.vi   v12, v1, -3
        vmsltu.vi  v13, v1, 7

        vmseq.vv   v14, v1, v2, v0.t
        vmslt.vx   v15, v1, t1, v0.t
        vmsgt.vi   v16, v1, 0, v0.t

        vmand.mm   v17, v3, v4
        vmnand.mm  v18, v3, v4
        vmandn.mm  v19, v3, v4
        vmor.mm    v20, v3, v5
        vmnor.mm   v21, v3, v5
        vmorn.mm   v22, v3, v5
        vmxor.mm   v23, v3, v5
        vmxnor.mm  v24, v3, v5

        vmsbf.m    v25, v3
        vmsif.m    v26, v3
        vmsof.m    v27, v3
        vmsbf.m    v28, v3, v0.t
        vmsif.m    v29, v3, v0.t
        vmsof.m    v30, v3, v0.t

        viota.m    v4, v3
        vid.v      v5
        viota.m    v6, v3, v0.t
        vid.v      v7, v0.t

        vcpop.m    a1, v3
        vfirst.m   a2, v3
        vcpop.m    a3, v3, v0.t
        vfirst.m   a4, v3, v0.t

        li      a0, 5
        vsetvli t0, a0, e16, m1, tu, mu
        vmseq.vv   v3, v1, v2
        vmsltu.vx  v4, v1, t1
        vmsbf.m    v8, v3
        viota.m    v9, v3
        vid.v      v10
        vcpop.m    a5, v3
        vfirst.m   a6, v3

        li      a0, 0
        vsetvli t0, a0, e32, m1, tu, mu
        vmseq.vv   v3, v1, v2
        vcpop.m    a7, v3
        vfirst.m   t5, v3

        li      a0, 12
        vsetvli t0, a0, e32, m2, tu, mu
        vmslt.vv   v3, v16, v18
        viota.m    v20, v3
        vid.v      v22
        vcpop.m    t6, v3
        li      a0, 20
        vsetvli t0, a0, e8, m1, tu, mu
        addi    t3, s0, 48
        vlm.v   v11, (t3)
        addi    t3, s0, 64
        vsm.v   v11, (t3)
        li      a0, 8
        vsetvli t0, a0, e16, m2, tu, mu
        addi    t3, s0, 80
        vlm.v   v12, (t3)
        addi    t3, s0, 96
        vsm.v   v12, (t3)
        li      a0, 0
        vsetvli t0, a0, e8, m1, tu, mu
        addi    t3, s0, 112
        vlm.v   v13, (t3)
        vsm.v   v13, (t3)
Ldone:  beq     x0, x0, Ldone
