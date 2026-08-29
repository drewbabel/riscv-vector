# Vector extension plan

Adding the RISC-V Vector extension, version 1.0, to the five-stage pipelined RV32IM core. Every
decision below is made. Each round still gets its own design work before any of it is written.

## Target

A documented subset of `Zve32x`. That standard subset covers 32 vector registers, the
configuration instructions, vector loads and stores, and vector integer arithmetic on 8-, 16- and
32-bit elements, with no floating point. What is deliberately left out is accounted for in the
subset section below.

`Zve32f` is the same subset plus vector floating point, and its definition requires the scalar core
to already implement the F extension. This core is RV32IM with no scalar floating-point unit, so
`Zve32f` is two separate builds. One is a scalar floating-point unit containing no vector work at
all, and the other is floating-point lanes in the vector unit. `Zve32x` is therefore the base, and
the sequencer, the register file, the memory path and the configuration control registers are all
reused unchanged if floating point is added later. Nothing built for `Zve32x` is thrown away by a
later move to `Zve32f`.

## Parameters

### VLEN = 128

Bits per vector register. A design-time constant that software never sees.

The core's memory system is already 128 bits wide end to end. `cache_pkg.sv` sets `LineBits = 128`,
the cache line is 128 bits, `mem_arb`'s datapath to the memory controller is 128 bits, and the
controller's `app_wdf_data` and `app_rd_data` are 128 bits.

At VLEN of 128 one vector register is exactly one cache line and exactly one memory transaction. A
full-register vector load is a single request with no splitting, no reassembly and no
lane-alignment logic. Any other VLEN requires building that shim and maintaining it permanently.

### DLEN = 128

Width of the vector arithmetic datapath. Four parallel 32-bit lanes, or eight 16-bit, or sixteen
8-bit, depending on the element width in force.

1. A full-register-wide datapath makes the element sequencer a register counter rather than an
   element-offset counter. At LMUL of 1 an operation is one cycle, and at LMUL of 8 it is eight
   cycles, one register per cycle. That is less logic, and less logic on the critical path matters
   because frequency is the core's remaining open gap.
2. Four 32-bit adders is negligible area. Four 32-bit multipliers is a handful of DSP blocks on the
   XC7A200T, which carries far more than that.
3. It matches the memory width above, so a load fills exactly one register per transaction and the
   datapath is uniform from DDR3 to the vector arithmetic unit.

### ELEN = 32, and what it forces

Not a choice, since `Zve32x` fixes it. It carries an obligation that is easy to miss. Section 3.4.2
of the specification requires `LMUL >= SEW_MIN/ELEN`, and `SEW_MIN` is 8 in the standard
extensions, so an ELEN of 32 must support fractional LMUL values of 1/2 and 1/4, where only part of
a vector register holds live elements and the remainder is tail. The same section requires
supporting SEW from `SEW_MIN` up to `LMUL * ELEN` inclusive, which reduces to the single condition
that SEW divided by LMUL never exceeds 32. The element-count logic carries that condition from the
first round rather than gaining it afterwards.

## Microarchitecture

### Coupling

A decoupled co-processor, per Jain's stated steer, built as a one-deep instruction queue and a busy
signal. The scalar core issues vector instructions and continues, except where an instruction
produces a value the scalar pipeline needs. Those cases are `vsetvli`, `vsetivli` and `vsetvl`
writing the new `vl` into `rd`, `vmv.x.s` moving element 0 into an x register, and `vcpop.m` and
`vfirst.m` writing mask summaries into an x register. A Zicsr access to `vxsat` or `vcsr`, read or
write, also waits, because an in-flight fixed-point instruction may still write the saturation
flag, and a younger write that lands first would be clobbered when it does. `vxrm` is captured
when an instruction issues, and a later `csrw` to it needs no wait.

The existing `muldiv` unit is the precedent for the stall mechanism, using `start`, `busy` and
`done` with `muldiv_hold` gating the pipeline. The vector unit is the same shape, decoupled by
default rather than stalling by default. It instantiates inside `datapath.sv` beside `muldiv`,
because everything its issue interface needs lives there, `instr_ex`, the forwarded operands and
`commit_valid`, and its memory traffic leaves through the core's existing data-memory outputs via
the mux the memory path section places.

The waits, both the x-register-result cases above and the memory-ordering rule below, are
implemented as EX holds in the `muldiv_hold` shape, one more term in `ex_hold`. A scalar load or
store is identifiable in EX from `result_src_ex` and `mem_write_ex`, and holds there while the
vector unit reports conflicting pending work. Nothing changes in the MEM stage, and the existing
`exmem_bubble` machinery injects the NOPs for free.

Memory ordering follows the rule every comparable decoupled unit ships, from Vicuna through Ara,
Spatz and Hwacha. A scalar load waits until no vector store is pending, a scalar store waits until
no vector load or store is pending, and a `fence` drains the unit entirely. The scalar-store half
matters as much as the load half. A younger scalar store slipping past a queued older vector store
inverts a write-after-write order, and slipping past a queued older vector load hands that load
data it should not see yet. Version 1 implements the rule as a conservative wait with no address
comparison. Comparing addresses, the way Saturn's disambiguation CAM does, is an optimization that
needs a measurement behind it before it earns its complexity.

The pending-work flags those holds test are two signals, a vector load pending and a vector store
pending, and their edges are exact. Each sets the cycle its instruction enters the issue queue,
never at execution start, because the window between queue entry and first beat is precisely where
a younger scalar access could otherwise slip past. Each clears when the instruction's final beat
completes its handshake on the cache port. The port is shared and in order, which makes the
handshake the visibility point: a store beat the cache has accepted is a store beat any later
scalar load through the same port will see. With a one-deep queue the flags need no counters, one
flag per queue slot and one per executing instruction, ORed.

### Configuration state

`vl`, `vtype`, `vlenb` and `vstart` live in `csr.sv` alongside the machine-mode registers, at
addresses `0xC20`, `0xC21`, `0xC22` and `0x008`. The read multiplexer, the write case and the trap
gating already exist. `vl`, `vtype` and `vlenb` are read-only through the Zicsr instructions and
need read entries plus one write port from the configuration unit. `vstart` is a read-write
register that unprivileged code may write, per section 3.7, and takes the ordinary Zicsr write
path with the value masked to its 7 writable bits, the same masking Spike applies.

The configuration logic itself is a separate purely combinational module rather than logic inside
`csr.sv`, so that the `vill` table and the VLMAX computation get a directed testbench and a bounded
SymbiYosys proof of their own. Buried inside `csr.sv` they could only be tested through the whole
pipeline.

`vtype` is stored as its nine architectural bits and the full word is rebuilt on a read. The
specification suggests a seven-bit encoding that hides `vill` inside an illegal `vsew` combination,
which saves two flip-flops in exchange for logic that has to be reasoned about twice. `vl` is 8
bits, holding 0 through 128, since the largest VLMAX on this machine is LMUL of 8 at SEW of 8.
`vstart` is 7 bits, holding indices 0 through 127. At reset `vtype.vill` is set, the remaining bits
are zero and `vl` is zero, per section 3.11, so a single `vsetvl` can restore the reset state.

`vl` is set to the smaller of AVL and VLMAX. The specification permits a range of answers when AVL
falls between VLMAX and twice VLMAX, and Spike's `set_vl` resolves that range with the same
smaller-of-the-two choice, verified in its source. Matching Spike removes the likeliest silent
divergence the lockstep comparison could produce.

`mstatus.VS` is implemented at bits 10:9, including the illegal-instruction trap when the field
reads Off. The trap covers vector CSR accesses as well as vector instructions, and `mstatus.SD` at
bit 31 reads 1 whenever the field is Dirty. Spike models both, verified by running it, and even a
`vsetvli` traps under Spike until software turns the field on. Skipping the field is tempting on a
bare-metal machine with no context switching, and lockstep would diverge on the Dirty and SD bits.
Implementing the field forces a change `csr.sv` has gotten away without: `mstatus` is currently
written raw, `mstatus <= csr_wdata` with no mask, and a stored SD bit or an unlegalized VS value
would diverge from Spike on the first `csrw`. Round 2 adds the write legalizer, VS as a two-bit
WARL field and SD derived on read rather than stored.

Two Zicsr behaviors in `csr.sv` also diverge from Spike and shape round 2. A write to the
read-only CSR address quadrant, `csr_addr[11:10]` of `2'b11`, which is where `vl`, `vtype` and
`vlenb` live, is silently ignored today where Spike raises illegal instruction. Round 2 adds that
check, one comparator on an address range, with the set-and-clear forms whose source is zero
exempt because they perform no write. Reads of unimplemented CSR addresses return zero without
trapping, also unlike Spike; that divergence predates the vector work, stays out of its scope,
and lockstep tests simply never touch an unimplemented address.

`vta` and `vma` are stored and reported back, and the hardware always uses the undisturbed policy.
Section 3.4.3 permits exactly this for an in-order implementation.

### Vector register file

One module holding 32 registers of 128 bits in distributed RAM, mirroring `regfile.sv`'s
combinational-read write-first shape. Three full-width read ports, one write port, and a dedicated
narrow read port for `v0`. The third port exists because multiply-accumulate reads three vector
operands, `vs1`, `vs2` and the accumulator in `vd`, and the headline kernel is multiply-accumulate
in its inner loop. With two ports every such instruction spends a second cycle per register
fetching the accumulator, which halves the number the project is measured on, and Saturn and Spatz
both provision three read ports for the same reason. In distributed RAM a read port is one more
replicated copy of the array, cheap on this part. A mask always lives in `v0` and always occupies
exactly one register regardless of LMUL, and a dedicated narrow port for it is cheaper than a
fourth general one.

What the mask gates is decided here so no round has to guess: write enables, nothing upstream.
The write port carries per-byte enables, the lanes always compute every element, and the mask
from the `v0` port suppresses the enables for masked-off elements, exactly as the tail bound from
the sequencer suppresses them past `vl`. Undisturbed-everywhere is therefore not a policy the
datapath implements but the natural consequence of a suppressed write enable, one mechanism
serving masking and tails both. For masked stores the same mask suppresses the memory beat or its
strobes instead, since the destination is memory rather than the register file.

Distributed RAM rather than block RAM because block RAM reads are synchronous and the scalar
register file is combinational, and matching it keeps the sequencer simple. One deliberate
divergence from `regfile.sv`: that module zeroes its array in a reset loop, and an array with a
reset cannot infer distributed RAM, which is an acceptable price at 32 by 32 bits and a 4096-flop
mistake at 32 by 128. The vector register file mirrors the read-write shape and omits the reset,
which leaves its simulation power-up state X, and the test prologue that initializes every
register before comparing is what makes lockstep deterministic. This module gets its own row in the README
area table in the same change that lands it.

### The element sequencer

The control spine of the vector unit, and everything else in it is a slave to this block. One
sequencer, running one instruction at a time, which is the same capacity as the one-deep issue
queue, holding a single register-group counter. That counter drives four things in lockstep: the
register file read addresses, the base register numbers from the instruction plus the counter; the
register file write address, the same way; the per-lane enables, computed from `vl`, the element
width and the counter position, which is where the tail begins; and the beat count for loads and
stores. At LMUL of 1 an arithmetic instruction is one cycle and the counter never increments. At
LMUL of 8 the counter walks the group in 8 cycles, one register per cycle. At fractional LMUL the
counter stays at zero and the lane enables cover only the live fraction. `busy` holds while the
sequencer runs, `done` pulses when the counter completes, mirroring `muldiv`'s handshake. The
fast-forms round is what splits this block: concurrent memory and arithmetic execution means two
sequencers, one per unit, with the per-register-group scoreboard arbitrating between them.

### Vector multiply and divide

A dedicated 4-lane 32-bit multiply array inside the vector unit. Routing vector multiplies through
the existing `muldiv` would serialize every element behind a single unit whose `muldiv_hold` stalls
the entire pipeline, which defeats the decoupling above. The design uses 15 DSP blocks today on a
part that carries far more.

Vector divide is not built. `Zve32x` mandates it, and the kernels this core is aimed at use divide
only in normalization and matrix inversion steps, both off the inner loop and rare enough for the
scalar divider to absorb.

### Fixed-point arithmetic

Built, and the reason is precision rather than conformance. The target workloads are matrix and
matrix-vector multiply inside control dynamics, simultaneous localization and mapping, and model
predictive control, and those algorithms fail to converge at 8-bit integer precision. This core has
no floating-point unit, so fixed-point Q-format arithmetic is the only route to the precision those
algorithms need.

Four instruction families carry it. `vsadd` and `vssub` are the saturating add and subtract, which
keep an accumulating update from wrapping. `vsmul` is the fractional multiply, computing
`clip(roundoff_signed(vs2[i]*vs1[i], SEW-1))`. `vssrl` and `vssra` are the rounding scaling shifts.
`vnclip` is the saturating narrowing clip. All four reuse the multiply array and the adders built
for single-width arithmetic, so the added hardware is the rounding increment logic, the saturation
comparators, and the `vxrm` and `vxsat` control registers at addresses `0x00A` and `0x009`, mirrored
in `vcsr` at `0x00F`. The hardware carries no radix point of its own, so the software chooses the Q
format freely.

### Memory access patterns

Unit-stride and strided loads and stores are both built. A matrix stored in row-major order and read
by column is a strided access, so a general matrix multiply without `vlse32.v` falls back to
element-by-element scalar loads, and the vector unit then starves waiting for operands. That turns
the headline benchmark into a measurement of the memory bottleneck rather than of the vector unit.
The delta over unit-stride is address generation, base plus index times stride rather than base plus
a fixed element size, and the loss of the whole-line fast path.

### Traps, interrupts and `vstart`

Every check that could reject a vector instruction resolves in EX, before the instruction enters
the queue. Those checks are the opcode and encoding, `vtype.vill`, `mstatus.VS` reading Off, and
alignment, judged up front from the base address, the stride and the element count. An instruction
that passes them is committed, runs to completion, and is never restarted. The machine therefore
never produces a nonzero `vstart`, and a vector instruction that finds `vstart` nonzero raises an
illegal-instruction exception, which section 3.7 permits per instruction for exactly this design.
The resumable form of `vstart` exists for machines that can fault partway through a vector memory
access, and this core has no source of such a fault. A decoupled unit also cannot reach it, because
the scalar pipeline has retired younger instructions by the time a vector memory access executes,
and a resumable trap would have no instruction left to return to. Saturn and Ara keep resumable
`vstart` only by resolving every possible fault before the scalar core commits, which is the same
structure at larger scale.

Interrupts are taken at scalar instruction boundaries without waiting for the vector unit. Work
already issued is committed and finishes in the background while the handler runs, and the
memory-ordering rule above keeps the handler's own loads and stores ordered behind it. One caveat
comes from how this core recognizes interrupts: `csr.sv` sees `timer_irq` and `ext_irq` gated by
`commit_valid`, meaning an interrupt is taken only against a committing instruction, and during an
x-register-result wait `commit_valid` is low for the whole hold. An interrupt arriving mid-wait
therefore waits it out, exactly as it waits out a 32-cycle divide today. Interrupt latency is
otherwise unchanged from the scalar core.

The `fence` drain needs a decode that does not exist yet. `OpcodeMiscMem` falls into
`control_decoder.sv`'s default case and produces a NOP with no side effects, which is correct for a
core whose every memory access is in order and in the pipeline. The vector memory round adds an
`is_fence` output and routes it into the same EX hold as the ordering waits, draining the vector
unit before the fence retires.

One divergence to know about when tests are written. Spike accepts a software-written nonzero
`vstart` on vector memory instructions where this machine traps, and no generated or planned test
writes one.

### Memory path

Vector loads and stores go through the existing data cache port first, at 32 bits per beat and `vl`
beats per instruction. The cache's CPU port is 32 bits wide and `cpu_ready` asserts only on a hit in
COMPARE, so a 4-element load is 4 sequential accesses. That is slow, and it is coherent with scalar
accesses for free.

The path has exactly one requester today. `board_top.sv` wires the cache's `cpu_valid` straight to
`dmem_req && !periph_sel` from the MEM stage, with no mux in between, and the flat simulation `top`
that the lockstep runs wires the same core outputs straight into `dmem`. Sharing is therefore a
structure the vector memory round builds, not a wire it borrows, and it lands inside the core, in
front of the core's single data-memory interface, `dmem_req`, `mem_addr`, `store_data`,
`store_wstrb` and `read_data`, rather than at any board's cache port. Placed there, every top gets
vector memory without modification, the flat `top` the co-simulation runs, both board tops, and the
uncached and single-cycle parameter builds, whereas a board-level mux would leave the lockstep with
no way to execute a vector load at all. The scalar side wins the grant, because a stalled MEM stage
stalls the whole pipeline while the vector unit is built to wait, and each vector beat is an
independent transaction, letting the grant re-arbitrate between beats with no mid-transfer abort.
One wiring trap comes with the mux: `mem_hold` at `datapath.sv:405` is computed from `dmem_req`,
and if the muxed request drove it, a vector beat missing in the cache would stall the entire
scalar pipeline for the duration of the miss, which is exactly what decoupling exists to avoid.
The hold keys on the scalar request alone; the muxed output feeds only the port. The
memory-ordering rule above already keeps the two sides from needing the port for conflicting
accesses at the same time.

One address-space constraint rides on this placement. The boards decode peripheral selects from
`mem_addr`, the muxed address, and a vector beat aimed at a peripheral tag would reach the
peripheral one element at a time with side effects no specification covers. Vector memory
instructions target main memory only. That is a documented software contract with no hardware
guard, and no generated or planned test produces a peripheral-range vector access.

The dedicated 128-bit path is a later change with a before-and-after measurement attached, built as
a fourth source on `mem_arb` rather than as a second cache. `mem_arb` already serializes 3 sources
at one outstanding transaction, and a `dc_req_wstrb` of `4'h0` already means write the whole 128-bit
line, which is exactly what a full-register vector store needs. The data cache is write-back, and
any path that reaches memory around it meets lines that are dirty or stale in the cache. Round 8
therefore carries a cache-interaction mechanism in its scope, a lookup, a flush or an invalidate
sweep, chosen in that round alongside the measurement. A second cache would carry the same
obligation twice over, which is the reason the dedicated path lands on `mem_arb`. One decision
that round carries which this plan does not make: `mem_arb` grants by fixed priority, boot first,
then the data cache, then the instruction cache, latched in IDLE with no fairness mechanism, and
the fourth `src_t` encoding says nothing about where a vector port sits in that order. Any
placement starves someone under sustained vector traffic, and the round picks the slot with the
starvation cost priced. The measurement
also arbitrates one remaining fork, since widening the data cache's own CPU port to the full line
is the other route to bandwidth. A hit-bound profile favors the wider cache port and a miss-bound
or streaming profile favors the direct path, and round 8 decides with the numbers in hand.

## The fast forms, planned

Each block lands basic first and upgrades on a measurement, and the upgrades are planned work with
their own round. In priority order:

1. The dedicated memory path, decided between the `mem_arb` port and the widened cache port by the
   measured profile. The memory path section above carries the whole decision.
2. Concurrent execution inside the vector unit. The issue queue deepens to 2 and the memory unit
   runs a load or store while the arithmetic lanes execute a later instruction, tracked by a
   per-register-group busy scoreboard. Memory beats dominate vector cycles on this machine, and
   the overlap hides them behind arithmetic the program already pays for.
3. Scalar-vector address disambiguation. The conservative ordering waits become an address-range
   compare against the pending vector access. A shallow queue makes the compare one bounds check
   where Saturn needs a CAM, which is what makes the upgrade cheap here.

Two upgrades are deliberately off the ladder. Element-level chaining pays when a vector instruction
runs for many cycles, and at DLEN equal to VLEN an arithmetic instruction takes 1 to 8 cycles,
which leaves nothing worth forwarding into. A larger VLEN would outrun the 128-bit memory system,
grow the register file past the distributed-RAM sweet spot, and buy little for workloads that are
memory-bound before they are compute-bound.

The vector unit also must not move the core's critical path. The multiply array keeps its DSP
pipeline registers, and the frequency gap the scalar core already carries stays its own
workstream, unchanged by vector work.

## Verification

Three layers, each named by its real technique.

1. riscv-formal stays scalar only. The upstream `insns/` directory carries no vector instruction
   models, so there is nothing to enable. Its value is that the existing proof must still pass
   unchanged after the vector work lands, which shows the vector unit did not break the scalar core.
2. Spike lockstep co-simulation extended over `v0` through `v31`, `vl`, `vtype` and `vstart`. This
   is the primary check on vector behavior, it starts at round 2 by checking `vl` and `vtype` after
   every configuration instruction, and it grows with each round. Spike 1.1.1-dev accepts
   `--isa=rv32im_zve32x_zvl128b`, so VLEN of 128 is selected through the `Zvl128b` ISA string, and
   the bare string without `Zvl128b` silently models VLEN of 32.
3. A directed testbench for every new module, plus one bounded SymbiYosys proof on the configuration
   unit. That unit is purely combinational over a small input space, so a proof covers every SEW,
   LMUL, AVL and instruction variant exhaustively where a testbench only samples.

Four facts about the reference model shape the tests, each verified by running Spike and reading
its source. Spike implements both agnostic policies as undisturbed and has no mode that writes
ones, which means a machine that is undisturbed everywhere, mask-destination tails included,
matches it bit for bit. Spike zeroes all 32 vector registers at reset where this register file,
built without a reset so distributed RAM infers, powers up as X in simulation, and every test
therefore initializes the full register file before comparing. Spike traps
every vector instruction, `vsetvli` included, until `mstatus.VS` is turned on, and the test
prologue sets the field first. And Spike's `vl` choice is the smaller-of rule already fixed above.

`riscv64-elf-gcc` 16.1.0 assembles `-march=rv32im_zve32x` without modification. Compiled C takes
`-march=rv32im_zve32x_zvl128b -mabi=ilp32 -fno-tree-vectorize -mstringop-strategy=scalar`, because
gcc otherwise inline-expands `memcpy`, `strlen` and `strcmp` into vector code, fault-only-first
load included, even at `-O1`. A build step greps the generated assembly for `vsetvl` as the
guarantee that scalar baselines stayed scalar. chipsalliance/riscv-vector-tests generates
per-instruction tests at VLEN of 128 and XLEN of 32 and filters to a chosen subset by filename
pattern. Its rv32 defaults assume a floating-point scalar core, which means the `MARCH`, `MABI`
and `VARCH` variables get overridden, and it never exercises agnostic policies, nonzero `vstart`,
or a SEW of 64 that must set `vill`. The last two are hand-written tests.

## The subset, accounted against `Zve32x`

`Zve32x` includes every instruction chapter of the specification except vector floating point, and
its single named carve-out is the floating-point scalar moves. A build that omits anything else is
a subset. Describe the result as a documented subset of `Zve32x`, never as conformant, and keep
this accounting complete, because a toolchain targeting `zve32x` is entitled to emit any mandated
instruction. The lists are derived from the target workloads and from the toolchain that compiles
for them.

Also in the build, each named here because a round title alone would not imply it:

- `vmin` and `vmax` in vector-vector and vector-scalar forms, because the model-predictive-control
  projection clamps against per-element bounds held in memory.
- `vmerge`, the `vmv.v` moves, and the sign and zero extensions `vsext` and `vzext`.
- The narrowing shifts `vnsra` and `vnsrl`, which the standard Q15 kernel epilogue runs before
  `vnclip`.
- The sum, widening sum, minimum and maximum reductions, with `vmv.s.x` and `vmv.x.s` seeding and
  reading them, because the solver's convergence test is an infinity norm.
- The whole-register moves, loads and stores, which cost a hardwired configuration on paths that
  already exist and close off a class of compiler and generated-test surprises.
- The mask instructions `vcpop`, `vfirst`, `vmsbf`, `vmsif`, `vmsof`, `viota` and `vid`.

Stretch, in priority order, and each one is genuinely useful to the target workloads.

1. Indexed loads and stores, `vluxei32.v`, `vloxei32.v`, `vsuxei32.v` and `vsoxei32.v`. Sparse
   matrix-vector multiply is the core of graph-based simultaneous localization and mapping, and a
   gather is how it reads operands. The address comes from a vector register, so the memory unit
   gains a vector read port, which makes this a structural addition rather than a variation on the
   existing address generator.
2. Segment loads and stores. A point cloud of x, y and z triples is an array of structures, and a
   segment load deinterleaves it in one instruction. A stride-3 strided load covers the same ground
   more slowly, so this only pays once the strided path is measured.
3. `vcompress`, which packs the active elements of a register down into consecutive positions.
   Landmark pruning uses it, and the software fallback is inexpensive.
4. `vslide1up` and `vslide1down`. Finite-impulse-response filtering keeps its sliding window in a
   register with them, and no matrix or solver kernel touches them.

Out, and not planned.

- `vrgather`. A full crossbar across all 128 bits, the most expensive permutation structure in the
  extension. The broadcast pattern that matrix multiply actually needs is covered by the `.vx`
  scalar operand forms and `vmv.v.x` at a small fraction of the area.
- The multi-element slides `vslideup` and `vslidedown`. No target kernel uses them.
- Fault-only-first loads. They exist to vectorize loops over data of unknown length, and no target
  workload has that shape. The compiler flags in the verification section keep them out of
  compiled code.
- The carry chains `vadc`, `vsbc`, `vmadc` and `vmsbc`, which serve multi-word arithmetic.
- The averaging adds `vaadd` and `vasub`.
- Vector divide and remainder, per the reasoning above.

## Where the vector opcodes enter the existing core

Recorded from reading the core, so no round has to rediscover it.

- `datapath.sv` computes `exc_illegal` from an opcode whitelist. `OP-V` at `0x57`, `LOAD-FP` at
  `0x07` and `STORE-FP` at `0x27` are all absent, so every vector instruction currently traps as
  illegal. That whitelist is where vector opcodes are admitted, one `funct3` value at a time.
- `csr.sv` is a flat read multiplexer plus a write case statement, and an unimplemented address
  currently reads as zero rather than trapping. The vector control registers follow the same shape.
- The EX result multiplexer at `datapath.sv:617` (`result_ex`) already routes `csr_rdata` for the
  Zicsr instructions, and the configuration instructions ride the same path with the select widened
  to admit them. Their `rd` value then flows through `alu_result_mem` and writes back on the
  existing `result_src` value of zero, exactly the route a `muldiv` result takes, so the forwarding
  network needs no change. The writeback multiplexer is the separate `result_src_wb` case statement
  at `datapath.sv:722`, and its `2'd3` encoding is the one still free for a later
  vector-to-x-register move.
- Every sequential block in the core gates on `core_en`, the divided tick from `tick_gen`
  (`ClkDiv` is 2 on both board tops, half the board clock; the flat simulation `top` ties it
  high). A vector `always_ff` without that
  gate runs at the board rate against a half-rate core and is simply wrong, and every flop the
  vector unit adds carries the same `if (core_en)` guard. Neither constraints file claims the
  divided rate as timing slack today, and once the vector multiply array exists, a
  `set_multicycle_path` exception on the enable-gated paths is the cheap way to buy it timing
  room without touching the clock.
- `regfile.sv` is a flat array with combinational reads and write-first bypass. The vector register
  file mirrors it, wider.
- `commit_valid` at `datapath.sv:371` is what gates every architectural write in `csr.sv`. Vector
  state writes gate on the same signal, since a vector instruction in the shadow of a mispredicted
  branch would otherwise corrupt `vtype` with no way to recover it.

## Rounds

Work proceeds one round at a time. Each round designs its own scope, builds it, and stops. No round
starts before the one before it closes.

1. What a vector instruction is on this core. **Closed.** Settled VLEN and DLEN.
2. The configuration instructions and the vector control registers. First RTL.
3. The vector register file and single-width integer arithmetic.
4. Unit-stride and strided vector loads and stores through the existing data cache, including the
   in-core memory mux and the `fence` decode and drain that the memory path and trap sections name.
5. Multiply, multiply-add, widening and narrowing operations, and the reductions.
6. Fixed-point saturating add, multiply, scaling shifts, saturating narrow, and the rounding-mode
   registers.
7. Masks and compares.
8. The dedicated vector memory port on `mem_arb`, with the speedup measured against round 4 and the
   cache-interaction mechanism the memory path section names.
9. The full-subset lockstep sweep, and the measured kernel against the scalar core.
10. The fast forms in priority order, the deeper issue queue with concurrent memory and arithmetic
    execution, then scalar-vector address disambiguation, each with a before-and-after
    measurement.

The headline result is a fixed-point matrix-vector multiply measured on the board against the scalar
core at the same clock, in cycles from `mcycle`. It is the inner loop of the workload the project
targets, it exercises strided loads, multiply-accumulate, a reduction and the fixed-point rounding
path, and Embench `matmult-int` already gives a scalar baseline measured on the same flow. The
kernel runs Q15 data through widening multiply-accumulate into 32-bit accumulators and narrows the
result with `vnclip`, the shape production fixed-point libraries use, and a Q31 variant runs
single-width through `vsmul`. Accumulating Q31 in 64 bits is the one path `Zve32x` forecloses,
since the widest element is 32 bits.
