`timescale 1ns/1ps
import axi_pkg::*;

module axi_sram_slave_tb;

  parameter ID_W   = 4;
  parameter ADDR_W = 32;
  parameter DATA_W = 32;
  parameter DEPTH  = 256;
  parameter DEBUG  = 1;

  logic clk;
  logic rst_n;

  axi_if #(ID_W, ADDR_W, DATA_W) intf (clk, rst_n);

  int error_count;

  // =========================================================
  // DUT
  // =========================================================

  axi_sram_slave #(
    .ID_W(ID_W),
    .ADDR_W(ADDR_W),
    .DATA_W(DATA_W),
    .DEPTH(DEPTH)
  ) dut (
    .clk(clk),
    .rst_n(rst_n),
    .intf(intf)
  );

  // =========================================================
  // CLOCK / RESET
  // =========================================================

  initial clk = 0;
  always #5 clk = ~clk;

  initial begin
    rst_n = 0;
    #20;
    rst_n = 1;
  end

  // =========================================================
  // MASTER INIT
  // =========================================================

  task automatic init_master;
    begin
      intf.aw_valid = 1'b0;
      intf.aw       = '0;

      intf.w_valid  = 1'b0;
      intf.w        = '0;

      intf.b_ready  = 1'b0;

      intf.ar_valid = 1'b0;
      intf.ar       = '0;

      intf.r_ready  = 1'b0;
    end
  endtask

  // =========================================================
  // SINGLE WRITE
  // =========================================================

  task automatic axi_write_word(
    input logic [ADDR_W-1:0] addr,
    input logic [DATA_W-1:0] data
  );
    begin
      // AW
      @(posedge clk);
      intf.aw_valid <= 1'b1;
      intf.aw.id    <= 4'd0;
      intf.aw.addr  <= addr;
      intf.aw.len   <= 8'd0;
      intf.aw.size  <= 3'b010;
      intf.aw.burst <= AXI_BURST_INCR;

      do @(posedge clk); while (!intf.aw_ready);
      intf.aw_valid <= 1'b0;

      // W
      @(posedge clk);
      intf.w_valid <= 1'b1;
      intf.w.data  <= data;
      intf.w.strb  <= '1;
      intf.w.last  <= 1'b1;

      do @(posedge clk); while (!intf.w_ready);
      intf.w_valid <= 1'b0;
      intf.w.last  <= 1'b0;

      // B
      @(posedge clk);
      intf.b_ready <= 1'b1;

      do @(posedge clk); while (!intf.b_valid);

      if (intf.b.resp !== AXI_RESP_OKAY) begin
        $error("WRITE RESP ERROR: expected OKAY got=%0d", intf.b.resp);
        error_count++;
      end

      intf.b_ready <= 1'b0;

      if (DEBUG)
        $display("WRITE WORD DONE: addr=%h data=%h @ %t", addr, data, $time);
    end
  endtask

  // =========================================================
  // SINGLE READ CHECK
  // =========================================================

  task automatic axi_read_check(
    input logic [ADDR_W-1:0] addr,
    input logic [DATA_W-1:0] expected
  );
    logic [DATA_W-1:0] got;

    begin
      // AR
      @(posedge clk);
      intf.ar_valid <= 1'b1;
      intf.ar.id    <= 4'd0;
      intf.ar.addr  <= addr;
      intf.ar.len   <= 8'd0;
      intf.ar.size  <= 3'b010;
      intf.ar.burst <= AXI_BURST_INCR;

      do @(posedge clk); while (!intf.ar_ready);
      intf.ar_valid <= 1'b0;

      // R
      @(posedge clk);
      intf.r_ready <= 1'b1;

      do @(posedge clk); while (!intf.r_valid);

      got = intf.r.data;

      if (intf.r.resp !== AXI_RESP_OKAY) begin
        $error("READ RESP ERROR: expected OKAY got=%0d", intf.r.resp);
        error_count++;
      end

      if (intf.r.last !== 1'b1) begin
        $error("READ ERROR: single-beat read should have RLAST=1");
        error_count++;
      end

      if (got !== expected) begin
        $error("READ MISMATCH: addr=%h expected=%h got=%h",
               addr, expected, got);
        error_count++;
      end
      else begin
        $display("READ PASS: addr=%h data=%h", addr, got);
      end

      intf.r_ready <= 1'b0;
    end
  endtask

  // =========================================================
  // BURST WRITE
  // =========================================================

  task automatic axi_burst_write(
    input logic [ADDR_W-1:0] addr,
    input logic [DATA_W-1:0] base_data,
    input logic [7:0]        len
  );
    begin
      // AW
      @(posedge clk);
      intf.aw_valid <= 1'b1;
      intf.aw.id    <= 4'd0;
      intf.aw.addr  <= addr;
      intf.aw.len   <= len;
      intf.aw.size  <= 3'b010;
      intf.aw.burst <= AXI_BURST_INCR;

      do @(posedge clk); while (!intf.aw_ready);
      intf.aw_valid <= 1'b0;

      // W beats
      for (int i = 0; i <= len; i++) begin
        @(posedge clk);
        intf.w_valid <= 1'b1;
        intf.w.data  <= base_data + i;
        intf.w.strb  <= '1;
        intf.w.last  <= (i == len);

        do @(posedge clk); while (!intf.w_ready);

        intf.w_valid <= 1'b0;
        intf.w.last  <= 1'b0;

        // one bubble to avoid duplicate accepted beat in TB
        @(posedge clk);
      end

      // B
      @(posedge clk);
      intf.b_ready <= 1'b1;

      do @(posedge clk); while (!intf.b_valid);

      if (intf.b.resp !== AXI_RESP_OKAY) begin
        $error("BURST WRITE RESP ERROR: expected OKAY got=%0d", intf.b.resp);
        error_count++;
      end

      intf.b_ready <= 1'b0;

      $display("BURST WRITE DONE: addr=%h len=%0d base=%h",
               addr, len, base_data);
    end
  endtask

  // =========================================================
  // BURST READ CHECK
  // =========================================================

  task automatic axi_burst_read_check(
    input logic [ADDR_W-1:0] addr,
    input logic [DATA_W-1:0] expected_base,
    input logic [7:0]        len
  );
    logic [DATA_W-1:0] got;
    logic              got_last;

    begin
      // AR
      @(posedge clk);
      intf.ar_valid <= 1'b1;
      intf.ar.id    <= 4'd0;
      intf.ar.addr  <= addr;
      intf.ar.len   <= len;
      intf.ar.size  <= 3'b010;
      intf.ar.burst <= AXI_BURST_INCR;

      do @(posedge clk); while (!intf.ar_ready);
      intf.ar_valid <= 1'b0;

      @(posedge clk);
      intf.r_ready <= 1'b1;

      for (int i = 0; i <= len; i++) begin
        do @(posedge clk); while (!intf.r_valid);

        got      = intf.r.data;
        got_last = intf.r.last;

        if (intf.r.resp !== AXI_RESP_OKAY) begin
          $error("BURST READ RESP ERROR: beat=%0d resp=%0d", i, intf.r.resp);
          error_count++;
        end

        if (got !== (expected_base + i)) begin
          $error("BURST READ MISMATCH: beat=%0d addr=%h expected=%h got=%h",
                 i, addr + (i * 4), expected_base + i, got);
          error_count++;
        end
        else begin
          $display("BURST READ PASS: beat=%0d data=%h", i, got);
        end

        if ((i != len) && got_last) begin
          $error("BURST READ ERROR: early RLAST beat=%0d len=%0d", i, len);
          error_count++;
        end

        if ((i == len) && !got_last) begin
          $error("BURST READ ERROR: missing RLAST final beat=%0d", i);
          error_count++;
        end

        @(posedge clk);
      end

      intf.r_ready <= 1'b0;

      $display("BURST READ CHECK DONE: addr=%h len=%0d", addr, len);
    end
  endtask

  // =========================================================
  // RANDOM REGRESSION
  // =========================================================

  task automatic random_sram_regression(input int num_tests);
    int unsigned addr_idx;
    int unsigned len;
    logic [31:0] pattern;

    begin
      for (int t = 0; t < num_tests; t++) begin
        len      = $urandom_range(0, 15); // AXI LEN, so 1 to 16 beats
        addr_idx = $urandom_range(0, DEPTH - 1 - len);
        pattern  = $urandom();

        $display("----------------------------------------");
        $display("RANDOM SRAM TEST %0d: addr_idx=%0d len=%0d pattern=%h",
                 t, addr_idx, len, pattern);

        axi_burst_write(addr_idx << 2, pattern, len[7:0]);
        axi_burst_read_check(addr_idx << 2, pattern, len[7:0]);
      end
    end
  endtask

  // =========================================================
  // TEST SEQUENCE
  // =========================================================

  initial begin
    error_count = 0;

    init_master();

    wait(rst_n);
    repeat (2) @(posedge clk);

    // Single-beat tests
    axi_write_word(32'h0000_0010, 32'hAAAA_AAAA);
    axi_read_check(32'h0000_0010, 32'hAAAA_AAAA);

    axi_write_word(32'h0000_0020, 32'h1234_5678);
    axi_read_check(32'h0000_0020, 32'h1234_5678);

    // Burst tests
    axi_burst_write(32'h0000_0040, 32'hBBBB_0000, 8'd3);  // 4 beats
    axi_burst_read_check(32'h0000_0040, 32'hBBBB_0000, 8'd3);

    axi_burst_write(32'h0000_0080, 32'hCCCC_0000, 8'd7);  // 8 beats
    axi_burst_read_check(32'h0000_0080, 32'hCCCC_0000, 8'd7);

    axi_burst_write(32'h0000_00C0, 32'hDDDD_0000, 8'd15); // 16 beats
    axi_burst_read_check(32'h0000_00C0, 32'hDDDD_0000, 8'd15);

    // Random tests
    random_sram_regression(20);

    #20;

    if (error_count == 0) begin
      $display("========================================");
      $display("PHASE 6 STEP 2 PASS: AXI SRAM slave verified");
      $display("single-beat, burst, and randomized SRAM accesses passed");
      $display("========================================");
    end
    else begin
      $error("PHASE 6 STEP 2 FAILED: error_count=%0d", error_count);
    end

    #50;
    $finish;
  end

endmodule