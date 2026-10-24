        .section .text
        .globl _start

        .macro  trap op:vararg
        jal     ra, 1f
        j       2f
1:      \op
2:
        .endm

        .macro  wall
        trap    vfwadd.vv v16, v2, v3
        trap    vfwadd.vf v16, v2, f1
        trap    vfwadd.wv v16, v20, v3
        trap    vfwadd.wf v16, v20, f1
        trap    vfwsub.vv v16, v2, v3
        trap    vfwsub.vf v16, v2, f1
        trap    vfwsub.wv v16, v20, v3
        trap    vfwsub.wf v16, v20, f1
        trap    vfwmul.vv v16, v2, v3
        trap    vfwmul.vf v16, v2, f1
        trap    vfwmacc.vv v16, v2, v3
        trap    vfwmacc.vf v16, f1, v2
        trap    vfwnmacc.vv v16, v2, v3
        trap    vfwnmacc.vf v16, f1, v2
        trap    vfwmsac.vv v16, v2, v3
        trap    vfwmsac.vf v16, f1, v2
        trap    vfwnmsac.vv v16, v2, v3
        trap    vfwnmsac.vf v16, f1, v2
        trap    vfwredusum.vs v16, v2, v3
        trap    vfwredosum.vs v16, v2, v3
        .endm

_start:
        jal     t0, Lvec
        j       handler
Lvec:   csrw    mtvec, t0

        li      t0, 0x2200
        csrs    mstatus, t0
        csrwi   fcsr, 0
        li      t1, 0x3f800000
        fmv.w.x f1, t1
        li      a0, 4
        vsetvli t0, a0, e32, m1, tu, mu
        vmv.v.x v2, t1
        li      t1, 0x40000000
        vmv.v.x v3, t1
        vmv.v.x v16, t1
        vmv.v.x v20, t1

        wall
        csrr    s2, fflags
        li      a0, 8
        vsetvli t0, a0, e16, m1, tu, mu
        wall
        csrr    s3, fflags
        csrr    s1, mcause

Ldone:  beq     x0, x0, Ldone

handler:
        csrr    t3, mcause
        csrw    mepc, ra
        mret
