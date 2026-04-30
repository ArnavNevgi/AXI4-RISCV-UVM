# Phase 1: AXI Foundation

## Goal

Build and verify a basic AXI4 master with burst write/read support using a self-checking SystemVerilog testbench.

## Implemented Files

- `axi_pkg.sv`
  - AXI enums
  - AXI packed structs
  - burst and response type definitions

- `axi_if.sv`
  - AXI channel interface
  - master/slave modports
  - basic protocol assertions

- `axi_master.sv`
  - FSM-based AXI master
  - AW, W, B, AR, R channel support
  - burst write support
  - burst read support
  - variable burst length support

- `axi_ifdummytb.sv`
  - AXI memory-model slave
  - randomized ready/backpressure
  - delayed B response
  - self-checking scoreboard

## Features Verified

### Write Path

- AWVALID/AWREADY handshake
- WVALID/WREADY handshake
- WDATA stable during WREADY stalls
- WLAST asserted only on final beat
- BVALID/BREADY response completion

### Read Path

- ARVALID/ARREADY handshake
- RVALID/RREADY handshake
- RDATA returned correctly from memory
- RLAST asserted only on final beat

### Burst Support

Verified variable AXI burst lengths:

| AXI LEN | Number of Beats |
|---:|---:|
| 0 | 1 |
| 1 | 2 |
| 3 | 4 |
| 7 | 8 |

### Backpressure

Randomized backpressure was applied on:

- AWREADY
- WREADY
- ARREADY

B response delay was randomized.

## Scoreboard

The testbench contains an expected-memory scoreboard.

Write beats update expected memory.

Read beats are compared against expected memory.

A test passes only if every read beat matches the expected data.

## Final Result

Example passing output:

```text
PHASE 1 PASS
AXI4 burst write/read test completed
Variable burst lengths passed
Backpressure handling passed
Scoreboard matched all read data