transcript file uvm_regression.log

echo "========================================"
echo "UVM REGRESSION: CLEAN BUILD"
echo "========================================"

if {[file exists work]} {
  vdel -all
}

vlib work

vlog -sv axi_pkg.sv
vlog -sv axi_if.sv
vlog -sv alu.sv
vlog -sv reg_file.sv
vlog -sv control_unit.sv
vlog -sv riscv_core.sv
vlog -sv cpu_axi_adapter.sv
vlog -sv dma_controller_burst.sv
vlog -sv axi_interconnect_2m2s.sv
vlog -sv axi_sram_slave.sv
vlog -sv dma_reg_slave.sv
vlog -sv soc_top.sv

vlog -sv -L mtiUvm +incdir+uvm uvm/axi_uvm_pkg.sv
vlog -sv -L mtiUvm +incdir+uvm soc_top_uvm_tb.sv

echo "========================================"
echo "UVM REGRESSION TEST 1: default 16-word copy"
echo "========================================"

vsim -coverage -L mtiUvm -voptargs=+acc soc_top_uvm_tb +UVM_NO_RELNOTES +DMA_SRC=00000040 +DMA_DST=00000180 +DMA_LEN=16 +DMA_PATTERN=FACE0000
run -all
coverage save -onexit test1.ucdb
quit -sim

echo "========================================"
echo "UVM REGRESSION TEST 2: 8-word copy"
echo "========================================"

vsim -coverage -L mtiUvm -voptargs=+acc soc_top_uvm_tb +UVM_NO_RELNOTES +DMA_SRC=00000080 +DMA_DST=000001C0 +DMA_LEN=8 +DMA_PATTERN=BEEF0000
run -all
coverage save -onexit test2.ucdb
quit -sim

echo "========================================"
echo "UVM REGRESSION TEST 3: 4-word copy"
echo "========================================"

vsim -coverage -L mtiUvm -voptargs=+acc soc_top_uvm_tb +UVM_NO_RELNOTES +DMA_SRC=00000020 +DMA_DST=00000100 +DMA_LEN=4 +DMA_PATTERN=CAFE0000
run -all
coverage save -onexit test3.ucdb
quit -sim

echo "========================================"
echo "UVM REGRESSION TEST 4: 12-word copy"
echo "========================================"

vsim -coverage -L mtiUvm -voptargs=+acc soc_top_uvm_tb +UVM_NO_RELNOTES +DMA_SRC=000000C0 +DMA_DST=00000140 +DMA_LEN=12 +DMA_PATTERN=ABCD0000
run -all
coverage save -onexit test4.ucdb
quit -sim

echo "========================================"
echo "MERGING COVERAGE"
echo "========================================"

vcover merge phase8_merged.ucdb test1.ucdb test2.ucdb test3.ucdb test4.ucdb
vcover report phase8_merged.ucdb -details -output phase8_coverage_report.txt

echo "========================================"
echo "PHASE 8 STEP 6 COMPLETE: UVM regression and coverage saved"
echo "Generated:"
echo "  uvm_regression.log"
echo "  test1.ucdb"
echo "  test2.ucdb"
echo "  test3.ucdb"
echo "  test4.ucdb"
echo "  phase8_merged.ucdb"
echo "  phase8_coverage_report.txt"
echo "Check log for UVM_ERROR/UVM_FATAL"
echo "========================================"

transcript file ""