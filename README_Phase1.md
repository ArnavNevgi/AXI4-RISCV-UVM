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