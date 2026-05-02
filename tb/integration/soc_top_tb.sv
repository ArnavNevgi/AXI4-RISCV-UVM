`timescale 1ns/1ps
import axi_pkg::*;

module soc_top_tb;

  parameter ID_W       = 4;
  parameter ADDR_W     = 32;
  parameter DATA_W     = 32;
  parameter SRAM_DEPTH = 256;
  parameter MAX_BURST  = 16;

  logic clk;
  logic rst_n;

  logic [31:0] imem_addr;
  logic [31:0] imem_rdata;
  logic [31:0] debug_pc;

  logic dma_busy;
  logic dma_done;
  logic dma_error;

  logic [31:0] imem [0:31];

  logic dma_done_seen;
  logic dma_start_seen;

  int error_count;

  // =========================================================
  // DUT: SoC top
  // =========================================================

  soc_top #(
    .ID_W(ID_W),
    .ADDR_W(ADDR_W),
    .DATA_W(DATA_W),
    .SRAM_DEPTH(SRAM_DEPTH),
    .MAX_BURST(MAX_BURST)
  ) dut (
    .clk(clk),
    .rst_n(rst_n),

    .imem_addr(imem_addr),
    .imem_rdata(imem_rdata),

    .debug_pc(debug_pc),

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
    if (imem_addr[6:2] < 5'd9)
      imem_rdata = imem[imem_addr[6:2]];
    else
      imem_rdata = 32'h0000_0013; // NOP
  end

  // =========================================================
  // DMA monitors
  // =========================================================

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      dma_done_seen  <= 1'b0;
      dma_start_seen <= 1'b0;
    end
    else begin
      if (dut.dma_start_pulse)
        dma_start_seen <= 1'b1;

      if (dma_done)
        dma_done_seen <= 1'b1;
    end
  end

  // =========================================================
  // Debug monitor
  // =========================================================

  always @(posedge clk) begin
    if (rst_n) begin
      if (dut.cpu_axi_if.aw_valid && dut.cpu_axi_if.aw_ready) begin
        $display("CPU AW: addr=%h @ %t", dut.cpu_axi_if.aw.addr, $time);
      end

      if (dut.cpu_axi_if.w_valid && dut.cpu_axi_if.w_ready) begin
        $display("CPU W : data=%h last=%0d @ %t",
                 dut.cpu_axi_if.w.data, dut.cpu_axi_if.w.last, $time);
      end

      if (dut.dma_start_pulse) begin
        $display("DMA START PULSE @ %t", $time);
      end

      if (dma_done) begin
        $display("DMA DONE @ %t", $time);
      end
    end
  end

  // =========================================================
  // Init/program
  // =========================================================

  task automatic init_all;
    begin
      for (int i = 0; i < 32; i++) begin
        imem[i] = 32'h0000_0013; // NOP
      end

      for (int i = 0; i < SRAM_DEPTH; i++) begin
        dut.u_sram.mem[i] = 32'h0000_0000;
      end
    end
  endtask

  task automatic load_cpu_dma_program;
    begin
      // CPU-controlled DMA program:
      //
      // lui  x5, 0x00010       // x5 = 0x0001_0000 DMA register base
      // addi x6, x0, 0x040     // x6 = source address 0x40
      // sw   x6, 8(x5)         // DMA SRC_ADDR
      // addi x6, x0, 0x180     // x6 = destination address 0x180
      // sw   x6, 12(x5)        // DMA DST_ADDR
      // addi x6, x0, 16        // x6 = length 16 words
      // sw   x6, 16(x5)        // DMA LENGTH
      // addi x6, x0, 1         // x6 = start bit
      // sw   x6, 0(x5)         // DMA CONTROL.START

      imem[0] = 32'h0001_02B7; // lui  x5, 0x00010

      imem[1] = 32'h0400_0313; // addi x6, x0, 64
      imem[2] = 32'h0062_A423; // sw   x6, 8(x5)

      imem[3] = 32'h1800_0313; // addi x6, x0, 384
      imem[4] = 32'h0062_A623; // sw   x6, 12(x5)

      imem[5] = 32'h0100_0313; // addi x6, x0, 16
      imem[6] = 32'h0062_A823; // sw   x6, 16(x5)

      imem[7] = 32'h0010_0313; // addi x6, x0, 1
      imem[8] = 32'h0062_A023; // sw   x6, 0(x5)
    end
  endtask

  task automatic check_copy(
    input int unsigned src_idx,
    input int unsigned dst_idx,
    input int unsigned len,
    input string msg
  );
    begin
      for (int i = 0; i < len; i++) begin
        if (dut.u_sram.mem[dst_idx + i] !== dut.u_sram.mem[src_idx + i]) begin
          $error("%s failed beat=%0d src_idx=%0d dst_idx=%0d expected=%h got=%h",
                 msg,
                 i,
                 src_idx + i,
                 dst_idx + i,
                 dut.u_sram.mem[src_idx + i],
                 dut.u_sram.mem[dst_idx + i]);
          error_count++;
        end
        else begin
          $display("%s PASS beat=%0d dst_idx=%0d data=%h",
                   msg, i, dst_idx + i, dut.u_sram.mem[dst_idx + i]);
        end
      end
    end
  endtask

  // =========================================================
  // Main test
  // =========================================================

  task automatic soc_top_cpu_controlled_dma_test;
    begin
      $display("----------------------------------------");
      $display("SOC TOP CPU-CONTROLLED DMA TEST");

      init_all();
      load_cpu_dma_program();

      // DMA source region: SRAM[16:31], address 0x40 to 0x7C
      for (int i = 0; i < 16; i++) begin
        dut.u_sram.mem[16 + i] = 32'hABCD_0000 + i;
      end

      pulse_reset();

      fork
        begin
          wait(dma_start_seen);
          $display("TB observed CPU-generated DMA start @ %t", $time);
        end

        begin
          repeat (1000) @(posedge clk);
          if (!dma_start_seen) begin
            $error("TIMEOUT: CPU did not generate DMA start");
            $display("DEBUG: pc=%h imem_rdata=%h", debug_pc, imem_rdata);
            $display("DEBUG: src=%h dst=%h len=%0d",
                     dut.dma_src_addr, dut.dma_dst_addr, dut.dma_length);
            error_count++;
          end
        end
      join_any
      disable fork;

      if (dut.dma_src_addr !== 32'h0000_0040) begin
        $error("DMA SRC config error: expected 00000040 got=%h", dut.dma_src_addr);
        error_count++;
      end
      else begin
        $display("DMA SRC config PASS: %h", dut.dma_src_addr);
      end

      if (dut.dma_dst_addr !== 32'h0000_0180) begin
        $error("DMA DST config error: expected 00000180 got=%h", dut.dma_dst_addr);
        error_count++;
      end
      else begin
        $display("DMA DST config PASS: %h", dut.dma_dst_addr);
      end

      if (dut.dma_length !== 16'd16) begin
        $error("DMA LENGTH config error: expected 16 got=%0d", dut.dma_length);
        error_count++;
      end
      else begin
        $display("DMA LENGTH config PASS: %0d", dut.dma_length);
      end

      fork
        begin
          wait(dma_done_seen);
          $display("TB observed DMA completion @ %t", $time);
        end

        begin
          repeat (3000) @(posedge clk);
          if (!dma_done_seen) begin
            $error("TIMEOUT: DMA did not complete");
            error_count++;
          end
        end
      join_any
      disable fork;

      repeat (2) @(posedge clk);

      if (dma_error) begin
        $error("DMA ERROR asserted");
        error_count++;
      end

      check_copy(16, 96, 16, "SOC TOP CPU-controlled DMA copy");

      if (dut.u_dma_regs.done_sticky !== 1'b1) begin
        $error("DMA REG STATUS ERROR: done sticky should be 1");
        error_count++;
      end
      else begin
        $display("DMA REG STATUS DONE sticky PASS");
      end

      $display("SOC TOP CPU-CONTROLLED DMA TEST COMPLETE");
    end
  endtask

  // =========================================================
  // Test sequence
  // =========================================================

  initial begin
    error_count = 0;

    soc_top_cpu_controlled_dma_test();

    #20;

    if (error_count == 0) begin
      $display("========================================");
      $display("PHASE 7 STEP 7 PASS: soc_top CPU-controlled DMA verified");
      $display("Reusable SoC top integrated CPU, DMA, 2M2S interconnect, SRAM, and DMA regs");
      $display("========================================");
    end
    else begin
      $error("PHASE 7 STEP 7 FAILED: error_count=%0d", error_count);
    end

    #50;
    $finish;
  end

endmodule