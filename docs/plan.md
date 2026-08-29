# Vector extension plan

Adding the RISC-V Vector extension, version 1.0, to the five-stage pipelined RV32IM core. Every
decision below is made. Each round still gets its own design work before any of it is written.

## Target

A documented subset of `Zve32x`. That standard subset covers 32 vector registers, the
configuration instructions, vector loads and stores, and vector integer arithmetic on 8-, 16- and
32-bit elements, with no floating point. What is deliberately left out is accounted for in the
subset section below.

`Zve32f` is the same subset plus vector floating point, and its definition requires the scalar core
to already implement the F extension or its Zfinx replacement. This core is RV32IM with neither, so
`Zve32f` is two separate builds. One is scalar floating-point capability containing no vector work
at all, with Zfinx the cheaper branch since it reuses the x registers, and the other is
floating-point lanes in the vector unit. `Zve32x` is therefore the base, and
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
   element-offset counter. At LMUL of 1 an adder-class operation is one cycle, and at LMUL of 8 it
   is eight cycles, one register per cycle. Multiply-class and mixed-width operations run at the
   lane rate the multiply section fixes, on the subcounter the sequencer section defines. That is
   less logic, and less logic on the critical path matters because frequency is the core's
   remaining open gap.
2. Four 32-bit adders is negligible area. Four 32-bit multipliers is a handful of DSP blocks on the
   XC7A200T, which carries far more than that.
3. It matches the memory width above, so a load fills exactly one register per transaction and the
   datapath is uniform from DDR3 to the vector arithmetic unit.

### ELEN = 32, and what it forces

Not a choice, since `Zve32x` fixes it. It carries an obligation that is easy to miss. Section 3.4.2
of the specification requires `LMUL >= SEW_MIN/ELEN`, and `SEW_MIN` is 8 in the standard
extensions, so an ELEN of 32 must support fractional LMUL values of 1/2 and 1/4, where only part of
a vector register holds live elements and the remainder is tail. The same section requires, for
each supported fractional LMUL, SEW settings from `SEW_MIN` up to `LMUL * ELEN` inclusive. Two
conditions come out of it and the `vill` table carries both: SEW never exceeds 32, and SEW divided
by LMUL never exceeds 32. The first is not implied by the second. LMUL of 2 at SEW of 64 passes the
ratio test and names an element width this machine cannot represent, so the SEW cap is its own term
from the first round.

## Microarchitecture

### Coupling

A decoupled co-processor, per Jain's stated steer, built as a one-deep instruction queue and a busy
signal. The scalar core issues vector instructions and continues, except where an instruction
produces a value only the vector unit can supply. Those cases are `vmv.x.s` moving element 0 into
an x register, and `vcpop.m` and `vfirst.m` writing mask summaries into an x register. The
configuration instructions are not wait cases: the configuration section below computes them
combinationally in EX, and their `rd` value is ready the same cycle. A Zicsr access to `vxsat` or
`vcsr`, read or write, also waits, because an in-flight fixed-point instruction may still write the
saturation flag, and a younger write that lands first would be clobbered when it does. The value a
wait produces returns the way a `muldiv` result does: the vector unit hands it back during the
hold, it enters the EX result path, and the writeback and forwarding networks never learn anything
new.

Every queue entry carries a snapshot of the configuration it was issued under: `vl`, the `vtype`
fields and `vxrm`, captured the cycle the instruction enters the queue. The sequencer, the lane
enables and the beat counts read only the snapshot. A younger `vsetvli` can therefore retire and
rewrite the live registers while an older instruction is still queued or mid-execution, which is
the reconfigure-between-loops pattern every vector program runs, and nothing downstream of issue
ever reads the live copy. A later `csrw` to `vxrm` needs no wait for the same reason.

The existing `muldiv` unit is the precedent for the stall mechanism, using `start`, `busy` and
`done` with `muldiv_hold` gating the pipeline. The vector unit is the same shape, decoupled by
default rather than stalling by default. It instantiates inside `datapath.sv` beside `muldiv`,
because everything its issue interface needs lives there, `instr_ex`, the forwarded operands and
`commit_valid`, and its memory traffic leaves through the core's existing data-memory outputs via
the mux the memory path section places.

The waits, both the x-register-result cases above and the memory-ordering rule below, are
implemented as EX holds in the `muldiv_hold` shape. That shape is every expression `muldiv_hold`
appears in, four sites: `commit_valid` at `datapath.sv:371`, `ex_hold` at 403, `stall` at 399 and
`fwd_hold` at 418. The vector hold term joins each site the same way `muldiv` answers it, and the
371 site is the one that cannot be missed, because without it a held instruction re-fires its
architectural writes every cycle of the hold, `minstret` counts the hold's length, and the
interrupt behavior below inverts. A scalar load or store is identifiable in EX from
`result_src_ex` and `mem_write_ex`, and holds there while the
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
flag per queue slot and one per executing instruction, ORed; up to two vector instructions are
resident at once, one queued and one executing, and every capacity statement in this plan means
those two. A load or store at `vl` of 0 issues zero beats and completes the cycle it reaches the
sequencer, clearing its flag then, and it still emits its retirement event so the comparator's
tag sequence stays gapless. A masked store issues its full beat count with the masked elements'
strobes zeroed; suppressing whole beats would make the beat count mask-dependent and buys nothing
on an in-order port.

### Configuration state

`vl`, `vtype`, `vlenb` and `vstart` live in `csr.sv` alongside the machine-mode registers, at
addresses `0xC20`, `0xC21`, `0xC22` and `0x008`. The read multiplexer, the write case and the trap
gating already exist. `vl`, `vtype` and `vlenb` are read-only through the Zicsr instructions and
need read entries plus one write port from the configuration unit. `vstart` is a read-write
register that unprivileged code may write, per section 3.7, and takes the ordinary Zicsr write
path with the value masked to its 7 writable bits, the same masking Spike applies.

The configuration logic itself is a separate purely combinational module rather than logic inside
`csr.sv`, instantiated in EX beside the CSR file, so that the `vill` table and the VLMAX
computation get a directed testbench and a bounded SymbiYosys proof of their own. Buried inside
`csr.sv` they could only be tested through the whole pipeline. Configuration instructions never
enter the vector issue queue: the new `vl` and `vtype` are computed combinationally from the
instruction and the forwarded operand in EX, written at EX commit under `commit_valid`, and the
`rd` value rides the existing `csr_rdata` result path with no hold. All encodings behave the same
way, the `rd = x0` forms included: `rd = x0` with `rs1` nonzero takes AVL from `rs1` and updates
`vl` without writing a register, and the `rd = x0, rs1 = x0` form keeps the current `vl` while
changing `vtype`. The specification reserves that last form when the new `vtype` changes VLMAX;
the configuration unit sets `vill` there, and round 2's first lockstep sweep confirms Spike
resolves it the same way before any test relies on it.

`vtype` is stored as its nine architectural bits and the full word is rebuilt on a read, except
under `vill`, where section 3.4.4 requires the other bits to read zero and the rebuild honors
that. The specification's alternative is an eight-bit encoding that hides `vill` inside an illegal
`vsew` combination, which saves one flip-flop in exchange for logic that has to be reasoned about
twice. The `vill` table judges four things: the SEW cap of 32, the SEW-to-LMUL ratio from the
parameters section, the reserved `vsew` and `vlmul` encodings, and the reserved field, because
`vsetvl` carries a full 32-bit `vtype` in a register and section 3.4.4 requires every bit
considered, so a nonzero value in bits 30:8 sets `vill` rather than being silently dropped. `vl`
is 8 bits, holding 0 through 128, since the largest VLMAX on this machine is LMUL of 8 at SEW of
8. `vstart` is 7 bits, holding indices 0 through 127. At reset `vtype.vill` is set, the remaining
bits are zero and `vl` is zero, per section 3.11, so a single `vsetvl` can restore the reset
state.

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
WARL field, SD derived on read rather than stored, and the Dirty transition itself: every vector
instruction reaching EX commit, configuration instructions included, and every Zicsr write to a
vector CSR sets the field to Dirty at that commit. That is per-instruction timing, so the
decoupled unit's later register writes carry no `mstatus` side effect of their own, and the first
`mstatus` read after a `vsetvli` in round 2's lockstep confirms it matches Spike's marking.

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
combinational-read shape. Three full-width read ports, one write port, and a dedicated
narrow read port for `v0`. The third port exists because multiply-accumulate reads three vector
operands, `vs1`, `vs2` and the accumulator in `vd`, and the headline kernel is multiply-accumulate
in its inner loop. With two ports every such instruction spends a second cycle per register
fetching the accumulator, which halves the number the project is measured on, and Saturn and Spatz
both provision three read ports for the same reason. The count holds for the widening accumulate,
which reads half a source register of each operand and one full accumulator register per cycle. In
distributed RAM a read port is one more replicated copy of the array, cheap on this part. A mask
always lives in `v0` and always occupies exactly one register regardless of LMUL, and a dedicated
narrow port for it is cheaper than a fourth general one. The `v0` port delivers the mask bits for
the elements in flight in the current cycle, at most 16 at SEW of 8, indexed by the sequencer's
position.

Two deliberate divergences from `regfile.sv`, each with its reason. First, the vector file is
read-first, with no write-first bypass. A multiply-accumulate reads `vd` and writes `vd` in the
same cycle, and a write-first bypass would feed the adder its own output combinationally.
Read-first returns the pre-write value, which is the architecturally correct operand, and no
vector case needs the bypass: the sequencer runs one instruction at a time, so a result written at
one clock edge is readable the cycle after, and no reader ever races a writer across instructions.
Second, the reset. `regfile.sv` zeroes its array in a reset loop, and an array with a reset cannot
infer distributed RAM, an acceptable price at 32 by 32 bits and a 4096-flop mistake at 32 by 128.
The vector register file omits the reset and zero-fills the array in an `initial` block instead,
the `bram_sdp.sv` idiom already in this repo. Initialization does not block distributed-RAM
inference the way a reset does, and it makes the contents zero at simulation start and at
configuration, which is exactly Spike's reset state. A soft reset does not re-zero it, and the
test prologue that initializes every register before comparing stays, covering that one gap. This
module gets its own row in the README area table in the same change that lands it.

What the mask gates is decided here so no round has to guess, and there are two mechanisms because
instructions consume `v0` two ways. Masked ordinary instructions, the `vm` bit clear, use the mask
to suppress write enables: the lanes always compute every element, the mask from the `v0` port
suppresses the enables for masked-off elements, and the tail bound from the sequencer suppresses
them past `vl`, one mechanism serving masking and tails both. The enables are per bit, not per
byte. Byte granularity covers element masking down to SEW of 8, but round 7's compares and the
mask-format instructions write one bit per element into `vd` and must leave neighboring bits of
the same byte undisturbed, which byte enables cannot express; in distributed RAM the array is
bit-sliced anyway, so a per-bit enable is gating that already exists rather than new structure.
The second mechanism is `v0` as a data operand. `vmerge` gives a masked-off element the value of
`vs2[i]`, not its old value, so enable suppression would compute the wrong result, and `viota`,
`vcpop` and `vfirst` consume mask bits as input data; for these the `v0` port feeds the datapath
directly. For masked stores the mask zeroes the affected beats' strobes, since the destination is
memory rather than the register file.

### The element sequencer

The control spine of the vector unit, and everything else in it is a slave to this block. One
sequencer, running one instruction at a time, which matches the single executing slot beside the
one-deep issue queue, holding a register-group counter with an element-phase subcounter beneath
it. The counter drives four things in lockstep: the register file read addresses, the base
register numbers from the instruction plus the counter; the register file write address, the same
way; the per-lane enables, computed from the snapshot's `vl`, the element width and the counter
position, which is where the tail begins; and the beat count for loads and stores. At LMUL of 1 an
adder-class instruction is one cycle and the counter never increments. At LMUL of 8 the counter
walks the group in 8 cycles, one register per cycle. At fractional LMUL the counter stays at zero
and the lane enables cover only the live fraction.

Four instruction classes step differently, and the subcounter carries them all. Multiply-class
instructions run at the multiply array's rate, four elements per phase at every SEW, so a 16-bit
multiply spends two phases per register and an 8-bit one four. Widening instructions produce
double-width results, 128 bits of output from half a source register, so each phase consumes half
a source register and writes one full destination register; the destination group walks at twice
the source counter, which is the mechanical face of EMUL doubling, and it caps the legal source
LMUL at 4. Narrowing instructions invert it, two phases of double-width source reads assembling
one destination register written once, and the sign and zero extensions read their source at half
or a quarter of the phase rate the same way. A reduction reads the group with the ordinary
counter, folds each phase's lanes through a cross-lane tree into an accumulator carried between
phases, and performs a single element-0 write when the walk completes; its write address never
comes from the counter. Whole-register moves, loads and stores ignore the snapshot's `vl`
entirely: section 7.9 fixes their element count at NFIELDS times VLEN over EEW regardless of `vl`
and `vtype`, so their bound is hardwired, and the same override drives `vlm.v` and `vsm.v` at
ceil(vl/8) bytes per section 7.4.

`busy` holds while the sequencer runs. `done` pulses when the last result write lands, which for
pipelined multiplies is after the array's registers drain, not at the counter's last step. The
fast-forms round is what splits this block: concurrent memory and arithmetic execution means two
sequencers, one per unit, with the per-register-group scoreboard arbitrating between them.

### Vector multiply and divide

A dedicated 4-lane 32-bit multiply array inside the vector unit, each lane producing the full
64-bit product, because `vmulh` and its unsigned and mixed forms return the high half, the
widening multiplies return both halves, and `vsmul`'s rounding examines it. Throughput is four
products per phase at every SEW; the multipliers do not subdivide the way the adders do, and
packing two 16-bit multiplies into one DSP is an optimization with no kernel demanding it. Routing
vector multiplies through the existing `muldiv` would serialize every element behind a single unit
whose `muldiv_hold` stalls the entire pipeline, which defeats the decoupling above. The scalar
core's own DSP usage sits in the README's utilization table, a small fraction of what the XC7A200T
carries.

Vector divide is not built. `Zve32x` mandates it, and the kernels this core is aimed at use divide
only in normalization and matrix inversion steps, both off the inner loop. The fallback is priced
in the subset section, and it is rare enough for the scalar divider to absorb.

### Fixed-point arithmetic

Built, and the reason is precision rather than conformance. The target workloads are matrix and
matrix-vector multiply inside control dynamics and model predictive control, with the dense
subproblems of simultaneous localization and mapping behind them; SLAM's sparse core needs the
indexed gather at the top of the stretch list, so it arrives in full only if that lands. Those
algorithms fail to converge at 8-bit integer precision. This core has no floating-point unit, so
fixed-point Q-format arithmetic is the only route to the precision they need.

Four instruction families carry it. `vsadd` and `vssub` are the saturating add and subtract, which
keep an accumulating update from wrapping. `vsmul` is the fractional multiply, computing
`clip(roundoff_signed(vs2[i]*vs1[i], SEW-1))`. `vssrl` and `vssra` are the rounding scaling shifts.
`vnclip` is the saturating narrowing clip. All four reuse the multiply array and the adders built
for single-width arithmetic, so the added hardware is the rounding increment logic, the saturation
comparators, and the `vxrm` and `vxsat` control registers at addresses `0x00A` and `0x009`,
mirrored in `vcsr` at `0x00F`. Both registers live in the vector unit rather than in `csr.sv`,
because `csr.sv`'s writes gate on `commit_valid` and a decoupled saturation update lands cycles
after its instruction committed, on a cycle the CSR file may be frozen. `csr.sv` keeps the
addresses: its read multiplexer returns the vector unit's live values through a read port, a Zicsr
write forwards across the same interface, and the wait in the coupling section keeps both
directions ordered against in-flight fixed-point work. The hardware carries no radix point of its
own, so the software chooses the Q format freely.

One obligation rides with 32-bit accumulation. The production reference for this shape,
CMSIS-DSP's `arm_mat_mult_q15`, accumulates in 64 bits precisely to absorb row-length growth, and
`Zve32x`'s 32-bit ceiling forecloses that. A 2.30 product in a 32-bit accumulator leaves one spare
integer bit, so the kernel owns its overflow headroom, pre-scaling inputs or bounding row length,
and the round 9 kernel documents that choice beside the measurement.

### Memory access patterns

Unit-stride and strided loads and stores are both built, at every element width `Zve32x` names, 8,
16 and 32. The headline kernel is the reason. The column form of a Q15 matrix-vector multiply
accumulates the output vector across matrix columns, and a column of a row-major matrix is a
strided access, `vlse16.v` at a row-length stride, while the row form is unit-stride but spends a
reduction per output element; Embench's `matmult-int` source reads its B operand by column the
same way. Through round 8 a strided element is one 32-bit cache access, the same traffic as the
scalar load it replaces, so the strided win there is instruction count and decoupling, not
bandwidth, and the dedicated path's whole-line transfers never apply to a strided access at all,
which the round 8 fork prices. The delta over unit-stride is address generation, base plus index
times stride rather than base plus a fixed element size, and the loss of the whole-line fast path.

### Traps, interrupts and `vstart`

Every check that could reject a vector instruction resolves in EX, before the instruction enters
the queue. Those checks are the opcode and encoding against the decode table, `vtype.vill` for the
instructions that depend on `vtype`, `mstatus.VS` reading Off, and alignment, judged up front from
the base address, the stride and the element count. Section 3.4.4 exempts the configuration
instructions and the whole-register loads, stores and moves from the `vill` gate, and the
exemption is load-bearing: `vill` is set at reset, and a gated `vsetvli` could never clear it. An
instruction that passes the checks is accepted into the queue, runs to completion, and is never
restarted. The machine therefore
never produces a nonzero `vstart`, and a vector instruction that finds `vstart` nonzero raises an
illegal-instruction exception, which section 3.7 permits per instruction for exactly this design.
The resumable form of `vstart` exists for machines that can fault partway through a vector memory
access, and this core has no source of such a fault. A decoupled unit also cannot reach it, because
the scalar pipeline has retired younger instructions by the time a vector memory access executes,
and a resumable trap would have no instruction left to return to. Saturn and Ara keep resumable
`vstart` only by resolving every possible fault before the scalar core commits, which is the same
structure at larger scale.

Interrupts are taken at scalar instruction boundaries without waiting for the vector unit. Work
already issued is committed and finishes in the background while the handler runs, the
memory-ordering rule above keeps the handler's own loads and stores ordered behind it, and the
configuration snapshot means a handler's own `vsetvli` cannot corrupt in-flight work. One caveat
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

Two divergences to know about when tests are written. Spike accepts a software-written nonzero
`vstart` where this machine traps, on any vector instruction, and no generated or planned test
writes one. And the up-front alignment trap is stricter than the specification's per-element
model: Spike completes the elements before a misaligned one, traps with `vstart` naming it, and
never faults a masked-off element, where this machine rejects the whole instruction with nothing
done. No generated or planned test issues a misaligned vector access, and the round 4 test filter
enforces that.

### Memory path

Vector loads and stores go through the existing data cache port first, at 32 bits per beat, the
beat count from the sequencer's element rules. The cache's CPU port is 32 bits wide and
`cpu_ready` asserts only on a hit in
COMPARE, so a 4-element load is 4 sequential accesses. That is slow, and it is coherent with scalar
accesses for free.

The path has exactly one requester today. `board_top.sv` wires the cache's `cpu_valid` straight to
`dmem_req && !periph_sel` from the MEM stage, with no mux in between, and the flat simulation `top`
that the lockstep runs wires the same core outputs straight into `dmem`. Sharing is therefore a
structure the vector memory round builds, not a wire it borrows, and it lands inside the core, in
front of the core's single data-memory interface, `dmem_req`, `mem_addr`, `store_data`,
`store_wstrb` and `read_data`, rather than at any board's cache port. Placed there, every top that
instantiates the pipelined core gets vector memory without modification, the flat `top` the
co-simulation runs, both board tops, and the uncached parameter build, whereas a board-level mux
would leave the lockstep with no way to execute a vector load at all. The single-cycle build is a
separate RTL tree with no vector unit and is out of scope.

The scalar side wins the grant, because a stalled MEM stage stalls the whole pipeline while the
vector unit is built to wait, and each vector beat is an independent transaction, letting the
grant re-arbitrate between beats with no mid-transfer abort. The grant is a latch, not a wire. The
cache samples a request in IDLE and answers in COMPARE with an untagged `cpu_ready` level, so the
mux latches the winner when the cache accepts it, holds that side's address, data and strobes
stable until its `cpu_ready`, and masks `dmem_ready` from the scalar pipeline whenever the port is
serving a vector beat. Without the mask, a scalar load arriving one cycle behind a vector beat
would see the beat's `cpu_ready`, sample the beat's read data as its own and never issue its
access; the ordering waits in the coupling section do not close that hole, because a scalar load
is allowed to run concurrently with a pending vector load. One wiring trap comes with the mux:
`mem_hold` at `datapath.sv:405` is computed from `dmem_req`,
and if the muxed request drove it, a vector beat missing in the cache would stall the entire
scalar pipeline for the duration of the miss, which is exactly what decoupling exists to avoid.
The hold keys on the scalar request alone; the muxed output feeds only the port.

One address-space constraint rides on this placement. The boards decode peripheral selects from
`mem_addr`, the muxed address, and a vector beat aimed at a peripheral tag would reach the
peripheral one element at a time with side effects no specification covers. Vector memory
instructions target main memory only. That is a documented software contract with no hardware
guard, and no generated or planned test produces a peripheral-range vector access.

The dedicated 128-bit path is a later change with a before-and-after measurement attached, built as
a fourth source on `mem_arb` rather than as a second cache. `mem_arb` already serializes 3 sources
at one outstanding transaction, and a `dc_req_wstrb` of `4'h0` already means write the whole
128-bit line, which is what an unmasked full-register vector store needs. A masked store cannot
ride that sentinel, because the 4-bit strobe field addresses one word of the line, so masked
stores stay on the 32-bit port or round 8 widens the strobe input, priced in that round. The
arbiter also exists only on the nexys_video top, which is where the measurement runs; the basys3
top keeps the 32-bit port. The data cache is write-back, and
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
or streaming profile favors the direct path, strided traffic is per-element on either route and
gains from neither, and round 8 decides with the numbers in hand.

## The fast forms, planned

Each block lands basic first and upgrades on a measurement, and the upgrades are planned work with
their own round. In priority order:

1. The dedicated memory path, decided between the `mem_arb` port and the widened cache port by the
   measured profile. The memory path section above carries the constraints; round 8 makes the
   call with the measurement in hand.
2. Concurrent execution inside the vector unit. The issue queue deepens to 2 and the memory unit
   runs a load or store while the arithmetic lanes execute a later instruction, tracked by a
   per-register-group busy scoreboard, with the register file gaining the port headroom
   concurrency needs, a store read port beside the arithmetic three and arbitration or a second
   port on writes. Memory beats dominate vector cycles on this machine, and
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
pipeline registers, which is where the drain in the sequencer's `done` rule comes from, and the
frequency gap the scalar core already carries stays its own workstream, unchanged by vector work.

## Verification

Three layers, each named by its real technique.

1. riscv-formal stays scalar only. The upstream `insns/` directory carries no vector instruction
   models, so there is nothing to enable. Its value is that the existing proof must still pass
   unchanged after the vector work lands, which shows the vector unit did not break the scalar core.
2. Spike lockstep co-simulation extended over `v0` through `v31`, `vl`, `vtype` and `vstart`. This
   is the primary check on vector behavior, it starts at round 2 by checking `vl` and `vtype` after
   every configuration instruction, and it grows with each round. The scalar stream carries no CSR
   fields today, so round 2 adds the `vl`, `vtype` and `vstart` debug taps beside the existing
   eight, the same threading pattern. Spike 1.1.1-dev accepts
   `--isa=rv32im_zve32x_zvl128b`, so VLEN of 128 is selected through the `Zvl128b` ISA string, and
   the bare string without `Zvl128b` silently models VLEN of 32.

   What "state after instruction i" means is decided here, because a decoupled unit breaks the
   scalar definition from round 3 on: vector register writes land cycles after the scalar pipeline
   retired the instruction, and sampling at scalar retirement would compare state that does not
   exist yet. The rule: the vector unit exports its own retirement stream, one event per vector
   instruction at the cycle its last write lands, carrying the register updates and any `vxsat`
   effect, and the comparator matches each event against Spike's state after that instruction, in
   program order. Configuration state and the x-register wait cases stay on the existing scalar
   stream, since they resolve at EX commit. Every issued vector instruction carries a sequence tag
   from issue, and the comparator orders events by tag rather than by arrival. Version 1 completes
   in order and the tag is redundant there, but the fast-forms round runs memory and arithmetic
   concurrently, which lets completions arrive out of program order, and a harness built on
   arrival order would need rebuilding the day the round lands. The tag exists from the first
   event. A vector store's event is defined the same way: its completion is the final beat's
   accepted handshake, its payload is the beat log, address, data and strobes per beat, and the
   comparator checks that log against the per-element memory writes Spike prints, because register
   comparison alone would catch a bad store only if a later load happened to read it back. An
   instruction that issues no writes at all, a load or store at `vl` of 0, still emits its event so
   the tag sequence stays gapless. `vxsat` belongs to the vector stream: each event's saturation
   effect updates the comparator's model, and a Zicsr read of it is checked as an ordinary `rd`
   value on the scalar stream, with the coupling section's wait guaranteeing the two views agree.
   One monitor obligation rides with this: `tb/cosim.sv` ends on a park sentinel, the same
   pc retiring twice, and a completion event still in flight at that moment would be dropped
   without any test failing. The monitor finishes only after the vector unit reports idle, and
   idle is a conjunction, issue queue empty, sequencer not busy, both pending flags clear, and no
   retirement event still unexported.
3. A directed testbench for every new module, plus one bounded SymbiYosys proof on the configuration
   unit. That unit is purely combinational over a small input space, so a proof covers every SEW,
   LMUL, AVL and instruction variant exhaustively where a testbench only samples.

Four facts about the reference model shape the tests, each verified by running Spike and reading
its source. Spike implements both agnostic policies as undisturbed and has no mode that writes
ones, which means a machine that is undisturbed everywhere, mask-destination tails included,
matches it bit for bit. Spike zeroes all 32 vector registers at reset, and the register file's
`initial` zero-fill matches that at simulation start; every test still initializes the full
register file before comparing, because a soft reset does not re-zero the array. Spike traps
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

Also in the build, each named here with its round, because a round title alone would not imply it:

- `vmin` and `vmax` in vector-vector and vector-scalar forms, because the model-predictive-control
  projection clamps against per-element bounds held in memory. Round 3.
- `vrsub`, whose `x0` form is the negate `vneg`, because the extension has no integer absolute
  value and negation is how one is composed. Round 3.
- `vmerge`, the `vmv.v` moves, and the sign and zero extensions `vsext` and `vzext`. `vmerge` and
  the moves land in round 3 with the `v0` data port they need; the extensions land with the other
  mixed-width work in round 5.
- `vmulh`, `vmulhu` and `vmulhsu`, the high-half multiplies, mandated and near-free once the array
  produces full products. Round 5.
- The narrowing shifts `vnsra` and `vnsrl`, the plain narrowing right shifts for Q-format
  conversions that do not want `vnclip`'s saturation, sharing its datapath minus the rounding and
  clip. Round 5.
- The sum, widening sum, minimum, maximum, and, or and xor reductions, with `vmv.s.x` and
  `vmv.x.s` seeding and reading them. Round 5. The sum pair closes the row form of a dot product;
  the minimum and maximum pair computes the solver's infinity-norm convergence test without an
  absolute-value instruction, as the max of the max and the negated min; the logical three are
  mandated and cost one mux each on the existing tree.
- The whole-register moves, loads and stores, at the fixed element count section 7.9 assigns them,
  which close off a class of compiler and generated-test surprises. Moves in round 3, loads and
  stores in round 4. The EEW 64 whole-register loads, `vl1re64.v` through `vl8re64.v`, trap as an
  unsupported element width, checked against Spike's decode in round 4.
- The mask loads and stores `vlm.v` and `vsm.v`, at ceil(vl/8) bytes per section 7.4. Round 7, on
  round 4's path.
- The mask instructions `vcpop`, `vfirst`, `vmsbf`, `vmsif`, `vmsof`, `viota` and `vid`, and the
  mask-logical eight, `vmand`, `vmnand`, `vmandn`, `vmor`, `vmnor`, `vmorn`, `vmxor` and
  `vmxnor`, whose aliases `vmset`, `vmclr`, `vmmv` and `vmnot` are how generated tests initialize
  masks. Round 7.

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
- The multi-element slides `vslideup` and `vslidedown`. No inner-loop kernel touches them, and the
  rare element extraction the divide fallback needs goes through memory instead.
- Fault-only-first loads. They exist to vectorize loops over data of unknown length, and no target
  workload has that shape. The compiler flags in the verification section keep them out of
  compiled code.
- The carry chains `vadc`, `vsbc`, `vmadc` and `vmsbc`, which serve multi-word arithmetic.
- The averaging adds `vaadd` and `vasub`.
- Vector divide and remainder, per the reasoning in the multiply section. The fallback is priced
  here: spill the vector to memory, run the scalar divider element by element, reload, every step
  ordered behind the pending-store wait. Normalization and inversion steps are rare enough to
  absorb it, and that pricing is why the multi-element slides stay out rather than becoming an
  extraction path.

## Where the vector opcodes enter the existing core

Recorded from reading the core, so no round has to rediscover it.

- `datapath.sv` computes `exc_illegal` from an opcode whitelist. `OP-V` at `0x57`, `LOAD-FP` at
  `0x07` and `STORE-FP` at `0x27` are all absent, so every vector instruction currently traps as
  illegal. That whitelist is where vector opcodes are admitted, and admission is per instruction,
  not per group: `funct3` only selects the operand class, `vdiv` shares OPMVV with `vmul` and
  `vrgather` shares OPIVV with `vadd`, so each round extends a `funct6`, `funct3` and `vm` decode
  table and every encoding the table does not list traps as illegal instruction. Spike executes
  the unbuilt instructions, so no lockstep test may contain one; the filename filter in the
  verification section is what enforces that.
- `csr.sv` is a flat read multiplexer plus a write case statement, and an unimplemented address
  currently reads as zero rather than trapping. The vector control registers follow the same shape.
- The EX result multiplexer at `datapath.sv:617` (`result_ex`) already routes `csr_rdata` for the
  Zicsr instructions, and the configuration instructions ride the same path with the select widened
  to admit them. Their `rd` value then flows through `alu_result_mem` and writes back on the
  existing `result_src` value of zero, exactly the route a `muldiv` result takes, so the forwarding
  network needs no change. The x-register wait cases, `vmv.x.s`, `vcpop.m` and `vfirst.m`, return
  through the same EX path during their hold, the `muldiv` route, so the separate writeback
  multiplexer, the `result_src_wb` case statement at `datapath.sv:723`, keeps its `2'd3` encoding
  spare and no new writeback source exists.
- Every sequential block in the core gates on `core_en`, the divided tick from `tick_gen`
  (`ClkDiv` is 2 on both board tops, half the board clock; the flat simulation `top` ties it
  high), the riscv-formal shadow pipeline under its `ifdef` excepted, which the formal and cosim
  tops tie high anyway. A vector `always_ff` without that
  gate runs at the board rate against a half-rate core and is simply wrong, and every flop the
  vector unit adds carries the same `if (core_en)` guard. Neither constraints file claims the
  divided rate as timing slack today, and once the vector multiply array exists, a
  `set_multicycle_path` exception on the enable-gated paths is the cheap way to buy it timing
  room without touching the clock.
- `regfile.sv` is a flat array with combinational reads and write-first bypass. The vector register
  file mirrors the read shape, wider, and drops the bypass for the reason the register file
  section gives.
- `commit_valid` at `datapath.sv:371` gates the architectural writes `csr.sv` makes for retiring
  instructions; the free-running `mcycle` is the deliberate exception, counting cycles on
  `cycle_en` by design. Vector issue gates on the same signal: an instruction enters the issue
  queue only on a committing cycle, and configuration-state writes commit the same way, since a
  vector instruction in the shadow of a mispredicted branch would otherwise corrupt `vtype` or
  enqueue work with no way to recover it. The register writes the decoupled unit makes later are
  deliberately not gated by it, because their instruction committed cycles earlier; the queue gate
  is what keeps shadowed work out.

## Rounds

Work proceeds one round at a time. Each round designs its own scope, builds it, and stops. No round
starts before the one before it closes.

1. What a vector instruction is on this core. **Closed.** Settled VLEN and DLEN.
2. The configuration instructions and the vector control registers. First RTL: the combinational
   configuration unit and its `vill` table, the CSR entries, `mstatus.VS` with its write
   legalizer, Dirty transition and derived SD, the read-only-quadrant trap, and the `vl`, `vtype`
   and `vstart` debug taps the lockstep's scalar stream reads.
3. The vector unit's skeleton and single-width integer arithmetic: the issue queue with its
   configuration snapshot and `commit_valid` gate, the element sequencer, the busy and done
   handshake and the hold terms, the register file with its `v0` data port, the decode table, the
   retirement-event export with its sequence tags and idle signal, and the comparator extension
   over `v0` through `v31` that consumes it.
4. Unit-stride and strided vector loads and stores through the existing data cache, including the
   in-core memory mux with its grant latch, the pending-work flags and their ordering holds, the
   whole-register loads and stores, and the `fence` decode and drain that the memory path and trap
   sections name.
5. Multiply, multiply-add, widening and narrowing operations, the high-half multiplies, and the
   reductions, with the x-register return path `vmv.x.s` rides through its EX hold.
6. Fixed-point saturating add, multiply, scaling shifts, saturating narrow, and the rounding-mode
   registers in the vector unit with their `csr.sv` read and write forwarding.
7. Masks and compares: the mask-format destination writes on the per-bit enables, the mask-logical
   instructions, the masked-store strobe suppression reaching into round 4's beat generator,
   `vlm.v` and `vsm.v`, and `vcpop` and `vfirst` on the round 5 return path.
8. The dedicated vector memory bandwidth, decided between a fourth `mem_arb` source and a widened
   cache CPU port by the measured profile, with the speedup measured against round 4 and the
   cache-interaction mechanism the memory path section names.
9. The full-subset lockstep sweep, the scalar Q15 reference kernel written for the baseline, and
   the measured kernel against the scalar core.
10. The fast forms in priority order, the deeper issue queue with concurrent memory and arithmetic
    execution and the register-file ports it needs, then scalar-vector address disambiguation,
    each with a before-and-after measurement.

The headline result is a fixed-point matrix-vector multiply measured on the board against the
scalar core at the same clock, in cycles from `mcycle`, in the column form: the output vector
accumulates across matrix columns, each column one strided load, each step a widening
multiply-accumulate of Q15 data into 32-bit accumulators, the epilogue one `vnclip`, and the
source LMUL capped at 4 by the widening destination. That form exercises strided loads,
multiply-accumulate and the fixed-point rounding path; the reductions are exercised by the second
measured kernel, the solver's infinity-norm convergence test, built from the max and negated min
reductions. A Q31 variant runs single-width through `vsmul`. Embench `matmult-int` gives an
integer matrix baseline already measured on this flow, and the scalar Q15 reference the headline
compares against is written in round 9. Accumulating in 64 bits is the one path `Zve32x`
forecloses, since the widest element is 32 bits, and the accumulator-headroom note in the
fixed-point section is the price.
