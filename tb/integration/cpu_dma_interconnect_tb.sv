`timescale 1ns/1ps
import axi_pkg::*;

module cpu_dma_interconnect_tb;

  parameter ID_W      = 4;
  parameter ADDR_W    = 32;
  parameter DATA_W    = 32;
  parameter MAX_BURST = 16;
  parameter DEBUG     = 1;

  logic clk;
  logic rst_n;

  // ---------------------------------------------------------
  // CPU instruction memory interface
  // ---------------------------------------------------------
  logic [31:0] imem_addr;
  logic [31:0] imem_rdata;
  logic [31:0] debug_pc;

  logic [31:0] imem [0:31];

  // ---------------------------------------------------------
  // CPU simple data memory interface
  // ---------------------------------------------------------
  logic        cpu_dmem_valid;
  logic        cpu_dmem_write;
  logic [31:0] cpu_dmem_addr;
  logic [31:0] cpu_dmem_wdata;
  logic [31:0] cpu_dmem_rdata;
  logic        cpu_dmem_ready;

  // ---------------------------------------------------------
  // DMA control
  // ---------------------------------------------------------
  logic              dma_start;
  logic [ADDR_W-1:0] dma_src_addr;
  logic [ADDR_W-1:0] dma_dst_addr;
  logic [15:0]       dma_length;

  logic dma_busy;
  logic dma_done;
  logic dma_error;
  logic dma_done_seen;

  // ---------------------------------------------------------
  // AXI interfaces
  // ---------------------------------------------------------
  axi_if #(ID_W, ADDR_W, DATA_W) cpu_axi_if (clk, rst_n); // M0
  axi_if #(ID_W, ADDR_W, DATA_W) dma_axi_if (clk, rst_n); // M1
  axi_if #(ID_W, ADDR_W, DATA_W) s0_if      (clk, rst_n); // shared memory

  // Shared memory
  logic [DATA_W-1:0] mem [0:255];

  int error_count;

  // =========================================================
  // DUT 1: RISC-V core
  // =========================================================

  riscv_core u_core (
    .clk(clk),
    .rst_n(rst_n),

    .imem_addr(imem_addr),
    .imem_rdata(imem_rdata),

    .dmem_valid(cpu_dmem_valid),
    .dmem_write(cpu_dmem_write),
    .dmem_addr(cpu_dmem_addr),
    .dmem_wdata(cpu_dmem_wdata),
    .dmem_rdata(cpu_dmem_rdata),
    .dmem_ready(cpu_dmem_ready),

    .debug_pc(debug_pc)
  );

  // =========================================================
  // DUT 2: CPU to AXI adapter = M0
  // =========================================================

  cpu_axi_adapter #(
    .ID_W(ID_W),
    .ADDR_W(ADDR_W),
    .DATA_W(DATA_W)
  ) u_cpu_adapter (
    .clk(clk),
    .rst_n(rst_n),

    .cpu_valid(cpu_dmem_valid),
    .cpu_write(cpu_dmem_write),
    .cpu_addr(cpu_dmem_addr),
    .cpu_wdata(cpu_dmem_wdata),
    .cpu_rdata(cpu_dmem_rdata),
    .cpu_ready(cpu_dmem_ready),

    .intf(cpu_axi_if)
  );

  // =========================================================
  // DUT 3: DMA burst controller = M1
  // =========================================================

  dma_controller_burst #(
    .ID_W(ID_W),
    .ADDR_W(ADDR_W),
    .DATA_W(DATA_W),
    .MAX_BURST(MAX_BURST)
  ) u_dma (
    .clk(clk),
    .rst_n(rst_n),

    .start(dma_start),
    .src_addr(dma_src_addr),
    .dst_addr(dma_dst_addr),
    .length(dma_length),

    .busy(dma_busy),
    .done(dma_done),
    .error(dma_error),

    .intf(dma_axi_if)
  );

  // =========================================================
  // DUT 4: AXI interconnect
  // M0 = CPU adapter
  // M1 = DMA
  // S0 = shared memory
  // =========================================================

  axi_interconnect_2m1s #(
    .ID_W(ID_W),
    .ADDR_W(ADDR_W),
    .DATA_W(DATA_W)
  ) u_ic (
    .clk(clk),
    .rst_n(rst_n),

    .m0(cpu_axi_if),
    .m1(dma_axi_if),
    .s0(s0_if)
  );

  // =========================================================
  // CLOCK / RESET
  // =========================================================

  initial clk = 0;
  always #5 clk = ~clk;

  initial begin
  rst_n = 1'b0;
  end

  // =========================================================
  // INSTRUCTION MEMORY
  // =========================================================

  always_comb begin
  if (imem_addr < 32'd24)
    imem_rdata = imem[imem_addr[6:2]];
  else
    imem_rdata = 32'h0000_0013; // NOP: addi x0, x0, 0
end

  // =========================================================
  // AXI MEMORY SLAVE MODEL
  // Burst-capable shared memory
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

  task automatic init_all;
    begin
      for (int i = 0; i < 32; i++) begin
        imem[i] = 32'h0000_0000;
      end

      for (int i = 0; i < 256; i++) begin
        mem[i] = 32'h0000_0000;
      end

      dma_start    = 1'b0;
      dma_src_addr = '0;
      dma_dst_addr = '0;
      dma_length   = '0;
      dma_done_seen = 1'b0;
    end
  endtask

  task automatic load_cpu_program;
    begin
      // Program:
      // lw  x1, 0(x0)      // x1 = mem[0] = 10
      // lw  x2, 4(x0)      // x2 = mem[1] = 25
      // add x3, x1, x2     // x3 = 35
      // sub x4, x2, x1     // x4 = 15
      // sw  x3, 8(x0)      // mem[2] = 35
      // sw  x4, 12(x0)     // mem[3] = 15

      imem[0] = 32'h0000_2083; // lw  x1, 0(x0)
      imem[1] = 32'h0040_2103; // lw  x2, 4(x0)
      imem[2] = 32'h0020_81b3; // add x3, x1, x2
      imem[3] = 32'h4011_0233; // sub x4, x2, x1
      imem[4] = 32'h0030_2423; // sw  x3, 8(x0)
      imem[5] = 32'h0040_2623; // sw  x4, 12(x0)
    end
  endtask

  task automatic check_mem_word(
    input int unsigned index,
    input logic [31:0] expected,
    input string msg
  );
    begin
      if (mem[index] !== expected) begin
        $error("%s failed: mem[%0d] expected=%h got=%h",
               msg, index, expected, mem[index]);
        error_count++;
      end
      else begin
        $display("%s PASS: mem[%0d]=%h", msg, index, mem[index]);
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
      dma_src_addr <= src;
      dma_dst_addr <= dst;
      dma_length   <= len;
      dma_start    <= 1'b1;

      @(posedge clk);
      dma_start <= 1'b0;

      wait(dma_busy);
      $display("DMA BUSY observed @ %t", $time);

      wait(dma_done);
      $display("DMA DONE observed @ %t", $time);

      @(posedge clk);
      #1;

      if (dma_busy !== 1'b0) begin
        $error("DMA STATUS ERROR: dma_busy should be low after done");
        error_count++;
      end

      if (dma_error) begin
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

  task automatic pulse_reset;
  begin
    rst_n = 1'b0;
    repeat (3) @(posedge clk);
    rst_n = 1'b1;
    repeat (2) @(posedge clk);
  end
endtask

  task automatic cpu_dma_overlap_test;
  begin
    $display("----------------------------------------");
    $display("CPU + DMA OVERLAP ARBITRATION TEST");

    init_all();
    load_cpu_program();

    // CPU input data
    mem[0] = 32'd10;
    mem[1] = 32'd25;

    // DMA source data: mem[16:31]
    for (int i = 0; i < 16; i++) begin
      mem[16 + i] = 32'hDADA_0000 + i;
    end

    pulse_reset();

    // Let CPU begin memory traffic, then start DMA.
    repeat (6) @(posedge clk);

    dma_done_seen = 1'b0;

    @(posedge clk);
    dma_src_addr <= 32'h0000_0040; // mem[16]
    dma_dst_addr <= 32'h0000_0180; // mem[96]
    dma_length   <= 16'd16;
    dma_start    <= 1'b1;

    @(posedge clk);
    dma_start <= 1'b0;

    $display("DMA started during CPU execution @ %t", $time);

    fork
      begin
        wait(mem[2] == 32'd35 && mem[3] == 32'd15);
        $display("CPU completed during overlap test @ %t", $time);
      end

      begin
        wait(dma_done);
        dma_done_seen = 1'b1;
        $display("DMA completed during overlap test @ %t", $time);
      end
    join

    @(posedge clk);
    #1;

    if (!dma_done_seen) begin
      $error("OVERLAP TEST ERROR: DMA done was not observed");
      error_count++;
    end

    if (dma_error) begin
      $error("OVERLAP TEST ERROR: DMA error asserted");
      error_count++;
    end

    check_mem_word(2, 32'd35, "Overlap CPU ADD result");
    check_mem_word(3, 32'd15, "Overlap CPU SUB result");

    check_copy(32'h0000_0040, 32'h0000_0180, 16, "Overlap DMA copy");

    $display("CPU + DMA OVERLAP ARBITRATION TEST COMPLETE");
  end
endtask

  // =========================================================
  // TEST SEQUENCE
  // =========================================================

  initial begin
  error_count = 0;

  init_all();
  load_cpu_program();

  pulse_reset();

  // Initial data for CPU program
  mem[0] = 32'd10;
  mem[1] = 32'd25;

  // Step 7: CPU completes, then DMA copies CPU results
  wait(mem[2] == 32'd35 && mem[3] == 32'd15);

  $display("CPU PROGRAM COMPLETED THROUGH INTERCONNECT");

  check_mem_word(2, 32'd35, "CPU ADD result");
  check_mem_word(3, 32'd15, "CPU SUB result");

  start_dma_copy(32'h0000_0008, 32'h0000_0100, 16'd2);

  check_copy(32'h0000_0008, 32'h0000_0100, 2, "DMA copy of CPU results");

  // Step 8: overlap CPU and DMA traffic
  cpu_dma_overlap_test();

  #20;

  if (error_count == 0) begin
    $display("========================================");
    $display("PHASE 5 STEP 8 PASS: CPU + DMA arbitration stress verified");
    $display("CPU and DMA completed correctly while sharing AXI interconnect");
    $display("========================================");
  end
  else begin
    $error("PHASE 5 STEP 8 FAILED: error_count=%0d", error_count);
  end

  #50;
  $finish;
end

endmodule
