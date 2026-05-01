`timescale 1ns/1ps
import axi_pkg::*;

module cpu_axi_adapter_tb;

  parameter ID_W   = 4;
  parameter ADDR_W = 32;
  parameter DATA_W = 32;
  parameter DEBUG  = 1;

  logic clk;
  logic rst_n;

  // CPU-side signals
  logic              cpu_valid;
  logic              cpu_write;
  logic [ADDR_W-1:0] cpu_addr;
  logic [DATA_W-1:0] cpu_wdata;
  logic [DATA_W-1:0] cpu_rdata;
  logic              cpu_ready;

  // AXI interface
  axi_if #(ID_W, ADDR_W, DATA_W) intf (clk, rst_n);

  // Simple AXI memory
  logic [DATA_W-1:0] mem [0:255];

  // AXI slave helper state
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

  assign aw_accept = intf.aw_valid && intf.aw_ready;
  assign w_accept  = intf.w_valid  && intf.w_ready && aw_seen;
  assign b_accept  = intf.b_valid  && intf.b_ready;
  assign ar_accept = intf.ar_valid && intf.ar_ready;
  assign r_accept  = intf.r_valid  && intf.r_ready;

  cpu_axi_adapter #(
    .ID_W(ID_W),
    .ADDR_W(ADDR_W),
    .DATA_W(DATA_W)
  ) dut (
    .clk(clk),
    .rst_n(rst_n),

    .cpu_valid(cpu_valid),
    .cpu_write(cpu_write),
    .cpu_addr(cpu_addr),
    .cpu_wdata(cpu_wdata),
    .cpu_rdata(cpu_rdata),
    .cpu_ready(cpu_ready),

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
  // AXI SLAVE MEMORY MODEL
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

  // Track accepted AW
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
      else if (w_accept && intf.w.last) begin
        aw_seen <= 1'b0;
      end
    end
  end

  // Memory write
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (int i = 0; i < 256; i++) begin
        mem[i] <= '0;
      end
    end
    else begin
      if (w_accept) begin
        mem[curr_wr_addr >> 2] <= intf.w.data;

        if (DEBUG) begin
          $display("AXI MEM WRITE: addr=%h data=%h last=%0d @ %t",
                   curr_wr_addr, intf.w.data, intf.w.last, $time);
        end

        curr_wr_addr <= curr_wr_addr + 4;
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

  // Random ARREADY, block new AR while read response is active
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
  // CPU-SIDE TASKS
  // =========================================================

  task automatic cpu_write_word(
    input logic [ADDR_W-1:0] addr,
    input logic [DATA_W-1:0] data
  );
    begin
      @(posedge clk);
      cpu_valid <= 1'b1;
      cpu_write <= 1'b1;
      cpu_addr  <= addr;
      cpu_wdata <= data;

      @(posedge clk);
      cpu_valid <= 1'b0;

      wait(cpu_ready);
      $display("CPU WRITE DONE: addr=%h data=%h @ %t", addr, data, $time);
    end
  endtask

  task automatic cpu_read_check(
    input logic [ADDR_W-1:0] addr,
    input logic [DATA_W-1:0] expected
  );
    begin
      @(posedge clk);
      cpu_valid <= 1'b1;
      cpu_write <= 1'b0;
      cpu_addr  <= addr;
      cpu_wdata <= '0;

      @(posedge clk);
      cpu_valid <= 1'b0;

      wait(cpu_ready);
      $display("CPU READ DONE: addr=%h data=%h @ %t",
               addr, cpu_rdata, $time);

      if (cpu_rdata !== expected) begin
        $error("CPU READ MISMATCH: addr=%h expected=%h got=%h",
               addr, expected, cpu_rdata);
        error_count++;
      end
      else begin
        $display("CPU READ PASS: addr=%h data=%h", addr, cpu_rdata);
      end
    end
  endtask

  // =========================================================
  // TEST SEQUENCE
  // =========================================================

  initial begin
    error_count = 0;

    cpu_valid = 1'b0;
    cpu_write = 1'b0;
    cpu_addr  = '0;
    cpu_wdata = '0;

    wait(rst_n);
    repeat (2) @(posedge clk);

    cpu_write_word(32'h0000_0010, 32'hAAAA_AAAA);
    cpu_read_check (32'h0000_0010, 32'hAAAA_AAAA);

    cpu_write_word(32'h0000_0014, 32'h1234_5678);
    cpu_read_check (32'h0000_0014, 32'h1234_5678);

    cpu_write_word(32'h0000_0020, 32'hDEAD_BEEF);
    cpu_read_check (32'h0000_0020, 32'hDEAD_BEEF);

    #20;

    if (error_count == 0) begin
      $display("========================================");
      $display("CPU AXI ADAPTER TB PASS");
      $display("single-beat CPU read/write over AXI verified");
      $display("========================================");
    end
    else begin
      $error("CPU AXI ADAPTER TB FAILED: error_count=%0d", error_count);
    end

    #50;
    $finish;
  end

endmodule