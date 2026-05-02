`timescale 1ns/1ps
import axi_pkg::*;

module dma_controller_tb;

  parameter ID_W   = 4;
  parameter ADDR_W = 32;
  parameter DATA_W = 32;
  parameter DEBUG  = 1;

  logic clk;
  logic rst_n;

  logic              start;
  logic [ADDR_W-1:0] src_addr;
  logic [ADDR_W-1:0] dst_addr;
  logic [15:0]       length;

  logic busy;
  logic done;
  logic error;

  axi_if #(ID_W, ADDR_W, DATA_W) intf (clk, rst_n);

  logic [DATA_W-1:0] mem [0:255];

  logic aw_seen;
  logic [ADDR_W-1:0] curr_wr_addr;
  logic [ID_W-1:0]   saved_aw_id;

  logic [2:0] b_delay;
  logic       b_pending;

  logic r_active;
  logic [ADDR_W-1:0] r_addr_reg;
  logic [ID_W-1:0]   r_id_reg;
  logic [2:0]        r_delay;

  logic aw_accept;
  logic w_accept;
  logic b_accept;
  logic ar_accept;
  logic r_accept;

  int error_count;

  // =========================================================
  // DMA AXI PROTOCOL CHECKER
  // =========================================================

  logic [15:0] dma_read_count;
  logic [15:0] dma_write_count;

  assign aw_accept = intf.aw_valid && intf.aw_ready;
  assign w_accept  = intf.w_valid  && intf.w_ready && aw_seen;
  assign b_accept  = intf.b_valid  && intf.b_ready;
  assign ar_accept = intf.ar_valid && intf.ar_ready;
  assign r_accept  = intf.r_valid  && intf.r_ready;

// =========================================================
// DMA AXI PROTOCOL CHECKER
// Checks that DMA emits single-beat AXI transactions correctly
// =========================================================

always @(posedge clk or negedge rst_n) begin
  if (!rst_n) begin
    dma_read_count  <= 0;
    dma_write_count <= 0;
  end
  else begin

    if (start) begin
      dma_read_count  <= 0;
      dma_write_count <= 0;
    end

    if (ar_accept) begin
      if (intf.ar.len !== 8'd0) begin
        $error("DMA CHECKER ERROR: ARLEN must be 0 for single-beat DMA. got=%0d @ %t",
               intf.ar.len, $time);
        error_count <= error_count + 1;
      end

      if (intf.ar.size !== 3'b010) begin
        $error("DMA CHECKER ERROR: ARSIZE must be 3'b010 for 32-bit word. got=%0b @ %t",
               intf.ar.size, $time);
        error_count <= error_count + 1;
      end

      dma_read_count <= dma_read_count + 1;
    end

    if (aw_accept) begin
      if (intf.aw.len !== 8'd0) begin
        $error("DMA CHECKER ERROR: AWLEN must be 0 for single-beat DMA. got=%0d @ %t",
               intf.aw.len, $time);
        error_count <= error_count + 1;
      end

      if (intf.aw.size !== 3'b010) begin
        $error("DMA CHECKER ERROR: AWSIZE must be 3'b010 for 32-bit word. got=%0b @ %t",
               intf.aw.size, $time);
        error_count <= error_count + 1;
      end

      dma_write_count <= dma_write_count + 1;
    end

    if (w_accept) begin
      if (intf.w.last !== 1'b1) begin
        $error("DMA CHECKER ERROR: WLAST must be 1 for single-beat DMA write @ %t",
               $time);
        error_count <= error_count + 1;
      end
    end

  end
end

  dma_controller #(
    .ID_W(ID_W),
    .ADDR_W(ADDR_W),
    .DATA_W(DATA_W)
  ) dut (
    .clk(clk),
    .rst_n(rst_n),

    .start(start),
    .src_addr(src_addr),
    .dst_addr(dst_addr),
    .length(length),

    .busy(busy),
    .done(done),
    .error(error),

    .intf(intf)
  );

  initial clk = 0;
  always #5 clk = ~clk;

  initial begin
    rst_n = 0;
    #20;
    rst_n = 1;
  end

  // =========================================================
  // AXI MEMORY SLAVE MODEL
  // =========================================================

  // Random AWREADY
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      intf.aw_ready <= 1'b0;
    else
      intf.aw_ready <= $urandom_range(0, 1);
  end

  // Random WREADY
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      intf.w_ready <= 1'b0;
    else
      intf.w_ready <= $urandom_range(0, 1);
  end

  // Track accepted AW and write address
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      aw_seen      <= 1'b0;
      curr_wr_addr <= '0;
      saved_aw_id  <= '0;
    end
    else begin
      if (aw_accept) begin
        aw_seen      <= 1'b1;
        curr_wr_addr <= intf.aw.addr;
        saved_aw_id  <= intf.aw.id;
      end
      else if (w_accept) begin
        if (intf.w.last)
          aw_seen <= 1'b0;
        else
          curr_wr_addr <= curr_wr_addr + 4;
      end
    end
  end

  // Memory write
  always @(posedge clk) begin
    if (rst_n) begin
      if (w_accept) begin
        mem[curr_wr_addr >> 2] <= intf.w.data;

        if (DEBUG) begin
          $display("AXI MEM WRITE: addr=%h data=%h last=%0d @ %t",
                   curr_wr_addr, intf.w.data, intf.w.last, $time);
        end
      end
    end
  end

  // Delayed B response
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      intf.b_valid <= 1'b0;
      intf.b       <= '0;
      b_delay      <= 0;
      b_pending    <= 1'b0;
    end
    else begin
      if (w_accept && intf.w.last) begin
        b_pending <= 1'b1;
        b_delay   <= $urandom_range(0, 3);
      end

      if (b_pending && b_delay != 0) begin
        b_delay <= b_delay - 1;
      end

      if (b_pending && b_delay == 0) begin
        intf.b_valid <= 1'b1;
        intf.b.id    <= saved_aw_id;
        intf.b.resp  <= AXI_RESP_OKAY;
        b_pending    <= 1'b0;
      end

      if (b_accept) begin
        intf.b_valid <= 1'b0;
      end
    end
  end

  // Random ARREADY
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      intf.ar_ready <= 1'b0;
    else if (!r_active && !intf.r_valid)
      intf.ar_ready <= $urandom_range(0, 1);
    else
      intf.ar_ready <= 1'b0;
  end

  // Delayed single-beat read response
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      intf.r_valid <= 1'b0;
      intf.r       <= '0;
      r_active     <= 1'b0;
      r_addr_reg   <= '0;
      r_id_reg     <= '0;
      r_delay      <= 0;
    end
    else begin
      if (ar_accept) begin
        r_active   <= 1'b1;
        r_addr_reg <= intf.ar.addr;
        r_id_reg   <= intf.ar.id;
        r_delay    <= $urandom_range(0, 3);

        intf.r_valid <= 1'b0;
      end
      else if (r_active && !intf.r_valid) begin
        if (r_delay != 0) begin
          r_delay <= r_delay - 1;
        end
        else begin
          intf.r_valid <= 1'b1;
          intf.r.id    <= r_id_reg;
          intf.r.data  <= mem[r_addr_reg >> 2];
          intf.r.resp  <= AXI_RESP_OKAY;
          intf.r.last  <= 1'b1;
        end
      end
      else if (r_accept) begin
        intf.r_valid <= 1'b0;
        intf.r.last  <= 1'b0;
        r_active     <= 1'b0;
      end
    end
  end

  // =========================================================
  // DEBUG
  // =========================================================

  always @(posedge clk) begin
    if (DEBUG && ar_accept)
      $display("AXI AR: addr=%h @ %t", intf.ar.addr, $time);

    if (DEBUG && r_accept)
      $display("AXI R : data=%h last=%0d @ %t",
               intf.r.data, intf.r.last, $time);

    if (DEBUG && aw_accept)
      $display("AXI AW: addr=%h @ %t", intf.aw.addr, $time);

    if (DEBUG && w_accept)
      $display("AXI W : data=%h last=%0d @ %t",
               intf.w.data, intf.w.last, $time);

    if (DEBUG && b_accept)
      $display("AXI B : response accepted @ %t", $time);
  end

  // =========================================================
  // TASKS
  // =========================================================

  task automatic init_mem;
    begin
      for (int i = 0; i < 256; i++) begin
        mem[i] = 32'h0000_0000;
      end
    end
  endtask

  task automatic check_zero_length_copy;
  logic [DATA_W-1:0] before_src;
  logic [DATA_W-1:0] before_dst;
  begin
    init_mem();

    mem[4]  = 32'hAAAA_AAAA;
    mem[32] = 32'h5555_5555;

    before_src = mem[4];
    before_dst = mem[32];

    @(posedge clk);
    src_addr <= 32'h0000_0010;
    dst_addr <= 32'h0000_0080;
    length   <= 16'd0;
    start    <= 1'b1;

    @(posedge clk);
    start <= 1'b0;

    wait(done);

    if (busy !== 1'b0) begin
      $error("ZERO LENGTH ERROR: busy should be 0 after zero-length done");
      error_count++;
    end

    if (mem[4] !== before_src) begin
      $error("ZERO LENGTH ERROR: source memory changed. expected=%h got=%h",
             before_src, mem[4]);
      error_count++;
    end

    if (mem[32] !== before_dst) begin
      $error("ZERO LENGTH ERROR: destination memory changed. expected=%h got=%h",
             before_dst, mem[32]);
      error_count++;
    end

    $display("ZERO LENGTH COPY PASS");
    @(posedge clk);
  end
endtask

  task automatic start_dma_copy(
    input logic [ADDR_W-1:0] src,
    input logic [ADDR_W-1:0] dst,
    input logic [15:0]       len
  );
    begin
      @(posedge clk);
      src_addr <= src;
      dst_addr <= dst;
      length   <= len;
      start    <= 1'b1;

      @(posedge clk);
      start <= 1'b0;

      wait(done);
      $display("DMA DONE: src=%h dst=%h length=%0d @ %t",
               src, dst, len, $time);

      if (len != 0) begin
      if (dma_read_count !== len) begin
        $error("DMA READ COUNT ERROR: expected=%0d got=%0d", len, dma_read_count);
        error_count++;
      end

      if (dma_write_count !== len) begin
        $error("DMA WRITE COUNT ERROR: expected=%0d got=%0d", len, dma_write_count);
        error_count++;
      end
    end         

      if (error) begin
        $error("DMA ERROR asserted");
        error_count++;
      end

      @(posedge clk);
    end
  endtask

  task automatic check_copy(
    input logic [ADDR_W-1:0] src,
    input logic [ADDR_W-1:0] dst,
    input int unsigned       len,
    input string             msg
  );
    int unsigned src_idx;
    int unsigned dst_idx;
    begin
      for (int i = 0; i < len; i++) begin
        src_idx = (src >> 2) + i;
        dst_idx = (dst >> 2) + i;

        if (mem[dst_idx] !== mem[src_idx]) begin
          $error("%s failed beat=%0d src_idx=%0d dst_idx=%0d expected=%h got=%h",
                 msg, i, src_idx, dst_idx, mem[src_idx], mem[dst_idx]);
          error_count++;
        end
        else begin
          $display("%s pass beat=%0d dst_idx=%0d data=%h",
                   msg, i, dst_idx, mem[dst_idx]);
        end
      end
    end
  endtask

  task automatic random_dma_regression(
  input int num_tests
);
  int unsigned src_idx;
  int unsigned dst_idx;
  int unsigned len;
  logic [31:0] pattern_base;

  begin
    for (int t = 0; t < num_tests; t++) begin
      init_mem();

      // Random length: 1 to 16 words
      len = $urandom_range(1, 16);

      // Keep regions inside mem[0:255]
      // Use source in lower half, destination in upper half to avoid overlap.
      src_idx = $urandom_range(0, 120 - len);
      dst_idx = $urandom_range(128, 255 - len);

      pattern_base = $urandom();

      // Fill source region with known pattern
      for (int i = 0; i < len; i++) begin
        mem[src_idx + i] = pattern_base + i;
      end

      $display("----------------------------------------");
      $display("RANDOM DMA TEST %0d: src_idx=%0d dst_idx=%0d len=%0d pattern=%h",
               t, src_idx, dst_idx, len, pattern_base);

      start_dma_copy(src_idx << 2, dst_idx << 2, len[15:0]);
      check_copy    (src_idx << 2, dst_idx << 2, len, "random DMA copy");
    end
  end
endtask

task automatic start_during_busy_test;
  begin
    init_mem();

    // Source data for intended transfer
    for (int i = 0; i < 8; i++) begin
      mem[4 + i] = 32'hFACE_0000 + i;
    end

    // Source data for the fake second transfer
    for (int i = 0; i < 4; i++) begin
      mem[64 + i] = 32'hBAD0_0000 + i;
    end

    $display("----------------------------------------");
    $display("START-DURING-BUSY TEST");

    // Start real DMA transfer: src=0x10, dst=0x80, len=8
    @(posedge clk);
    src_addr <= 32'h0000_0010;
    dst_addr <= 32'h0000_0080;
    length   <= 16'd8;
    start    <= 1'b1;

    @(posedge clk);
    start <= 1'b0;

    // Wait until DMA is busy
    wait(busy);

    // While DMA is busy, try to start a fake transfer.
    // Correct behavior: DMA must ignore this.
    repeat (3) @(posedge clk);

    src_addr <= 32'h0000_0100;  // mem[64]
    dst_addr <= 32'h0000_00C0;  // mem[48]
    length   <= 16'd4;
    start    <= 1'b1;

    @(posedge clk);
    start <= 1'b0;

    $display("Injected start while busy @ %t", $time);

    // Wait for original DMA to complete
    wait(done);
    @(posedge clk);

    // Original transfer must complete correctly
    check_copy(32'h0000_0010, 32'h0000_0080, 8, "start-during-busy original copy");

    // Fake transfer destination should remain unchanged
    for (int i = 0; i < 4; i++) begin
      if (mem[48 + i] !== 32'h0000_0000) begin
        $error("START-DURING-BUSY ERROR: fake transfer modified mem[%0d]=%h",
               48 + i, mem[48 + i]);
        error_count++;
      end
      else begin
        $display("START-DURING-BUSY PASS: fake dst mem[%0d] unchanged", 48 + i);
      end
    end
  end
endtask

  // =========================================================
  // TEST SEQUENCE
  // =========================================================

  initial begin
    error_count = 0;

    start    = 1'b0;
    src_addr = '0;
    dst_addr = '0;
    length   = '0;

    wait(rst_n);
    repeat (2) @(posedge clk);
    check_zero_length_copy();

    
    // ---------------- TEST 1: 1-word copy ----------------
    init_mem();
    mem[4] = 32'hAAAA_AAAA;

    start_dma_copy(32'h0000_0010, 32'h0000_0080, 16'd1);
    check_copy    (32'h0000_0010, 32'h0000_0080, 1, "1-word copy");

    // ---------------- TEST 2: 4-word copy ----------------
    init_mem();
    mem[4] = 32'h1111_1111;
    mem[5] = 32'h2222_2222;
    mem[6] = 32'h3333_3333;
    mem[7] = 32'h4444_4444;

    start_dma_copy(32'h0000_0010, 32'h0000_0080, 16'd4);
    check_copy    (32'h0000_0010, 32'h0000_0080, 4, "4-word copy");

    // ---------------- TEST 3: 8-word copy ----------------
    init_mem();
    for (int i = 0; i < 8; i++) begin
      mem[8 + i] = 32'hCAFE_0000 + i;
    end

    start_dma_copy(32'h0000_0020, 32'h0000_00A0, 16'd8);
    check_copy    (32'h0000_0020, 32'h0000_00A0, 8, "8-word copy");

    // ---------------- TEST 4: Randomized DMA regression ----------------
    random_dma_regression(20);

    // ---------------- TEST 5: Start while busy ----------------
    start_during_busy_test();

    #20;

    if (error_count == 0) begin
      $display("========================================");
      $display("PHASE 4 STEP 5 PASS: DMA busy/start protection verified");
      $display("zero-length, fixed-length, random, and busy-start tests passed");
      $display("========================================");
    end
    else begin
      $error("PHASE 4 STEP 5 FAILED: error_count=%0d", error_count);
    end

    #50;
    $finish;
  end

endmodule