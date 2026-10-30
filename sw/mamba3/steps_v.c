#include <string.h>

#include "mamba3.h"

#define OP(n) n##_v
#define STEP(n) void m3_##n##_v(void)

#include "steps.inc"
