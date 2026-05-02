`timescale 1ns/1ps
import axi_pkg::*;

module dma_controller_burst_tb;

  parameter ID_W      = 4;
  parameter ADDR_W    = 32;
  parameter DATA_W    = 32;
  parameter MAX_BURST = 16;
  parameter DEBUG     = 1;

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

  int error_count;

  // =========================================================
  // DUT
  // =========================================================

  dma_controller_burst #(
    .ID_W(ID_W),
    .ADDR_W(ADDR_W),
    .DATA_W(DATA_W),
    .MAX_BURST(MAX_BURST)
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
  // HANDSHAKES
  // =========================================================

  logic aw_accept;
  logic w_accept;
  logic b_accept;
  logic ar_accept;
  logic r_accept;

  assign aw_accept = intf.aw_valid && intf.aw_ready;
  assign w_accept  = intf.w_valid  && intf.w_ready;
  assign b_accept  = intf.b_valid  && intf.b_ready;
  assign ar_accept = intf.ar_valid && intf.ar_ready;
  assign r_accept  = intf.r_valid  && intf.r_ready;

  // =========================================================
  // AXI MEMORY SLAVE MODEL
  // =========================================================

  logic              aw_active;
  logic [ADDR_W-1:0] wr_addr_reg;
  logic [ID_W-1:0]   aw_id_reg;
  logic [7:0]        aw_len_reg;
  logic [7:0]        w_cnt;

  logic [2:0]        b_delay;
  logic              b_pending;

  logic              r_active;
  logic              r_waiting;
  logic [2:0]        r_delay;
  logic [ADDR_W-1:0] r_addr_reg;
  logic [ID_W-1:0]   ar_id_reg;
  logic [7:0]        ar_len_reg;
  logic [7:0]        r_cnt;

  function automatic logic [7:0] expected_burst_len(input logic [15:0] rem);
  begin
    if (rem > 16)
      expected_burst_len = 8'd15;       // 16 beats -> LEN=15
    else
      expected_burst_len = rem[7:0] - 8'd1;
  end
endfunction

  // ---------------- AWREADY random backpressure ----------------
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      intf.aw_ready <= 1'b0;
    else if (!aw_active)
      intf.aw_ready <= $urandom_range(0, 1);
    else
      intf.aw_ready <= 1'b0;
  end

  // ---------------- WREADY random backpressure ----------------
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      intf.w_ready <= 1'b0;
    else
      intf.w_ready <= $urandom_range(0, 1);
  end

  // ---------------- Write address/data handling ----------------
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      aw_active   <= 1'b0;
      wr_addr_reg <= '0;
      aw_id_reg   <= '0;
      aw_len_reg  <= '0;
      w_cnt       <= '0;
    end
    else begin
      if (aw_accept) begin
        aw_active   <= 1'b1;
        wr_addr_reg <= intf.aw.addr;
        aw_id_reg   <= intf.aw.id;
        aw_len_reg  <= intf.aw.len;
        w_cnt       <= 0;
      end
      else if (w_accept && aw_active) begin
        mem[wr_addr_reg >> 2] <= intf.w.data;

        if (DEBUG) begin
          $display("AXI MEM WRITE: beat=%0d addr=%h data=%h last=%0d @ %t",
                   w_cnt, wr_addr_reg, intf.w.data, intf.w.last, $time);
        end

        if ((w_cnt != aw_len_reg) && intf.w.last) begin
          $error("SLAVE ERROR: early WLAST beat=%0d aw_len=%0d", w_cnt, aw_len_reg);
          error_count++;
        end

        if ((w_cnt == aw_len_reg) && !intf.w.last) begin
          $error("SLAVE ERROR: missing WLAST on final beat=%0d", w_cnt);
          error_count++;
        end

        if (intf.w.last) begin
          aw_active <= 1'b0;
        end
        else begin
          wr_addr_reg <= wr_addr_reg + 4;
          w_cnt       <= w_cnt + 1;
        end
      end
    end
  end

  // ---------------- B response with delay ----------------
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      intf.b_valid <= 1'b0;
      intf.b       <= '0;
      b_pending    <= 1'b0;
      b_delay      <= 0;
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
        intf.b.id    <= aw_id_reg;
        intf.b.resp  <= AXI_RESP_OKAY;
        b_pending    <= 1'b0;
      end

      if (b_accept) begin
        intf.b_valid <= 1'b0;
      end
    end
  end

  // ---------------- ARREADY random backpressure ----------------
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      intf.ar_ready <= 1'b0;
    else if (!r_active && !r_waiting && !intf.r_valid)
      intf.ar_ready <= $urandom_range(0, 1);
    else
      intf.ar_ready <= 1'b0;
  end

  // ---------------- Read burst response with gaps ----------------
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      intf.r_valid <= 1'b0;
      intf.r       <= '0;

      r_active     <= 1'b0;
      r_waiting    <= 1'b0;
      r_delay      <= 0;
      r_addr_reg   <= '0;
      ar_id_reg    <= '0;
      ar_len_reg   <= '0;
      r_cnt        <= '0;
    end
    else begin
      if (ar_accept) begin
        r_active   <= 1'b1;
        r_waiting  <= 1'b1;
        r_delay    <= $urandom_range(0, 3);
        r_addr_reg <= intf.ar.addr;
        ar_id_reg  <= intf.ar.id;
        ar_len_reg <= intf.ar.len;
        r_cnt      <= 0;

        intf.r_valid <= 1'b0;
      end

      else if (r_active && r_waiting) begin
        if (r_delay != 0) begin
          r_delay <= r_delay - 1;
        end
        else begin
          intf.r_valid <= 1'b1;
          intf.r.id    <= ar_id_reg;
          intf.r.data  <= mem[r_addr_reg >> 2];
          intf.r.resp  <= AXI_RESP_OKAY;
          intf.r.last  <= (r_cnt == ar_len_reg);

          r_waiting <= 1'b0;
        end
      end

      else if (r_accept) begin
        if (intf.r.last) begin
          intf.r_valid <= 1'b0;
          intf.r.last  <= 1'b0;
          r_active     <= 1'b0;
          r_waiting    <= 1'b0;
        end
        else begin
          intf.r_valid <= 1'b0;
          intf.r.last  <= 1'b0;

          r_addr_reg <= r_addr_reg + 4;
          r_cnt      <= r_cnt + 1;
          r_delay    <= $urandom_range(0, 3);
          r_waiting  <= 1'b1;
        end
      end
    end
  end

// =========================================================
// DMA BURST PROTOCOL CHECKER
// Checks each accepted AR/AW burst independently
// =========================================================

logic [7:0] chk_ar_len;
logic [7:0] chk_aw_len;
logic [7:0] chk_r_cnt;
logic [7:0] chk_w_cnt;

logic       chk_read_active;
logic       chk_write_active;

always @(posedge clk or negedge rst_n) begin
  if (!rst_n) begin
    chk_ar_len       <= 0;
    chk_aw_len       <= 0;
    chk_r_cnt        <= 0;
    chk_w_cnt        <= 0;
    chk_read_active  <= 0;
    chk_write_active <= 0;
  end
  else begin

    // ---------------- READ BURST TRACKING ----------------
    if (ar_accept) begin
      chk_read_active <= 1'b1;
      chk_ar_len      <= intf.ar.len;
      chk_r_cnt       <= 0;

      if (intf.ar.size !== 3'b010) begin
        $error("DMA BURST CHECK ERROR: ARSIZE expected 010 got=%0b @ %t",
               intf.ar.size, $time);
        error_count++;
      end

      if (intf.ar.burst !== AXI_BURST_INCR) begin
        $error("DMA BURST CHECK ERROR: ARBURST expected INCR @ %t", $time);
        error_count++;
      end
    end

    if (r_accept && chk_read_active) begin
      if ((chk_r_cnt != chk_ar_len) && intf.r.last) begin
        $error("DMA BURST CHECK ERROR: early RLAST beat=%0d ar_len=%0d @ %t",
               chk_r_cnt, chk_ar_len, $time);
        error_count++;
      end

      if ((chk_r_cnt == chk_ar_len) && !intf.r.last) begin
        $error("DMA BURST CHECK ERROR: missing RLAST final beat=%0d @ %t",
               chk_r_cnt, $time);
        error_count++;
      end

      if (intf.r.last) begin
        chk_read_active <= 1'b0;
        chk_r_cnt       <= 0;
      end
      else begin
        chk_r_cnt <= chk_r_cnt + 1;
      end
    end

    // ---------------- WRITE BURST TRACKING ----------------
    if (aw_accept) begin
      chk_write_active <= 1'b1;
      chk_aw_len       <= intf.aw.len;
      chk_w_cnt        <= 0;

      if (intf.aw.size !== 3'b010) begin
        $error("DMA BURST CHECK ERROR: AWSIZE expected 010 got=%0b @ %t",
               intf.aw.size, $time);
        error_count++;
      end

      if (intf.aw.burst !== AXI_BURST_INCR) begin
        $error("DMA BURST CHECK ERROR: AWBURST expected INCR @ %t", $time);
        error_count++;
      end
    end

    if (w_accept && chk_write_active) begin
      if ((chk_w_cnt != chk_aw_len) && intf.w.last) begin
        $error("DMA BURST CHECK ERROR: early WLAST beat=%0d aw_len=%0d @ %t",
               chk_w_cnt, chk_aw_len, $time);
        error_count++;
      end

      if ((chk_w_cnt == chk_aw_len) && !intf.w.last) begin
        $error("DMA BURST CHECK ERROR: missing WLAST final beat=%0d @ %t",
               chk_w_cnt, $time);
        error_count++;
      end

      if (intf.w.last) begin
        chk_write_active <= 1'b0;
        chk_w_cnt        <= 0;
      end
      else begin
        chk_w_cnt <= chk_w_cnt + 1;
      end
    end

  end
end

  // =========================================================
  // DEBUG
  // =========================================================

  always @(posedge clk) begin
    if (DEBUG && ar_accept)
      $display("AXI AR BURST: addr=%h len=%0d @ %t", intf.ar.addr, intf.ar.len, $time);

    if (DEBUG && r_accept)
      $display("AXI R  BURST: data=%h last=%0d @ %t", intf.r.data, intf.r.last, $time);

    if (DEBUG && aw_accept)
      $display("AXI AW BURST: addr=%h len=%0d @ %t", intf.aw.addr, intf.aw.len, $time);

    if (DEBUG && w_accept)
      $display("AXI W  BURST: data=%h last=%0d @ %t", intf.w.data, intf.w.last, $time);

    if (DEBUG && b_accept)
      $display("AXI B  BURST: response accepted @ %t", $time);
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

  task automatic start_dma_burst_copy(
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
      // DMA should become busy for non-zero transfers
        if (len != 0) begin
        wait(busy);
        $display("DMA BUSY observed for len=%0d @ %t", len, $time);
        end

      wait(done);
    // DONE should occur while transfer completes
        $display("DMA DONE observed @ %t", $time);

        @(posedge clk);
        #1;

        // DONE should be one-cycle pulse
        if (done !== 1'b0) begin
        $error("DMA STATUS ERROR: done should be one-cycle pulse");
        error_count++;
        end

        // BUSY should be low after done
        if (busy !== 1'b0) begin
        $error("DMA STATUS ERROR: busy should be low after done");
        error_count++;
        end

      $display("DMA BURST DONE: src=%h dst=%h length=%0d @ %t",
               src, dst, len, $time);

      if (error) begin
        $error("DMA BURST ERROR asserted");
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

  task automatic zero_length_status_test;
  begin
    init_mem();

    mem[4]  = 32'hAAAA_AAAA;
    mem[32] = 32'h5555_5555;

    @(posedge clk);
    src_addr <= 32'h0000_0010;
    dst_addr <= 32'h0000_0080;
    length   <= 16'd0;
    start    <= 1'b1;

    @(posedge clk);
    start <= 1'b0;

    wait(done);
    $display("ZERO LENGTH DONE observed @ %t", $time);

    @(posedge clk);
    #1;

    if (done !== 1'b0) begin
    $error("ZERO LENGTH STATUS ERROR: done should be one-cycle pulse");
    error_count++;
    end
    
    if (busy !== 1'b0) begin
      $error("ZERO LENGTH STATUS ERROR: busy should remain low");
      error_count++;
    end

    if (mem[4] !== 32'hAAAA_AAAA) begin
      $error("ZERO LENGTH ERROR: source modified");
      error_count++;
    end

    if (mem[32] !== 32'h5555_5555) begin
      $error("ZERO LENGTH ERROR: destination modified");
      error_count++;
    end

    $display("ZERO LENGTH STATUS TEST PASS");
  end
endtask

  task automatic run_burst_test(
    input logic [ADDR_W-1:0] src,
    input logic [ADDR_W-1:0] dst,
    input int unsigned       len,
    input logic [31:0]       base_pattern,
    input string             msg
  );
    begin
      init_mem();

      for (int i = 0; i < len; i++) begin
        mem[(src >> 2) + i] = base_pattern + i;
      end

      start_dma_burst_copy(src, dst, len[15:0]);
      check_copy(src, dst, len, msg);
    end
  endtask

  task automatic random_burst_dma_regression(
  input int num_tests
);
  int unsigned src_idx;
  int unsigned dst_idx;
  int unsigned len;
  logic [31:0] pattern_base;

  begin
    for (int t = 0; t < num_tests; t++) begin
      init_mem();

      // Burst DMA supports 1 to 16 words for now
      len = $urandom_range(1, 64);

      // Keep source and destination non-overlapping.
      // Source in lower half, destination in upper half.
        src_idx = $urandom_range(0, 100 - len);
        dst_idx = $urandom_range(128, 255 - len);

      pattern_base = $urandom();

      for (int i = 0; i < len; i++) begin
        mem[src_idx + i] = pattern_base + i;
      end

      $display("----------------------------------------");
      $display("RANDOM BURST DMA TEST %0d: src_idx=%0d dst_idx=%0d len=%0d pattern=%h",
               t, src_idx, dst_idx, len, pattern_base);

      start_dma_burst_copy(src_idx << 2, dst_idx << 2, len[15:0]);
      check_copy          (src_idx << 2, dst_idx << 2, len, "random burst DMA copy");
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

    zero_length_status_test(); 

    run_burst_test(32'h0000_0010, 32'h0000_0080, 1,  32'hAAAA_AAAA, "1-word burst DMA");
    run_burst_test(32'h0000_0020, 32'h0000_00A0, 4,  32'hBBBB_0000, "4-word burst DMA");
    run_burst_test(32'h0000_0040, 32'h0000_00C0, 8,  32'hCCCC_0000, "8-word burst DMA");
    run_burst_test(32'h0000_0060, 32'h0000_0100, 16, 32'hDDDD_0000, "16-word burst DMA");
    // Multi-burst transfer tests
    run_burst_test(32'h0000_0010, 32'h0000_0080, 17, 32'hE111_0000, "17-word multi-burst DMA");
    run_burst_test(32'h0000_0020, 32'h0000_00A0, 20, 32'hE222_0000, "20-word multi-burst DMA");
    run_burst_test(32'h0000_0030, 32'h0000_00C0, 32, 32'hE333_0000, "32-word multi-burst DMA");
    run_burst_test(32'h0000_0040, 32'h0000_0100, 40, 32'hE444_0000, "40-word multi-burst DMA");
    // ---------------- Randomized burst DMA regression ----------------
    random_burst_dma_regression(20);

    #20;

        if (error_count == 0) begin
        $display("========================================");
        $display("PHASE 4 STEP 9 PASS: DMA status/control behavior verified");
        $display("multi-burst copy, randomized regression, busy/done/zero-length status passed");
        $display("========================================");
        end
        else begin
        $error("PHASE 4 STEP 9 FAILED: error_count=%0d", error_count);
        end

    #50;
    $finish;
  end

endmodule