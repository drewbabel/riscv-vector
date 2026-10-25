  .section .text.init
  .globl _start
_start:
  li t0, 0x2200
  csrs mstatus, t0
  la sp, _stack_top
  la t0, __bss_start
  la t1, __bss_end
1: bgeu t0, t1, 2f
  sw zero, 0(t0)
  addi t0, t0, 4
  j 1b
2: call __libc_init_array
  call main
3: j 3b
