`timescale 1ns/1ps
import axi_pkg::*;

module axi_interconnect_2m2s_tb;

  parameter ID_W   = 4;
  parameter ADDR_W = 32;
  parameter DATA_W = 32;
  parameter DEPTH  = 256;

  logic clk;
  logic rst_n;

  int error_count;

  // Master interfaces
  axi_if #(ID_W, ADDR_W, DATA_W) m0_if   (clk, rst_n);
  axi_if #(ID_W, ADDR_W, DATA_W) m1_if   (clk, rst_n);

  // Slave interfaces
  axi_if #(ID_W, ADDR_W, DATA_W) sram_if (clk, rst_n);
  axi_if #(ID_W, ADDR_W, DATA_W) regs_if (clk, rst_n);

  // =========================================================
  // DUT: 2-master / 2-slave interconnect
  // =========================================================

  axi_interconnect_2m2s #(
    .ID_W(ID_W),
    .ADDR_W(ADDR_W),
    .DATA_W(DATA_W)
  ) dut (
    .clk(clk),
    .rst_n(rst_n),

    .m0(m0_if),
    .m1(m1_if),

    .s0(sram_if),
    .s1(regs_if)
  );

  // =========================================================
  // Slave 0: AXI SRAM
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
  // Slave 1: AXI-Lite register slave
  // =========================================================

  axi_lite_reg_slave #(
    .ID_W(ID_W),
    .ADDR_W(ADDR_W),
    .DATA_W(DATA_W)
  ) u_regs (
    .clk(clk),
    .rst_n(rst_n),
    .intf(regs_if)
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
  // Master init
  // =========================================================

  task automatic init_masters;
    begin
      m0_if.aw_valid = 1'b0;
      m0_if.aw       = '0;
      m0_if.w_valid  = 1'b0;
      m0_if.w        = '0;
      m0_if.b_ready  = 1'b0;
      m0_if.ar_valid = 1'b0;
      m0_if.ar       = '0;
      m0_if.r_ready  = 1'b0;

      m1_if.aw_valid = 1'b0;
      m1_if.aw       = '0;
      m1_if.w_valid  = 1'b0;
      m1_if.w        = '0;
      m1_if.b_ready  = 1'b0;
      m1_if.ar_valid = 1'b0;
      m1_if.ar       = '0;
      m1_if.r_ready  = 1'b0;
    end
  endtask

  // =========================================================
  // M0 write/read tasks
  // =========================================================

  task automatic m0_write(
    input logic [ADDR_W-1:0] addr,
    input logic [DATA_W-1:0] data
  );
    begin
      @(posedge clk);
      m0_if.aw_valid <= 1'b1;
      m0_if.aw.id    <= 4'd0;
      m0_if.aw.addr  <= addr;
      m0_if.aw.len   <= 8'd0;
      m0_if.aw.size  <= 3'b010;
      m0_if.aw.burst <= AXI_BURST_INCR;

      do @(posedge clk); while (!m0_if.aw_ready);
      m0_if.aw_valid <= 1'b0;

      @(posedge clk);
      m0_if.w_valid <= 1'b1;
      m0_if.w.data  <= data;
      m0_if.w.strb  <= '1;
      m0_if.w.last  <= 1'b1;

      do @(posedge clk); while (!m0_if.w_ready);
      m0_if.w_valid <= 1'b0;
      m0_if.w.last  <= 1'b0;

      @(posedge clk);
      m0_if.b_ready <= 1'b1;

      do @(posedge clk); while (!m0_if.b_valid);

      if (m0_if.b.resp !== AXI_RESP_OKAY) begin
        $error("M0 WRITE RESP ERROR: addr=%h resp=%0d", addr, m0_if.b.resp);
        error_count++;
      end

      m0_if.b_ready <= 1'b0;

      $display("M0 WRITE DONE: addr=%h data=%h", addr, data);
    end
  endtask

  task automatic m0_read_check(
    input logic [ADDR_W-1:0] addr,
    input logic [DATA_W-1:0] expected
  );
    logic [DATA_W-1:0] got;

    begin
      @(posedge clk);
      m0_if.ar_valid <= 1'b1;
      m0_if.ar.id    <= 4'd0;
      m0_if.ar.addr  <= addr;
      m0_if.ar.len   <= 8'd0;
      m0_if.ar.size  <= 3'b010;
      m0_if.ar.burst <= AXI_BURST_INCR;

      do @(posedge clk); while (!m0_if.ar_ready);
      m0_if.ar_valid <= 1'b0;

      @(posedge clk);
      m0_if.r_ready <= 1'b1;

      do @(posedge clk); while (!m0_if.r_valid);

      got = m0_if.r.data;

      if (m0_if.r.resp !== AXI_RESP_OKAY) begin
        $error("M0 READ RESP ERROR: addr=%h resp=%0d", addr, m0_if.r.resp);
        error_count++;
      end

      if (m0_if.r.last !== 1'b1) begin
        $error("M0 READ ERROR: RLAST should be 1");
        error_count++;
      end

      if (got !== expected) begin
        $error("M0 READ MISMATCH: addr=%h expected=%h got=%h",
               addr, expected, got);
        error_count++;
      end
      else begin
        $display("M0 READ PASS: addr=%h data=%h", addr, got);
      end

      m0_if.r_ready <= 1'b0;
    end
  endtask

  // =========================================================
  // M1 write/read tasks
  // =========================================================

  task automatic m1_write(
    input logic [ADDR_W-1:0] addr,
    input logic [DATA_W-1:0] data
  );
    begin
      @(posedge clk);
      m1_if.aw_valid <= 1'b1;
      m1_if.aw.id    <= 4'd1;
      m1_if.aw.addr  <= addr;
      m1_if.aw.len   <= 8'd0;
      m1_if.aw.size  <= 3'b010;
      m1_if.aw.burst <= AXI_BURST_INCR;

      do @(posedge clk); while (!m1_if.aw_ready);
      m1_if.aw_valid <= 1'b0;

      @(posedge clk);
      m1_if.w_valid <= 1'b1;
      m1_if.w.data  <= data;
      m1_if.w.strb  <= '1;
      m1_if.w.last  <= 1'b1;

      do @(posedge clk); while (!m1_if.w_ready);
      m1_if.w_valid <= 1'b0;
      m1_if.w.last  <= 1'b0;

      @(posedge clk);
      m1_if.b_ready <= 1'b1;

      do @(posedge clk); while (!m1_if.b_valid);

      if (m1_if.b.resp !== AXI_RESP_OKAY) begin
        $error("M1 WRITE RESP ERROR: addr=%h resp=%0d", addr, m1_if.b.resp);
        error_count++;
      end

      m1_if.b_ready <= 1'b0;

      $display("M1 WRITE DONE: addr=%h data=%h", addr, data);
    end
  endtask

  task automatic m1_read_check(
    input logic [ADDR_W-1:0] addr,
    input logic [DATA_W-1:0] expected
  );
    logic [DATA_W-1:0] got;

    begin
      @(posedge clk);
      m1_if.ar_valid <= 1'b1;
      m1_if.ar.id    <= 4'd1;
      m1_if.ar.addr  <= addr;
      m1_if.ar.len   <= 8'd0;
      m1_if.ar.size  <= 3'b010;
      m1_if.ar.burst <= AXI_BURST_INCR;

      do @(posedge clk); while (!m1_if.ar_ready);
      m1_if.ar_valid <= 1'b0;

      @(posedge clk);
      m1_if.r_ready <= 1'b1;

      do @(posedge clk); while (!m1_if.r_valid);

      got = m1_if.r.data;

      if (m1_if.r.resp !== AXI_RESP_OKAY) begin
        $error("M1 READ RESP ERROR: addr=%h resp=%0d", addr, m1_if.r.resp);
        error_count++;
      end

      if (m1_if.r.last !== 1'b1) begin
        $error("M1 READ ERROR: RLAST should be 1");
        error_count++;
      end

      if (got !== expected) begin
        $error("M1 READ MISMATCH: addr=%h expected=%h got=%h",
               addr, expected, got);
        error_count++;
      end
      else begin
        $display("M1 READ PASS: addr=%h data=%h", addr, got);
      end

      m1_if.r_ready <= 1'b0;
    end
  endtask

  // =========================================================
  // Tests
  // =========================================================

  task automatic m0_sram_test;
    begin
      $display("----------------------------------------");
      $display("M0 SRAM DECODE TEST");

      m0_write(32'h0000_0010, 32'hAAAA_1111);
      m0_read_check(32'h0000_0010, 32'hAAAA_1111);

      m0_write(32'h0000_0020, 32'hAAAA_2222);
      m0_read_check(32'h0000_0020, 32'hAAAA_2222);

      $display("M0 SRAM DECODE TEST COMPLETE");
    end
  endtask

  task automatic m0_regs_test;
    begin
      $display("----------------------------------------");
      $display("M0 REGISTER DECODE TEST");

      // Full address 0x0001_0008 should localize to register offset 0x08
      m0_write(32'h0001_0008, 32'h0000_1000); // SRC_ADDR
      m0_write(32'h0001_000C, 32'h0000_2000); // DST_ADDR
      m0_write(32'h0001_0010, 32'h0000_0040); // LENGTH
      m0_write(32'h0001_0000, 32'h0000_0001); // CONTROL

      m0_read_check(32'h0001_0008, 32'h0000_1000);
      m0_read_check(32'h0001_000C, 32'h0000_2000);
      m0_read_check(32'h0001_0010, 32'h0000_0040);
      m0_read_check(32'h0001_0000, 32'h0000_0001);

      $display("M0 REGISTER DECODE TEST COMPLETE");
    end
  endtask

  task automatic m1_sram_test;
    begin
      $display("----------------------------------------");
      $display("M1 SRAM DECODE TEST");

      m1_write(32'h0000_0040, 32'hBBBB_4444);
      m1_read_check(32'h0000_0040, 32'hBBBB_4444);

      m1_write(32'h0000_0050, 32'hBBBB_5555);
      m1_read_check(32'h0000_0050, 32'hBBBB_5555);

      $display("M1 SRAM DECODE TEST COMPLETE");
    end
  endtask

  task automatic cross_master_test;
    begin
      $display("----------------------------------------");
      $display("CROSS MASTER ROUTING TEST");

      // M0 writes SRAM, M1 reads same SRAM location
      m0_write(32'h0000_0060, 32'hCAFE_0060);
      m1_read_check(32'h0000_0060, 32'hCAFE_0060);

      // M1 writes SRAM, M0 reads same SRAM location
      m1_write(32'h0000_0064, 32'hFACE_0064);
      m0_read_check(32'h0000_0064, 32'hFACE_0064);

      // M0 writes regs, M1 reads regs. This proves S1 response routing works too.
      m0_write(32'h0001_0010, 32'h0000_0077);
      m1_read_check(32'h0001_0010, 32'h0000_0077);

      $display("CROSS MASTER ROUTING TEST COMPLETE");
    end
  endtask

  // =========================================================
  // Test sequence
  // =========================================================

  initial begin
    error_count = 0;

    init_masters();

    wait(rst_n);
    repeat (2) @(posedge clk);

    m0_sram_test();
    m0_regs_test();
    m1_sram_test();
    cross_master_test();

    #20;

    if (error_count == 0) begin
      $display("========================================");
      $display("PHASE 7 STEP 2 PASS: 2M2S AXI interconnect verified");
      $display("SRAM/register address decode and response routing passed");
      $display("========================================");
    end
    else begin
      $error("PHASE 7 STEP 2 FAILED: error_count=%0d", error_count);
    end

    #50;
    $finish;
  end

endmodule