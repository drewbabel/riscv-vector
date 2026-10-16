OUTPUT_ARCH( "riscv" )
ENTRY(_start)
SECTIONS
{
  . = 0x80000000;
  .text.init : { *(.text.init) }
  .text : { *(.text*) }
  .data : { *(.data*) *(.sdata*) }
  .bss : { *(.bss*) *(COMMON) }
  _end = .;
}
