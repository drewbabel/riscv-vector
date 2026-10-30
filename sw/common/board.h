#ifndef BOARD_H
#define BOARD_H

#include <stdint.h>

#define UART_DATA (*(volatile uint32_t *)0x0A000000)
#define UART_STAT (*(volatile uint32_t *)0x0A000004)

void board_putc(char c);
void board_puts(const char *s);
void board_putu(uint32_t v);

static inline uint32_t read_cycles(void) {
    uint32_t c;
    __asm__ volatile("csrr %0, mcycle" : "=r"(c) : : "memory");
    return c;
}

#endif
