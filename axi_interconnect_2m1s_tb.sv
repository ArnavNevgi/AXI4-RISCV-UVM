`timescale 1ns/1ps
import axi_pkg::*;

module axi_interconnect_2m1s_tb;

  parameter ID_W   = 4;
  parameter ADDR_W = 32;
  parameter DATA_W = 32;
  parameter DEBUG  = 1;

  logic clk;
  logic rst_n;

  axi_if #(ID_W, ADDR_W, DATA_W) m0_if (clk, rst_n);
  axi_if #(ID_W, ADDR_W, DATA_W) m1_if (clk, rst_n);
  axi_if #(ID_W, ADDR_W, DATA_W) s0_if (clk, rst_n);

  int error_count;

  logic [DATA_W-1:0] mem [0:255];

  // =========================================================
  // DUT: 2-master / 1-slave AXI interconnect
  // =========================================================

  axi_interconnect_2m1s #(
    .ID_W(ID_W),
    .ADDR_W(ADDR_W),
    .DATA_W(DATA_W)
  ) dut (
    .clk(clk),
    .rst_n(rst_n),

    .m0(m0_if),
    .m1(m1_if),
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
  // SIMPLE AXI MEMORY SLAVE
  // =========================================================

  logic              aw_active;
  logic [ADDR_W-1:0] wr_addr_reg;
  logic [ID_W-1:0]   aw_id_reg;

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

    // Write address tracking
    always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        aw_active   <= 1'b0;
        wr_addr_reg <= '0;
        aw_id_reg   <= '0;
    end
    else begin
        if (aw_accept) begin
        aw_active   <= 1'b1;
        wr_addr_reg <= s0_if.aw.addr;
        aw_id_reg   <= s0_if.aw.id;
        end
        else if (w_accept) begin
        if (s0_if.w.last) begin
            aw_active <= 1'b0;
        end
        else begin
            wr_addr_reg <= wr_addr_reg + 4;
        end
        end
    end
end

  // Memory write
    always @(posedge clk) begin
    if (rst_n) begin
        if (w_accept) begin
        mem[wr_addr_reg >> 2] <= s0_if.w.data;

        if (DEBUG) begin
            $display("SLAVE WRITE: addr=%h data=%h last=%0d @ %t",
                    wr_addr_reg, s0_if.w.data, s0_if.w.last, $time);
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
        b_delay   <= $urandom_range(0, 2);
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

    // Capture AR
    if (ar_accept) begin
      r_active    <= 1'b1;
      r_waiting   <= 1'b1;
      r_delay     <= $urandom_range(0, 2);

      rd_addr_reg <= s0_if.ar.addr;
      ar_id_reg   <= s0_if.ar.id;
      ar_len_reg  <= s0_if.ar.len;
      r_cnt       <= 0;

      s0_if.r_valid <= 1'b0;
      s0_if.r.last  <= 1'b0;
    end

    // Wait before launching each R beat
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

    // R handshake accepted
    else if (r_accept) begin
      if (r_cnt == ar_len_reg) begin
        // Final beat accepted
        s0_if.r_valid <= 1'b0;
        s0_if.r.last  <= 1'b0;

        r_active  <= 1'b0;
        r_waiting <= 1'b0;
      end
      else begin
        // Current beat accepted; prepare next delayed beat
        s0_if.r_valid <= 1'b0;
        s0_if.r.last  <= 1'b0;

        rd_addr_reg <= rd_addr_reg + 4;
        r_cnt       <= r_cnt + 1;

        r_delay   <= $urandom_range(0, 2);
        r_waiting <= 1'b1;
      end
    end

  end
end

  // =========================================================
  // MASTER INIT
  // =========================================================

  task automatic init_master_signals;
    begin
      m0_if.aw_valid = 1'b0;
      m0_if.aw       = '0;
      m0_if.w_valid  = 1'b0;
      m0_if.w        = '0;
      m0_if.b_ready  = 1'b0;
      m0_if.ar_valid = 1'b0;
      m0_if.ar       = '0;
      m0_if.r_ready  = 1'b0;

      m1_if.aw_valid = 1'b0;
      m1_if.aw       = '0;
      m1_if.w_valid  = 1'b0;
      m1_if.w        = '0;
      m1_if.b_ready  = 1'b0;
      m1_if.ar_valid = 1'b0;
      m1_if.ar       = '0;
      m1_if.r_ready  = 1'b0;
    end
  endtask

  task automatic init_mem;
    begin
      for (int i = 0; i < 256; i++) begin
        mem[i] = 32'h0000_0000;
      end
    end
  endtask

  // =========================================================
  // MASTER 0 TASKS
  // =========================================================

  task automatic m0_write(
    input logic [ADDR_W-1:0] addr,
    input logic [DATA_W-1:0] data
  );
    begin
      @(posedge clk);
      m0_if.aw_valid <= 1'b1;
      m0_if.aw.id    <= 4'd0;
      m0_if.aw.addr  <= addr;
      m0_if.aw.len   <= 8'd0;
      m0_if.aw.size  <= 3'b010;
      m0_if.aw.burst <= AXI_BURST_INCR;

      do @(posedge clk); while (!m0_if.aw_ready);
      m0_if.aw_valid <= 1'b0;

      @(posedge clk);
      m0_if.w_valid <= 1'b1;
      m0_if.w.data  <= data;
      m0_if.w.strb  <= '1;
      m0_if.w.last  <= 1'b1;

      do @(posedge clk); while (!m0_if.w_ready);
      m0_if.w_valid <= 1'b0;
      m0_if.w.last  <= 1'b0;

        @(posedge clk);
        m0_if.b_ready <= 1'b1;

        // Wait for B response on an accepting edge
        do @(posedge clk); while (!m0_if.b_valid);

        // Keep BREADY high until interconnect write ownership clears
        do begin
        @(posedge clk);
        #1;
        end while (dut.write_active);

        m0_if.b_ready <= 1'b0;

      $display("M0 WRITE DONE: addr=%h data=%h @ %t", addr, data, $time);
    end
  endtask

  task automatic m0_read_check(
    input logic [ADDR_W-1:0] addr,
    input logic [DATA_W-1:0] expected
  );
    logic [DATA_W-1:0] got;
    begin
      @(posedge clk);
      m0_if.ar_valid <= 1'b1;
      m0_if.ar.id    <= 4'd0;
      m0_if.ar.addr  <= addr;
      m0_if.ar.len   <= 8'd0;
      m0_if.ar.size  <= 3'b010;
      m0_if.ar.burst <= AXI_BURST_INCR;

      do @(posedge clk); while (!m0_if.ar_ready);
      m0_if.ar_valid <= 1'b0;

      @(posedge clk);
      m0_if.r_ready <= 1'b1;

      do @(posedge clk); while (!m0_if.r_valid);
      got = m0_if.r.data;
      m0_if.r_ready <= 1'b0;

      if (got !== expected) begin
        $error("M0 READ MISMATCH: addr=%h expected=%h got=%h",
               addr, expected, got);
        error_count++;
      end
      else begin
        $display("M0 READ PASS: addr=%h data=%h", addr, got);
      end
    end
  endtask

    task automatic m0_burst_write(
  input logic [ADDR_W-1:0] addr,
  input logic [DATA_W-1:0] base_data,
  input logic [7:0]        len
);
  begin
    // AW
    @(posedge clk);
    m0_if.aw_valid <= 1'b1;
    m0_if.aw.id    <= 4'd0;
    m0_if.aw.addr  <= addr;
    m0_if.aw.len   <= len;
    m0_if.aw.size  <= 3'b010;
    m0_if.aw.burst <= AXI_BURST_INCR;

    do @(posedge clk); while (!m0_if.aw_ready);

    m0_if.aw_valid <= 1'b0;

    // W beats, one clean accepted beat at a time
    for (int i = 0; i <= len; i++) begin
      @(posedge clk);
      m0_if.w_valid <= 1'b1;
      m0_if.w.data  <= base_data + i;
      m0_if.w.strb  <= '1;
      m0_if.w.last  <= (i == len);

      do @(posedge clk); while (!m0_if.w_ready);

      // Deassert after this beat is accepted to avoid duplicate handshakes
      m0_if.w_valid <= 1'b0;
      m0_if.w.last  <= 1'b0;

      // Bubble cycle before next beat
      @(posedge clk);
      #1;
    end

    @(posedge clk);
    m0_if.b_ready <= 1'b1;

    // Wait for B response on an accepting edge
    do @(posedge clk); while (!m0_if.b_valid);

    // Keep BREADY high until interconnect write ownership clears
    do begin
      @(posedge clk);
      #1;
    end while (dut.write_active);

    m0_if.b_ready <= 1'b0;

    $display("M0 BURST WRITE DONE: addr=%h len=%0d base=%h @ %t",
             addr, len, base_data, $time);
  end
endtask

    task automatic m0_burst_read_check(
  input logic [ADDR_W-1:0] addr,
  input logic [DATA_W-1:0] expected_base,
  input logic [7:0]        len
);
  logic [DATA_W-1:0] got;
  logic              got_last;

  begin
    @(posedge clk);
    m0_if.ar_valid <= 1'b1;
    m0_if.ar.id    <= 4'd0;
    m0_if.ar.addr  <= addr;
    m0_if.ar.len   <= len;
    m0_if.ar.size  <= 3'b010;
    m0_if.ar.burst <= AXI_BURST_INCR;

    do @(posedge clk); while (!m0_if.ar_ready);

    m0_if.ar_valid <= 1'b0;

    @(posedge clk);
    m0_if.r_ready <= 1'b1;

    for (int i = 0; i <= len; i++) begin

      // Wait for an accepted R beat
      do @(posedge clk); while (!m0_if.r_valid);

      got      = m0_if.r.data;
      got_last = m0_if.r.last;

      if (got !== (expected_base + i)) begin
        $error("M0 BURST READ MISMATCH: beat=%0d addr=%h expected=%h got=%h",
               i, addr + (i * 4), expected_base + i, got);
        error_count++;
      end
      else begin
        $display("M0 BURST READ PASS: beat=%0d data=%h", i, got);
      end

      if ((i != len) && got_last) begin
        $error("M0 BURST READ ERROR: early RLAST beat=%0d len=%0d", i, len);
        error_count++;
      end

      if ((i == len) && !got_last) begin
        $error("M0 BURST READ ERROR: missing RLAST on final beat=%0d", i);
        error_count++;
      end

      // Let accepted beat clear before checking next beat
      @(posedge clk);
      #1;
    end

    m0_if.r_ready <= 1'b0;

    $display("M0 BURST READ CHECK DONE: addr=%h len=%0d", addr, len);
  end
endtask

  // =========================================================
  // MASTER 1 TASKS
  // =========================================================

  task automatic m1_write(
    input logic [ADDR_W-1:0] addr,
    input logic [DATA_W-1:0] data
  );
    begin
      @(posedge clk);
      m1_if.aw_valid <= 1'b1;
      m1_if.aw.id    <= 4'd1;
      m1_if.aw.addr  <= addr;
      m1_if.aw.len   <= 8'd0;
      m1_if.aw.size  <= 3'b010;
      m1_if.aw.burst <= AXI_BURST_INCR;

      do @(posedge clk); while (!m1_if.aw_ready);
      m1_if.aw_valid <= 1'b0;

      @(posedge clk);
      m1_if.w_valid <= 1'b1;
      m1_if.w.data  <= data;
      m1_if.w.strb  <= '1;
      m1_if.w.last  <= 1'b1;

      do @(posedge clk); while (!m1_if.w_ready);
      m1_if.w_valid <= 1'b0;
      m1_if.w.last  <= 1'b0;

      @(posedge clk);
        m1_if.b_ready <= 1'b1;

        // Wait for B response on an accepting edge
        do @(posedge clk); while (!m1_if.b_valid);

        // Keep BREADY high until interconnect write ownership clears
        do begin
        @(posedge clk);
        #1;
        end while (dut.write_active);

        m1_if.b_ready <= 1'b0;

      $display("M1 WRITE DONE: addr=%h data=%h @ %t", addr, data, $time);
    end
  endtask

  task automatic m1_read_check(
    input logic [ADDR_W-1:0] addr,
    input logic [DATA_W-1:0] expected
  );
    logic [DATA_W-1:0] got;
    begin
      @(posedge clk);
      m1_if.ar_valid <= 1'b1;
      m1_if.ar.id    <= 4'd1;
      m1_if.ar.addr  <= addr;
      m1_if.ar.len   <= 8'd0;
      m1_if.ar.size  <= 3'b010;
      m1_if.ar.burst <= AXI_BURST_INCR;

      do @(posedge clk); while (!m1_if.ar_ready);
      m1_if.ar_valid <= 1'b0;

      @(posedge clk);
      m1_if.r_ready <= 1'b1;

      do @(posedge clk); while (!m1_if.r_valid);
      got = m1_if.r.data;
      m1_if.r_ready <= 1'b0;

      if (got !== expected) begin
        $error("M1 READ MISMATCH: addr=%h expected=%h got=%h",
               addr, expected, got);
        error_count++;
      end
      else begin
        $display("M1 READ PASS: addr=%h data=%h", addr, got);
      end
    end
  endtask

    task automatic m1_burst_write(
  input logic [ADDR_W-1:0] addr,
  input logic [DATA_W-1:0] base_data,
  input logic [7:0]        len
);
  begin
    // AW
    @(posedge clk);
    m1_if.aw_valid <= 1'b1;
    m1_if.aw.id    <= 4'd1;
    m1_if.aw.addr  <= addr;
    m1_if.aw.len   <= len;
    m1_if.aw.size  <= 3'b010;
    m1_if.aw.burst <= AXI_BURST_INCR;

    do @(posedge clk); while (!m1_if.aw_ready);

    m1_if.aw_valid <= 1'b0;

    // W beats, one clean accepted beat at a time
    for (int i = 0; i <= len; i++) begin
      @(posedge clk);
      m1_if.w_valid <= 1'b1;
      m1_if.w.data  <= base_data + i;
      m1_if.w.strb  <= '1;
      m1_if.w.last  <= (i == len);

      do @(posedge clk); while (!m1_if.w_ready);

      // Deassert after this beat is accepted to avoid duplicate handshakes
      m1_if.w_valid <= 1'b0;
      m1_if.w.last  <= 1'b0;

      // Bubble cycle before next beat
      @(posedge clk);
      #1;
    end

    @(posedge clk);
    m1_if.b_ready <= 1'b1;

    // Wait for B response on an accepting edge
    do @(posedge clk); while (!m1_if.b_valid);

    // Keep BREADY high until interconnect write ownership clears
    do begin
      @(posedge clk);
      #1;
    end while (dut.write_active);

    m1_if.b_ready <= 1'b0;

    $display("M1 BURST WRITE DONE: addr=%h len=%0d base=%h @ %t",
             addr, len, base_data, $time);
  end
endtask

    task automatic m1_burst_read_check(
  input logic [ADDR_W-1:0] addr,
  input logic [DATA_W-1:0] expected_base,
  input logic [7:0]        len
);
  logic [DATA_W-1:0] got;
  logic              got_last;

  begin
    @(posedge clk);
    m1_if.ar_valid <= 1'b1;
    m1_if.ar.id    <= 4'd1;
    m1_if.ar.addr  <= addr;
    m1_if.ar.len   <= len;
    m1_if.ar.size  <= 3'b010;
    m1_if.ar.burst <= AXI_BURST_INCR;

    do @(posedge clk); while (!m1_if.ar_ready);

    m1_if.ar_valid <= 1'b0;

    @(posedge clk);
    m1_if.r_ready <= 1'b1;

    for (int i = 0; i <= len; i++) begin

      // Wait for an accepted R beat
      do @(posedge clk); while (!m1_if.r_valid);

      got      = m1_if.r.data;
      got_last = m1_if.r.last;

      if (got !== (expected_base + i)) begin
        $error("M1 BURST READ MISMATCH: beat=%0d addr=%h expected=%h got=%h",
               i, addr + (i * 4), expected_base + i, got);
        error_count++;
      end
      else begin
        $display("M1 BURST READ PASS: beat=%0d data=%h", i, got);
      end

      if ((i != len) && got_last) begin
        $error("M1 BURST READ ERROR: early RLAST beat=%0d len=%0d", i, len);
        error_count++;
      end

      if ((i == len) && !got_last) begin
        $error("M1 BURST READ ERROR: missing RLAST on final beat=%0d", i);
        error_count++;
      end

      // Let accepted beat clear before checking next beat
      @(posedge clk);
      #1;
    end

    m1_if.r_ready <= 1'b0;

    $display("M1 BURST READ CHECK DONE: addr=%h len=%0d", addr, len);
  end
endtask

  // =========================================================
  // PRIORITY TEST
  // =========================================================

  task automatic simultaneous_aw_priority_test;
    begin
      $display("----------------------------------------");
      $display("SIMULTANEOUS AW PRIORITY TEST");

      @(posedge clk);

      m0_if.aw_valid <= 1'b1;
      m0_if.aw.id    <= 4'd0;
      m0_if.aw.addr  <= 32'h0000_0030;
      m0_if.aw.len   <= 8'd0;
      m0_if.aw.size  <= 3'b010;
      m0_if.aw.burst <= AXI_BURST_INCR;

      m1_if.aw_valid <= 1'b1;
      m1_if.aw.id    <= 4'd1;
      m1_if.aw.addr  <= 32'h0000_0034;
      m1_if.aw.len   <= 8'd0;
      m1_if.aw.size  <= 3'b010;
      m1_if.aw.burst <= AXI_BURST_INCR;

      @(posedge clk);

      if (m0_if.aw_ready !== 1'b1) begin
        $error("PRIORITY ERROR: M0 should receive AWREADY first");
        error_count++;
      end

      if (m1_if.aw_ready !== 1'b0) begin
        $error("PRIORITY ERROR: M1 should not receive AWREADY while M0 granted");
        error_count++;
      end

      m0_if.aw_valid <= 1'b0;

      // Complete M0 write
      @(posedge clk);
      m0_if.w_valid <= 1'b1;
      m0_if.w.data  <= 32'hAAAA_0030;
      m0_if.w.strb  <= '1;
      m0_if.w.last  <= 1'b1;

      do @(posedge clk); while (!m0_if.w_ready);
      m0_if.w_valid <= 1'b0;
      m0_if.w.last  <= 1'b0;

      @(posedge clk);
      m0_if.b_ready <= 1'b1;

      do @(posedge clk); while (!m0_if.b_valid);
      m0_if.b_ready <= 1'b0;

      // M1 AW should eventually be accepted after M0 write completes
      do @(posedge clk); while (!m1_if.aw_ready);
      m1_if.aw_valid <= 1'b0;

      // Complete M1 write
      @(posedge clk);
      m1_if.w_valid <= 1'b1;
      m1_if.w.data  <= 32'hBBBB_0034;
      m1_if.w.strb  <= '1;
      m1_if.w.last  <= 1'b1;

      do @(posedge clk); while (!m1_if.w_ready);
      m1_if.w_valid <= 1'b0;
      m1_if.w.last  <= 1'b0;

      @(posedge clk);
      m1_if.b_ready <= 1'b1;

      do @(posedge clk); while (!m1_if.b_valid);
      m1_if.b_ready <= 1'b0;

      if (mem[32'h30 >> 2] !== 32'hAAAA_0030) begin
        $error("PRIORITY TEST ERROR: M0 write data missing");
        error_count++;
      end

      if (mem[32'h34 >> 2] !== 32'hBBBB_0034) begin
        $error("PRIORITY TEST ERROR: M1 write data missing");
        error_count++;
      end

      $display("SIMULTANEOUS AW PRIORITY TEST COMPLETE");
    end
  endtask

    // =========================================================
  // SIMULTANEOUS AR PRIORITY TEST
  // =========================================================

  task automatic simultaneous_ar_priority_test;
    logic [DATA_W-1:0] m0_got;
    logic [DATA_W-1:0] m1_got;

    begin
      $display("----------------------------------------");
      $display("SIMULTANEOUS AR PRIORITY TEST");

      // Preload memory directly
      mem[32'h40 >> 2] = 32'hAAAA_0040;
      mem[32'h44 >> 2] = 32'hBBBB_0044;

      @(posedge clk);

      // Both masters request read at same time
      m0_if.ar_valid <= 1'b1;
      m0_if.ar.id    <= 4'd0;
      m0_if.ar.addr  <= 32'h0000_0040;
      m0_if.ar.len   <= 8'd0;
      m0_if.ar.size  <= 3'b010;
      m0_if.ar.burst <= AXI_BURST_INCR;

      m1_if.ar_valid <= 1'b1;
      m1_if.ar.id    <= 4'd1;
      m1_if.ar.addr  <= 32'h0000_0044;
      m1_if.ar.len   <= 8'd0;
      m1_if.ar.size  <= 3'b010;
      m1_if.ar.burst <= AXI_BURST_INCR;

      @(posedge clk);

      if (m0_if.ar_ready !== 1'b1) begin
        $error("AR PRIORITY ERROR: M0 should receive ARREADY first");
        error_count++;
      end

      if (m1_if.ar_ready !== 1'b0) begin
        $error("AR PRIORITY ERROR: M1 should not receive ARREADY while M0 granted");
        error_count++;
      end

      // Complete M0 AR
      m0_if.ar_valid <= 1'b0;

      // Accept M0 R response
      @(posedge clk);
      m0_if.r_ready <= 1'b1;

      do @(posedge clk); while (!m0_if.r_valid);
      m0_got = m0_if.r.data;

      if (m0_got !== 32'hAAAA_0040) begin
        $error("AR PRIORITY ERROR: M0 read data wrong. expected=%h got=%h",
               32'hAAAA_0040, m0_got);
        error_count++;
      end
      else begin
        $display("AR PRIORITY M0 READ PASS: data=%h", m0_got);
      end

      m0_if.r_ready <= 1'b0;

      // M1 AR should eventually be accepted after M0 read completes
      do @(posedge clk); while (!m1_if.ar_ready);
      m1_if.ar_valid <= 1'b0;

      // Accept M1 R response
      @(posedge clk);
      m1_if.r_ready <= 1'b1;

      do @(posedge clk); while (!m1_if.r_valid);
      m1_got = m1_if.r.data;

      if (m1_got !== 32'hBBBB_0044) begin
        $error("AR PRIORITY ERROR: M1 read data wrong. expected=%h got=%h",
               32'hBBBB_0044, m1_got);
        error_count++;
      end
      else begin
        $display("AR PRIORITY M1 READ PASS: data=%h", m1_got);
      end

      m1_if.r_ready <= 1'b0;

      $display("SIMULTANEOUS AR PRIORITY TEST COMPLETE");
    end
  endtask

    // =========================================================
  // RESPONSE BACKPRESSURE TEST
  // =========================================================

  task automatic response_backpressure_test;
    logic [DATA_W-1:0] got;

    begin
      $display("----------------------------------------");
      $display("RESPONSE BACKPRESSURE TEST");

      // -----------------------------------------------------
      // M0 RREADY delayed
      // -----------------------------------------------------
      mem[32'h50 >> 2] = 32'hAAAA_0050;

      @(posedge clk);
      m0_if.ar_valid <= 1'b1;
      m0_if.ar.id    <= 4'd0;
      m0_if.ar.addr  <= 32'h0000_0050;
      m0_if.ar.len   <= 8'd0;
      m0_if.ar.size  <= 3'b010;
      m0_if.ar.burst <= AXI_BURST_INCR;

      do @(posedge clk); while (!m0_if.ar_ready);
      m0_if.ar_valid <= 1'b0;

      // Intentionally hold RREADY low for a few cycles
      m0_if.r_ready <= 1'b0;
      repeat (4) @(posedge clk);

      if (m0_if.r_valid !== 1'b1) begin
        $error("BACKPRESSURE ERROR: M0 RVALID should remain high while RREADY=0");
        error_count++;
      end

      got = m0_if.r.data;

        // Drive RREADY before the next posedge so DUT samples it cleanly
        @(negedge clk);
        m0_if.r_ready = 1'b1;

        @(posedge clk);
        #1;

        if (dut.read_active !== 1'b0) begin
        $error("BACKPRESSURE ERROR: M0 read_active did not clear after R handshake");
        error_count++;
        end

        @(negedge clk);
        m0_if.r_ready = 1'b0;

      if (got !== 32'hAAAA_0050) begin
        $error("BACKPRESSURE ERROR: M0 delayed read wrong expected=%h got=%h",
               32'hAAAA_0050, got);
        error_count++;
      end
      else begin
        $display("M0 RREADY backpressure PASS: data=%h", got);
      end

      $display("DEBUG after M0 R backpressure: read_active=%0b m1_ar_valid=%0b m1_ar_ready=%0b s0_ar_valid=%0b s0_ar_ready=%0b @ %t",
         dut.read_active, m1_if.ar_valid, m1_if.ar_ready,
         s0_if.ar_valid, s0_if.ar_ready, $time);

      // -----------------------------------------------------
      // M1 RREADY delayed
      // -----------------------------------------------------
      mem[32'h54 >> 2] = 32'hBBBB_0054;

      @(posedge clk);
      m1_if.ar_valid <= 1'b1;
      m1_if.ar.id    <= 4'd1;
      m1_if.ar.addr  <= 32'h0000_0054;
      m1_if.ar.len   <= 8'd0;
      m1_if.ar.size  <= 3'b010;
      m1_if.ar.burst <= AXI_BURST_INCR;

      do @(posedge clk); while (!m1_if.ar_ready);
      m1_if.ar_valid <= 1'b0;

      m1_if.r_ready <= 1'b0;
      repeat (4) @(posedge clk);

      if (m1_if.r_valid !== 1'b1) begin
        $error("BACKPRESSURE ERROR: M1 RVALID should remain high while RREADY=0");
        error_count++;
      end

      got = m1_if.r.data;

        // Drive RREADY before the next posedge so DUT samples it cleanly
        @(negedge clk);
        m1_if.r_ready = 1'b1;

        @(posedge clk);
        #1;

        if (dut.read_active !== 1'b0) begin
        $error("BACKPRESSURE ERROR: M1 read_active did not clear after R handshake");
        error_count++;
        end

        @(negedge clk);
        m1_if.r_ready = 1'b0;

      if (got !== 32'hBBBB_0054) begin
        $error("BACKPRESSURE ERROR: M1 delayed read wrong expected=%h got=%h",
               32'hBBBB_0054, got);
        error_count++;
      end
      else begin
        $display("M1 RREADY backpressure PASS: data=%h", got);
      end

      // -----------------------------------------------------
      // M0 BREADY delayed
      // -----------------------------------------------------
      @(posedge clk);
      m0_if.aw_valid <= 1'b1;
      m0_if.aw.id    <= 4'd0;
      m0_if.aw.addr  <= 32'h0000_0060;
      m0_if.aw.len   <= 8'd0;
      m0_if.aw.size  <= 3'b010;
      m0_if.aw.burst <= AXI_BURST_INCR;

      do @(posedge clk); while (!m0_if.aw_ready);
      m0_if.aw_valid <= 1'b0;

      @(posedge clk);
      m0_if.w_valid <= 1'b1;
      m0_if.w.data  <= 32'hAAAA_0060;
      m0_if.w.strb  <= '1;
      m0_if.w.last  <= 1'b1;

      do @(posedge clk); while (!m0_if.w_ready);
      m0_if.w_valid <= 1'b0;
      m0_if.w.last  <= 1'b0;

      // Hold BREADY low while BVALID should be routed to M0
      m0_if.b_ready <= 1'b0;
      repeat (4) @(posedge clk);

      if (m0_if.b_valid !== 1'b1) begin
        $error("BACKPRESSURE ERROR: M0 BVALID should remain high while BREADY=0");
        error_count++;
      end

      m0_if.b_ready <= 1'b1;
      @(posedge clk);
      m0_if.b_ready <= 1'b0;

      if (mem[32'h60 >> 2] !== 32'hAAAA_0060) begin
        $error("BACKPRESSURE ERROR: M0 delayed B write missing");
        error_count++;
      end
      else begin
        $display("M0 BREADY backpressure PASS");
      end

      // -----------------------------------------------------
      // M1 BREADY delayed
      // -----------------------------------------------------
      @(posedge clk);
      m1_if.aw_valid <= 1'b1;
      m1_if.aw.id    <= 4'd1;
      m1_if.aw.addr  <= 32'h0000_0064;
      m1_if.aw.len   <= 8'd0;
      m1_if.aw.size  <= 3'b010;
      m1_if.aw.burst <= AXI_BURST_INCR;

      do @(posedge clk); while (!m1_if.aw_ready);
      m1_if.aw_valid <= 1'b0;

      @(posedge clk);
      m1_if.w_valid <= 1'b1;
      m1_if.w.data  <= 32'hBBBB_0064;
      m1_if.w.strb  <= '1;
      m1_if.w.last  <= 1'b1;

      do @(posedge clk); while (!m1_if.w_ready);
      m1_if.w_valid <= 1'b0;
      m1_if.w.last  <= 1'b0;

      m1_if.b_ready <= 1'b0;
      repeat (4) @(posedge clk);

      if (m1_if.b_valid !== 1'b1) begin
        $error("BACKPRESSURE ERROR: M1 BVALID should remain high while BREADY=0");
        error_count++;
      end

      m1_if.b_ready <= 1'b1;
      @(posedge clk);
      m1_if.b_ready <= 1'b0;

      if (mem[32'h64 >> 2] !== 32'hBBBB_0064) begin
        $error("BACKPRESSURE ERROR: M1 delayed B write missing");
        error_count++;
      end
      else begin
        $display("M1 BREADY backpressure PASS");
      end

      $display("RESPONSE BACKPRESSURE TEST COMPLETE");
    end
  endtask

    // =========================================================
  // BURST ROUTING TEST
  // =========================================================

  task automatic burst_routing_test;
    begin
      $display("----------------------------------------");
      $display("BURST ROUTING TEST");

      m0_burst_write(32'h0000_0080, 32'hA000_0000, 8'd3); // 4 beats
      m0_burst_read_check(32'h0000_0080, 32'hA000_0000, 8'd3);

      m1_burst_write(32'h0000_00C0, 32'hB000_0000, 8'd7); // 8 beats
      m1_burst_read_check(32'h0000_00C0, 32'hB000_0000, 8'd7);

      // Cross-read to verify response routing still works
      m0_burst_read_check(32'h0000_00C0, 32'hB000_0000, 8'd7);
      m1_burst_read_check(32'h0000_0080, 32'hA000_0000, 8'd3);

      $display("BURST ROUTING TEST COMPLETE");
    end
  endtask

  // =========================================================
  // TEST SEQUENCE
  // =========================================================

  initial begin
    error_count = 0;

    init_master_signals();
    init_mem();

    wait(rst_n);
    repeat (2) @(posedge clk);

    // M0 basic write/read
    m0_write(32'h0000_0010, 32'hAAAA_AAAA);
    m0_read_check(32'h0000_0010, 32'hAAAA_AAAA);

    // M1 basic write/read
    m1_write(32'h0000_0020, 32'hBBBB_BBBB);
    m1_read_check(32'h0000_0020, 32'hBBBB_BBBB);

    // Cross-check ownership
    m0_read_check(32'h0000_0020, 32'hBBBB_BBBB);
    m1_read_check(32'h0000_0010, 32'hAAAA_AAAA);

    // Priority when both masters request AW and AR together. //Backpresure test //Burst routing test
    simultaneous_aw_priority_test();
    simultaneous_ar_priority_test();
    response_backpressure_test();
    burst_routing_test();

    #20;

    if (error_count == 0) begin
        $display("========================================");
        $display("PHASE 5 STEP 5 PASS: burst routing through interconnect verified");
        $display("M0/M1 single-beat, arbitration, backpressure, and burst routing passed");
        $display("========================================");
        end
        else begin
        $error("PHASE 5 STEP 5 FAILED: error_count=%0d", error_count);
        end

    #50;
    $finish;
  end

endmodule
