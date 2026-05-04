# RISC-V SoC with AXI4 DMA and UVM Verification

## Overview

This repository implements a SystemVerilog SoC-style design that connects a minimal RISC-V control core, AXI4-style interconnects, AXI-accessible SRAM/register slaves, and a CPU-controlled DMA engine. The CPU programs DMA source, destination, length, and control registers through an AXI path, and the DMA then performs memory-to-memory copies through the shared interconnect. The project includes directed SystemVerilog testbenches, protocol assertions, passive UVM monitors, a UVM scoreboard, functional coverage, and a saved Questa/ModelSim coverage report. The design is intended as a focused digital design and ASIC verification project, not as a full production RISC-V processor or tapeout-ready SoC.

## Key Features

- Minimal multicycle RISC-V control core with `FETCH`, `DECODE`, `EXECUTE`, `MEM`, and `WRITEBACK` states.
- Supported instruction subset visible in RTL/tests: `ADD`, `SUB`, `LW`, `SW`, `ADDI`, and `LUI`.
- CPU-to-AXI adapter that converts CPU load/store requests into single-beat AXI read/write transactions.
- AXI4 subset package/interface with typed AW/AR, W, B, and R channel structs, master/slave modports, and protocol stability assertions.
- Standalone AXI master block with INCR burst support.
- Single-beat and burst DMA controllers; the burst DMA supports AXI INCR bursts up to 16 words and splits larger transfers into multiple bursts.
- 2-master/1-slave and 2-master/2-slave AXI interconnects with fixed-priority arbitration (`M0 > M1`), ownership tracking, response routing, and burst routing.
- 2M2S address map in `soc_top.sv`:
  - `0x0000_xxxx`: AXI SRAM
  - `0x0001_xxxx`: DMA register space
- CPU-controlled DMA register slave with:
  - `0x00 CONTROL` - bit 0 starts DMA
  - `0x04 STATUS` - done, busy, and error status
  - `0x08 SRC_ADDR`
  - `0x0C DST_ADDR`
  - `0x10 LENGTH`
- AXI SRAM slave with single-beat and burst read/write support.
- Additional AXI-accessible register and FIFO slave examples.
- Directed self-checking tests for CPU blocks, DMA controllers, AXI slaves including the DMA register slave, interconnects, and SoC integration.
- UVM environment with passive CPU/DMA AXI monitors, scoreboard checks, and functional coverage.
- AXI/SVA checks for stable VALID payloads and `WLAST`/`RLAST` validity.

## Repository Structure

```text
AXI4-RISCV-UVM/
|-- rtl/
|   |-- common/        AXI package and AXI interface with assertions
|   |-- axi/           AXI master and 2M1S/2M2S interconnect RTL
|   |-- cpu/           Minimal RISC-V core, ALU, register file, decoder, CPU AXI adapter
|   |-- dma/           Single-beat and burst DMA controller RTL
|   |-- slaves/        AXI SRAM, AXI-Lite register, DMA register, and FIFO slaves
|   `-- top/           Integrated SoC top level
|-- tb/
|   |-- phase1_axi/    AXI master/interface directed testbench
|   |-- cpu/           CPU block and CPU/AXI directed testbenches
|   |-- dma/           DMA controller directed and randomized testbenches
|   |-- interconnect/  AXI interconnect directed testbenches
|   |-- slaves/        AXI slave directed testbenches
|   |-- integration/   CPU, DMA, SRAM, interconnect, and SoC integration tests
|   `-- uvm/           UVM top-level SoC testbench
|-- uvm/               UVM transaction, monitor, scoreboard, environment, and base test
|-- scripts/           Questa/ModelSim DO scripts
|-- docs/              Phase-by-phase project notes
`-- regressions/
    `-- coverage/      Saved Phase 8 functional coverage report
```

Generated simulator artifacts such as `work/`, `*.ucdb`, `*.wlf`, and logs are ignored by git and may appear after running simulations.

## Architecture

The top-level integration is in `rtl/top/soc_top.sv`.

```text
External instruction memory
        |
        v
Minimal RISC-V core
        |
        v
CPU data-memory request interface
        |
        v
cpu_axi_adapter --------------.
        |                     |
        | M0                  | M1
        v                     v
2-master / 2-slave AXI interconnect <--- dma_controller_burst
        |
        |-- S0: axi_sram_slave at 0x0000_xxxx
        |
        `-- S1: dma_reg_slave at 0x0001_xxxx
```

The CPU currently fetches instructions from an external instruction-memory interface. Data accesses are converted into AXI transactions by `cpu_axi_adapter.sv`. To start a DMA transfer, the CPU writes `SRC_ADDR`, `DST_ADDR`, `LENGTH`, and `CONTROL.START` in the DMA register slave. The register slave generates a one-cycle `dma_start_pulse`, which starts `dma_controller_burst.sv`. The DMA then reads from the source region in AXI SRAM and writes the copied data to the destination region through the shared AXI interconnect.

The interconnect routes CPU traffic as master `M0` and DMA traffic as master `M1`. The 2M2S version decodes SRAM versus DMA-register space using the upper address bits and strips the register-space base address before accessing the local register map.

## Verification Strategy

- Directed SystemVerilog tests verify individual CPU blocks: ALU, register file, control unit, RISC-V core, CPU AXI adapter, and CPU-plus-AXI behavior.
- AXI directed tests exercise handshakes, INCR bursts, delayed read responses, randomized ready/backpressure, and write/read data integrity.
- DMA tests check zero-length transfers, fixed-length copies, randomized copies, start-while-busy behavior, status signaling, burst transfers, and multi-burst splitting.
- Interconnect tests check master routing, fixed-priority arbitration, response ownership, `RREADY`/`BREADY` backpressure, and burst read/write routing.
- Slave tests cover AXI SRAM single-beat/burst access, AXI-Lite register/FIFO behavior, and DMA register programming/status behavior.
- Integration tests connect CPU, DMA, interconnect, and SRAM/register slaves, including CPU-generated DMA register programming.
- UVM verification uses passive monitors on CPU AXI and DMA AXI interfaces and a scoreboard that checks:
  - CPU writes expected DMA `SRC_ADDR`, `DST_ADDR`, `LENGTH`, and `CONTROL.START`
  - DMA reads from the expected source range
  - DMA writes to the expected destination range
  - DMA write data matches previously observed DMA read data
  - DMA read queue is empty at end of test
- Functional coverage is implemented in `uvm/soc_scoreboard.sv` for agent type, read/write kind, CPU register addresses, DMA address ranges, burst length, last-beat behavior, and agent/kind cross coverage.
- SVA assertions in `rtl/common/axi_if.sv` check payload stability while waiting for READY and ensure `WLAST`/`RLAST` are only asserted with valid data channels.

## How to Run

The repository contains Questa/ModelSim DO scripts:

```tcl
scripts/run.do
scripts/run_uvm_regression.do
```

From a Questa/ModelSim shell, the intended UVM regression entry point is:

```tcl
do scripts/run_uvm_regression.do
```

The checked-in DO files use bare source filenames. If your simulator cannot resolve those files from the current repository layout, run from a simulator setup where the source directories are on the search path, or update the DO file to use the current repo-relative paths under `rtl/`, `tb/`, and `uvm/`.

A repository-root compile order for the current UVM SoC test is:

```tcl
vlib work
vmap work work

vlog -sv rtl/common/axi_pkg.sv
vlog -sv rtl/common/axi_if.sv
vlog -sv rtl/cpu/alu.sv
vlog -sv rtl/cpu/reg_file.sv
vlog -sv rtl/cpu/control_unit.sv
vlog -sv rtl/cpu/riscv_core.sv
vlog -sv rtl/cpu/cpu_axi_adapter.sv
vlog -sv rtl/dma/dma_controller_burst.sv
vlog -sv rtl/axi/axi_interconnect_2m2s.sv
vlog -sv rtl/slaves/axi_sram_slave.sv
vlog -sv rtl/slaves/dma_reg_slave.sv
vlog -sv rtl/top/soc_top.sv

vlog -sv -L mtiUvm +incdir+uvm uvm/axi_uvm_pkg.sv
vlog -sv -L mtiUvm +incdir+uvm tb/uvm/soc_top_uvm_tb.sv
```

Example UVM run:

```tcl
vsim -coverage -L mtiUvm -voptargs=+acc soc_top_uvm_tb +UVM_NO_RELNOTES +DMA_SRC=00000040 +DMA_DST=00000180 +DMA_LEN=16 +DMA_PATTERN=FACE0000
run -all
coverage save -onexit test1.ucdb
quit -sim
```

The regression script runs four parameterized DMA-copy scenarios and then merges coverage:

```tcl
vcover merge phase8_merged.ucdb test1.ucdb test2.ucdb test3.ucdb test4.ucdb
vcover report phase8_merged.ucdb -details -output phase8_coverage_report.txt
```

### DMA Register Slave Directed Test

From the repository root, the standalone DMA register slave testbench can be compiled and run with:

```tcl
vlib work
vmap work work
vlog -sv rtl/common/axi_pkg.sv
vlog -sv rtl/common/axi_if.sv
vlog -sv rtl/slaves/dma_reg_slave.sv
vlog -sv tb/slaves/dma_reg_slave_tb.sv
vsim -voptargs=+acc dma_reg_slave_tb
run -all
```

## Results

The UVM regression script defines four parameterized DMA-copy scenarios:

| Test | Source | Destination | Length | Pattern |
|---|---:|---:|---:|---:|
| 1 | `0x00000040` | `0x00000180` | 16 words | `0xFACE0000` |
| 2 | `0x00000080` | `0x000001C0` | 8 words | `0xBEEF0000` |
| 3 | `0x00000020` | `0x00000100` | 4 words | `0xCAFE0000` |
| 4 | `0x000000C0` | `0x00000140` | 12 words | `0xABCD0000` |

The saved coverage report at `regressions/coverage/phase8_coverage_report.txt` reports:

- Total UVM covergroup coverage: `75.78%`
- `cp_agent`, `cp_kind`, `cp_cpu_reg_addr`, and `cp_last`: `100%`
- `cross_agent_kind`: `75%`
- Assertion report: zero failures for the listed AXI interface assertions

Known limitations and notes:

- The CPU is a small instructional subset, not a complete RISC-V implementation.
- Instruction memory remains external to `soc_top.sv`; data memory and DMA registers are integrated through AXI.
- The UVM environment is passive and scoreboard-focused; it does not yet include active UVM sequencers/drivers for generating AXI traffic.
- Functional coverage is not closed. The saved report shows uncovered bins for CPU reads, some DMA source/destination ranges, and several burst-length bins.
- DMA register slave behavior is covered by a standalone directed self-checking testbench and integration/UVM-level tests.
- Local regression runs generate `uvm_regression.log` and `*.ucdb` files, but these generated simulator artifacts are ignored by git.

## Skills Demonstrated

- SystemVerilog RTL design
- UVM testbench architecture
- AXI4-style protocol modeling and verification
- SVA protocol assertions
- RISC-V control-path design
- CPU-to-AXI adaptation
- DMA controller design
- SoC integration and memory-mapped register design
- Self-checking directed verification
- Scoreboarding and data integrity checking
- Functional coverage planning
- Regression scripting with QuestaSim/ModelSim

## Future Improvements

- Expand the RISC-V instruction subset and add a more complete instruction-memory/program-loading flow.
- Add active UVM AXI agents with sequences for CPU, DMA, SRAM, and register-space traffic.
- Increase randomized AXI protocol corner cases, including error responses, unaligned accesses if supported, deeper backpressure, and more arbitration stress.
- Close functional coverage gaps for CPU reads, DMA address ranges, and burst-length bins.
- Add more negative/protocol-stress cases around DMA register accesses and AXI error handling.
- Add lint, synthesis checks, and FPGA implementation collateral if the project is extended toward FPGA bring-up.

## Resume Summary

Designed and verified a SystemVerilog SoC-style project integrating a minimal RISC-V core, AXI4-style interconnect, AXI SRAM, memory-mapped DMA control registers, and a burst DMA engine. Built directed and UVM self-checking verification with AXI monitors, scoreboard checks, SVA assertions, functional coverage, and Questa/ModelSim coverage evidence.
