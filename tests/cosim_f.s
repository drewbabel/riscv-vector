        .section .text
        .globl _start
_start:
        jal     t0, Lvec
        j       handler
Lvec:   csrw    mtvec, t0

        jal     ra, T1
        j       R1
T1:     fadd.s  f1, f2, f3
R1:     jal     ra, T2
        j       R2
T2:     csrr    a0, fflags
R2:     jal     ra, T3
        j       R3
T3:     fmv.w.x f1, zero

R3:     li      t0, 0x2000
        csrs    mstatus, t0
        csrr    t1, mstatus
        srli    t1, t1, 13
        andi    s1, t1, 3

        fmv.w.x f0, zero
        li      t0, 0x3f800000
        fmv.w.x f1, t0
        csrr    t1, mstatus
        srli    t1, t1, 13
        andi    s2, t1, 3
        li      t0, 0x40400000
        fmv.w.x f2, t0
        li      t0, 0xbfc00000
        fmv.w.x f3, t0
        li      t0, 0x7f7fffff
        fmv.w.x f4, t0
        li      t0, 0x00800000
        fmv.w.x f5, t0
        li      t0, 0x7fc00000
        fmv.w.x f6, t0
        li      t0, 0x7f800001
        fmv.w.x f7, t0
        li      t0, 0x80000000
        fmv.w.x f8, t0
        li      t0, 0x3eaaaaab
        fmv.w.x f9, t0
        li      t0, 0x4b800001
        fmv.w.x f10, t0

        fadd.s  f11, f1, f2
        fsub.s  f12, f1, f2
        fmul.s  f13, f2, f3
        fadd.s  f14, f11, f12
        fmul.s  f15, f14, f13
        fadd.s  f16, f15, f1
        csrr    a0, fflags

        fdiv.s  f17, f1, f2
        fadd.s  f18, f1, f1
        fadd.s  f19, f2, f2
        fmul.s  f20, f2, f2
        fadd.s  f21, f18, f19
        fsub.s  f22, f17, f1
        csrr    a1, fflags
        csrw    fflags, zero

        fmadd.s  f23, f1, f2, f3
        fmsub.s  f24, f2, f9, f1
        fnmsub.s f25, f2, f9, f1
        fnmadd.s f26, f3, f2, f1
        fmadd.s  f27, f23, f24, f25
        csrr    a2, fflags

        fsqrt.s f28, f2
        fsqrt.s f29, f3
        csrr    a3, fflags
        fdiv.s  f30, f1, f8
        csrr    a4, fflags
        fmul.s  f31, f4, f2
        csrr    a5, fflags
        fmul.s  f31, f5, f9
        csrr    a6, fcsr
        csrw    fcsr, zero

        fmin.s  f11, f1, f3
        fmax.s  f12, f1, f3
        fmin.s  f13, f6, f2
        fmax.s  f14, f7, f2
        fmin.s  f15, f8, f0
        csrr    a7, fflags
        fsgnj.s  f16, f2, f3
        fsgnjn.s f17, f2, f3
        fsgnjx.s f18, f3, f3

        fclass.s s3, f1
        fclass.s s4, f3
        fclass.s s5, f6
        fclass.s s6, f7
        fclass.s s7, f8
        fclass.s s8, f4
        feq.s   s9, f1, f1
        flt.s   s10, f1, f2
        fle.s   s11, f2, f1
        feq.s   t3, f6, f1
        flt.s   t4, f6, f1
        csrr    t5, fflags
        csrw    fflags, zero

        fcvt.w.s  t0, f2
        fcvt.w.s  t1, f3
        fcvt.wu.s t2, f3
        fcvt.w.s  t3, f4
        fcvt.w.s  t4, f9, rup
        fcvt.wu.s t5, f2, rtz
        csrr    t6, fflags
        li      a0, -7
        fcvt.s.w  f19, a0
        fcvt.s.wu f20, a0
        li      a1, 16777217
        fcvt.s.w  f21, a1
        fcvt.s.w  f22, a1, rup
        fmv.x.w   a2, f21
        fmv.x.w   a3, f22
        fmv.x.w   a4, f20
        csrr    a5, fflags

        li      t0, 0x00800000
        fmv.w.x f5, t0
        fadd.s  f23, f1, f5
        fmv.x.w a6, f23
        csrwi   frm, 3
        fadd.s  f24, f1, f5
        fmv.x.w a7, f24
        csrwi   frm, 2
        fsub.s  f25, f1, f5
        fmv.x.w s1, f25
        csrwi   frm, 1
        fmul.s  f26, f9, f2
        fdiv.s  f27, f1, f2
        fmv.x.w s2, f26
        fmv.x.w s3, f27
        li      t0, 0x80
        csrw    fcsr, t0
        fsqrt.s f28, f2
        fmv.x.w s4, f28
        csrr    s5, frm
        csrr    s6, fcsr
        csrwi   frm, 0

        jal     ra, T4
        j       R4
T4:     .word   0x00115053
R4:     csrwi   frm, 5
        jal     ra, T5
        j       R5
T5:     fadd.s  f1, f2, f3
R5:     csrwi   frm, 0
        fadd.s  f1, f2, f3, rne
        fmv.x.w s7, f1

        fdiv.s  f2, f1, f9
        fadd.s  f3, f2, f1
        fmul.s  f4, f3, f2
        fmadd.s f5, f4, f3, f2
        fmv.x.w s8, f5
        fdiv.s  f6, f1, f9
        fadd.s  f7, f1, f1
        fadd.s  f8, f7, f7
        fadd.s  f9, f8, f8
        fmv.x.w s9, f6
        fmv.x.w s10, f9
        csrr    s11, fcsr
        csrr    t1, mstatus
        srli    t1, t1, 13
        andi    t2, t1, 3

        li      t0, 0x7f800001
        fmv.w.x f20, t0
        li      t0, 0x3f800000
        fmv.w.x f22, t0
        csrw    fflags, zero
        li      t0, 0x6000
        csrc    mstatus, t0
        jal     ra, T6
        j       R6
T6:     fdiv.s  f21, f22, f0
R6:     jal     ra, T7
        j       R7
T7:     flt.s   s1, f20, f22
R7:     li      t0, 0x6000
        csrs    mstatus, t0
        csrr    s2, fflags
        fdiv.s  f21, f22, f0
        flt.s   s3, f20, f22
        csrr    s4, fflags

        jal     ra, T8
        j       R8
T8:     csrwi   frm, 5
        fadd.s  f1, f22, f22
R8:     jal     ra, T9
        j       R9
T9:     csrwi   frm, 2
        fadd.s  f2, f22, f9
        fmv.x.w s5, f2
R9:     csrr    s6, frm
        csrr    s7, fcsr

done:   beq     x0, x0, done

handler:
        csrr    t3, mcause
        csrw    mepc, ra
        mret
