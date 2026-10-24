        .section .text
        .globl _start

        .macro  vset4 vr, a, b, c, d
        li      t1, \a
        vmv.v.x \vr, t1
        li      t1, 2
        vmv.v.x v0, t1
        li      t1, \b
        vmerge.vxm \vr, \vr, t1, v0
        li      t1, 4
        vmv.v.x v0, t1
        li      t1, \c
        vmerge.vxm \vr, \vr, t1, v0
        li      t1, 8
        vmv.v.x v0, t1
        li      t1, \d
        vmerge.vxm \vr, \vr, t1, v0
        .endm

        .macro  cvtall
        vfcvt.xu.f.v v10, v1
        vfcvt.x.f.v v11, v1
        vfcvt.x.f.v v12, v2
        vfcvt.xu.f.v v13, v3
        vfcvt.x.f.v v14, v3
        vfcvt.f.xu.v v15, v4
        vfcvt.f.x.v v16, v4
        vfcvt.f.x.v v17, v5
        .endm

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

        vset4   v1, 0x3fc00000, 0xc0200000, 0x4f800000, 0xcf000001
        vset4   v2, 0x7fc00000, 0xff800000, 0x3f000000, 0x80000001
        vset4   v3, 0x477fff80, 0x46ffff00, 0xc7000080, 0xbf000000
        vset4   v4, 0x00000007, 0xffffffff, 0x80000000, 0x7fffffff
        vset4   v5, 0x0001ffff, 0x8000ffff, 0x12348001, 0x00007fff
        vset4   v6, 0x40400000, 0xbfc00000, 0x7f800001, 0x4b000001

        csrwi   frm, 0
        cvtall
        csrr    s2, fflags
        csrwi   fflags, 0
        csrwi   frm, 1
        cvtall
        csrr    s3, fflags
        csrwi   fflags, 0
        csrwi   frm, 2
        cvtall
        csrr    s4, fflags
        csrwi   fflags, 0
        csrwi   frm, 3
        cvtall
        csrr    s5, fflags
        csrwi   fflags, 0
        csrwi   frm, 4
        cvtall
        csrr    s6, fflags
        csrwi   fflags, 0

        csrwi   frm, 3
        vfcvt.rtz.xu.f.v v10, v1
        vfcvt.rtz.x.f.v v11, v1
        vfcvt.rtz.x.f.v v12, v3
        vfcvt.rtz.xu.f.v v13, v6
        csrr    s7, fflags
        csrwi   fflags, 0

        li      t1, 0x5
        vmv.v.x v0, t1
        li      t1, 0xdeadbeef
        vmv.v.x v26, t1
        vmv.v.x v27, t1
        vfcvt.x.f.v v26, v2, v0.t
        vfcvt.f.xu.v v27, v4, v0.t
        csrr    s8, fflags
        csrwi   fflags, 0

        vmv.v.v v16, v1
        vmv.v.v v17, v2
        vmv.v.v v18, v3
        vmv.v.v v19, v6
        li      a0, 14
        vsetvli t0, a0, e32, m4, tu, mu
        li      t1, 0x96a5
        vmv.s.x v0, t1
        vfcvt.x.f.v v24, v16
        vfcvt.f.x.v v28, v16, v0.t
        vfcvt.rtz.xu.f.v v20, v16, v0.t
        csrr    s9, fflags
        csrwi   fflags, 0

        li      a0, 0
        vsetvli t0, a0, e32, m1, tu, mu
        vfcvt.x.f.v v10, v2
        vfcvt.f.x.v v11, v2
        csrr    s10, fflags

        li      a0, 8
        vsetvli t0, a0, e16, m1, tu, mu
        jal     ra, T1
        j       R1
T1:     vfcvt.x.f.v v10, v1
R1:     jal     ra, T2
        j       R2
T2:     vfcvt.f.xu.v v10, v1
R2:     li      a0, 4
        vsetvli t0, a0, e32, m1, tu, mu
        csrwi   frm, 5
        jal     ra, T3
        j       R3
T3:     vfcvt.rtz.x.f.v v10, v1
R3:     jal     ra, T4
        j       R4
T4:     vfcvt.f.x.v v10, v1
R4:     csrwi   frm, 0
        csrr    s11, fflags
        csrr    s1, mcause

Ldone:  beq     x0, x0, Ldone

handler:
        csrr    t3, mcause
        csrw    mepc, ra
        mret
