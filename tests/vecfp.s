        .section .text
        .globl _start
_start:
        jal     t0, Lvec
        j       handler
Lvec:   csrw    mtvec, t0

        li      t0, 0x200
        csrs    mstatus, t0
        li      a0, 4
        vsetvli t0, a0, e32, m1, ta, ma
        jal     ra, T1
        j       R1
T1:     vfadd.vv v1, v2, v3

R1:     li      t0, 0x2000
        csrs    mstatus, t0
        csrwi   fflags, 0
        li      t0, 0x3f800000
        fmv.w.x f1, t0
        li      t0, 0xc0400000
        fmv.w.x f2, t0
        li      t0, 0x7f7fffff
        fmv.w.x f3, t0
        li      t0, 0x7f800001
        fmv.w.x f4, t0

        li      a0, 8
        vsetvli t0, a0, e16, m1, ta, ma
        jal     ra, T2
        j       R2
T2:     vfadd.vv v1, v2, v3
R2:     li      a0, 4
        vsetvli t0, a0, e32, m1, ta, ma
        csrwi   frm, 5
        jal     ra, T3
        j       R3
T3:     vfmul.vv v1, v2, v3
R3:     csrwi   frm, 0

        vid.v   v3
        vsll.vi v3, v3, 23
        li      t1, 0x3faaaaab
        vadd.vx v1, v3, t1
        li      t1, 0x40490fdb
        vadd.vx v2, v3, t1
        li      t1, 0x80000000
        vxor.vx v5, v2, t1
        vxor.vx v6, v1, t1
        li      t1, 0x7f7fffff
        vmv.v.x v7, t1
        li      t1, 0x7f800001
        vmv.s.x v7, t1
        li      t1, 0x00800000
        vmv.v.x v8, t1

        vfadd.vv v10, v1, v2
        vfadd.vf v11, v1, f1
        vfsub.vv v12, v1, v2
        vfsub.vf v13, v2, f2
        vfrsub.vf v14, v1, f2
        vfmul.vv v15, v1, v6
        vfmul.vf v16, v7, f3
        vfmul.vv v17, v8, v8
        csrr    a1, fflags
        csrwi   fflags, 0

        vmv.v.v v18, v1
        vfmacc.vv v18, v2, v6
        vmv.v.v v19, v1
        vfnmacc.vf v19, f1, v2
        vmv.v.v v20, v1
        vfmsac.vv v20, v2, v1
        vmv.v.v v21, v1
        vfnmsac.vf v21, f2, v2
        vmv.v.v v22, v1
        vfmadd.vv v22, v2, v6
        vmv.v.v v23, v1
        vfnmadd.vf v23, f1, v2
        vmv.v.v v24, v1
        vfmsub.vv v24, v2, v6
        vmv.v.v v25, v1
        vfnmsub.vf v25, f2, v2
        csrr    a2, fflags
        csrwi   fflags, 0

        vfmin.vv v26, v1, v7
        vfmax.vf v27, v7, f4
        vfsgnj.vv v28, v1, v6
        vfsgnjn.vf v29, v1, f2
        vfsgnjx.vv v30, v6, v5
        csrr    a3, fflags
        csrwi   fflags, 0

        vmfeq.vv v9, v1, v1
        vmfne.vf v9, v7, f4
        vmflt.vv v9, v1, v2
        vmfle.vf v9, v7, f1
        vmfgt.vf v9, v2, f1
        vmfge.vf v9, v7, f3
        csrr    a4, fflags

        li      t1, 0x9
        vmv.v.x v0, t1
        csrwi   fflags, 0
        vfmul.vf v16, v7, f3, v0.t
        csrr    a5, fflags
        li      t1, 0x6
        vmv.v.x v0, t1
        csrwi   fflags, 0
        vfadd.vv v10, v7, v7, v0.t
        csrr    a6, fflags
        vmflt.vv v9, v7, v1, v0.t

        csrwi   frm, 1
        vfadd.vv v11, v1, v2
        csrwi   frm, 2
        vfmul.vv v12, v1, v2
        csrwi   frm, 3
        vfmacc.vv v18, v1, v2
        csrwi   frm, 4
        vfsub.vf v13, v1, f2
        csrwi   frm, 0

        fadd.s  f5, f1, f2
        vfadd.vf v14, v1, f5
        fmul.s  f6, f3, f3
        vfmul.vf v15, v2, f6

        li      a0, 3
        vsetvli t0, a0, e32, m1, ta, ma
        vfadd.vv v10, v1, v2
        vmfle.vv v9, v1, v2

        li      a0, 8
        vsetvli t0, a0, e32, m2, ta, ma
        vfmacc.vv v18, v20, v22
        vfadd.vv v24, v20, v2

        li      a0, 32
        vsetvli t0, a0, e32, m8, ta, ma
        vfmul.vv v8, v16, v24
        vfadd.vv v16, v24, v8
        csrwi   frm, 1
        vfsub.vv v24, v8, v16
        csrwi   frm, 0
        csrr    a7, fcsr

        li      a0, 4
        vsetvli t0, a0, e32, m1, ta, ma
        li      t0, 0x6000
        csrc    mstatus, t0
        li      t0, 0x4000
        csrs    mstatus, t0
        csrr    s1, mstatus
        vfsgnj.vv v11, v1, v1
        csrr    s2, mstatus
        vfadd.vv v11, v1, v2
        csrr    s3, mstatus
        vfmul.vv v12, v1, v2
        li      t0, 0x6000
        csrc    mstatus, t0
        li      t0, 0x4000
        csrs    mstatus, t0
        csrr    s4, mstatus
        li      t0, 0x2000
        csrs    mstatus, t0
        csrr    s5, fflags

Ldone:  beq     x0, x0, Ldone

handler:
        csrr    t3, mcause
        csrw    mepc, ra
        mret
