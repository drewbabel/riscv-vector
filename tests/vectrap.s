        .section .text
        .globl _start
_start:
        jal     t0, Lvec
        j       handler
Lvec:   csrw    mtvec, t0
        li      t0, 0x200
        csrs    mstatus, t0
        lui     s0, 0x80008
        li      t1, 0x11223344
        sw      t1, 0(s0)
        sw      t1, 4(s0)
        sw      t1, 8(s0)
        sw      t1, 12(s0)

        # Illegal while vill
        jal     ra, T1
        j       R1
T1:     vle8.v  v1, (s0)
R1:     jal     ra, T2
        j       R2
T2:     vse8.v  v1, (s0)
R2:     .word   0x02840107
        jal     ra, T45
        j       R45
T45:    vmv1r.v v3, v1
R45:    jal     ra, T46
        j       R46
T46:    vmv2r.v v2, v2
R46:

        # Group too wide
        li      a0, 4
        vsetvli t0, a0, e8, m8, tu, mu
        jal     ra, T3
        j       R3
T3:     vle32.v v2, (s0)

        # Reserved forms
R3:     li      a0, 4
        vsetvli t0, a0, e32, m1, tu, mu
        jal     ra, T5
        j       R5
T5:     .word   0x02047087
R5:     jal     ra, T6
        j       R6
T6:     .word   0x02845127
R6:     vle32.v v3, (s0)
        lw      t2, 0(s0)

        # Reserved register numbers
        li      a0, 8
        vsetvli t0, a0, e8, m4, tu, mu
        jal     ra, T8
        j       R8
T8:     .word   0x028200d7
R8:     vsetvli t0, a0, e8, m1, tu, mu
        jal     ra, T9
        j       R9
T9:     .word   0xc220a157
R9:     jal     ra, T10
        j       R10
T10:    .word   0x00820057
R10:    jal     ra, T11
        j       R11
T11:    .word   0xc620a157
R11:    jal     ra, T12
        j       R12
T12:    .word   0xc6208157
R12:    vsetvli t0, a0, e8, m4, tu, mu
        jal     ra, T13
        j       R13
T13:    .word   0x026120d7
R13:    vsetvli t0, a0, e8, m1, tu, mu
        lw      t2, 8(s0)

        # Mask destination overlap
        vsetvli t0, a0, e8, m2, tu, mu
        li      t1, 0x5a
        jal     ra, T14
        j       R14
T14:    vmseq.vv   v9, v8, v4
R14:    jal     ra, T15
        j       R15
T15:    vmslt.vv   v5, v8, v4
R15:    jal     ra, T16
        j       R16
T16:    vmsgtu.vi  v9, v8, 3
R16:    jal     ra, T17
        j       R17
T17:    vmsne.vx   v9, v8, t1
R17:    jal     ra, T18
        j       R18
T18:    vmadc.vvm  v9, v8, v4, v0
R18:    jal     ra, T19
        j       R19
T19:    vmsbc.vx   v9, v8, t1
R19:    vmseq.vv   v8, v8, v4
        vmadc.vv   v4, v8, v4
        vmsltu.vx  v12, v8, t1
        vsetvli t0, a0, e8, m1, tu, mu
        lw      t2, 12(s0)

        # Unmasked carry forms
        jal     ra, T20
        j       R20
T20:    .insn r 0x57, 0, 0x21, x3, x2, x1
R20:    jal     ra, T21
        j       R21
T21:    .insn r 0x57, 4, 0x21, x3, x6, x1
R21:    jal     ra, T22
        j       R22
T22:    .insn r 0x57, 3, 0x21, x3, x5, x1
R22:    jal     ra, T23
        j       R23
T23:    .insn r 0x57, 0, 0x25, x3, x2, x1
R23:    jal     ra, T24
        j       R24
T24:    .insn r 0x57, 4, 0x25, x3, x6, x1
R24:    vadc.vvm   v3, v1, v2, v0
        vsbc.vxm   v5, v1, t1, v0
        vmadc.vv   v6, v1, v2
        lw      t2, 0(s0)

        # Nonzero vstart
        li      a0, 4
        vsetvli t0, a0, e32, m1, tu, mu
        csrwi   vstart, 1
        jal     ra, T25
        j       R25
T25:    vadd.vv    v3, v1, v2
R25:    jal     ra, T26
        j       R26
T26:    vmsbf.m    v6, v5
R26:    jal     ra, T27
        j       R27
T27:    viota.m    v6, v5
R27:    jal     ra, T28
        j       R28
T28:    vid.v      v6
R28:    jal     ra, T29
        j       R29
T29:    vcpop.m    a1, v5
R29:    jal     ra, T30
        j       R30
T30:    vfirst.m   a1, v5
R30:    jal     ra, T31
        j       R31
T31:    vmv.x.s    a1, v1
R31:    jal     ra, T32
        j       R32
T32:    vmv.s.x    v6, a1
R32:    jal     ra, T33
        j       R33
T33:    vmand.mm   v6, v5, v4
R33:    jal     ra, T34
        j       R34
T34:    vmseq.vv   v6, v1, v2
R34:    jal     ra, T35
        j       R35
T35:    vmul.vv    v6, v1, v2
R35:    jal     ra, T36
        j       R36
T36:    vmv1r.v    v6, v1
R36:    jal     ra, T37
        j       R37
T37:    vmerge.vvm v6, v1, v2, v0
R37:    csrr    t5, vstart
        csrwi   vstart, 0
        vadd.vv    v3, v1, v2
        vmsbf.m    v6, v5
        viota.m    v7, v5
        vid.v      v6
        vcpop.m    a1, v5
        vfirst.m   a1, v5
        vmv1r.v    v6, v1
        lw      t2, 4(s0)

        # Mask unary overlap
        jal     ra, T38
        j       R38
T38:    .word   0x5250a2d7
R38:    jal     ra, T39
        j       R39
T39:    .word   0x5051a057
R39:    jal     ra, T40
        j       R40
T40:    .word   0x527123d7
R40:    vmsbf.m    v6, v5
        vmsif.m    v0, v5
        vmsof.m    v6, v5, v0.t
        vsetvli t0, a0, e32, m4, tu, mu
        jal     ra, T41
        j       R41
T41:    .word   0x52982457
R41:    jal     ra, T42
        j       R42
T42:    .word   0x52882457
R42:    viota.m    v8, v12
        vsetvli t0, a0, e32, m1, tu, mu
        lw      t2, 8(s0)

        # Reserved vid source
        jal     ra, T43
        j       R43
T43:    .word   0x5238a457
R43:    jal     ra, T44
        j       R44
T44:    .word   0x5108a457
R44:    vid.v      v8
        lw      t2, 12(s0)

        # Vector state off
        li      t0, 0x600
        csrc    mstatus, t0
        jal     ra, T7
        j       R7
T7:     vle32.v v4, (s0)
R7:     lw      t2, 4(s0)
Ldone:  beq     x0, x0, Ldone

handler:
        csrr    t3, mcause
        csrw    mepc, ra
        mret
