`timescale 1ns/1ps

module riscv_core_addi_lui_tb;

  logic clk;
  logic rst_n;

  // Instruction memory interface
  logic [31:0] imem_addr;
  logic [31:0] imem_rdata;

  // Data memory interface
  logic        dmem_valid;
  logic        dmem_write;
  logic [31:0] dmem_addr;
  logic [31:0] dmem_wdata;
  logic [31:0] dmem_rdata;
  logic        dmem_ready;

  logic [31:0] debug_pc;

  logic [31:0] imem [0:31];
  logic [31:0] dmem [0:31];

  int error_count;

  // =========================================================
  // DUT
  // =========================================================

  riscv_core dut (
    .clk(clk),
    .rst_n(rst_n),

    .imem_addr(imem_addr),
    .imem_rdata(imem_rdata),

    .dmem_valid(dmem_valid),
    .dmem_write(dmem_write),
    .dmem_addr(dmem_addr),
    .dmem_wdata(dmem_wdata),
    .dmem_rdata(dmem_rdata),
    .dmem_ready(dmem_ready),

    .debug_pc(debug_pc)
  );

  // =========================================================
  // Clock / reset
  // =========================================================

  initial clk = 0;
  always #5 clk = ~clk;

  initial begin
    rst_n = 0;
    #20;
    rst_n = 1;
  end

  // =========================================================
  // Instruction memory
  // =========================================================

  always_comb begin
    if (imem_addr < 32'd16)
      imem_rdata = imem[imem_addr[6:2]];
    else
      imem_rdata = 32'h0000_0013; // NOP: addi x0, x0, 0
  end

  // =========================================================
  // Simple data memory
  // =========================================================

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      dmem_ready <= 1'b0;
      dmem_rdata <= 32'h0000_0000;
    end
    else begin
      dmem_ready <= 1'b0;

      if (dmem_valid) begin
        dmem_ready <= 1'b1;

        if (dmem_write) begin
          dmem[dmem_addr >> 2] <= dmem_wdata;
          $display("DMEM WRITE: addr=%h data=%h @ %t",
                   dmem_addr, dmem_wdata, $time);
        end
        else begin
          dmem_rdata <= dmem[dmem_addr >> 2];
        end
      end
    end
  end

  // =========================================================
  // Init program
  // =========================================================

  task automatic init_memories;
    begin
      for (int i = 0; i < 32; i++) begin
        imem[i] = 32'h0000_0013; // NOP
        dmem[i] = 32'h0000_0000;
      end
    end
  endtask

  task automatic load_program;
    begin
      // Program:
      // lui  x5, 0x00010      // x5 = 0x0001_0000
      // addi x6, x0, 0x040    // x6 = 0x0000_0040
      // sw   x6, 0(x0)        // dmem[0] = 0x40
      // sw   x5, 4(x0)        // dmem[1] = 0x0001_0000

      imem[0] = 32'h0001_02B7; // lui  x5, 0x00010
      imem[1] = 32'h0400_0313; // addi x6, x0, 0x040
      imem[2] = 32'h0060_2023; // sw   x6, 0(x0)
      imem[3] = 32'h0050_2223; // sw   x5, 4(x0)
    end
  endtask

  // =========================================================
  // Test sequence
  // =========================================================

  initial begin
    error_count = 0;

    init_memories();
    load_program();

    wait(rst_n);

    // Wait until both stores complete
    wait(dmem[0] == 32'h0000_0040 && dmem[1] == 32'h0001_0000);

    if (dmem[0] !== 32'h0000_0040) begin
      $error("ADDI TEST FAILED: dmem[0] expected 00000040 got=%h", dmem[0]);
      error_count++;
    end
    else begin
      $display("ADDI TEST PASS: dmem[0]=%h", dmem[0]);
    end

    if (dmem[1] !== 32'h0001_0000) begin
      $error("LUI TEST FAILED: dmem[1] expected 00010000 got=%h", dmem[1]);
      error_count++;
    end
    else begin
      $display("LUI TEST PASS: dmem[1]=%h", dmem[1]);
    end

    #20;

    if (error_count == 0) begin
      $display("========================================");
      $display("PHASE 7 STEP 6D PASS: ADDI and LUI verified");
      $display("CPU can generate immediate values and high register addresses");
      $display("========================================");
    end
    else begin
      $error("PHASE 7 STEP 6D FAILED: error_count=%0d", error_count);
    end

    #50;
    $finish;
  end

endmodule