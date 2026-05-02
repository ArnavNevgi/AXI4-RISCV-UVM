`timescale 1ns/1ps
import axi_pkg::*;

module cpu_dma_sram_tb;

  parameter ID_W      = 4;
  parameter ADDR_W    = 32;
  parameter DATA_W    = 32;
  parameter DEPTH     = 256;
  parameter MAX_BURST = 16;

  logic clk;
  logic rst_n;

  // ---------------------------------------------------------
  // CPU instruction memory
  // ---------------------------------------------------------
  logic [31:0] imem_addr;
  logic [31:0] imem_rdata;
  logic [31:0] debug_pc;

  logic [31:0] imem [0:31];

  // ---------------------------------------------------------
  // CPU simple data-memory interface
  // ---------------------------------------------------------
  logic        cpu_dmem_valid;
  logic        cpu_dmem_write;
  logic [31:0] cpu_dmem_addr;
  logic [31:0] cpu_dmem_wdata;
  logic [31:0] cpu_dmem_rdata;
  logic        cpu_dmem_ready;

  // ---------------------------------------------------------
  // DMA control
  // ---------------------------------------------------------
  logic              dma_start;
  logic [ADDR_W-1:0] dma_src_addr;
  logic [ADDR_W-1:0] dma_dst_addr;
  logic [15:0]       dma_length;

  logic dma_busy;
  logic dma_done;
  logic dma_error;
  logic dma_done_seen;

  // ---------------------------------------------------------
  // AXI interfaces
  // ---------------------------------------------------------
  axi_if #(ID_W, ADDR_W, DATA_W) cpu_axi_if (clk, rst_n); // M0
  axi_if #(ID_W, ADDR_W, DATA_W) dma_axi_if (clk, rst_n); // M1
  axi_if #(ID_W, ADDR_W, DATA_W) sram_if    (clk, rst_n); // S0

  int error_count;

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
  // DUT 3: DMA burst controller = M1
  // =========================================================

  dma_controller_burst #(
    .ID_W(ID_W),
    .ADDR_W(ADDR_W),
    .DATA_W(DATA_W),
    .MAX_BURST(MAX_BURST)
  ) u_dma (
    .clk(clk),
    .rst_n(rst_n),

    .start(dma_start),
    .src_addr(dma_src_addr),
    .dst_addr(dma_dst_addr),
    .length(dma_length),

    .busy(dma_busy),
    .done(dma_done),
    .error(dma_error),

    .intf(dma_axi_if)
  );

  // =========================================================
  // DUT 4: AXI interconnect
  // =========================================================

  axi_interconnect_2m1s #(
    .ID_W(ID_W),
    .ADDR_W(ADDR_W),
    .DATA_W(DATA_W)
  ) u_ic (
    .clk(clk),
    .rst_n(rst_n),

    .m0(cpu_axi_if),
    .m1(dma_axi_if),
    .s0(sram_if)
  );

  // =========================================================
  // DUT 5: Reusable AXI SRAM slave
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
  // CLOCK / RESET
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
  // INSTRUCTION MEMORY
  // Prevent PC wraparound by returning NOP after program
  // =========================================================

  always_comb begin
    if (imem_addr < 32'd24)
      imem_rdata = imem[imem_addr[6:2]];
    else
      imem_rdata = 32'h0000_0013; // NOP: addi x0, x0, 0
  end

  // =========================================================
  // TASKS
  // =========================================================

  task automatic init_all;
    begin
      for (int i = 0; i < 32; i++) begin
        imem[i] = 32'h0000_0000;
      end

      for (int i = 0; i < DEPTH; i++) begin
        u_sram.mem[i] = 32'h0000_0000;
      end

      dma_start     = 1'b0;
      dma_src_addr  = '0;
      dma_dst_addr  = '0;
      dma_length    = '0;
      dma_done_seen = 1'b0;
    end
  endtask

  task automatic load_cpu_program;
    begin
      // Program:
      // lw  x1, 0(x0)      // x1 = mem[0] = 10
      // lw  x2, 4(x0)      // x2 = mem[1] = 25
      // add x3, x1, x2     // x3 = 35
      // sub x4, x2, x1     // x4 = 15
      // sw  x3, 8(x0)      // mem[2] = 35
      // sw  x4, 12(x0)     // mem[3] = 15

      imem[0] = 32'h0000_2083; // lw  x1, 0(x0)
      imem[1] = 32'h0040_2103; // lw  x2, 4(x0)
      imem[2] = 32'h0020_81b3; // add x3, x1, x2
      imem[3] = 32'h4011_0233; // sub x4, x2, x1
      imem[4] = 32'h0030_2423; // sw  x3, 8(x0)
      imem[5] = 32'h0040_2623; // sw  x4, 12(x0)
    end
  endtask

  task automatic check_mem_word(
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

  task automatic check_copy(
    input logic [ADDR_W-1:0] src,
    input logic [ADDR_W-1:0] dst,
    input int unsigned       len,
    input string             msg
  );
    int unsigned src_idx;
    int unsigned dst_idx;

    begin
      for (int i = 0; i < len; i++) begin
        src_idx = (src >> 2) + i;
        dst_idx = (dst >> 2) + i;

        if (u_sram.mem[dst_idx] !== u_sram.mem[src_idx]) begin
          $error("%s failed beat=%0d src_idx=%0d dst_idx=%0d expected=%h got=%h",
                 msg, i, src_idx, dst_idx,
                 u_sram.mem[src_idx], u_sram.mem[dst_idx]);
          error_count++;
        end
        else begin
          $display("%s PASS beat=%0d dst_idx=%0d data=%h",
                   msg, i, dst_idx, u_sram.mem[dst_idx]);
        end
      end
    end
  endtask

  task automatic start_dma_copy(
    input logic [ADDR_W-1:0] src,
    input logic [ADDR_W-1:0] dst,
    input logic [15:0]       len
  );
    begin
      dma_done_seen = 1'b0;

      @(posedge clk);
      dma_src_addr <= src;
      dma_dst_addr <= dst;
      dma_length   <= len;
      dma_start    <= 1'b1;

      @(posedge clk);
      dma_start <= 1'b0;

      wait(dma_busy);
      $display("DMA BUSY observed @ %t", $time);

      wait(dma_done);
      dma_done_seen = 1'b1;
      $display("DMA DONE observed @ %t", $time);

      @(posedge clk);
      #1;

      if (dma_busy !== 1'b0) begin
        $error("DMA STATUS ERROR: dma_busy should be low after done");
        error_count++;
      end

      if (dma_error) begin
        $error("DMA ERROR asserted");
        error_count++;
      end
    end
  endtask

  task automatic cpu_then_dma_test;
    begin
      $display("----------------------------------------");
      $display("CPU THEN DMA TEST USING AXI SRAM SLAVE");

      init_all();
      load_cpu_program();

      pulse_reset();

      // CPU input data in SRAM
      u_sram.mem[0] = 32'd10;
      u_sram.mem[1] = 32'd25;

      // Wait for CPU to execute program through AXI/interconnect/SRAM
      wait(u_sram.mem[2] == 32'd35 && u_sram.mem[3] == 32'd15);

      $display("CPU PROGRAM COMPLETED THROUGH INTERCONNECT + SRAM");

      check_mem_word(2, 32'd35, "CPU ADD result");
      check_mem_word(3, 32'd15, "CPU SUB result");

      // DMA copies CPU-generated results from mem[2:3] to mem[64:65]
      start_dma_copy(32'h0000_0008, 32'h0000_0100, 16'd2);

      check_copy(32'h0000_0008, 32'h0000_0100, 2, "DMA copy of CPU results");
    end
  endtask

  task automatic cpu_dma_overlap_sram_test;
    begin
      $display("----------------------------------------");
      $display("CPU + DMA OVERLAP TEST USING AXI SRAM SLAVE");

      init_all();
      load_cpu_program();

      // CPU input data
      u_sram.mem[0] = 32'd10;
      u_sram.mem[1] = 32'd25;

      // DMA source data: sram[16:31]
      for (int i = 0; i < 16; i++) begin
        u_sram.mem[16 + i] = 32'hDADA_0000 + i;
      end

      pulse_reset();

      // Let CPU begin, then start DMA while CPU is still active
      repeat (6) @(posedge clk);

      dma_done_seen = 1'b0;

      fork
        begin
          wait(dma_done);
          dma_done_seen = 1'b1;
          $display("DMA completed during overlap SRAM test @ %t", $time);
        end

        begin
          @(posedge clk);
          dma_src_addr <= 32'h0000_0040; // sram[16]
          dma_dst_addr <= 32'h0000_0180; // sram[96]
          dma_length   <= 16'd16;
          dma_start    <= 1'b1;

          @(posedge clk);
          dma_start <= 1'b0;

          $display("DMA started during CPU execution @ %t", $time);
        end

        begin
          wait(u_sram.mem[2] == 32'd35 && u_sram.mem[3] == 32'd15);
          $display("CPU completed during overlap SRAM test @ %t", $time);
        end
      join

      @(posedge clk);
      #1;

      if (!dma_done_seen) begin
        $error("OVERLAP SRAM ERROR: dma_done was not observed");
        error_count++;
      end

      if (dma_error) begin
        $error("OVERLAP SRAM ERROR: DMA error asserted");
        error_count++;
      end

      check_mem_word(2, 32'd35, "Overlap CPU ADD result");
      check_mem_word(3, 32'd15, "Overlap CPU SUB result");

      check_copy(32'h0000_0040, 32'h0000_0180, 16, "Overlap DMA copy");

      $display("CPU + DMA OVERLAP SRAM TEST COMPLETE");
    end
  endtask

  // =========================================================
  // TEST SEQUENCE
  // =========================================================

  initial begin
    error_count = 0;

    cpu_then_dma_test();

    cpu_dma_overlap_sram_test();

    #20;

    if (error_count == 0) begin
      $display("========================================");
      $display("PHASE 6 STEP 3 PASS: CPU + DMA integrated with AXI SRAM slave");
      $display("Reusable SRAM slave replaced TB memory model successfully");
      $display("========================================");
    end
    else begin
      $error("PHASE 6 STEP 3 FAILED: error_count=%0d", error_count);
    end

    #50;
    $finish;
  end

endmodule