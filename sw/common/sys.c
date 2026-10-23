#include <errno.h>
#include <stdint.h>
#include <sys/stat.h>

#include "board.h"

extern char _end[];
static char *heap_brk = _end;

void board_putc(char c) {
    while (!(UART_STAT & 1))
        ;
    UART_DATA = (uint8_t)c;
}

void board_puts(const char *s) {
    while (*s)
        board_putc(*s++);
}

void board_putu(uint32_t v) {
    char buf[10];
    int n = 0;
    do {
        buf[n++] = '0' + v % 10;
        v /= 10;
    } while (v);
    while (n)
        board_putc(buf[--n]);
}

void *_sbrk(int inc) {
    char *old = heap_brk;
    heap_brk += inc;
    return old;
}

int _write(int f, const void *b, int n) {
    const char *s = b;
    for (int i = 0; i < n; i++)
        board_putc(s[i]);
    return n;
}
int _read(int f, void *b, int n) { return 0; }
int _close(int f) { return -1; }
int _fstat(int f, struct stat *s) {
    s->st_mode = S_IFCHR;
    return 0;
}
int _isatty(int f) { return 1; }
int _lseek(int f, int o, int w) { return 0; }
void _exit(int c) {
    for (;;)
        ;
}
int _kill(int p, int s) {
    errno = EINVAL;
    return -1;
}
int _getpid(void) { return 1; }
int _open(const char *n, int f, int m) { return -1; }
int _gettimeofday(void *t, void *z) { return 0; }
void *__dso_handle = 0;
