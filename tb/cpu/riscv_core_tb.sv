`timescale 1ns/1ps

module riscv_core_tb;

  logic clk;
  logic rst_n;

  logic [31:0] imem_addr;
  logic [31:0] imem_rdata;

  logic        dmem_valid;
  logic        dmem_write;
  logic [31:0] dmem_addr;
  logic [31:0] dmem_wdata;
  logic [31:0] dmem_rdata;
  logic        dmem_ready;

  logic [31:0] debug_pc;

  int error_count;

  // Instruction memory
  logic [31:0] imem [0:31];

  // Data memory
  logic [31:0] dmem [0:31];

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

  initial clk = 0;
  always #5 clk = ~clk;

  // Instruction memory: word addressed by imem_addr[6:2]
  always_comb begin
    imem_rdata = imem[imem_addr[6:2]];
  end

  // Simple zero-latency data memory handshake
  always_comb begin
    dmem_ready = dmem_valid;

    if (dmem_valid && !dmem_write)
      dmem_rdata = dmem[dmem_addr[6:2]];
    else
      dmem_rdata = 32'h0000_0000;
  end

    // Store writes
    always @(posedge clk) begin
    if (rst_n) begin
        if (dmem_valid && dmem_ready && dmem_write) begin
        dmem[dmem_addr[6:2]] <= dmem_wdata;
        $display("DMEM WRITE: addr=%h data=%h @ %t",
                dmem_addr, dmem_wdata, $time);
        end
    end
    end

  task automatic check_mem(
    input int unsigned index,
    input logic [31:0] expected,
    input string msg
  );
    begin
      if (dmem[index] !== expected) begin
        $error("%s failed: dmem[%0d] expected=%h got=%h",
               msg, index, expected, dmem[index]);
        error_count++;
      end
      else begin
        $display("%s passed: dmem[%0d]=%h", msg, index, dmem[index]);
      end
    end
  endtask

  initial begin
    error_count = 0;

    // Clear memories
    for (int i = 0; i < 32; i++) begin
      imem[i] = 32'h0000_0000;
      dmem[i] = 32'h0000_0000;
    end

    // Program:
    // lw  x1, 0(x0)
    // lw  x2, 4(x0)
    // add x3, x1, x2
    // sub x4, x2, x1
    // sw  x3, 8(x0)
    // sw  x4, 12(x0)

    imem[0] = 32'h0000_2083; // lw  x1, 0(x0)
    imem[1] = 32'h0040_2103; // lw  x2, 4(x0)
    imem[2] = 32'h0020_81b3; // add x3, x1, x2
    imem[3] = 32'h4011_0233; // sub x4, x2, x1
    imem[4] = 32'h0030_2423; // sw  x3, 8(x0)
    imem[5] = 32'h0040_2623; // sw  x4, 12(x0)

    // Data:
    // dmem[0] = 10
    // dmem[1] = 25
    // Expected:
    // x3 = 35 -> dmem[2]
    // x4 = 15 -> dmem[3]
    dmem[0] = 32'd10;
    dmem[1] = 32'd25;

    rst_n = 0;
    repeat (3) @(posedge clk);
    rst_n = 1;

    // Each instruction currently takes about 5 states/cycles.
    // Run enough cycles for 6 instructions.
    repeat (60) @(posedge clk);

    check_mem(2, 32'd35, "ADD store result");
    check_mem(3, 32'd15, "SUB store result");

    if (error_count == 0) begin
      $display("========================================");
      $display("RISC-V CORE TB PASS");
      $display("LW/LW/ADD/SUB/SW/SW program verified");
      $display("========================================");
    end
    else begin
      $error("RISC-V CORE TB FAILED: error_count=%0d", error_count);
    end

    #20;
    $finish;
  end

endmodule