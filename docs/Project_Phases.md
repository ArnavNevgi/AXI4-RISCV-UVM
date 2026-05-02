# RISC-V + AXI4 + UVM SoC Project

## Project Goal

Build an industry-grade SoC-level design and verification project integrating:

- RISC-V CPU
- AXI4 master/slave components
- AXI4 interconnect
- DMA controller
- SRAM / FIFO / AXI-Lite register slaves
- UVM verification environment

Current focus: AXI4 foundation and robustness testing.

---

# Phase 1: AXI Foundation — Complete

## Implemented

### RTL / Design

- `axi_pkg.sv`
  - AXI parameters
  - AXI burst type enum
  - AXI response enum
  - Packed structs for AW/AR, W, B, and R channels

- `axi_if.sv`
  - AXI4 interface
  - Master and slave modports
  - Protocol stability assertions

- `axi_master.sv`
  - FSM-based AXI master
  - Write address channel: AW
  - Write data channel: W
  - Write response channel: B
  - Read address channel: AR
  - Read data channel: R
  - INCR burst support
  - Variable burst length support

- `axi_ifdummytb.sv`
  - SystemVerilog self-checking testbench
  - AXI memory-model slave
  - Randomized ready/backpressure behavior
  - Scoreboard-based data integrity checking

---

## Phase 1 Features Verified

### Write Path

- `AWVALID/AWREADY` handshake
- `WVALID/WREADY` handshake
- `WDATA` stability during `WREADY=0`
- Correct beat counter update only after handshake
- Correct `WLAST` assertion on final beat
- `BVALID/BREADY` response completion

### Read Path

- `ARVALID/ARREADY` handshake
- `RVALID/RREADY` handshake
- Correct `RDATA` return from memory model
- Correct `RLAST` assertion on final beat
- `rd_done` triggered only after final read beat

### Burst Support

Verified AXI `LEN` values:

| AXI LEN | Number of Beats |
|---:|---:|
| 0 | 1 |
| 1 | 2 |
| 3 | 4 |
| 7 | 8 |
| 15 | 16 |

---

# Phase 2: Advanced AXI Component Robustness — Complete

## Added in Phase 2

### 1. Delayed / Gapped Read Response

The slave model now adds randomized delay before read data beats.

This verifies that the master correctly waits for `RVALID` and does not assume fixed-latency reads.

### 2. Stronger Protocol Assertions

Assertions added in `axi_if.sv`:

- AW payload stable while waiting for `AWREADY`
- W payload stable while waiting for `WREADY`
- AR payload stable while waiting for `ARREADY`
- B payload stable while waiting for `BREADY`
- R payload stable while waiting for `RREADY`
- `WLAST` only asserted when `WVALID` is high
- `RLAST` only asserted when `RVALID` is high

### 3. Edge-Case Burst Tests

Added tests for:

- minimum address
- 1-beat bursts
- 2-beat bursts
- 4-beat bursts
- 8-beat bursts
- 16-beat bursts
- different aligned base addresses
- different data patterns

### 4. Write Burst Protocol Checker

The testbench checks:

- W data does not arrive before AW is accepted
- number of W beats matches `AWLEN + 1`
- `WLAST` occurs exactly on the final beat
- early `WLAST` is flagged
- missing `WLAST` is flagged
- excess W beats are flagged

### 5. Read Burst Protocol Checker

The testbench checks:

- R data does not arrive before AR is accepted
- number of R beats matches `ARLEN + 1`
- `RLAST` occurs exactly on the final beat
- early `RLAST` is flagged
- missing `RLAST` is flagged
- excess R beats are flagged

### 6. Randomized Burst Regression

Randomized regression tests include:

- random burst lengths from 1 to 16 beats
- random aligned addresses within memory range
- random write data
- randomized `AWREADY`
- randomized `WREADY`
- randomized `ARREADY`
- randomized `BVALID` delay
- randomized `RVALID` delay/gaps

---

# Self-Checking Verification

The testbench includes an expected-memory scoreboard.

## Scoreboard Behavior

- Every accepted W beat updates expected memory.
- Every accepted R beat is compared against expected memory.
- The test fails if any read data mismatch occurs.
- The test fails if any protocol checker error occurs.
- The test passes only when `error_count == 0`.

Example passing output:

```text
PHASE 2 STEP 7 PASS: Randomized burst regression completed

# Phase 3: CPU Integration — Complete

## Goal

Build a minimal RISC-V CPU core and connect it to the AXI infrastructure through a CPU-to-AXI adapter.

The CPU core uses a simple memory-request interface. The `cpu_axi_adapter.sv` module converts CPU load/store requests into AXI single-beat read/write transactions.

---

## Implemented Files

### `alu.sv`

Minimal ALU supporting:

- `ADD`
- `SUB`
- zero flag generation

Verified with:

- `alu_tb.sv`

---

### `reg_file.sv`

32-register RISC-V register file.

Features:

- 32 general-purpose registers
- two asynchronous read ports
- one synchronous write port
- `x0` hardwired to zero
- writes to `x0` ignored
- reset clears all registers

Verified with:

- `reg_file_tb.sv`

---

### `control_unit.sv`

Decoder for the supported RISC-V subset.

Supported instructions:

| Instruction | Type | Description |
|---|---|---|
| `ADD` | R-type | Register-register addition |
| `SUB` | R-type | Register-register subtraction |
| `LW` | I-type | Load word |
| `SW` | S-type | Store word |

Decoded control signals:

- `reg_write`
- `mem_read`
- `mem_write`
- `mem_to_reg`
- `alu_src`
- `alu_op`
- `rs1`
- `rs2`
- `rd`
- `imm`

Verified with:

- `control_unit_tb.sv`

---

### `riscv_core.sv`

Minimal multicycle RISC-V core.

FSM stages:

- `FETCH`
- `DECODE`
- `EXECUTE`
- `MEM`
- `WRITEBACK`

Supported instructions:

- `ADD`
- `SUB`
- `LW`
- `SW`

Interfaces:

- instruction memory interface:
  - `imem_addr`
  - `imem_rdata`

- simple data-memory interface:
  - `dmem_valid`
  - `dmem_write`
  - `dmem_addr`
  - `dmem_wdata`
  - `dmem_rdata`
  - `dmem_ready`

Verified with:

- `riscv_core_tb.sv`

---

### `cpu_axi_adapter.sv`

Adapter from the CPU memory interface to AXI.

CPU-side interface:

- `cpu_valid`
- `cpu_write`
- `cpu_addr`
- `cpu_wdata`
- `cpu_rdata`
- `cpu_ready`

AXI-side interface:

- `axi_if.master`

Supported behavior:

- CPU store converts to single-beat AXI write
- CPU load converts to single-beat AXI read
- `AWLEN = 0`
- `ARLEN = 0`
- `WLAST = 1`
- waits for `BVALID/BREADY` on writes
- waits for `RVALID/RREADY/RLAST` on reads
- uses a `DONE` state to safely handle held-valid CPU requests

Verified with:

- `cpu_axi_adapter_tb.sv`

---

### `riscv_core_axi_tb.sv`

Full Phase 3 integration testbench.

Integration path:

```text
RISC-V core
  ↓
simple CPU memory interface
  ↓
cpu_axi_adapter
  ↓
AXI interface
  ↓
AXI memory model

---

# Phase 4: DMA Controller — Complete

## Goal

Build a DMA controller that can copy data from one memory region to another using AXI transactions.

The DMA operates as an AXI master. It reads from a source address, writes to a destination address, and asserts `done` after the transfer completes.

---

## Implemented Files

### `dma_controller.sv`

Single-beat DMA controller.

Behavior:

- reads one 32-bit word from source address
- writes one 32-bit word to destination address
- increments source and destination addresses
- repeats until `length` words are copied
- supports `busy`, `done`, and `error` status

Verified with:

- `dma_controller_tb.sv`

Test coverage:

- zero-length transfer
- 1-word copy
- 4-word copy
- 8-word copy
- randomized DMA copy regression
- start-while-busy protection
- protocol checks for single-beat AXI transactions

---

### `dma_controller_burst.sv`

Burst-mode DMA controller.

Behavior:

- reads source memory using AXI INCR bursts
- buffers read data internally
- writes buffered data to destination memory using AXI INCR bursts
- supports burst transfers up to 16 words per AXI burst
- supports larger transfers by splitting into multiple bursts

Example:

```text
length = 40 words
burst 1 = 16 words
burst 2 = 16 words
burst 3 = 8 words

Verified with:

dma_controller_burst_tb.sv

Test coverage:

1-word burst copy
4-word burst copy
8-word burst copy
16-word burst copy
17-word multi-burst copy
20-word multi-burst copy
32-word multi-burst copy
40-word multi-burst copy
randomized burst DMA regression up to 64 words
randomized source and destination addresses
randomized data patterns
random AWREADY
random WREADY
random ARREADY
delayed/gapped RVALID
delayed BVALID
burst protocol checking
scoreboard-style memory copy checking
DMA Control / Status

DMA control inputs:

start
src_addr
dst_addr
length

DMA status outputs:

busy
done
error

Verified status behavior:

busy asserts during active DMA transfer
done is asserted after transfer completion
zero-length transfer completes without modifying memory
start while busy is ignored
error is asserted on AXI response errors
Phase 4 Verification Summary

The DMA was verified using self-checking SystemVerilog testbenches.

Verified scenarios:

fixed-length DMA copies
randomized DMA copies
single-beat DMA transfers
AXI burst DMA transfers
multi-burst splitting for transfers larger than 16 words
backpressure on AXI address/data channels
delayed AXI responses
status/control behavior
destination memory checked against source memory

---

# Phase 5: AXI Interconnect — Complete

## Goal

Build a 2-master / 1-slave AXI interconnect and use it to connect the CPU and DMA to shared AXI memory.

The interconnect allows multiple AXI masters to access one shared slave while preserving response routing and transaction ownership.

---

## Implemented Files

### `axi_interconnect_2m1s.sv`

2-master / 1-slave AXI interconnect.

Masters:

- `M0`: CPU AXI adapter
- `M1`: DMA burst controller

Slave:

- `S0`: shared AXI memory / slave port

Features:

- fixed-priority arbitration
  - `M0 > M1`
- independent read and write ownership tracking
- read response routing to correct master
- write response routing to correct master
- single-beat transaction support
- burst transaction support
- one active read transaction at a time
- one active write transaction at a time

---

## Verification Files

### `axi_interconnect_2m1s_tb.sv`

Standalone interconnect testbench.

Verified:

- `M0` write routing
- `M1` write routing
- `M0` read routing
- `M1` read routing
- cross-master reads
- fixed-priority AW arbitration
- fixed-priority AR arbitration
- `RREADY` backpressure routing
- `BREADY` backpressure routing
- burst write routing
- burst read routing
- `WLAST`/`RLAST` handling through interconnect

Passing output:

```text
PHASE 5 STEP 5 PASS: burst routing through interconnect verified
M0/M1 single-beat, arbitration, backpressure, and burst routing passed

dma_interconnect_tb.sv

DMA-through-interconnect testbench.

Integration path:

dma_controller_burst
  -> axi_interconnect_2m1s
  -> shared AXI memory

Verified:

real DMA burst master connected as M1
DMA transfers through interconnect
4-word transfer
16-word transfer
20-word multi-burst transfer
40-word multi-burst transfer
randomized DMA/interconnect regression
multi-burst DMA splitting through interconnect

cpu_dma_interconnect_tb.sv

CPU + DMA shared-interconnect integration testbench.

Integration path:

RISC-V core
  -> cpu_axi_adapter
  -> M0 of axi_interconnect_2m1s

dma_controller_burst
  -> M1 of axi_interconnect_2m1s

axi_interconnect_2m1s
  -> shared AXI memory

Verified:

CPU data accesses through interconnect
DMA accesses through interconnect
CPU-generated data copied by DMA
CPU and DMA sharing one AXI memory
overlapping CPU/DMA traffic
fixed-priority arbitration under active traffic
DMA completion while CPU is also accessing memory

---

# Phase 6: AXI Slaves — Complete

## Goal

Build reusable AXI-accessible slave blocks and replace testbench-only memory models with RTL-style slave modules.

Phase 6 adds reusable memory, register, and FIFO/peripheral slaves for future SoC integration.

---

## Implemented Files

### `axi_sram_slave.sv`

Reusable AXI SRAM slave.

Features:

- AXI write address/data/response support
- AXI read address/data support
- INCR burst support
- single-beat read/write support
- burst read/write support
- `WLAST` checking
- `RLAST` generation
- OKAY responses
- parameterized memory depth

Verified with:

- `axi_sram_slave_tb.sv`

Test coverage:

- single-beat write/read
- 4-beat burst write/read
- 8-beat burst write/read
- 16-beat burst write/read
- randomized burst access regression

Passing output:

```text
PHASE 6 STEP 2 PASS: AXI SRAM slave verified
single-beat, burst, and randomized SRAM accesses passed

cpu_dma_sram_tb.sv

Integration test using the reusable AXI SRAM slave.

Integration path:

RISC-V core
  -> cpu_axi_adapter
  -> M0 of axi_interconnect_2m1s

dma_controller_burst
  -> M1 of axi_interconnect_2m1s

axi_interconnect_2m1s
  -> axi_sram_slave

Verified:

CPU data accesses through interconnect and SRAM
DMA accesses through interconnect and SRAM
CPU-generated data copied by DMA
overlapping CPU/DMA traffic using reusable SRAM slave
replacement of previous testbench memory model

axi_lite_reg_slave.sv

AXI-Lite-style register slave.

Register map:

Address	Register
0x00	CONTROL
0x04	STATUS
0x08	SRC_ADDR
0x0C	DST_ADDR
0x10	LENGTH

Features:

single-beat AXI-style writes
single-beat AXI-style reads
OKAY responses
invalid writes ignored
invalid reads return zero

Verified with:

axi_lite_reg_slave_tb.sv

Test coverage:

reset values
register write/read
overwrite behavior
invalid address behavior
randomized register access regression

imple_fifo_slave.sv

Simple memory-mapped FIFO peripheral.

Register map:

Address	Register	Behavior
0x00	CONTROL	bit 0 clears FIFO
0x04	STATUS	empty/full/overflow/underflow/count
0x08	TX_DATA	write pushes data into FIFO
0x0C	RX_DATA	read pops data from FIFO
0x10	DEPTH	returns FIFO depth

STATUS bits:

Bit	Meaning
0	empty
1	full
2	overflow
3	underflow
15:8	FIFO count

Verified with:

simple_fifo_slave_tb.sv

Test coverage:

reset status
push/pop ordering
FIFO full behavior
overflow flag
FIFO drain behavior
underflow flag
clear behavior
invalid address behavior
randomized push/pop test

---

# Phase 7: Top Integration — Complete

## Goal

Build a reusable SoC-level top that integrates:

- RISC-V CPU
- CPU-to-AXI adapter
- burst DMA controller
- 2-master / 2-slave AXI interconnect
- AXI SRAM slave
- DMA control/status register slave

The main Phase 7 goal was to allow the CPU to configure and start DMA through memory-mapped registers.

---

## Implemented Files

### `axi_interconnect_2m2s.sv`

2-master / 2-slave AXI interconnect.

Masters:

- `M0`: CPU AXI adapter
- `M1`: DMA burst controller

Slaves:

- `S0`: AXI SRAM slave
- `S1`: DMA/register slave

Address map:

| Address Range | Slave |
|---:|---|
| `0x0000_xxxx` | AXI SRAM |
| `0x0001_xxxx` | DMA/register space |

Features:

- fixed-priority arbitration: `M0 > M1`
- SRAM/register address decoding
- read ownership tracking
- write ownership tracking
- read response routing
- write response routing
- burst routing to SRAM
- single-beat register access routing

Verified with:

- `axi_interconnect_2m2s_tb.sv`

Passing output:

```text
PHASE 7 STEP 2 PASS: 2M2S AXI interconnect verified
SRAM/register address decode and response routing passed
dma_reg_slave.sv

DMA control/status register slave.

Register map:

Address	Register	Description
0x00	CONTROL	bit 0 = write 1 to start DMA
0x04	STATUS	bit 0 = done, bit 1 = busy, bit 2 = error
0x08	SRC_ADDR	DMA source address
0x0C	DST_ADDR	DMA destination address
0x10	LENGTH	DMA transfer length in 32-bit words

Features:

CPU-writable DMA configuration registers
one-cycle dma_start_pulse
DMA busy/done/error status reflection
sticky done/error bits
status clear behavior
invalid reads return zero
invalid writes ignored

CPU ISA Extension

The CPU was extended to support:

ADDI
LUI

Reason:

The previous CPU supported only ADD, SUB, LW, and SW. To access DMA registers at 0x0001_0000, the CPU needed to generate high immediate addresses.

Verified with:

riscv_core_addi_lui_tb.sv

soc_2m2s_integration_tb.sv

Integration shell testbench.

Verified:

CPU accesses SRAM through the 2M2S interconnect
DMA register slave is integrated on the register slave port
DMA register outputs are correctly wired
SoC integration shell is structurally correct

soc_cpu_controlled_dma_tb.sv

End-to-end CPU-controlled DMA testbench.

Verified:

CPU executes LUI, ADDI, and SW instructions
CPU writes SRC_ADDR
CPU writes DST_ADDR
CPU writes LENGTH
CPU writes CONTROL.START
DMA register slave generates dma_start_pulse
DMA copies SRAM data
DMA completion is observed
DMA status done bit becomes sticky

soc_top.sv

Current external interface:

clock/reset
instruction memory interface
debug PC
DMA busy/done/error status

Instruction memory is still external. Data memory and DMA registers are integrated inside the SoC through AXI.

soc_top_tb.sv

Reusable SoC top-level testbench.

Verified:

CPU runs a program from external instruction memory
CPU configures DMA through memory-mapped registers
DMA copies SRAM data
DMA done status is set
reusable soc_top.sv works end-to-end

---

# Phase 8: UVM Verification — Complete

## Goal

Build a UVM-based verification environment around the integrated SoC top.

The UVM environment verifies CPU-controlled DMA behavior, AXI monitor traffic, scoreboard data correctness, functional coverage, and regression execution.

---

## Implemented Files

### `uvm/axi_uvm_pkg.sv`

UVM package containing:

- AXI transaction item
- AXI passive monitor
- SoC scoreboard
- SoC environment
- base UVM test

---

### `uvm/axi_transaction.sv`

UVM sequence item used by passive monitors.

Captured fields:

- transaction kind: read/write
- AXI ID
- address
- data
- burst length
- last beat
- response

---

### `uvm/axi_monitor.sv`

Passive AXI monitor.

Features:

- monitors AW/W/B write traffic
- monitors AR/R read traffic
- publishes transactions through analysis ports
- checks W beat before AW
- checks R beat before AR
- checks early/missing `WLAST`
- checks early/missing `RLAST`
- checks non-OKAY B/R responses
- supports CPU AXI and DMA AXI monitoring

---

### `uvm/soc_scoreboard.sv`

SoC scoreboard.

Checks:

- CPU writes DMA `SRC_ADDR`
- CPU writes DMA `DST_ADDR`
- CPU writes DMA `LENGTH`
- CPU writes DMA `CONTROL.START`
- DMA performs expected number of reads
- DMA performs expected number of writes
- DMA write data matches previously observed DMA read data
- DMA read queue is empty at end of test

Also includes functional coverage for:

- CPU vs DMA agent
- read vs write transaction
- CPU register write addresses
- DMA source address ranges
- DMA destination address ranges
- burst length
- last beat behavior
- agent/kind cross coverage

---

### `uvm/soc_env.sv`

UVM environment containing:

- CPU AXI monitor
- DMA AXI monitor
- SoC scoreboard

Connections:

```text
cpu_mon.analysis_port -> scoreboard.cpu_imp
dma_mon.analysis_port -> scoreboard.dma_imp
