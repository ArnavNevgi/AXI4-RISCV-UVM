`timescale 1ns/1ps
import axi_pkg::*;

module axi_lite_reg_slave_tb;

  parameter ID_W   = 4;
  parameter ADDR_W = 32;
  parameter DATA_W = 32;

  logic clk;
  logic rst_n;

  axi_if #(ID_W, ADDR_W, DATA_W) intf (clk, rst_n);

  int error_count;

  // =========================================================
  // DUT
  // =========================================================

  axi_lite_reg_slave #(
    .ID_W(ID_W),
    .ADDR_W(ADDR_W),
    .DATA_W(DATA_W)
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
  // Register addresses
  // =========================================================

  localparam logic [31:0] REG_CONTROL  = 32'h0000_0000;
  localparam logic [31:0] REG_STATUS   = 32'h0000_0004;
  localparam logic [31:0] REG_SRC_ADDR = 32'h0000_0008;
  localparam logic [31:0] REG_DST_ADDR = 32'h0000_000C;
  localparam logic [31:0] REG_LENGTH   = 32'h0000_0010;
  localparam logic [31:0] REG_INVALID  = 32'h0000_00FC;

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
  // AXI-Lite write
  // =========================================================

  task automatic axi_lite_write(
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
        $error("AXI-LITE WRITE RESP ERROR: addr=%h resp=%0d", addr, intf.b.resp);
        error_count++;
      end

      intf.b_ready <= 1'b0;

      $display("AXI-LITE WRITE DONE: addr=%h data=%h", addr, data);
    end
  endtask

  // =========================================================
  // AXI-Lite read
  // =========================================================

  task automatic axi_lite_read_check(
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
        $error("AXI-LITE READ RESP ERROR: addr=%h resp=%0d", addr, intf.r.resp);
        error_count++;
      end

      if (intf.r.last !== 1'b1) begin
        $error("AXI-LITE READ ERROR: RLAST should be 1 for single-beat read");
        error_count++;
      end

      if (got !== expected) begin
        $error("AXI-LITE READ MISMATCH: addr=%h expected=%h got=%h",
               addr, expected, got);
        error_count++;
      end
      else begin
        $display("AXI-LITE READ PASS: addr=%h data=%h", addr, got);
      end

      intf.r_ready <= 1'b0;
    end
  endtask

  // =========================================================
  // Register map test
  // =========================================================

  task automatic register_map_test;
    begin
      $display("----------------------------------------");
      $display("AXI-LITE REGISTER MAP TEST");

      axi_lite_write(REG_CONTROL,  32'h0000_0001);
      axi_lite_write(REG_STATUS,   32'h0000_00AA);
      axi_lite_write(REG_SRC_ADDR, 32'h0000_1000);
      axi_lite_write(REG_DST_ADDR, 32'h0000_2000);
      axi_lite_write(REG_LENGTH,   32'h0000_0040);

      axi_lite_read_check(REG_CONTROL,  32'h0000_0001);
      axi_lite_read_check(REG_STATUS,   32'h0000_00AA);
      axi_lite_read_check(REG_SRC_ADDR, 32'h0000_1000);
      axi_lite_read_check(REG_DST_ADDR, 32'h0000_2000);
      axi_lite_read_check(REG_LENGTH,   32'h0000_0040);

      $display("AXI-LITE REGISTER MAP TEST COMPLETE");
    end
  endtask

  // =========================================================
  // Overwrite test
  // =========================================================

  task automatic overwrite_test;
    begin
      $display("----------------------------------------");
      $display("AXI-LITE OVERWRITE TEST");

      axi_lite_write(REG_SRC_ADDR, 32'hAAAA_AAAA);
      axi_lite_read_check(REG_SRC_ADDR, 32'hAAAA_AAAA);

      axi_lite_write(REG_SRC_ADDR, 32'h5555_5555);
      axi_lite_read_check(REG_SRC_ADDR, 32'h5555_5555);

      axi_lite_write(REG_LENGTH, 32'h0000_0010);
      axi_lite_read_check(REG_LENGTH, 32'h0000_0010);

      axi_lite_write(REG_LENGTH, 32'h0000_0040);
      axi_lite_read_check(REG_LENGTH, 32'h0000_0040);

      $display("AXI-LITE OVERWRITE TEST COMPLETE");
    end
  endtask

  // =========================================================
  // Invalid address test
  // =========================================================

  task automatic invalid_address_test;
    begin
      $display("----------------------------------------");
      $display("AXI-LITE INVALID ADDRESS TEST");

      // Invalid writes are ignored
      axi_lite_write(REG_INVALID, 32'hDEAD_BEEF);

      // Invalid reads return zero
      axi_lite_read_check(REG_INVALID, 32'h0000_0000);

      $display("AXI-LITE INVALID ADDRESS TEST COMPLETE");
    end
  endtask

  // =========================================================
  // Reset value test
  // =========================================================

  task automatic reset_value_test;
    begin
      $display("----------------------------------------");
      $display("AXI-LITE RESET VALUE TEST");

      axi_lite_read_check(REG_CONTROL,  32'h0000_0000);
      axi_lite_read_check(REG_STATUS,   32'h0000_0000);
      axi_lite_read_check(REG_SRC_ADDR, 32'h0000_0000);
      axi_lite_read_check(REG_DST_ADDR, 32'h0000_0000);
      axi_lite_read_check(REG_LENGTH,   32'h0000_0000);

      $display("AXI-LITE RESET VALUE TEST COMPLETE");
    end
  endtask

  // =========================================================
  // Random register regression
  // =========================================================

  task automatic random_reg_regression(input int num_tests);
    logic [31:0] addr;
    logic [31:0] data;

    begin
      for (int i = 0; i < num_tests; i++) begin
        case ($urandom_range(0, 4))
          0: addr = REG_CONTROL;
          1: addr = REG_STATUS;
          2: addr = REG_SRC_ADDR;
          3: addr = REG_DST_ADDR;
          4: addr = REG_LENGTH;
          default: addr = REG_CONTROL;
        endcase

        data = $urandom();

        axi_lite_write(addr, data);
        axi_lite_read_check(addr, data);
      end

      $display("AXI-LITE RANDOM REGISTER REGRESSION COMPLETE");
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

    reset_value_test();
    register_map_test();
    overwrite_test();
    invalid_address_test();
    random_reg_regression(20);

    #20;

    if (error_count == 0) begin
      $display("========================================");
      $display("PHASE 6 STEP 5 PASS: AXI-Lite register slave verified");
      $display("register read/write, reset, overwrite, invalid address, and random tests passed");
      $display("========================================");
    end
    else begin
      $error("PHASE 6 STEP 5 FAILED: error_count=%0d", error_count);
    end

    #50;
    $finish;
  end

endmodule