        .section .text
        .globl _start
_start:
        li      t0, 0x200
        csrs    mstatus, t0

        li      a0, 16
        vsetvli t0, a0, e8, m1, ta, ma
        vid.v   v1
        vsll.vi v1, v1, 4
        li      t1, 0x80
        vmv.v.x v2, t1
        vxor.vv v3, v1, v2
        li      t2, 0x37
        vadd.vx v4, v1, t2

        vsaddu.vv v5, v1, v4
        csrr    a1, vxsat
        csrwi   vxsat, 0
        vsaddu.vv v6, v2, v2
        csrr    a2, vxsat
        csrwi   vxsat, 0
        vsadd.vv v7, v3, v4
        csrr    a3, vxsat
        csrwi   vxsat, 0
        vssubu.vv v8, v4, v1
        csrr    a4, vxsat
        csrwi   vxsat, 0
        vssub.vv v9, v3, v4
        csrr    a5, vxsat
        csrwi   vxsat, 0
        vsadd.vi v10, v3, -7
        vsaddu.vx v11, v1, t2
        vssub.vx v12, v3, t2
        csrr    a6, vxsat
        csrwi   vxsat, 0

        csrwi   vxrm, 0
        vssrl.vi v13, v4, 3
        vssra.vv v14, v3, v1
        vsmul.vv v15, v3, v4
        csrwi   vxrm, 1
        vssrl.vi v16, v4, 3
        vssra.vx v17, v3, t2
        vsmul.vv v18, v3, v4
        csrwi   vxrm, 2
        vssrl.vv v19, v4, v1
        vssra.vi v20, v3, 2
        vsmul.vx v21, v3, t2
        csrwi   vxrm, 3
        vssrl.vx v22, v4, t2
        vssra.vi v23, v3, 5
        vsmul.vv v24, v3, v4
        csrr    a7, vxsat
        csrwi   vxsat, 0
        vsmul.vv v25, v2, v2
        csrr    s2, vxsat
        csrwi   vxsat, 0

        li      a0, 8
        vsetvli t0, a0, e16, m1, ta, ma
        csrwi   vxrm, 0
        vsmul.vv v26, v3, v4
        vsadd.vv v27, v3, v3
        csrr    s3, vxsat
        csrwi   vxsat, 0

        li      a0, 16
        vsetvli t0, a0, e8, m1, ta, ma
        vnclipu.wi v28, v26, 2
        vnclip.wv v29, v26, v1
        csrr    s4, vxsat
        csrwi   vxsat, 0
        csrwi   vxrm, 1
        vnclip.wx v30, v26, t2
        vnclipu.wv v31, v26, v1
        csrr    s5, vxsat
        csrwi   vxsat, 0

        li      a0, 4
        vsetvli t0, a0, e16, m1, ta, ma
        csrwi   vxrm, 3
        vnclip.wi v28, v14, 1
        vnclipu.wx v29, v14, t2
        csrr    s6, vxsat

        li      a0, 4
        vsetvli t0, a0, e32, m1, ta, ma
        csrwi   vxrm, 0
        li      t3, 0x80000000
        vmv.v.x v0, t3
        vsmul.vv v5, v0, v0
        csrr    s7, vxsat
        csrwi   vxsat, 0
        vsadd.vv v6, v0, v0
        vssubu.vx v7, v1, t3
        vssra.vx v8, v3, t2
        csrr    s8, vxsat
        csrr    s9, vcsr

        li      a0, 16
        vsetvli t0, a0, e8, m1, ta, ma
        li      t5, 0x5A5A
        vmv.v.x v0, t5
        csrwi   vxsat, 0
        vsadd.vv v9, v3, v3, v0.t
        vnclipu.wi v10, v26, 0, v0.t
        csrr    s10, vxsat

        csrwi   vxsat, 0
        csrwi   vxrm, 0
        vaaddu.vv v11, v3, v4
        vaadd.vv v12, v3, v4
        vasubu.vv v13, v1, v4
        vasub.vx v14, v3, t2
        csrwi   vxrm, 1
        vaaddu.vx v15, v3, t1
        vaadd.vv v16, v2, v2
        vasubu.vv v17, v4, v1
        vasub.vv v18, v2, v4
        csrwi   vxrm, 2
        vaaddu.vv v19, v2, v3
        vaadd.vx v20, v3, t2
        vasubu.vx v21, v1, t1
        vasub.vv v22, v4, v2
        csrwi   vxrm, 3
        vaaddu.vv v23, v4, v4
        vaadd.vv v24, v3, v1
        vasubu.vv v25, v1, v3
        vasub.vx v26, v2, t2
        vaadd.vv v27, v3, v4, v0.t
        vasubu.vx v28, v4, t2, v0.t

        li      a0, 8
        vsetvli t0, a0, e16, m1, ta, ma
        csrwi   vxrm, 1
        vaaddu.vv v29, v3, v4
        vaadd.vv v30, v3, v3
        vasubu.vx v31, v1, t1
        csrwi   vxrm, 3
        vasub.vv v11, v2, v4

        li      a0, 4
        vsetvli t0, a0, e32, m1, ta, ma
        csrwi   vxrm, 0
        vaaddu.vv v12, v3, v4
        vaadd.vx v13, v3, t3
        csrwi   vxrm, 2
        vasubu.vv v14, v1, v3
        vasub.vx v15, v3, t3
        csrr    s11, vxsat

        li      a0, 32
        vsetvli t0, a0, e8, m2, ta, ma
        csrwi   vxrm, 1
        vaadd.vv v16, v2, v4
        vasubu.vv v18, v4, v2

Ldone:  beq     x0, x0, Ldone
