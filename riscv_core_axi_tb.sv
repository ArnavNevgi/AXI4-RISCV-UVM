`timescale 1ns/1ps
import axi_pkg::*;

module riscv_core_axi_tb;

  parameter ID_W   = 4;
  parameter ADDR_W = 32;
  parameter DATA_W = 32;
  parameter DEBUG  = 1;

  logic clk;
  logic rst_n;

  // ---------------------------------------------------------
  // Instruction memory interface
  // ---------------------------------------------------------
  logic [31:0] imem_addr;
  logic [31:0] imem_rdata;

  // ---------------------------------------------------------
  // CPU simple data-memory interface
  // ---------------------------------------------------------
  logic        dmem_valid;
  logic        dmem_write;
  logic [31:0] dmem_addr;
  logic [31:0] dmem_wdata;
  logic [31:0] dmem_rdata;
  logic        dmem_ready;

  logic [31:0] debug_pc;

  // ---------------------------------------------------------
  // AXI interface between adapter and memory model
  // ---------------------------------------------------------
  axi_if #(ID_W, ADDR_W, DATA_W) intf (clk, rst_n);

  // ---------------------------------------------------------
  // Memories
  // ---------------------------------------------------------
  logic [31:0] imem [0:31];
  logic [31:0] mem  [0:255];

  int error_count;

  // ---------------------------------------------------------
  // DUT: RISC-V core
  // ---------------------------------------------------------
  riscv_core u_core (
    .clk(clk),
    .rst_n(rst_n),

    .imem_addr(imem_addr),
    .imem_rdata(imem_rdata),

    .dmem_valid(dmem_valid),
    .dmem_write(dmem_write),
    .dmem_addr(dmem_addr),
    .dmem_wdata(dmem_wdata),
    .dmem_rdata(dmem_rdata),
    .dmem_ready(dmem_ready),

    .debug_pc(debug_pc)
  );

  // ---------------------------------------------------------
  // CPU to AXI adapter
  // ---------------------------------------------------------
  cpu_axi_adapter #(
    .ID_W(ID_W),
    .ADDR_W(ADDR_W),
    .DATA_W(DATA_W)
  ) u_adapter (
    .clk(clk),
    .rst_n(rst_n),

    .cpu_valid(dmem_valid),
    .cpu_write(dmem_write),
    .cpu_addr(dmem_addr),
    .cpu_wdata(dmem_wdata),
    .cpu_rdata(dmem_rdata),
    .cpu_ready(dmem_ready),

    .intf(intf)
  );

  // ---------------------------------------------------------
  // Clock / Reset
  // ---------------------------------------------------------
  initial clk = 0;
  always #5 clk = ~clk;

  initial begin
    rst_n = 0;
    #20;
    rst_n = 1;
  end

  // ---------------------------------------------------------
  // Instruction memory ROM
  // ---------------------------------------------------------
  always_comb begin
    imem_rdata = imem[imem_addr[6:2]];
  end

  // =========================================================
  // AXI MEMORY SLAVE MODEL
  // =========================================================

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

  assign aw_accept = intf.aw_valid && intf.aw_ready;
  assign w_accept  = intf.w_valid  && intf.w_ready && aw_seen;
  assign b_accept  = intf.b_valid  && intf.b_ready;
  assign ar_accept = intf.ar_valid && intf.ar_ready;
  assign r_accept  = intf.r_valid  && intf.r_ready;

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

    // Track accepted AW and write burst address
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
        if (intf.w.last) begin
            aw_seen <= 1'b0;
        end
        else begin
            curr_wr_addr <= curr_wr_addr + 4;
        end
        end
    end
    end

    // AXI memory write
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

  // ---------------------------------------------------------
  // Optional debug prints
  // ---------------------------------------------------------
  always @(posedge clk) begin
    if (DEBUG && ar_accept) begin
      $display("AXI AR: addr=%h @ %t", intf.ar.addr, $time);
    end

    if (DEBUG && r_accept) begin
      $display("AXI R : data=%h last=%0d @ %t",
               intf.r.data, intf.r.last, $time);
    end

    if (DEBUG && aw_accept) begin
      $display("AXI AW: addr=%h @ %t", intf.aw.addr, $time);
    end

    if (DEBUG && w_accept) begin
      $display("AXI W : data=%h last=%0d @ %t",
               intf.w.data, intf.w.last, $time);
    end

    if (DEBUG && b_accept) begin
      $display("AXI B : response accepted @ %t", $time);
    end
  end

  // ---------------------------------------------------------
  // Check helper
  // ---------------------------------------------------------
  task automatic check_mem(
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
        $display("%s passed: mem[%0d]=%h", msg, index, mem[index]);
      end
    end
  endtask

  // =========================================================
  // TEST PROGRAM
  // =========================================================

    initial begin
    error_count = 0;

    // Initialize instruction memory
    for (int i = 0; i < 32; i++) begin
        imem[i] = 32'h0000_0000;
    end

    // Initialize AXI data memory
    for (int i = 0; i < 256; i++) begin
        mem[i] = 32'h0000_0000;
    end


    // Program:
    // lw  x1, 0(x0)
    // lw  x2, 4(x0)
    // add x3, x1, x2
    // sub x4, x2, x1
    // sw  x3, 8(x0)
    // sw  x4, 12(x0)

    imem[0] = 32'h0000_2083; // lw  x1, 0(x0)
    imem[1] = 32'h0040_2103; // lw  x2, 4(x0)
    imem[2] = 32'h0020_81b3; // add x3, x1, x2
    imem[3] = 32'h4011_0233; // sub x4, x2, x1
    imem[4] = 32'h0030_2423; // sw  x3, 8(x0)
    imem[5] = 32'h0040_2623; // sw  x4, 12(x0)

    wait(rst_n);

    // Initialize AXI memory after reset because memory reset clears it.
    repeat (2) @(posedge clk);
    mem[0] = 32'd10;
    mem[1] = 32'd25;

    // 6 instructions, multicycle core + AXI delays.
    // Run enough time.
    repeat (150) @(posedge clk);

    check_mem(2, 32'd35, "ADD result through AXI");
    check_mem(3, 32'd15, "SUB result through AXI");

    if (error_count == 0) begin
      $display("========================================");
      $display("RISC-V CORE + AXI ADAPTER TB PASS");
      $display("LW/LW/ADD/SUB/SW/SW executed through AXI");
      $display("========================================");
    end
    else begin
      $error("RISC-V CORE + AXI ADAPTER TB FAILED: error_count=%0d",
             error_count);
    end

    #50;
    $finish;
  end

endmodule