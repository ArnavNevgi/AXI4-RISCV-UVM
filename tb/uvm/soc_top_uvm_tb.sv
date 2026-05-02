`timescale 1ns/1ps

import uvm_pkg::*;
`include "uvm_macros.svh"

import axi_pkg::*;
import axi_uvm_pkg::*;

module soc_top_uvm_tb;

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
  bit   tb_configured;
  bit   uvm_done_seen;

  int error_count;
  int uvm_error_count;
  int uvm_fatal_count;

  bit [31:0] test_src_addr = 32'h0000_0040;
  bit [31:0] test_dst_addr = 32'h0000_0180;
  int        test_len      = 16;
  bit [31:0] test_pattern  = 32'hFACE_0000;

  uvm_report_server report_server;

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

  initial clk = 0;
  always #5 clk = ~clk;

  initial begin
    rst_n = 1'b0;
  end

  always_comb begin
    if (imem_addr < 32'd36)
      imem_rdata = imem[imem_addr[6:2]];
    else
      imem_rdata = 32'h0000_0013; // NOP: addi x0, x0, 0
  end

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

  function automatic logic [31:0] encode_addi(
    input logic [4:0]  rd,
    input logic [4:0]  rs1,
    input logic [11:0] imm12
  );
    begin
      encode_addi = {imm12, rs1, 3'b000, rd, 7'b0010011};
    end
  endfunction

  function automatic logic [31:0] encode_sw(
    input logic [4:0]  rs2,
    input logic [4:0]  rs1,
    input logic [11:0] imm12
  );
    begin
      encode_sw = {imm12[11:5], rs2, rs1, 3'b010, imm12[4:0], 7'b0100011};
    end
  endfunction

  task automatic get_test_plusargs;
    bit [31:0] src_arg;
    bit [31:0] dst_arg;
    bit [31:0] pat_arg;
    int        len_arg;

    begin
      if ($value$plusargs("DMA_SRC=%h", src_arg))
        test_src_addr = src_arg;

      if ($value$plusargs("DMA_DST=%h", dst_arg))
        test_dst_addr = dst_arg;

      if ($value$plusargs("DMA_LEN=%d", len_arg))
        test_len = len_arg;

      if ($value$plusargs("DMA_PATTERN=%h", pat_arg))
        test_pattern = pat_arg;
    end
  endtask

  task automatic validate_test_config;
    begin
      if (test_src_addr > 32'h0000_07FF) begin
        $fatal(1, "DMA_SRC=%h cannot be encoded as a positive ADDI 12-bit immediate", test_src_addr);
      end

      if (test_dst_addr > 32'h0000_07FF) begin
        $fatal(1, "DMA_DST=%h cannot be encoded as a positive ADDI 12-bit immediate", test_dst_addr);
      end

      if (test_len <= 0) begin
        $fatal(1, "DMA_LEN must be greater than zero. Got %0d", test_len);
      end

      if (test_len > 2047) begin
        $fatal(1, "DMA_LEN=%0d cannot be encoded as a positive ADDI 12-bit immediate", test_len);
      end
    end
  endtask

  task automatic configure_uvm;
    begin
      get_test_plusargs();
      validate_test_config();

      $display("UVM TB CONFIG: src=%h dst=%h len=%0d pattern=%h",
               test_src_addr, test_dst_addr, test_len, test_pattern);

      uvm_config_db#(virtual axi_if)::set(null, "uvm_test_top.env.cpu_mon", "vif", dut.cpu_axi_if);
      uvm_config_db#(virtual axi_if)::set(null, "uvm_test_top.env.dma_mon", "vif", dut.dma_axi_if);

      uvm_config_db#(string)::set(null, "uvm_test_top.env.cpu_mon", "monitor_name", "CPU_AXI");
      uvm_config_db#(string)::set(null, "uvm_test_top.env.dma_mon", "monitor_name", "DMA_AXI");

      uvm_config_db#(bit [31:0])::set(null, "uvm_test_top.env.scb", "dma_src_addr_exp", test_src_addr);
      uvm_config_db#(bit [31:0])::set(null, "uvm_test_top.env.scb", "dma_dst_addr_exp", test_dst_addr);
      uvm_config_db#(int)::set(null, "uvm_test_top.env.scb", "dma_copy_words_exp", test_len);

      tb_configured = 1'b1;
    end
  endtask

  task automatic pulse_reset;
    begin
      rst_n = 1'b0;
      repeat (3) @(posedge clk);
      rst_n = 1'b1;
      repeat (2) @(posedge clk);
    end
  endtask

  task automatic init_all;
    begin
      for (int i = 0; i < 32; i++) begin
        imem[i] = 32'h0000_0013;
      end

      for (int i = 0; i < SRAM_DEPTH; i++) begin
        dut.u_sram.mem[i] = 32'h0000_0000;
      end

      dma_done_seen  = 1'b0;
      dma_start_seen = 1'b0;
    end
  endtask

  task automatic load_cpu_dma_program;
    logic [31:0] len_word;

    begin
      len_word = test_len;

      imem[0] = 32'h0001_02B7;                              // lui  x5, 0x00010
      imem[1] = encode_addi(5'd6, 5'd0, test_src_addr[11:0]); // addi x6, x0, SRC
      imem[2] = encode_sw  (5'd6, 5'd5, 12'd8);              // sw   x6, 8(x5)
      imem[3] = encode_addi(5'd6, 5'd0, test_dst_addr[11:0]); // addi x6, x0, DST
      imem[4] = encode_sw  (5'd6, 5'd5, 12'd12);             // sw   x6, 12(x5)
      imem[5] = encode_addi(5'd6, 5'd0, len_word[11:0]);     // addi x6, x0, LEN
      imem[6] = encode_sw  (5'd6, 5'd5, 12'd16);             // sw   x6, 16(x5)
      imem[7] = encode_addi(5'd6, 5'd0, 12'd1);              // addi x6, x0, 1
      imem[8] = encode_sw  (5'd6, 5'd5, 12'd0);              // sw   x6, 0(x5)
    end
  endtask

  task automatic preload_sram;
    int src_idx;

    begin
      src_idx = test_src_addr >> 2;

      for (int i = 0; i < test_len; i++) begin
        dut.u_sram.mem[src_idx + i] = test_pattern + i;
      end
    end
  endtask

  task automatic check_copy;
    int        src_idx;
    int        dst_idx;
    bit [31:0] expected;

    begin
      src_idx = test_src_addr >> 2;
      dst_idx = test_dst_addr >> 2;

      for (int i = 0; i < test_len; i++) begin
        expected = test_pattern + i;

        if (dut.u_sram.mem[src_idx + i] !== expected) begin
          `uvm_error("TB_CHECK",
                     $sformatf("Source preload mismatch beat=%0d src_idx=%0d expected=%h got=%h",
                               i, src_idx + i, expected, dut.u_sram.mem[src_idx + i]))
          error_count++;
        end

        if (dut.u_sram.mem[dst_idx + i] !== expected) begin
          `uvm_error("TB_CHECK",
                     $sformatf("DMA copy mismatch beat=%0d dst_idx=%0d expected=%h got=%h",
                               i, dst_idx + i, expected, dut.u_sram.mem[dst_idx + i]))
          error_count++;
        end
        else begin
          `uvm_info("TB_CHECK",
                    $sformatf("DMA copy PASS beat=%0d dst_idx=%0d data=%h",
                              i, dst_idx + i, dut.u_sram.mem[dst_idx + i]),
                    UVM_LOW)
        end
      end
    end
  endtask

  initial begin : uvm_startup
    tb_configured = 1'b0;
    uvm_done_seen = 1'b0;

    configure_uvm();
    uvm_top.finish_on_completion = 1'b0;
    run_test("soc_base_test");

    uvm_done_seen = 1'b1;
  end

  initial begin : tb_main
    error_count = 0;

    wait(tb_configured);

    init_all();
    load_cpu_dma_program();
    preload_sram();

    pulse_reset();

    fork
      begin
        wait(dma_start_seen);
        `uvm_info("TB", $sformatf("DMA start seen at %t", $time), UVM_LOW)
      end

      begin
        repeat (1000) @(posedge clk);
        if (!dma_start_seen) begin
          `uvm_error("TB", "TIMEOUT: CPU did not generate DMA start")
          error_count++;
        end
      end
    join_any
    disable fork;

    fork
      begin
        wait(dma_done_seen);
        `uvm_info("TB", $sformatf("DMA done seen at %t", $time), UVM_LOW)
      end

      begin
        repeat (3000) @(posedge clk);
        if (!dma_done_seen) begin
          `uvm_error("TB", "TIMEOUT: DMA did not complete")
          error_count++;
        end
      end
    join_any
    disable fork;

    repeat (5) @(posedge clk);

    if (dma_error) begin
      `uvm_error("TB", "DMA error asserted")
      error_count++;
    end

    check_copy();

    wait(uvm_done_seen);

    report_server = uvm_report_server::get_server();
    uvm_error_count = report_server.get_severity_count(UVM_ERROR);
    uvm_fatal_count = report_server.get_severity_count(UVM_FATAL);

    if (error_count == 0 && uvm_error_count == 0 && uvm_fatal_count == 0) begin
      $display("========================================");
      $display("PHASE 8 STEP 4 PASS: configurable UVM DMA scenario verified");
      $display("UVM scoreboard checked parameterized DMA copy and coverage");
      $display("========================================");
    end
    else begin
      $error("PHASE 8 STEP 4 FAILED: tb_errors=%0d uvm_errors=%0d uvm_fatals=%0d",
             error_count, uvm_error_count, uvm_fatal_count);
    end

    #100;
    $finish;
  end

endmodule
