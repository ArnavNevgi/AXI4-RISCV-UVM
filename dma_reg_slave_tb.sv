`timescale 1ns/1ps
import axi_pkg::*;

module dma_reg_slave_tb;

  parameter ID_W   = 4;
  parameter ADDR_W = 32;
  parameter DATA_W = 32;

  logic clk;
  logic rst_n;

  axi_if #(ID_W, ADDR_W, DATA_W) intf (clk, rst_n);

  // DMA control outputs from register slave
  logic        dma_start_pulse;
  logic [31:0] dma_src_addr;
  logic [31:0] dma_dst_addr;
  logic [15:0] dma_length;

  // DMA status inputs to register slave
  logic dma_busy;
  logic dma_done;
  logic dma_error;

  int error_count;
  logic start_pulse_seen;

  // Register map
  localparam logic [31:0] REG_CONTROL  = 32'h0000_0000;
  localparam logic [31:0] REG_STATUS   = 32'h0000_0004;
  localparam logic [31:0] REG_SRC_ADDR = 32'h0000_0008;
  localparam logic [31:0] REG_DST_ADDR = 32'h0000_000C;
  localparam logic [31:0] REG_LENGTH   = 32'h0000_0010;
  localparam logic [31:0] REG_INVALID  = 32'h0000_00FC;

  // =========================================================
  // DUT
  // =========================================================

  dma_reg_slave #(
    .ID_W(ID_W),
    .ADDR_W(ADDR_W),
    .DATA_W(DATA_W)
  ) dut (
    .clk(clk),
    .rst_n(rst_n),

    .intf(intf),

    .dma_start_pulse(dma_start_pulse),
    .dma_src_addr(dma_src_addr),
    .dma_dst_addr(dma_dst_addr),
    .dma_length(dma_length),

    .dma_busy(dma_busy),
    .dma_done(dma_done),
    .dma_error(dma_error)
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

  always @(posedge clk or negedge rst_n) begin
  if (!rst_n) begin
    start_pulse_seen <= 1'b0;
  end
  else begin
    if (dma_start_pulse)
      start_pulse_seen <= 1'b1;
  end
end

  // =========================================================
  // INIT
  // =========================================================

  task automatic init_signals;
    begin
      intf.aw_valid = 1'b0;
      intf.aw       = '0;

      intf.w_valid  = 1'b0;
      intf.w        = '0;

      intf.b_ready  = 1'b0;

      intf.ar_valid = 1'b0;
      intf.ar       = '0;

      intf.r_ready  = 1'b0;

      dma_busy  = 1'b0;
      dma_done  = 1'b0;
      dma_error = 1'b0;
    end
  endtask

  // =========================================================
  // AXI-LITE WRITE
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
  // AXI-LITE READ CHECK
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
  // STATUS EXPECTED HELPER
  // =========================================================

  function automatic logic [31:0] expected_status(
    input logic done_bit,
    input logic busy_bit,
    input logic error_bit
  );
    begin
      expected_status = 32'h0000_0000;
      expected_status[0] = done_bit;
      expected_status[1] = busy_bit;
      expected_status[2] = error_bit;
    end
  endfunction

  // =========================================================
  // TESTS
  // =========================================================

  task automatic reset_value_test;
    begin
      $display("----------------------------------------");
      $display("DMA REG RESET VALUE TEST");

      axi_read_check(REG_CONTROL,  32'h0000_0000, "CONTROL reset");
      axi_read_check(REG_STATUS,   32'h0000_0000, "STATUS reset");
      axi_read_check(REG_SRC_ADDR, 32'h0000_0000, "SRC reset");
      axi_read_check(REG_DST_ADDR, 32'h0000_0000, "DST reset");
      axi_read_check(REG_LENGTH,   32'h0000_0000, "LENGTH reset");

      if (dma_start_pulse !== 1'b0) begin
        $error("RESET ERROR: dma_start_pulse should be 0");
        error_count++;
      end

      $display("DMA REG RESET VALUE TEST COMPLETE");
    end
  endtask

  task automatic config_register_test;
    begin
      $display("----------------------------------------");
      $display("DMA REG CONFIG REGISTER TEST");

      axi_write(REG_SRC_ADDR, 32'h0000_0040);
      axi_write(REG_DST_ADDR, 32'h0000_0180);
      axi_write(REG_LENGTH,   32'h0000_0010);

      axi_read_check(REG_SRC_ADDR, 32'h0000_0040, "SRC readback");
      axi_read_check(REG_DST_ADDR, 32'h0000_0180, "DST readback");
      axi_read_check(REG_LENGTH,   32'h0000_0010, "LENGTH readback");

      if (dma_src_addr !== 32'h0000_0040) begin
        $error("OUTPUT ERROR: dma_src_addr expected 00000040 got=%h", dma_src_addr);
        error_count++;
      end

      if (dma_dst_addr !== 32'h0000_0180) begin
        $error("OUTPUT ERROR: dma_dst_addr expected 00000180 got=%h", dma_dst_addr);
        error_count++;
      end

      if (dma_length !== 16'h0010) begin
        $error("OUTPUT ERROR: dma_length expected 0010 got=%h", dma_length);
        error_count++;
      end

      $display("DMA REG CONFIG REGISTER TEST COMPLETE");
    end
  endtask

  task automatic start_pulse_test;
  begin
    $display("----------------------------------------");
    $display("DMA REG START PULSE TEST");

    if (dma_start_pulse !== 1'b0) begin
      $error("START PULSE ERROR: pulse should be 0 before start");
      error_count++;
    end

    // Clear monitor
    start_pulse_seen = 1'b0;
    repeat (1) @(posedge clk);

    // Normal AXI write to CONTROL[0]
    axi_write(REG_CONTROL, 32'h0000_0001);

    // Give monitor a cycle to observe pulse
    repeat (2) @(posedge clk);

    if (start_pulse_seen !== 1'b1) begin
      $error("START PULSE ERROR: dma_start_pulse was never observed");
      error_count++;
    end
    else begin
      $display("START PULSE OBSERVED PASS");
    end

    // Pulse should not remain stuck high
    if (dma_start_pulse !== 1'b0) begin
      $error("START PULSE ERROR: dma_start_pulse should not stay high");
      error_count++;
    end
    else begin
      $display("START PULSE ONE-CYCLE CLEAR PASS");
    end

    $display("DMA REG START PULSE TEST COMPLETE");
  end
endtask

  task automatic status_busy_test;
    begin
      $display("----------------------------------------");
      $display("DMA REG STATUS BUSY TEST");

      dma_busy = 1'b1;
      repeat (2) @(posedge clk);

      axi_read_check(REG_STATUS, expected_status(1'b0, 1'b1, 1'b0), "STATUS busy");

      dma_busy = 1'b0;
      repeat (2) @(posedge clk);

      axi_read_check(REG_STATUS, expected_status(1'b0, 1'b0, 1'b0), "STATUS not busy");

      $display("DMA REG STATUS BUSY TEST COMPLETE");
    end
  endtask

  task automatic status_done_sticky_test;
    begin
      $display("----------------------------------------");
      $display("DMA REG STATUS DONE STICKY TEST");

      dma_done = 1'b1;
      @(posedge clk);
      dma_done = 1'b0;

      repeat (2) @(posedge clk);

      axi_read_check(REG_STATUS, expected_status(1'b1, 1'b0, 1'b0), "STATUS done sticky");

      // Clear DONE by writing STATUS[0]=1
      axi_write(REG_STATUS, 32'h0000_0001);

      axi_read_check(REG_STATUS, expected_status(1'b0, 1'b0, 1'b0), "STATUS done cleared");

      $display("DMA REG STATUS DONE STICKY TEST COMPLETE");
    end
  endtask

  task automatic status_error_sticky_test;
    begin
      $display("----------------------------------------");
      $display("DMA REG STATUS ERROR STICKY TEST");

      dma_error = 1'b1;
      @(posedge clk);
      dma_error = 1'b0;

      repeat (2) @(posedge clk);

      axi_read_check(REG_STATUS, expected_status(1'b0, 1'b0, 1'b1), "STATUS error sticky");

      // Clear ERROR by writing STATUS[2]=1
      axi_write(REG_STATUS, 32'h0000_0004);

      axi_read_check(REG_STATUS, expected_status(1'b0, 1'b0, 1'b0), "STATUS error cleared");

      $display("DMA REG STATUS ERROR STICKY TEST COMPLETE");
    end
  endtask

  task automatic invalid_address_test;
    begin
      $display("----------------------------------------");
      $display("DMA REG INVALID ADDRESS TEST");

      axi_write(REG_INVALID, 32'hDEAD_BEEF);
      axi_read_check(REG_INVALID, 32'h0000_0000, "Invalid read returns zero");

      $display("DMA REG INVALID ADDRESS TEST COMPLETE");
    end
  endtask

  // =========================================================
  // TEST SEQUENCE
  // =========================================================

  initial begin
    error_count = 0;

    init_signals();

    wait(rst_n);
    repeat (2) @(posedge clk);

    reset_value_test();
    config_register_test();
    start_pulse_test();
    status_busy_test();
    status_done_sticky_test();
    status_error_sticky_test();
    invalid_address_test();

    #20;

    if (error_count == 0) begin
      $display("========================================");
      $display("PHASE 7 STEP 4 PASS: DMA register slave verified");
      $display("config registers, start pulse, busy/done/error status behavior passed");
      $display("========================================");
    end
    else begin
      $error("PHASE 7 STEP 4 FAILED: error_count=%0d", error_count);
    end

    #50;
    $finish;
  end

endmodule
