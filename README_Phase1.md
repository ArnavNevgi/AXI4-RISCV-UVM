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