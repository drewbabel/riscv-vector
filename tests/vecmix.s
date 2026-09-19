        .section .text
        .globl _start
_start:
        li      t0, 0x200
        csrs    mstatus, t0

        li      a0, 16
        vsetvli t0, a0, e8, m1, ta, ma
        li      t1, 0x817F03FF
        vmv.v.x v1, t1
        li      t2, 0x0F10F0A5
        vmv.v.x v2, t2
        li      t3, 5

        vwaddu.vv v4, v1, v2
        vwadd.vv  v6, v1, v2
        vwsubu.vv v8, v1, v2
        vwsub.vv  v10, v1, v2
        vwadd.vx  v12, v1, t2
        vwaddu.vx v14, v1, t3
        vwaddu.wv v16, v4, v2
        vwsub.wv  v18, v6, v2
        vwadd.wx  v20, v6, t3

        vnsrl.wv v22, v4, v2
        vnsra.wv v23, v6, v2
        vnsrl.wi v24, v8, 3
        vnsra.wi v25, v10, 7
        vnsrl.wx v26, v4, t3

        li      a0, 8
        vsetvli t0, a0, e16, m1, ta, ma
        vwaddu.vv v4, v1, v2
        vwadd.vv  v6, v1, v2
        vwsubu.vv v8, v1, v2
        vwsub.vv  v10, v1, v2
        vwadd.wv  v12, v4, v2
        vnsrl.wv  v27, v4, v2
        vnsra.wi  v28, v6, 9
        vzext.vf2 v29, v1
        vsext.vf2 v30, v1

        li      a0, 4
        vsetvli t0, a0, e32, m1, ta, ma
        vzext.vf2 v14, v1
        vsext.vf2 v15, v1
        vzext.vf4 v16, v1
        vsext.vf4 v17, v1

        vredsum.vs  v18, v1, v2
        vredand.vs  v19, v1, v2
        vredor.vs   v20, v1, v2
        vredxor.vs  v21, v1, v2
        vredminu.vs v22, v1, v2
        vredmin.vs  v23, v1, v2
        vredmaxu.vs v24, v1, v2
        vredmax.vs  v25, v1, v2

        li      a0, 8
        vsetvli t0, a0, e16, m1, ta, ma
        vwredsum.vs  v26, v1, v2
        vwredsumu.vs v27, v1, v2

        li      a0, 16
        vsetvli t0, a0, e8, m1, ta, ma
        vwredsum.vs  v28, v1, v2
        vredsum.vs   v29, v1, v2

        li      a0, 4
        vsetvli t0, a0, e32, m1, ta, ma
        li      t4, 0xDEADBEEF
        vmv.s.x v30, t4
        vmv.x.s t5, v1
        add     s0, t5, t5
        vmv.x.s s1, v30

        li      a0, 8
        vsetvli t0, a0, e16, m1, ta, ma
        vmv.s.x v31, t4
        vmv.x.s s2, v31

        li      a0, 16
        vsetvli t0, a0, e8, m1, ta, ma
        vmv.s.x v31, t4
        vmv.x.s s3, v31

        li      a0, 4
        vsetvli t0, a0, e32, m1, ta, ma
        li      t6, 0xA
        vmv.v.x v0, t6
        vredsum.vs v2, v1, v2, v0.t
        vzext.vf2 v3, v1, v0.t

        li      a0, 8
        vsetvli t0, a0, e16, m2, ta, ma
        vwadd.vv v8, v4, v6
        vnsrl.wv v12, v8, v4

        li      a0, 3
        vsetvli t0, a0, e32, m1, ta, ma
        vredsum.vs v13, v1, v1

        li      a0, 0
        vsetvli t0, a0, e32, m1, ta, ma
        vredsum.vs v14, v1, v1
        vmv.s.x v15, t4
        vmv.x.s s4, v1

Ldone:  beq     x0, x0, Ldone
