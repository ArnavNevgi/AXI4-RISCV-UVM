`timescale 1ns/1ps
import axi_pkg::*;

module soc_top #(
  parameter ID_W      = 4,
  parameter ADDR_W    = 32,
  parameter DATA_W    = 32,
  parameter SRAM_DEPTH = 256,
  parameter MAX_BURST = 16
)(
  input  logic clk,
  input  logic rst_n,

  // Instruction memory interface kept external for now
  output logic [31:0] imem_addr,
  input  logic [31:0] imem_rdata,

  // Debug outputs
  output logic [31:0] debug_pc,

  output logic        dma_busy,
  output logic        dma_done,
  output logic        dma_error
);

  // =========================================================
  // CPU simple data-memory interface
  // =========================================================

  logic        cpu_dmem_valid;
  logic        cpu_dmem_write;
  logic [31:0] cpu_dmem_addr;
  logic [31:0] cpu_dmem_wdata;
  logic [31:0] cpu_dmem_rdata;
  logic        cpu_dmem_ready;

  // =========================================================
  // DMA control wires from DMA register slave
  // =========================================================

  logic        dma_start_pulse;
  logic [31:0] dma_src_addr;
  logic [31:0] dma_dst_addr;
  logic [15:0] dma_length;

  // =========================================================
  // AXI interfaces
  // =========================================================

  axi_if #(ID_W, ADDR_W, DATA_W) cpu_axi_if  (clk, rst_n); // M0
  axi_if #(ID_W, ADDR_W, DATA_W) dma_axi_if  (clk, rst_n); // M1
  axi_if #(ID_W, ADDR_W, DATA_W) sram_if     (clk, rst_n); // S0
  axi_if #(ID_W, ADDR_W, DATA_W) dma_regs_if (clk, rst_n); // S1

  // =========================================================
  // RISC-V core
  // =========================================================

  riscv_core u_core (
    .clk(clk),
    .rst_n(rst_n),

    .imem_addr(imem_addr),
    .imem_rdata(imem_rdata),

    .dmem_valid(cpu_dmem_valid),
    .dmem_write(cpu_dmem_write),
    .dmem_addr(cpu_dmem_addr),
    .dmem_wdata(cpu_dmem_wdata),
    .dmem_rdata(cpu_dmem_rdata),
    .dmem_ready(cpu_dmem_ready),

    .debug_pc(debug_pc)
  );

  // =========================================================
  // CPU AXI adapter = Master 0
  // =========================================================

  cpu_axi_adapter #(
    .ID_W(ID_W),
    .ADDR_W(ADDR_W),
    .DATA_W(DATA_W)
  ) u_cpu_adapter (
    .clk(clk),
    .rst_n(rst_n),

    .cpu_valid(cpu_dmem_valid),
    .cpu_write(cpu_dmem_write),
    .cpu_addr(cpu_dmem_addr),
    .cpu_wdata(cpu_dmem_wdata),
    .cpu_rdata(cpu_dmem_rdata),
    .cpu_ready(cpu_dmem_ready),

    .intf(cpu_axi_if)
  );

  // =========================================================
  // DMA controller = Master 1
  // =========================================================

  dma_controller_burst #(
    .ID_W(ID_W),
    .ADDR_W(ADDR_W),
    .DATA_W(DATA_W),
    .MAX_BURST(MAX_BURST)
  ) u_dma (
    .clk(clk),
    .rst_n(rst_n),

    .start(dma_start_pulse),
    .src_addr(dma_src_addr),
    .dst_addr(dma_dst_addr),
    .length(dma_length),

    .busy(dma_busy),
    .done(dma_done),
    .error(dma_error),

    .intf(dma_axi_if)
  );

  // =========================================================
  // 2-master / 2-slave AXI interconnect
  // =========================================================

  axi_interconnect_2m2s #(
    .ID_W(ID_W),
    .ADDR_W(ADDR_W),
    .DATA_W(DATA_W)
  ) u_ic (
    .clk(clk),
    .rst_n(rst_n),

    .m0(cpu_axi_if),
    .m1(dma_axi_if),

    .s0(sram_if),
    .s1(dma_regs_if)
  );

  // =========================================================
  // SRAM slave = Slave 0
  // Address region: 0x0000_xxxx
  // =========================================================

  axi_sram_slave #(
    .ID_W(ID_W),
    .ADDR_W(ADDR_W),
    .DATA_W(DATA_W),
    .DEPTH(SRAM_DEPTH)
  ) u_sram (
    .clk(clk),
    .rst_n(rst_n),
    .intf(sram_if)
  );

  // =========================================================
  // DMA register slave = Slave 1
  // Address region: 0x0001_xxxx
  // =========================================================

  dma_reg_slave #(
    .ID_W(ID_W),
    .ADDR_W(ADDR_W),
    .DATA_W(DATA_W)
  ) u_dma_regs (
    .clk(clk),
    .rst_n(rst_n),

    .intf(dma_regs_if),

    .dma_start_pulse(dma_start_pulse),
    .dma_src_addr(dma_src_addr),
    .dma_dst_addr(dma_dst_addr),
    .dma_length(dma_length),

    .dma_busy(dma_busy),
    .dma_done(dma_done),
    .dma_error(dma_error)
  );

endmodule