`timescale 1ns/1ps
import axi_pkg::*;

module tb;

  parameter ID_W   = 4;
  parameter ADDR_W = 32;
  parameter DATA_W = 32;
  parameter DEBUG  = 1;

  logic [7:0] wr_len;
  logic [7:0] rd_len;

  // Clock / Reset
  logic clk;
  logic rst_n;

  initial clk = 0;
  always #5 clk = ~clk;

  initial begin
    rst_n = 0;
    #20;
    rst_n = 1;
  end

  // AXI Interface
  axi_if #(ID_W, ADDR_W, DATA_W) intf (clk, rst_n);

  // =========================================================
  // DUT CONNECTION
  // =========================================================

    logic wr_en;
  logic [ADDR_W-1:0] wr_addr;
  logic [DATA_W-1:0] wr_data;
  logic wr_done;

  logic rd_en;
  logic [ADDR_W-1:0] rd_addr;
  logic [DATA_W-1:0] rd_data;
  logic rd_done;
  
  // Read response state for slave memory model
  logic              r_active;
  logic [7:0]        r_len_reg;
  logic [7:0]        r_cnt_reg;
  logic [ADDR_W-1:0] r_addr_reg;
  logic [ID_W-1:0]   r_id_reg;
  
  axi_master master_inst (
    .clk(clk),
    .rst_n(rst_n),

    .wr_en(wr_en),
    .wr_addr(wr_addr),
    .wr_data(wr_data),
    .wr_len(wr_len),
    .wr_done(wr_done),

    .rd_en(rd_en),
    .rd_addr(rd_addr),
    .rd_len(rd_len),
    .rd_data(rd_data),
    .rd_done(rd_done),

    .intf(intf)
  );

   // =========================================================
  // SCOREBOARD
  // =========================================================

  logic [DATA_W-1:0] exp_mem [0:255];

  logic [ADDR_W-1:0] sb_wr_addr;
  logic [ADDR_W-1:0] sb_rd_addr;

  logic [7:0] sb_wr_cnt;
  logic [7:0] sb_rd_cnt;

  int error_count;

  // =========================================================
  // SIMPLE AXI SLAVE (MEMORY MODEL)
  // =========================================================

  logic [DATA_W-1:0] mem [0:255];
  logic [ADDR_W-1:0] saved_addr;
  logic [ADDR_W-1:0] curr_addr;

  logic aw_accept;
  logic w_accept;

  logic aw_seen;
  logic [ID_W-1:0] saved_id;

  assign aw_accept = intf.aw_valid && intf.aw_ready;
  assign w_accept  = intf.w_valid  && intf.w_ready && aw_seen;

  always_ff @(posedge clk or negedge rst_n) begin
  if (!rst_n)
    aw_seen <= 0;
  else if (aw_accept)
    aw_seen <= 1;
  else if (w_accept && intf.w.last)
    aw_seen <= 0;
end

// WRITE ADDRESS READY (random backpressure)
always_ff @(posedge clk or negedge rst_n) begin
  if (!rst_n)
    intf.aw_ready <= 0;
  else
    intf.aw_ready <= $urandom_range(0,1);
end

// WRITE DATA READY (random backpressure)
always_ff @(posedge clk or negedge rst_n) begin
  if (!rst_n)
    intf.w_ready <= 0;
  else
    intf.w_ready <= $urandom_range(0,1);
end

//   // READ ADDRESS (AR channel)
// always_ff @(posedge clk or negedge rst_n) begin
//   if (!rst_n) begin
//     intf.ar_ready <= 0;
//     r_addr <= 0;
//     r_len  <= 0;
//     r_cnt  <= 0;
//   end else begin
//     intf.ar_ready <= 1;

//     if (intf.ar_valid && intf.ar_ready) begin
//       r_addr <= intf.ar.addr;
//       r_len  <= intf.ar.len;
//       r_cnt  <= 0;
//     end
//   end
// end

// WRITE ADDRESS (AW channel)
always_ff @(posedge clk or negedge rst_n) begin
  if (!rst_n) begin
    saved_addr <= 0;
    curr_addr  <= 0;
  end else if (aw_accept) begin
    saved_addr <= intf.aw.addr;
    curr_addr  <= intf.aw.addr;   // critical for burst
  end
end

always_ff @(posedge clk) begin
  if (aw_accept)
    saved_id <= intf.aw.id;
end

// WRITE DATA INTO MEMORY (BURST SUPPORT)
always_ff @(posedge clk or negedge rst_n) begin
  if (!rst_n) begin
    for (int i = 0; i < 256; i++)
      mem[i] <= 0;
  end
  else if (w_accept) begin
    // Write each beat
    mem[curr_addr >> 2] <= intf.w.data;

    // Increment address (32-bit → 4 bytes)
    curr_addr <= curr_addr + 4;
  end
end

  // WRITE RESPONSE
logic [2:0] b_delay;
logic       b_pending;

always_ff @(posedge clk or negedge rst_n) begin
  if (!rst_n) begin
    intf.b_valid <= 0;
    b_delay      <= 0;
    b_pending    <= 0;
  end else begin

    // Detect last W beat → start delay
    if (intf.w_valid && intf.w_ready && intf.w.last) begin
      b_pending <= 1;
      b_delay   <= $urandom_range(0,3);  // random delay 0–3 cycles
    end

    // Countdown delay
    if (b_pending && b_delay != 0) begin
      b_delay <= b_delay - 1;
    end

    // Issue BVALID after delay
    if (b_pending && b_delay == 0) begin
      intf.b_valid <= 1;
      intf.b.resp  <= AXI_RESP_OKAY;
      intf.b.id    <= saved_id;
      b_pending    <= 0;
    end

    // Handshake clear
    if (intf.b_valid && intf.b_ready) begin
      intf.b_valid <= 0;
    end

  end
end

// =========================================================
// WRITE SCOREBOARD
// Captures expected memory contents from accepted W beats
// =========================================================

always_ff @(posedge clk or negedge rst_n) begin
  if (!rst_n) begin
    sb_wr_addr <= '0;
    sb_wr_cnt  <= '0;
    error_count <= 0;

    for (int i = 0; i < 256; i++) begin
      exp_mem[i] <= '0;
    end
  end
  else begin

    // Capture start address of write burst
    if (aw_accept) begin
      sb_wr_addr <= intf.aw.addr;
      sb_wr_cnt  <= 0;
    end

    // On every accepted W beat, update expected memory
    if (w_accept) begin
      if ((sb_wr_addr >> 2) > 255) begin
        $error("SCOREBOARD WRITE ADDRESS OUT OF RANGE: addr=%h index=%0d",
               sb_wr_addr, sb_wr_addr >> 2);
        error_count <= error_count + 1;
      end
      else begin
        exp_mem[sb_wr_addr >> 2] <= intf.w.data;

        $display("SB WRITE: beat=%0d addr=%h data=%h last=%0d @ %t",
                 sb_wr_cnt, sb_wr_addr, intf.w.data, intf.w.last, $time);
      end

      sb_wr_addr <= sb_wr_addr + 4;
      sb_wr_cnt  <= sb_wr_cnt + 1;
    end

  end
end

  // =========================================================
// READ ADDRESS + READ DATA RESPONSE
// =========================================================

always_ff @(posedge clk or negedge rst_n) begin
  if (!rst_n) begin
    intf.ar_ready <= 0;

    intf.r_valid  <= 0;
    intf.r.data   <= '0;
    intf.r.resp   <= AXI_RESP_OKAY;
    intf.r.id     <= '0;
    intf.r.last   <= 0;

    r_active      <= 0;
    r_len_reg     <= 0;
    r_cnt_reg     <= 0;
    r_addr_reg    <= 0;
    r_id_reg      <= 0;
  end
  else begin
    // Default randomized AR backpressure
    intf.ar_ready <= $urandom_range(0,1);

    // Accept AR only when not already serving a read burst
    if (intf.ar_valid && intf.ar_ready && !r_active) begin
      r_active   <= 1;
      r_len_reg  <= intf.ar.len;
      r_cnt_reg  <= 0;
      r_addr_reg <= intf.ar.addr;
      r_id_reg   <= intf.ar.id;

      // Launch first R beat
      intf.r_valid <= 1;
      intf.r.data  <= mem[intf.ar.addr >> 2];
      intf.r.resp  <= AXI_RESP_OKAY;
      intf.r.id    <= intf.ar.id;
      intf.r.last  <= (intf.ar.len == 0);
    end

    // R beat accepted
    else if (intf.r_valid && intf.r_ready) begin

      if (r_cnt_reg == r_len_reg) begin
        // Final beat was accepted
        intf.r_valid <= 0;
        intf.r.last  <= 0;
        r_active     <= 0;
      end
      else begin
        // Prepare next R beat
        r_cnt_reg  <= r_cnt_reg + 1;
        r_addr_reg <= r_addr_reg + 4;

        intf.r_valid <= 1;
        intf.r.data  <= mem[(r_addr_reg + 4) >> 2];
        intf.r.resp  <= AXI_RESP_OKAY;
        intf.r.id    <= r_id_reg;
        intf.r.last  <= ((r_cnt_reg + 1) == r_len_reg);
      end

    end
  end
end

// =========================================================
// READ SCOREBOARD
// Compares every accepted R beat against expected memory
// =========================================================

always_ff @(posedge clk or negedge rst_n) begin
  if (!rst_n) begin
    sb_rd_addr <= '0;
    sb_rd_cnt  <= '0;
  end
  else begin

    // Capture start address of read burst
    if (intf.ar_valid && intf.ar_ready) begin
      sb_rd_addr <= intf.ar.addr;
      sb_rd_cnt  <= 0;
    end

    // Check every accepted R beat
    if (intf.r_valid && intf.r_ready) begin

      if ((sb_rd_addr >> 2) > 255) begin
        $error("SCOREBOARD READ ADDRESS OUT OF RANGE: addr=%h index=%0d",
               sb_rd_addr, sb_rd_addr >> 2);
        error_count <= error_count + 1;
      end
      else if (intf.r.data !== exp_mem[sb_rd_addr >> 2]) begin
        $error("READ MISMATCH: beat=%0d addr=%h expected=%h got=%h last=%0d @ %t",
               sb_rd_cnt,
               sb_rd_addr,
               exp_mem[sb_rd_addr >> 2],
               intf.r.data,
               intf.r.last,
               $time);

        error_count <= error_count + 1;
      end
      else begin
        $display("SB READ PASS: beat=%0d addr=%h data=%h last=%0d @ %t",
                 sb_rd_cnt,
                 sb_rd_addr,
                 intf.r.data,
                 intf.r.last,
                 $time);
      end

      sb_rd_addr <= sb_rd_addr + 4;
      sb_rd_cnt  <= sb_rd_cnt + 1;
    end

  end
end

always @(posedge clk) begin
  if (DEBUG) begin
    if (aw_accept)
      $display("AW accepted: %h @ %t", intf.aw.addr, $time);

    if (w_accept)
      $display("W accepted: %h @ %t", intf.w.data, $time);

    if (intf.b_valid)
      $display("B response sent @ %t", $time);
  end
end

always @(posedge clk) begin
  if (intf.w_valid)
    $display("T=%0t WVALID=%0d WREADY=%0d DATA=%h BEAT=%0d",
      $time,
      intf.w_valid,
      intf.w_ready,
      intf.w.data,
      master_inst.beat_cnt   // 👈 FIX
    );
end

  // =========================================================
  // TEST SEQUENCE
  // =========================================================

task automatic axi_write_read_check(
  input logic [ADDR_W-1:0] addr,
  input logic [DATA_W-1:0] data,
  input logic [7:0]        len
);

  begin
    @(posedge clk);
    wr_en   <= 1;
    wr_addr <= addr;
    wr_data <= data;
    wr_len  <= len;

    @(posedge clk);
    wr_en <= 0;

    wait(wr_done);
    $display("WRITE DONE addr=%h data=%h @ %t", addr, data, $time);

    @(posedge clk);
    rd_en   <= 1;
    rd_addr <= addr;
    rd_len  <= len;

    @(posedge clk);
    rd_en <= 0;

    wait(rd_done);
    $display("READ DONE addr=%h data=%h @ %t", addr, rd_data, $time);
  end
endtask


  initial begin
    wr_en   = 0;
    rd_en   = 0;
    wr_addr = 0;
    wr_data = 0;
    rd_addr = 0;
    wr_len = 0;
    rd_len = 0;

    wait(rst_n);

    // axi_write_read_check(32'h0000_0010, 32'hAAAA_AAAA);
    // axi_write_read_check(32'h0000_0040, 32'hBBBB_BBBB);
    // axi_write_read_check(32'h0000_0080, 32'hCCCC_CCCC);
    // axi_write_read_check(32'h0000_00C0, 32'hDDDD_DDDD);

    axi_write_read_check(32'h0000_0010, 32'hAAAA_AAAA, 8'd0); // 1 beat
    axi_write_read_check(32'h0000_0040, 32'hBBBB_BBBB, 8'd1); // 2 beats
    axi_write_read_check(32'h0000_0080, 32'hCCCC_CCCC, 8'd3); // 4 beats
    axi_write_read_check(32'h0000_00C0, 32'hDDDD_DDDD, 8'd7); // 8 beats

    #20;

    #20;

if (error_count == 0) begin
  $display("========================================");
  $display("PHASE 1 PASS");
  $display("AXI4 burst write/read test completed");
  $display("Variable burst lengths passed");
  $display("Backpressure handling passed");
  $display("Scoreboard matched all read data");
  $display("========================================");
end
else begin
  $error("PHASE 1 FAILED: error_count=%0d", error_count);
end

#50;
$finish;
end
endmodule
