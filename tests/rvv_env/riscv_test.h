#ifndef RVV_ENV_RISCV_TEST_H
#define RVV_ENV_RISCV_TEST_H

#include "encoding.h"

#define RVTEST_RV32U                                                    \
  .macro init;                                                          \
  .endm

#define RVTEST_RV32UV RVTEST_RV32U
#define RVTEST_RV32UVX RVTEST_RV32U

#define INIT_XREG                                                       \
  li x1, 0;                                                             \
  li x2, 0;                                                             \
  li x3, 0;                                                             \
  li x4, 0;                                                             \
  li x5, 0;                                                             \
  li x6, 0;                                                             \
  li x7, 0;                                                             \
  li x8, 0;                                                             \
  li x9, 0;                                                             \
  li x10, 0;                                                            \
  li x11, 0;                                                            \
  li x12, 0;                                                            \
  li x13, 0;                                                            \
  li x14, 0;                                                            \
  li x15, 0;                                                            \
  li x16, 0;                                                            \
  li x17, 0;                                                            \
  li x18, 0;                                                            \
  li x19, 0;                                                            \
  li x20, 0;                                                            \
  li x21, 0;                                                            \
  li x22, 0;                                                            \
  li x23, 0;                                                            \
  li x24, 0;                                                            \
  li x25, 0;                                                            \
  li x26, 0;                                                            \
  li x27, 0;                                                            \
  li x28, 0;                                                            \
  li x29, 0;                                                            \
  li x30, 0;                                                            \
  li x31, 0;

// TRAP_SKIP steps over traps
#ifdef TRAP_SKIP
#define TRAP_TARGET trap_skip
#define TRAP_HANDLER                                                    \
trap_skip:                                                              \
        csrw mscratch, t0;                                              \
        csrr t0, mepc;                                                  \
        addi t0, t0, 4;                                                 \
        csrw mepc, t0;                                                  \
        csrr t0, mscratch;                                              \
        mret
#else
#define TRAP_TARGET park_trap
#define TRAP_HANDLER
#endif

// Any trap parks here
#define RVTEST_CODE_BEGIN                                               \
        .section .text.init;                                            \
        .align  6;                                                      \
        .globl _start;                                                  \
_start:                                                                 \
        j rvtest_init;                                                  \
        .align 2;                                                       \
        .globl park_trap;                                               \
park_trap:                                                              \
        j TRAP_TARGET;                                                  \
rvtest_init:                                                            \
        la t0, park_trap;                                               \
        csrw mtvec, t0;                                                 \
        li t0, MSTATUS_VS & (MSTATUS_VS >> 1);                          \
        csrs mstatus, t0;                                               \
        csrwi vcsr, 0;                                                  \
        INIT_XREG;                                                      \
        init;                                                           \
        j rvtest_body;                                                  \
rvtest_body:

#define RVTEST_CODE_END                                                 \
        unimp;                                                          \
        TRAP_HANDLER

#define TESTNUM gp

#define RVTEST_PASS                                                     \
        fence;                                                          \
        li TESTNUM, 1;                                                  \
        .globl park_pass;                                               \
park_pass:                                                              \
        j park_pass

#define RVTEST_FAIL                                                     \
        fence;                                                          \
        .globl park_fail;                                               \
park_fail:                                                              \
        j park_fail

#define EXTRA_DATA

#define RVTEST_DATA_BEGIN                                               \
        EXTRA_DATA                                                      \
        .align 4; .global begin_signature; begin_signature:

#define RVTEST_DATA_END .align 4; .global end_signature; end_signature:

#endif
