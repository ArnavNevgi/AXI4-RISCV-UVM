`timescale 1ns/1ps
import axi_pkg::*;

module dma_interconnect_tb;

  parameter ID_W      = 4;
  parameter ADDR_W    = 32;
  parameter DATA_W    = 32;
  parameter MAX_BURST = 16;
  parameter DEBUG     = 1;

  logic clk;
  logic rst_n;

  // ---------------------------------------------------------
  // AXI interfaces
  // ---------------------------------------------------------
  axi_if #(ID_W, ADDR_W, DATA_W) m0_if  (clk, rst_n); // unused/idle master
  axi_if #(ID_W, ADDR_W, DATA_W) dma_if (clk, rst_n); // DMA master = M1
  axi_if #(ID_W, ADDR_W, DATA_W) s0_if  (clk, rst_n); // shared slave

  // ---------------------------------------------------------
  // DMA control
  // ---------------------------------------------------------
  logic              start;
  logic [ADDR_W-1:0] src_addr;
  logic [ADDR_W-1:0] dst_addr;
  logic [15:0]       length;

  logic busy;
  logic done;
  logic error;

  int error_count;

  logic [DATA_W-1:0] mem [0:255];

  // =========================================================
  // DUT 1: DMA burst controller
  // =========================================================

  dma_controller_burst #(
    .ID_W(ID_W),
    .ADDR_W(ADDR_W),
    .DATA_W(DATA_W),
    .MAX_BURST(MAX_BURST)
  ) u_dma (
    .clk(clk),
    .rst_n(rst_n),

    .start(start),
    .src_addr(src_addr),
    .dst_addr(dst_addr),
    .length(length),

    .busy(busy),
    .done(done),
    .error(error),

    .intf(dma_if)
  );

  // =========================================================
  // DUT 2: AXI interconnect
  // m0 = idle
  // m1 = DMA
  // s0 = memory
  // =========================================================

  axi_interconnect_2m1s #(
    .ID_W(ID_W),
    .ADDR_W(ADDR_W),
    .DATA_W(DATA_W)
  ) u_ic (
    .clk(clk),
    .rst_n(rst_n),

    .m0(m0_if),
    .m1(dma_if),
    .s0(s0_if)
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
  // Keep M0 idle
  // =========================================================

  initial begin
    m0_if.aw_valid = 1'b0;
    m0_if.aw       = '0;
    m0_if.w_valid  = 1'b0;
    m0_if.w        = '0;
    m0_if.b_ready  = 1'b0;

    m0_if.ar_valid = 1'b0;
    m0_if.ar       = '0;
    m0_if.r_ready  = 1'b0;
  end

  // =========================================================
  // HANDSHAKES ON SLAVE SIDE
  // =========================================================

  logic aw_accept;
  logic w_accept;
  logic b_accept;
  logic ar_accept;
  logic r_accept;

  assign aw_accept = s0_if.aw_valid && s0_if.aw_ready;
  assign w_accept  = s0_if.w_valid  && s0_if.w_ready;
  assign b_accept  = s0_if.b_valid  && s0_if.b_ready;
  assign ar_accept = s0_if.ar_valid && s0_if.ar_ready;
  assign r_accept  = s0_if.r_valid  && s0_if.r_ready;

  // =========================================================
  // AXI MEMORY SLAVE MODEL
  // Burst read/write capable
  // =========================================================

  logic              aw_active;
  logic [ADDR_W-1:0] wr_addr_reg;
  logic [ID_W-1:0]   aw_id_reg;
  logic [7:0]        aw_len_reg;
  logic [7:0]        w_cnt;

  logic              b_pending;
  logic [2:0]        b_delay;

  logic              r_active;
  logic              r_waiting;
  logic [2:0]        r_delay;
  logic [ADDR_W-1:0] rd_addr_reg;
  logic [ID_W-1:0]   ar_id_reg;
  logic [7:0]        ar_len_reg;
  logic [7:0]        r_cnt;

  // Ready behavior
  always_comb begin
    s0_if.aw_ready = (!aw_active);
    s0_if.w_ready  = aw_active;
    s0_if.ar_ready = (!r_active && !r_waiting && !s0_if.r_valid);
  end

  // Write address/data handling
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
        wr_addr_reg <= s0_if.aw.addr;
        aw_id_reg   <= s0_if.aw.id;
        aw_len_reg  <= s0_if.aw.len;
        w_cnt       <= 0;
      end
      else if (w_accept && aw_active) begin
        mem[wr_addr_reg >> 2] <= s0_if.w.data;

        if (DEBUG) begin
          $display("MEM WRITE: beat=%0d addr=%h data=%h last=%0d @ %t",
                   w_cnt, wr_addr_reg, s0_if.w.data, s0_if.w.last, $time);
        end

        if ((w_cnt != aw_len_reg) && s0_if.w.last) begin
          $error("SLAVE ERROR: early WLAST beat=%0d aw_len=%0d", w_cnt, aw_len_reg);
          error_count++;
        end

        if ((w_cnt == aw_len_reg) && !s0_if.w.last) begin
          $error("SLAVE ERROR: missing WLAST final beat=%0d", w_cnt);
          error_count++;
        end

        if (s0_if.w.last) begin
          aw_active <= 1'b0;
        end
        else begin
          wr_addr_reg <= wr_addr_reg + 4;
          w_cnt       <= w_cnt + 1;
        end
      end
    end
  end

  // B response
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      s0_if.b_valid <= 1'b0;
      s0_if.b       <= '0;
      b_pending     <= 1'b0;
      b_delay       <= 0;
    end
    else begin
      if (w_accept && s0_if.w.last) begin
        b_pending <= 1'b1;
        b_delay   <= $urandom_range(0, 3);
      end

      if (b_pending && b_delay != 0) begin
        b_delay <= b_delay - 1;
      end

      if (b_pending && b_delay == 0) begin
        s0_if.b_valid <= 1'b1;
        s0_if.b.id    <= aw_id_reg;
        s0_if.b.resp  <= AXI_RESP_OKAY;
        b_pending     <= 1'b0;
      end

      if (b_accept) begin
        s0_if.b_valid <= 1'b0;
      end
    end
  end

  // Read burst response model
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      s0_if.r_valid <= 1'b0;
      s0_if.r       <= '0;

      r_active      <= 1'b0;
      r_waiting     <= 1'b0;
      r_delay       <= 0;
      rd_addr_reg   <= '0;
      ar_id_reg     <= '0;
      ar_len_reg    <= '0;
      r_cnt         <= '0;
    end
    else begin

      if (ar_accept) begin
        r_active    <= 1'b1;
        r_waiting   <= 1'b1;
        r_delay     <= $urandom_range(0, 3);

        rd_addr_reg <= s0_if.ar.addr;
        ar_id_reg   <= s0_if.ar.id;
        ar_len_reg  <= s0_if.ar.len;
        r_cnt       <= 0;

        s0_if.r_valid <= 1'b0;
        s0_if.r.last  <= 1'b0;
      end

      else if (r_active && r_waiting) begin
        if (r_delay != 0) begin
          r_delay <= r_delay - 1;
        end
        else begin
          s0_if.r_valid <= 1'b1;
          s0_if.r.id    <= ar_id_reg;
          s0_if.r.data  <= mem[rd_addr_reg >> 2];
          s0_if.r.resp  <= AXI_RESP_OKAY;
          s0_if.r.last  <= (r_cnt == ar_len_reg);

          r_waiting <= 1'b0;
        end
      end

      else if (r_accept) begin
        if (r_cnt == ar_len_reg) begin
          s0_if.r_valid <= 1'b0;
          s0_if.r.last  <= 1'b0;

          r_active  <= 1'b0;
          r_waiting <= 1'b0;
        end
        else begin
          s0_if.r_valid <= 1'b0;
          s0_if.r.last  <= 1'b0;

          rd_addr_reg <= rd_addr_reg + 4;
          r_cnt       <= r_cnt + 1;

          r_delay   <= $urandom_range(0, 3);
          r_waiting <= 1'b1;
        end
      end
    end
  end

  // =========================================================
  // DEBUG
  // =========================================================

  always @(posedge clk) begin
    if (DEBUG && ar_accept)
      $display("IC->MEM AR: addr=%h len=%0d @ %t", s0_if.ar.addr, s0_if.ar.len, $time);

    if (DEBUG && r_accept)
      $display("MEM->IC R : data=%h last=%0d @ %t", s0_if.r.data, s0_if.r.last, $time);

    if (DEBUG && aw_accept)
      $display("IC->MEM AW: addr=%h len=%0d @ %t", s0_if.aw.addr, s0_if.aw.len, $time);

    if (DEBUG && w_accept)
      $display("IC->MEM W : data=%h last=%0d @ %t", s0_if.w.data, s0_if.w.last, $time);

    if (DEBUG && b_accept)
      $display("MEM->IC B : accepted @ %t", $time);
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

      wait(busy);
      $display("DMA BUSY observed @ %t", $time);

      wait(done);
      $display("DMA DONE observed @ %t", $time);

      @(posedge clk);
      #1;

      if (busy !== 1'b0) begin
        $error("DMA STATUS ERROR: busy should be low after done");
        error_count++;
      end

      if (error) begin
        $error("DMA ERROR asserted");
        error_count++;
      end
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
          $display("%s PASS beat=%0d dst_idx=%0d data=%h",
                   msg, i, dst_idx, mem[dst_idx]);
        end
      end
    end
  endtask

  task automatic run_dma_test(
    input logic [ADDR_W-1:0] src,
    input logic [ADDR_W-1:0] dst,
    input int unsigned       len,
    input logic [31:0]       pattern,
    input string             msg
  );
    begin
      init_mem();

      for (int i = 0; i < len; i++) begin
        mem[(src >> 2) + i] = pattern + i;
      end

      start_dma_copy(src, dst, len[15:0]);
      check_copy(src, dst, len, msg);
    end
  endtask

  task automatic random_dma_interconnect_regression(
    input int num_tests
  );
    int unsigned src_idx;
    int unsigned dst_idx;
    int unsigned len;
    logic [31:0] pattern;

    begin
      for (int t = 0; t < num_tests; t++) begin
        len = $urandom_range(1, 64);

        src_idx = $urandom_range(0, 100 - len);
        dst_idx = $urandom_range(128, 255 - len);

        pattern = $urandom();

        $display("----------------------------------------");
        $display("RANDOM DMA+IC TEST %0d: src_idx=%0d dst_idx=%0d len=%0d pattern=%h",
                 t, src_idx, dst_idx, len, pattern);

        run_dma_test(src_idx << 2, dst_idx << 2, len, pattern, "random DMA through interconnect");
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

    init_mem();

    wait(rst_n);
    repeat (2) @(posedge clk);

    run_dma_test(32'h0000_0010, 32'h0000_0080, 4,  32'hAAAA_0000, "4-word DMA through interconnect");
    run_dma_test(32'h0000_0020, 32'h0000_00A0, 16, 32'hBBBB_0000, "16-word DMA through interconnect");
    run_dma_test(32'h0000_0030, 32'h0000_00C0, 20, 32'hCCCC_0000, "20-word DMA through interconnect");
    run_dma_test(32'h0000_0040, 32'h0000_0100, 40, 32'hDDDD_0000, "40-word DMA through interconnect");

    random_dma_interconnect_regression(10);

    #20;

    if (error_count == 0) begin
      $display("========================================");
      $display("PHASE 5 STEP 6 PASS: DMA burst master through interconnect verified");
      $display("DMA multi-burst transfers routed through 2M1S interconnect");
      $display("========================================");
    end
    else begin
      $error("PHASE 5 STEP 6 FAILED: error_count=%0d", error_count);
    end

    #50;
    $finish;
  end

endmodule