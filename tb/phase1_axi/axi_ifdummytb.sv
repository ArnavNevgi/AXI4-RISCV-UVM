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
  logic [2:0] r_delay;
  logic       r_waiting;
  
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
// WRITE BURST PROTOCOL CHECKER
// =========================================================

logic        chk_wr_active;
logic [7:0]  chk_aw_len;
logic [7:0]  chk_w_cnt;
// =========================================================
// READ BURST PROTOCOL CHECKER
// =========================================================

logic        chk_rd_active;
logic [7:0]  chk_ar_len;
logic [7:0]  chk_r_cnt;

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

  logic ar_accept;
  logic r_accept;
  logic b_accept;

  assign ar_accept = intf.ar_valid && intf.ar_ready;
  assign r_accept  = intf.r_valid  && intf.r_ready;
  assign b_accept  = intf.b_valid  && intf.b_ready;
  assign aw_accept = intf.aw_valid && intf.aw_ready;
  assign w_accept  = intf.w_valid  && intf.w_ready && aw_seen;

  // =========================================================
// WRITE BURST PROTOCOL CHECKER
// Checks AWLEN/WLAST/W beat count consistency
// =========================================================

always_ff @(posedge clk or negedge rst_n) begin
  if (!rst_n) begin
    chk_wr_active <= 0;
    chk_aw_len    <= 0;
    chk_w_cnt     <= 0;
  end
  else begin

    // AW accepted: start tracking one write burst
    if (aw_accept) begin
      if (chk_wr_active) begin
        $error("WRITE CHECKER ERROR: New AW accepted before previous W burst completed @ %t", $time);
        error_count <= error_count + 1;
      end

      chk_wr_active <= 1;
      chk_aw_len    <= intf.aw.len;
      chk_w_cnt     <= 0;
    end

    // Raw W handshake seen before any AW
    if (intf.w_valid && intf.w_ready && !chk_wr_active) begin
      $error("WRITE CHECKER ERROR: W beat accepted before AW burst active @ %t", $time);
      error_count <= error_count + 1;
    end

    // Valid W beat for active burst
    if (intf.w_valid && intf.w_ready && chk_wr_active) begin

      // Early WLAST check
      if ((chk_w_cnt != chk_aw_len) && intf.w.last) begin
        $error("WRITE CHECKER ERROR: Early WLAST. beat=%0d expected_last_beat=%0d @ %t",
               chk_w_cnt, chk_aw_len, $time);
        error_count <= error_count + 1;
      end

      // Missing WLAST check
      if ((chk_w_cnt == chk_aw_len) && !intf.w.last) begin
        $error("WRITE CHECKER ERROR: Missing WLAST on final beat. beat=%0d @ %t",
               chk_w_cnt, $time);
        error_count <= error_count + 1;
      end

      // Beat beyond AWLEN check
      if (chk_w_cnt > chk_aw_len) begin
        $error("WRITE CHECKER ERROR: Too many W beats. beat=%0d aw_len=%0d @ %t",
               chk_w_cnt, chk_aw_len, $time);
        error_count <= error_count + 1;
      end

      // End burst after final accepted beat
      if (chk_w_cnt == chk_aw_len) begin
        chk_wr_active <= 0;
        chk_w_cnt     <= 0;
      end
      else begin
        chk_w_cnt <= chk_w_cnt + 1;
      end
    end

  end
end

// =========================================================
// READ BURST PROTOCOL CHECKER
// Checks ARLEN/RLAST/R beat count consistency
// =========================================================

always_ff @(posedge clk or negedge rst_n) begin
  if (!rst_n) begin
    chk_rd_active <= 0;
    chk_ar_len    <= 0;
    chk_r_cnt     <= 0;
  end
  else begin

    // AR accepted: start tracking one read burst
    if (ar_accept) begin
      if (chk_rd_active) begin
        $error("READ CHECKER ERROR: New AR accepted before previous R burst completed @ %t", $time);
        error_count <= error_count + 1;
      end

      chk_rd_active <= 1;
      chk_ar_len    <= intf.ar.len;
      chk_r_cnt     <= 0;
    end

    // Raw R handshake seen before any AR burst is active
    if (r_accept && !chk_rd_active) begin
      $error("READ CHECKER ERROR: R beat accepted before AR burst active @ %t", $time);
      error_count <= error_count + 1;
    end

    // Valid R beat for active burst
    if (r_accept && chk_rd_active) begin

      // Early RLAST check
      if ((chk_r_cnt != chk_ar_len) && intf.r.last) begin
        $error("READ CHECKER ERROR: Early RLAST. beat=%0d expected_last_beat=%0d @ %t",
               chk_r_cnt, chk_ar_len, $time);
        error_count <= error_count + 1;
      end

      // Missing RLAST check
      if ((chk_r_cnt == chk_ar_len) && !intf.r.last) begin
        $error("READ CHECKER ERROR: Missing RLAST on final beat. beat=%0d @ %t",
               chk_r_cnt, $time);
        error_count <= error_count + 1;
      end

      // Beat beyond ARLEN check
      if (chk_r_cnt > chk_ar_len) begin
        $error("READ CHECKER ERROR: Too many R beats. beat=%0d ar_len=%0d @ %t",
               chk_r_cnt, chk_ar_len, $time);
        error_count <= error_count + 1;
      end

      // End burst after final accepted beat
      if (chk_r_cnt == chk_ar_len) begin
        chk_rd_active <= 0;
        chk_r_cnt     <= 0;
      end
      else begin
        chk_r_cnt <= chk_r_cnt + 1;
      end
    end

  end
end


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
    if (b_accept) begin
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
// READ ADDRESS + READ DATA RESPONSE WITH RANDOM RVALID DELAY
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

    r_delay       <= 0;
    r_waiting     <= 0;
  end
  else begin
    // Random AR backpressure.
    // Only accept new AR when not already serving a read burst.
    if (!r_active && !r_waiting)
      intf.ar_ready <= $urandom_range(0,1);
    else
      intf.ar_ready <= 0;

    // ---------------- AR HANDSHAKE ----------------
    if (ar_accept && !r_active && !r_waiting) begin
      r_active   <= 1;
      r_waiting  <= 1;
      r_delay    <= $urandom_range(0,3);

      r_len_reg  <= intf.ar.len;
      r_cnt_reg  <= 0;
      r_addr_reg <= intf.ar.addr;
      r_id_reg   <= intf.ar.id;

      intf.r_valid <= 0;
      intf.r.last  <= 0;
    end

    // ---------------- WAIT BEFORE NEXT R BEAT ----------------
    else if (r_active && r_waiting) begin
      if (r_delay != 0) begin
        r_delay <= r_delay - 1;
      end
      else begin
        // Launch current R beat
        intf.r_valid <= 1;
        intf.r.data  <= mem[r_addr_reg >> 2];
        intf.r.resp  <= AXI_RESP_OKAY;
        intf.r.id    <= r_id_reg;
        intf.r.last  <= (r_cnt_reg == r_len_reg);

        r_waiting <= 0;
      end
    end

    // ---------------- R HANDSHAKE ----------------
    else if (r_accept) begin

      if (r_cnt_reg == r_len_reg) begin
        // Final beat accepted
        intf.r_valid <= 0;
        intf.r.last  <= 0;

        r_active  <= 0;
        r_waiting <= 0;
      end
      else begin
        // Current beat accepted. Prepare delayed next beat.
        intf.r_valid <= 0;
        intf.r.last  <= 0;

        r_cnt_reg  <= r_cnt_reg + 1;
        r_addr_reg <= r_addr_reg + 4;

        r_delay   <= $urandom_range(0,3);
        r_waiting <= 1;
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
    if (ar_accept) begin
      sb_rd_addr <= intf.ar.addr;
      sb_rd_cnt  <= 0;
    end

    // Check every accepted R beat
    if (r_accept) begin

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

    axi_write_read_check(32'h0000_0010, 32'hAAAA_AAAA, 8'd0);
axi_write_read_check(32'h0000_0040, 32'hBBBB_BBBB, 8'd1);
axi_write_read_check(32'h0000_0080, 32'hCCCC_CCCC, 8'd3);
axi_write_read_check(32'h0000_00C0, 32'hDDDD_DDDD, 8'd7);

// Edge cases
axi_write_read_check(32'h0000_0000, 32'h1111_1111, 8'd0);
axi_write_read_check(32'h0000_0020, 32'h2222_2222, 8'd1);
axi_write_read_check(32'h0000_0060, 32'h3333_3333, 8'd3);
axi_write_read_check(32'h0000_00A0, 32'h4444_4444, 8'd7);
axi_write_read_check(32'h0000_0100, 32'h5555_5555, 8'd15);

#20;

for (int t = 0; t < 20; t++) begin
  logic [ADDR_W-1:0] rand_addr;
  logic [DATA_W-1:0] rand_data;
  logic [7:0]        rand_len;
  int unsigned       max_start_index;

  rand_len = $urandom_range(0, 15);

  // Keep burst inside mem[0:255]
  max_start_index = 255 - rand_len;

  rand_addr = ($urandom_range(0, max_start_index) << 2);
  rand_data = $urandom();

  axi_write_read_check(rand_addr, rand_data, rand_len);
end

if (error_count == 0) begin
  $display("========================================");
  $display("PHASE 2 STEP 7 PASS: Randomized burst regression completed");
  $display("========================================");
end
else begin
  $error("PHASE 2 STEP 7 FAILED: error_count=%0d", error_count);
end

#50;
$finish;
  end 
  endmodule
