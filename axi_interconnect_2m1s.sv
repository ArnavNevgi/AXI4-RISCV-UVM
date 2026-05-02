import axi_pkg::*;

module axi_interconnect_2m1s #(
  parameter ID_W   = 4,
  parameter ADDR_W = 32,
  parameter DATA_W = 32
)(
  input logic clk,
  input logic rst_n,

  // Upstream masters: interconnect acts as AXI slave
  axi_if.slave  m0,   // CPU
  axi_if.slave  m1,   // DMA

  // Downstream slave: interconnect acts as AXI master
  axi_if.master s0    // Memory / shared slave
);

  // ---------------------------------------------------------
  // Ownership tracking
  // ---------------------------------------------------------

  logic read_active;
  logic read_owner;    // 0 = m0, 1 = m1

  logic write_active;
  logic write_owner;   // 0 = m0, 1 = m1

  // Fixed-priority grants: m0 > m1
  logic grant_ar_m0;
  logic grant_ar_m1;

  logic grant_aw_m0;
  logic grant_aw_m1;

  assign grant_ar_m0 = (!read_active) && m0.ar_valid;
  assign grant_ar_m1 = (!read_active) && (!m0.ar_valid) && m1.ar_valid;

  assign grant_aw_m0 = (!write_active) && m0.aw_valid;
  assign grant_aw_m1 = (!write_active) && (!m0.aw_valid) && m1.aw_valid;

  // ---------------------------------------------------------
  // READ ADDRESS CHANNEL: M0/M1 -> S0
  // ---------------------------------------------------------

  always_comb begin
    // Defaults
    s0.ar_valid = 1'b0;
    s0.ar       = '0;

    m0.ar_ready = 1'b0;
    m1.ar_ready = 1'b0;

    if (grant_ar_m0) begin
      s0.ar_valid = m0.ar_valid;
      s0.ar       = m0.ar;
      m0.ar_ready = s0.ar_ready;
    end
    else if (grant_ar_m1) begin
      s0.ar_valid = m1.ar_valid;
      s0.ar       = m1.ar;
      m1.ar_ready = s0.ar_ready;
    end
  end

  // ---------------------------------------------------------
  // READ OWNER TRACKING
  // ---------------------------------------------------------

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      read_active <= 1'b0;
      read_owner  <= 1'b0;
    end
    else begin
      // Capture owner on AR handshake
      if (!read_active && s0.ar_valid && s0.ar_ready) begin
        read_active <= 1'b1;

        if (grant_ar_m0)
          read_owner <= 1'b0;
        else if (grant_ar_m1)
          read_owner <= 1'b1;
      end

      // Clear owner on final R beat accepted by selected master
      if (read_active && s0.r_valid && s0.r_ready && s0.r.last) begin
        read_active <= 1'b0;
      end
    end
  end

  // ---------------------------------------------------------
  // READ DATA CHANNEL: S0 -> owner master
  // ---------------------------------------------------------

  always_comb begin
    // Defaults
    m0.r_valid = 1'b0;
    m0.r       = '0;

    m1.r_valid = 1'b0;
    m1.r       = '0;

    s0.r_ready = 1'b0;

    if (read_active && read_owner == 1'b0) begin
      m0.r_valid = s0.r_valid;
      m0.r       = s0.r;
      s0.r_ready = m0.r_ready;
    end
    else if (read_active && read_owner == 1'b1) begin
      m1.r_valid = s0.r_valid;
      m1.r       = s0.r;
      s0.r_ready = m1.r_ready;
    end
  end

  // ---------------------------------------------------------
  // WRITE ADDRESS CHANNEL: M0/M1 -> S0
  // ---------------------------------------------------------

  always_comb begin
    // Defaults
    s0.aw_valid = 1'b0;
    s0.aw       = '0;

    m0.aw_ready = 1'b0;
    m1.aw_ready = 1'b0;

    if (grant_aw_m0) begin
      s0.aw_valid = m0.aw_valid;
      s0.aw       = m0.aw;
      m0.aw_ready = s0.aw_ready;
    end
    else if (grant_aw_m1) begin
      s0.aw_valid = m1.aw_valid;
      s0.aw       = m1.aw;
      m1.aw_ready = s0.aw_ready;
    end
  end

  // ---------------------------------------------------------
  // WRITE OWNER TRACKING
  // ---------------------------------------------------------

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      write_active <= 1'b0;
      write_owner  <= 1'b0;
    end
    else begin
      // Capture owner on AW handshake
      if (!write_active && s0.aw_valid && s0.aw_ready) begin
        write_active <= 1'b1;

        if (grant_aw_m0)
          write_owner <= 1'b0;
        else if (grant_aw_m1)
          write_owner <= 1'b1;
      end

      // Clear owner on B response accepted by selected master
      if (write_active && s0.b_valid && s0.b_ready) begin
        write_active <= 1'b0;
      end
    end
  end

  // ---------------------------------------------------------
  // WRITE DATA CHANNEL: owner master -> S0
  // ---------------------------------------------------------

  always_comb begin
    // Defaults
    s0.w_valid = 1'b0;
    s0.w       = '0;

    m0.w_ready = 1'b0;
    m1.w_ready = 1'b0;

    if (write_active && write_owner == 1'b0) begin
      s0.w_valid = m0.w_valid;
      s0.w       = m0.w;
      m0.w_ready = s0.w_ready;
    end
    else if (write_active && write_owner == 1'b1) begin
      s0.w_valid = m1.w_valid;
      s0.w       = m1.w;
      m1.w_ready = s0.w_ready;
    end
  end

  // ---------------------------------------------------------
  // WRITE RESPONSE CHANNEL: S0 -> owner master
  // ---------------------------------------------------------

  always_comb begin
    // Defaults
    m0.b_valid = 1'b0;
    m0.b       = '0;

    m1.b_valid = 1'b0;
    m1.b       = '0;

    s0.b_ready = 1'b0;

    if (write_active && write_owner == 1'b0) begin
      m0.b_valid = s0.b_valid;
      m0.b       = s0.b;
      s0.b_ready = m0.b_ready;
    end
    else if (write_active && write_owner == 1'b1) begin
      m1.b_valid = s0.b_valid;
      m1.b       = s0.b;
      s0.b_ready = m1.b_ready;
    end
  end

endmodule