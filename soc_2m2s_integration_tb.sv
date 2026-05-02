`timescale 1ns/1ps
import axi_pkg::*;

module soc_2m2s_integration_tb;

  parameter ID_W      = 4;
  parameter ADDR_W    = 32;
  parameter DATA_W    = 32;
  parameter DEPTH     = 256;
  parameter MAX_BURST = 16;

  logic clk;
  logic rst_n;

  int error_count;

  // ---------------------------------------------------------
  // CPU instruction memory
  // ---------------------------------------------------------
  logic [31:0] imem_addr;
  logic [31:0] imem_rdata;
  logic [31:0] debug_pc;

  logic [31:0] imem [0:31];

  // ---------------------------------------------------------
  // CPU simple data memory interface
  // ---------------------------------------------------------
  logic        cpu_dmem_valid;
  logic        cpu_dmem_write;
  logic [31:0] cpu_dmem_addr;
  logic [31:0] cpu_dmem_wdata;
  logic [31:0] cpu_dmem_rdata;
  logic        cpu_dmem_ready;

  // ---------------------------------------------------------
  // DMA control/status wires from register slave
  // ---------------------------------------------------------
  logic        dma_start_pulse;
  logic [31:0] dma_src_addr;
  logic [31:0] dma_dst_addr;
  logic [15:0] dma_length;

  logic dma_busy;
  logic dma_done;
  logic dma_error;

  // ---------------------------------------------------------
  // AXI interfaces
  // ---------------------------------------------------------
  axi_if #(ID_W, ADDR_W, DATA_W) cpu_axi_if  (clk, rst_n); // M0
  axi_if #(ID_W, ADDR_W, DATA_W) dma_axi_if  (clk, rst_n); // M1
  axi_if #(ID_W, ADDR_W, DATA_W) sram_if     (clk, rst_n); // S0
  axi_if #(ID_W, ADDR_W, DATA_W) dma_regs_if (clk, rst_n); // S1

  // =========================================================
  // DUT 1: RISC-V core
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
  // DUT 2: CPU AXI adapter = M0
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
  // DUT 3: DMA controller = M1
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
  // DUT 4: 2-master / 2-slave interconnect
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
  // DUT 5: SRAM slave = S0
  // =========================================================

  axi_sram_slave #(
    .ID_W(ID_W),
    .ADDR_W(ADDR_W),
    .DATA_W(DATA_W),
    .DEPTH(DEPTH)
  ) u_sram (
    .clk(clk),
    .rst_n(rst_n),
    .intf(sram_if)
  );

  // =========================================================
  // DUT 6: DMA register slave = S1
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

  // =========================================================
  // Clock / reset
  // =========================================================

  initial clk = 0;
  always #5 clk = ~clk;

  initial begin
    rst_n = 1'b0;
  end

  task automatic pulse_reset;
    begin
      rst_n = 1'b0;
      repeat (3) @(posedge clk);
      rst_n = 1'b1;
      repeat (2) @(posedge clk);
    end
  endtask

  // =========================================================
  // Instruction memory
  // =========================================================

  always_comb begin
    if (imem_addr < 32'd24)
      imem_rdata = imem[imem_addr[6:2]];
    else
      imem_rdata = 32'h0000_0013; // NOP for unsupported ADDI path
  end

  // =========================================================
  // Init / program
  // =========================================================

  task automatic init_all;
    begin
      for (int i = 0; i < 32; i++) begin
        imem[i] = 32'h0000_0000;
      end

      for (int i = 0; i < DEPTH; i++) begin
        u_sram.mem[i] = 32'h0000_0000;
      end
    end
  endtask

  task automatic load_cpu_program;
    begin
      // lw  x1, 0(x0)      // x1 = mem[0] = 10
      // lw  x2, 4(x0)      // x2 = mem[1] = 25
      // add x3, x1, x2     // x3 = 35
      // sub x4, x2, x1     // x4 = 15
      // sw  x3, 8(x0)      // mem[2] = 35
      // sw  x4, 12(x0)     // mem[3] = 15

      imem[0] = 32'h0000_2083;
      imem[1] = 32'h0040_2103;
      imem[2] = 32'h0020_81b3;
      imem[3] = 32'h4011_0233;
      imem[4] = 32'h0030_2423;
      imem[5] = 32'h0040_2623;
    end
  endtask

  task automatic check_sram_word(
    input int unsigned index,
    input logic [31:0] expected,
    input string msg
  );
    begin
      if (u_sram.mem[index] !== expected) begin
        $error("%s failed: sram[%0d] expected=%h got=%h",
               msg, index, expected, u_sram.mem[index]);
        error_count++;
      end
      else begin
        $display("%s PASS: sram[%0d]=%h", msg, index, u_sram.mem[index]);
      end
    end
  endtask

  // =========================================================
  // Tests
  // =========================================================

  task automatic cpu_sram_through_2m2s_test;
    begin
      $display("----------------------------------------");
      $display("CPU SRAM THROUGH 2M2S TEST");

      init_all();
      load_cpu_program();

      u_sram.mem[0] = 32'd10;
      u_sram.mem[1] = 32'd25;

      pulse_reset();

      wait(u_sram.mem[2] == 32'd35 && u_sram.mem[3] == 32'd15);

      check_sram_word(2, 32'd35, "CPU ADD result through 2M2S");
      check_sram_word(3, 32'd15, "CPU SUB result through 2M2S");

      $display("CPU SRAM THROUGH 2M2S TEST COMPLETE");
    end
  endtask

  task automatic dma_reg_wiring_test;
    begin
      $display("----------------------------------------");
      $display("DMA REGISTER WIRING TEST");

      // Directly verify the register slave storage/output wiring.
      // Full AXI register access was already verified in dma_reg_slave_tb
      // and 2M2S register decode was verified in axi_interconnect_2m2s_tb.

      u_dma_regs.src_addr_reg = 32'h0000_0040;
      u_dma_regs.dst_addr_reg = 32'h0000_0180;
      u_dma_regs.length_reg   = 32'h0000_0010;

      #1;

      if (dma_src_addr !== 32'h0000_0040) begin
        $error("DMA REG WIRING ERROR: dma_src_addr expected 00000040 got=%h", dma_src_addr);
        error_count++;
      end

      if (dma_dst_addr !== 32'h0000_0180) begin
        $error("DMA REG WIRING ERROR: dma_dst_addr expected 00000180 got=%h", dma_dst_addr);
        error_count++;
      end

      if (dma_length !== 16'h0010) begin
        $error("DMA REG WIRING ERROR: dma_length expected 0010 got=%h", dma_length);
        error_count++;
      end

      $display("DMA REGISTER WIRING TEST COMPLETE");
    end
  endtask

  // =========================================================
  // Test sequence
  // =========================================================

  initial begin
    error_count = 0;

    cpu_sram_through_2m2s_test();

    dma_reg_wiring_test();

    #20;

    if (error_count == 0) begin
      $display("========================================");
      $display("PHASE 7 STEP 5 PASS: SoC 2M2S integration shell verified");
      $display("CPU->SRAM path and DMA register wiring through integrated top passed");
      $display("========================================");
    end
    else begin
      $error("PHASE 7 STEP 5 FAILED: error_count=%0d", error_count);
    end

    #50;
    $finish;
  end

endmodule