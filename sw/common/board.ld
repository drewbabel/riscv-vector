ENTRY(_start)
MEMORY { ram (rwx) : ORIGIN = 0x00000000, LENGTH = 0x04000000 }
SECTIONS {
  .text : { *(.text.init) *(.text*) } > ram
  .init_array : { PROVIDE_HIDDEN(__init_array_start = .); KEEP(*(.init_array*)) PROVIDE_HIDDEN(__init_array_end = .); } > ram
  .preinit_array : { PROVIDE_HIDDEN(__preinit_array_start = .); KEEP(*(.preinit_array*)) PROVIDE_HIDDEN(__preinit_array_end = .); } > ram
  .fini_array : { PROVIDE_HIDDEN(__fini_array_start = .); KEEP(*(.fini_array*)) PROVIDE_HIDDEN(__fini_array_end = .); } > ram
  .rodata : { *(.rodata*) *(.srodata*) } > ram
  .data : { *(.data*) *(.sdata*) } > ram
  .bss : { __bss_start = .; *(.sbss*) *(.bss*) *(COMMON) . = ALIGN(4); __bss_end = .; } > ram
  _end = .;
  PROVIDE(end = .);
  _stack_top = ORIGIN(ram) + LENGTH(ram);
}
