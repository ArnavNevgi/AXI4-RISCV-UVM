`timescale 1ns/1ps
import axi_pkg::*;

module simple_fifo_slave_tb;

  parameter ID_W       = 4;
  parameter ADDR_W     = 32;
  parameter DATA_W     = 32;
  parameter FIFO_DEPTH = 16;

  logic clk;
  logic rst_n;

  axi_if #(ID_W, ADDR_W, DATA_W) intf (clk, rst_n);

  int error_count;

  // Register map
  localparam logic [31:0] REG_CONTROL = 32'h0000_0000;
  localparam logic [31:0] REG_STATUS  = 32'h0000_0004;
  localparam logic [31:0] REG_TX_DATA = 32'h0000_0008;
  localparam logic [31:0] REG_RX_DATA = 32'h0000_000C;
  localparam logic [31:0] REG_DEPTH   = 32'h0000_0010;
  localparam logic [31:0] REG_INVALID = 32'h0000_00FC;

  // =========================================================
  // DUT
  // =========================================================

  simple_fifo_slave #(
    .ID_W(ID_W),
    .ADDR_W(ADDR_W),
    .DATA_W(DATA_W),
    .FIFO_DEPTH(FIFO_DEPTH)
  ) dut (
    .clk(clk),
    .rst_n(rst_n),
    .intf(intf)
  );

  // =========================================================
  // Clock / Reset
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
  // AXI-Lite style write
  // =========================================================

  task automatic axi_write(
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
        $error("WRITE RESP ERROR: addr=%h resp=%0d", addr, intf.b.resp);
        error_count++;
      end

      intf.b_ready <= 1'b0;

      $display("WRITE DONE: addr=%h data=%h", addr, data);
    end
  endtask

  // =========================================================
  // AXI-Lite style read
  // =========================================================

  task automatic axi_read_check(
    input logic [ADDR_W-1:0] addr,
    input logic [DATA_W-1:0] expected,
    input string             msg
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
        $error("%s RESP ERROR: addr=%h resp=%0d", msg, addr, intf.r.resp);
        error_count++;
      end

      if (intf.r.last !== 1'b1) begin
        $error("%s ERROR: RLAST should be 1", msg);
        error_count++;
      end

      if (got !== expected) begin
        $error("%s MISMATCH: addr=%h expected=%h got=%h",
               msg, addr, expected, got);
        error_count++;
      end
      else begin
        $display("%s PASS: addr=%h data=%h", msg, addr, got);
      end

      intf.r_ready <= 1'b0;
    end
  endtask

  // =========================================================
  // Status helper
  // =========================================================

  task automatic check_status(
    input logic expected_empty,
    input logic expected_full,
    input logic expected_overflow,
    input logic expected_underflow,
    input int unsigned expected_count,
    input string msg
  );
    logic [31:0] expected_status;

    begin
      expected_status = 32'h0000_0000;
      expected_status[0]    = expected_empty;
      expected_status[1]    = expected_full;
      expected_status[2]    = expected_overflow;
      expected_status[3]    = expected_underflow;
      expected_status[15:8] = expected_count[7:0];

      axi_read_check(REG_STATUS, expected_status, msg);
    end
  endtask

  // =========================================================
  // Tests
  // =========================================================

  task automatic reset_status_test;
    begin
      $display("----------------------------------------");
      $display("FIFO RESET STATUS TEST");

      check_status(1'b1, 1'b0, 1'b0, 1'b0, 0, "Reset status");
      axi_read_check(REG_DEPTH, FIFO_DEPTH, "Depth register");

      $display("FIFO RESET STATUS TEST COMPLETE");
    end
  endtask

  task automatic push_pop_test;
    begin
      $display("----------------------------------------");
      $display("FIFO PUSH/POP TEST");

      axi_write(REG_TX_DATA, 32'hAAAA_0001);
      axi_write(REG_TX_DATA, 32'hAAAA_0002);
      axi_write(REG_TX_DATA, 32'hAAAA_0003);

      check_status(1'b0, 1'b0, 1'b0, 1'b0, 3, "Status after 3 pushes");

      axi_read_check(REG_RX_DATA, 32'hAAAA_0001, "Pop 1");
      axi_read_check(REG_RX_DATA, 32'hAAAA_0002, "Pop 2");
      axi_read_check(REG_RX_DATA, 32'hAAAA_0003, "Pop 3");

      check_status(1'b1, 1'b0, 1'b0, 1'b0, 0, "Status after pops");

      $display("FIFO PUSH/POP TEST COMPLETE");
    end
  endtask

  task automatic full_overflow_test;
    begin
      $display("----------------------------------------");
      $display("FIFO FULL/OVERFLOW TEST");

      // Clear FIFO first
      axi_write(REG_CONTROL, 32'h0000_0001);
      check_status(1'b1, 1'b0, 1'b0, 1'b0, 0, "Status after clear");

      // Fill FIFO
      for (int i = 0; i < FIFO_DEPTH; i++) begin
        axi_write(REG_TX_DATA, 32'hF000_0000 + i);
      end

      check_status(1'b0, 1'b1, 1'b0, 1'b0, FIFO_DEPTH, "Status full");

      // One extra push should set overflow
      axi_write(REG_TX_DATA, 32'hDEAD_BEEF);

      check_status(1'b0, 1'b1, 1'b1, 1'b0, FIFO_DEPTH, "Status overflow");

      // Clear overflow flag by writing STATUS[2]=1
      axi_write(REG_STATUS, 32'h0000_0004);

      check_status(1'b0, 1'b1, 1'b0, 1'b0, FIFO_DEPTH, "Overflow cleared");

      $display("FIFO FULL/OVERFLOW TEST COMPLETE");
    end
  endtask

  task automatic drain_underflow_test;
    begin
      $display("----------------------------------------");
      $display("FIFO DRAIN/UNDERFLOW TEST");

      // Drain current full FIFO
      for (int i = 0; i < FIFO_DEPTH; i++) begin
        axi_read_check(REG_RX_DATA, 32'hF000_0000 + i, "Drain FIFO");
      end

      check_status(1'b1, 1'b0, 1'b0, 1'b0, 0, "Status empty after drain");

      // One extra pop should underflow and return 0
      axi_read_check(REG_RX_DATA, 32'h0000_0000, "Underflow pop returns zero");

      check_status(1'b1, 1'b0, 1'b0, 1'b1, 0, "Status underflow");

      // Clear underflow flag by writing STATUS[3]=1
      axi_write(REG_STATUS, 32'h0000_0008);

      check_status(1'b1, 1'b0, 1'b0, 1'b0, 0, "Underflow cleared");

      $display("FIFO DRAIN/UNDERFLOW TEST COMPLETE");
    end
  endtask

  task automatic clear_test;
    begin
      $display("----------------------------------------");
      $display("FIFO CLEAR TEST");

      axi_write(REG_TX_DATA, 32'h1111_1111);
      axi_write(REG_TX_DATA, 32'h2222_2222);
      check_status(1'b0, 1'b0, 1'b0, 1'b0, 2, "Status before clear");

      axi_write(REG_CONTROL, 32'h0000_0001);
      check_status(1'b1, 1'b0, 1'b0, 1'b0, 0, "Status after clear");

      axi_read_check(REG_RX_DATA, 32'h0000_0000, "Read after clear returns zero");
      check_status(1'b1, 1'b0, 1'b0, 1'b1, 0, "Underflow after clear read");

      axi_write(REG_STATUS, 32'h0000_0008);
      check_status(1'b1, 1'b0, 1'b0, 1'b0, 0, "Final clear status");

      $display("FIFO CLEAR TEST COMPLETE");
    end
  endtask

  task automatic invalid_address_test;
    begin
      $display("----------------------------------------");
      $display("FIFO INVALID ADDRESS TEST");

      axi_write(REG_INVALID, 32'hCAFE_BABE);
      axi_read_check(REG_INVALID, 32'h0000_0000, "Invalid address read");

      $display("FIFO INVALID ADDRESS TEST COMPLETE");
    end
  endtask

  task automatic random_fifo_test(input int num_items);
    logic [31:0] expected_q [0:FIFO_DEPTH-1];

    begin
      $display("----------------------------------------");
      $display("FIFO RANDOM PUSH/POP TEST");

      axi_write(REG_CONTROL, 32'h0000_0001);

      for (int i = 0; i < num_items; i++) begin
        expected_q[i] = $urandom();
        axi_write(REG_TX_DATA, expected_q[i]);
      end

      check_status(1'b0, (num_items == FIFO_DEPTH), 1'b0, 1'b0, num_items,
                   "Random push status");

      for (int i = 0; i < num_items; i++) begin
        axi_read_check(REG_RX_DATA, expected_q[i], "Random pop");
      end

      check_status(1'b1, 1'b0, 1'b0, 1'b0, 0, "Random final empty");

      $display("FIFO RANDOM PUSH/POP TEST COMPLETE");
    end
  endtask

  // =========================================================
  // Test sequence
  // =========================================================

  initial begin
    error_count = 0;

    init_master();

    wait(rst_n);
    repeat (2) @(posedge clk);

    reset_status_test();
    push_pop_test();
    full_overflow_test();
    drain_underflow_test();
    clear_test();
    invalid_address_test();
    random_fifo_test(8);

    #20;

    if (error_count == 0) begin
      $display("========================================");
      $display("PHASE 6 STEP 7 PASS: simple FIFO slave verified");
      $display("push/pop, full, empty, overflow, underflow, clear, and random tests passed");
      $display("========================================");
    end
    else begin
      $error("PHASE 6 STEP 7 FAILED: error_count=%0d", error_count);
    end

    #50;
    $finish;
  end

endmodule