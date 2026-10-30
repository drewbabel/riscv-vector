#include <string.h>

#include "mamba3.h"

#define OP(n) n##_s
#define STEP(n) void m3_##n##_s(void)

#include "steps.inc"
