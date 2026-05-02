`timescale 1ns/1ps
import axi_pkg::*;

module soc_cpu_controlled_dma_tb;

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
  logic dma_done_seen;
  logic dma_start_seen;

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
  if (imem_addr[6:2] < 5'd9)
    imem_rdata = imem[imem_addr[6:2]];
  else
    imem_rdata = 32'h0000_0013; // NOP
end

  // =========================================================
  // DMA event monitors
  // =========================================================

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      dma_done_seen  <= 1'b0;
      dma_start_seen <= 1'b0;
    end
    else begin
      if (dma_start_pulse)
        dma_start_seen <= 1'b1;

      if (dma_done)
        dma_done_seen <= 1'b1;
    end
  end

  always @(posedge clk) begin
  if (rst_n) begin
    if (cpu_axi_if.aw_valid && cpu_axi_if.aw_ready) begin
      $display("CPU AW: addr=%h len=%0d @ %t",
               cpu_axi_if.aw.addr, cpu_axi_if.aw.len, $time);
    end

    if (cpu_axi_if.w_valid && cpu_axi_if.w_ready) begin
      $display("CPU W : data=%h last=%0d @ %t",
               cpu_axi_if.w.data, cpu_axi_if.w.last, $time);
    end

    if (dma_regs_if.aw_valid && dma_regs_if.aw_ready) begin
      $display("REG AW: addr=%h len=%0d @ %t",
               dma_regs_if.aw.addr, dma_regs_if.aw.len, $time);
    end

    if (dma_regs_if.w_valid && dma_regs_if.w_ready) begin
      $display("REG W : data=%h last=%0d @ %t",
               dma_regs_if.w.data, dma_regs_if.w.last, $time);
    end

    if (dma_start_pulse) begin
      $display("DMA START PULSE SEEN @ %t", $time);
    end
  end
end

  // =========================================================
  // Init / program
  // =========================================================

  task automatic init_all;
    begin
      for (int i = 0; i < 32; i++) begin
        imem[i] = 32'h0000_0013; // NOP
      end

      for (int i = 0; i < DEPTH; i++) begin
        u_sram.mem[i] = 32'h0000_0000;
      end
    end
  endtask

 task automatic load_cpu_dma_program;
  begin
    // lui  x5, 0x00010       // x5 = 0x0001_0000
    // addi x6, x0, 0x040     // x6 = 0x0000_0040
    // sw   x6, 8(x5)         // DMA SRC_ADDR
    // addi x6, x0, 0x180     // x6 = 0x0000_0180
    // sw   x6, 12(x5)        // DMA DST_ADDR
    // addi x6, x0, 16        // x6 = 16
    // sw   x6, 16(x5)        // DMA LENGTH
    // addi x6, x0, 1         // x6 = 1
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

  task automatic check_copy(
    input int unsigned src_idx,
    input int unsigned dst_idx,
    input int unsigned len,
    input string msg
  );
    begin
      for (int i = 0; i < len; i++) begin
        if (u_sram.mem[dst_idx + i] !== u_sram.mem[src_idx + i]) begin
          $error("%s failed beat=%0d src_idx=%0d dst_idx=%0d expected=%h got=%h",
                 msg, i, src_idx + i, dst_idx + i,
                 u_sram.mem[src_idx + i], u_sram.mem[dst_idx + i]);
          error_count++;
        end
        else begin
          $display("%s PASS beat=%0d dst_idx=%0d data=%h",
                   msg, i, dst_idx + i, u_sram.mem[dst_idx + i]);
        end
      end
    end
  endtask

  // =========================================================
  // Main CPU-controlled DMA test
  // =========================================================

  task automatic cpu_controlled_dma_test;
    begin
      $display("----------------------------------------");
      $display("CPU-CONTROLLED DMA TEST");

      init_all();
      load_cpu_dma_program();

      // DMA source region: SRAM[16:31] = address 0x40 to 0x7C
      for (int i = 0; i < 16; i++) begin
        u_sram.mem[16 + i] = 32'hCDCD_0000 + i;
      end

      pulse_reset();

      // Wait for CPU to write CONTROL.START, which should generate start pulse.
      fork
        begin
            wait(dma_start_seen);
            $display("CPU generated DMA start pulse @ %t", $time);
        end
        begin
            repeat (500) @(posedge clk);
            if (!dma_start_seen) begin
            $error("TIMEOUT: CPU did not generate DMA start pulse");
            $display("DEBUG: pc=%h instr=%h cpu_valid=%0b cpu_write=%0b cpu_addr=%h cpu_wdata=%h cpu_ready=%0b",
                    debug_pc, imem_rdata, cpu_dmem_valid, cpu_dmem_write,
                    cpu_dmem_addr, cpu_dmem_wdata, cpu_dmem_ready);
            $display("DEBUG REGS: src=%h dst=%h len=%0d start_seen=%0b",
                    dma_src_addr, dma_dst_addr, dma_length, dma_start_seen);
            error_count++;
            end
        end
        join_any
        disable fork;

      // Verify register outputs were configured by CPU writes.
      #1;

      if (dma_src_addr !== 32'h0000_0040) begin
        $error("DMA SRC config error: expected 00000040 got=%h", dma_src_addr);
        error_count++;
      end
      else begin
        $display("DMA SRC config PASS: %h", dma_src_addr);
      end

      if (dma_dst_addr !== 32'h0000_0180) begin
        $error("DMA DST config error: expected 00000180 got=%h", dma_dst_addr);
        error_count++;
      end
      else begin
        $display("DMA DST config PASS: %h", dma_dst_addr);
      end

      if (dma_length !== 16'd16) begin
        $error("DMA LENGTH config error: expected 16 got=%0d", dma_length);
        error_count++;
      end
      else begin
        $display("DMA LENGTH config PASS: %0d", dma_length);
      end

      // Wait for real DMA completion.
      wait(dma_done_seen);
      $display("DMA completed after CPU register start @ %t", $time);

      repeat (2) @(posedge clk);

      if (dma_error) begin
        $error("DMA ERROR asserted during CPU-controlled DMA test");
        error_count++;
      end

      // Destination region: SRAM[96:111] = address 0x180 to 0x1BC
      check_copy(16, 96, 16, "CPU-controlled DMA copy");

      // STATUS should show DONE sticky bit = 1 and BUSY = 0.
      if (u_dma_regs.done_sticky !== 1'b1) begin
        $error("DMA STATUS ERROR: done_sticky should be 1 after DMA completion");
        error_count++;
      end
      else begin
        $display("DMA STATUS DONE sticky PASS");
      end

      if (dma_busy !== 1'b0) begin
        $error("DMA STATUS ERROR: dma_busy should be 0 after completion");
        error_count++;
      end
      else begin
        $display("DMA STATUS BUSY clear PASS");
      end

      $display("CPU-CONTROLLED DMA TEST COMPLETE");
    end
  endtask

  // =========================================================
  // Test sequence
  // =========================================================

  initial begin
    error_count = 0;

    cpu_controlled_dma_test();

    #20;

    if (error_count == 0) begin
      $display("========================================");
      $display("PHASE 7 STEP 6E PASS: CPU-controlled DMA verified");
      $display("CPU configured DMA registers and DMA copied SRAM through 2M2S interconnect");
      $display("========================================");
    end
    else begin
      $error("PHASE 7 STEP 6E FAILED: error_count=%0d", error_count);
    end

    #50;
    $finish;
  end

endmodule
