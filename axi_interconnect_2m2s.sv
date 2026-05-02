import axi_pkg::*;

module axi_interconnect_2m2s #(
  parameter ID_W   = 4,
  parameter ADDR_W = 32,
  parameter DATA_W = 32
)(
  input logic clk,
  input logic rst_n,

  // Upstream masters: interconnect acts as AXI slave
  axi_if.slave  m0,   // CPU
  axi_if.slave  m1,   // DMA

  // Downstream slaves: interconnect acts as AXI master
  axi_if.master s0,   // SRAM: 0x0000_xxxx
  axi_if.master s1    // REGs: 0x0001_xxxx
);

  // =========================================================
  // Address decode
  // =========================================================
  // S0 SRAM region: 0x0000_0000 - 0x0000_FFFF
  // S1 REG  region: 0x0001_0000 - 0x0001_FFFF

  function automatic logic decode_sram(input logic [ADDR_W-1:0] addr);
    begin
      decode_sram = (addr[31:16] == 16'h0000);
    end
  endfunction

  function automatic logic decode_regs(input logic [ADDR_W-1:0] addr);
    begin
      decode_regs = (addr[31:16] == 16'h0001);
    end
  endfunction

  function automatic axi_aw_ar_t localize_addr(input axi_aw_ar_t in_chan);
    axi_aw_ar_t tmp;
    begin
      tmp = in_chan;

      // For register block, strip upper address region.
      // Example: 0x0001_0008 -> 0x0000_0008
      if (decode_regs(in_chan.addr)) begin
        tmp.addr = {16'h0000, in_chan.addr[15:0]};
      end

      localize_addr = tmp;
    end
  endfunction

  // =========================================================
  // Ownership tracking
  // =========================================================

  logic read_active;
  logic read_owner;      // 0 = m0, 1 = m1
  logic read_slave;      // 0 = s0, 1 = s1

  logic write_active;
  logic write_owner;     // 0 = m0, 1 = m1
  logic write_slave;     // 0 = s0, 1 = s1

  // Fixed-priority grants: m0 > m1
  logic grant_ar_m0;
  logic grant_ar_m1;

  logic grant_aw_m0;
  logic grant_aw_m1;

  assign grant_ar_m0 = (!read_active) && m0.ar_valid;
  assign grant_ar_m1 = (!read_active) && (!m0.ar_valid) && m1.ar_valid;

  assign grant_aw_m0 = (!write_active) && m0.aw_valid;
  assign grant_aw_m1 = (!write_active) && (!m0.aw_valid) && m1.aw_valid;

  // Decode selected AR/AW target
  logic selected_ar_s0;
  logic selected_ar_s1;
  logic selected_aw_s0;
  logic selected_aw_s1;

  always_comb begin
    selected_ar_s0 = 1'b0;
    selected_ar_s1 = 1'b0;

    if (grant_ar_m0) begin
      selected_ar_s0 = decode_sram(m0.ar.addr);
      selected_ar_s1 = decode_regs(m0.ar.addr);
    end
    else if (grant_ar_m1) begin
      selected_ar_s0 = decode_sram(m1.ar.addr);
      selected_ar_s1 = decode_regs(m1.ar.addr);
    end
  end

  always_comb begin
    selected_aw_s0 = 1'b0;
    selected_aw_s1 = 1'b0;

    if (grant_aw_m0) begin
      selected_aw_s0 = decode_sram(m0.aw.addr);
      selected_aw_s1 = decode_regs(m0.aw.addr);
    end
    else if (grant_aw_m1) begin
      selected_aw_s0 = decode_sram(m1.aw.addr);
      selected_aw_s1 = decode_regs(m1.aw.addr);
    end
  end

  // =========================================================
  // READ ADDRESS CHANNEL: M0/M1 -> S0/S1
  // =========================================================

  always_comb begin
    // Defaults to slaves
    s0.ar_valid = 1'b0;
    s0.ar       = '0;

    s1.ar_valid = 1'b0;
    s1.ar       = '0;

    // Defaults to masters
    m0.ar_ready = 1'b0;
    m1.ar_ready = 1'b0;

    if (grant_ar_m0) begin
      if (selected_ar_s0) begin
        s0.ar_valid = m0.ar_valid;
        s0.ar       = localize_addr(m0.ar);
        m0.ar_ready = s0.ar_ready;
      end
      else if (selected_ar_s1) begin
        s1.ar_valid = m0.ar_valid;
        s1.ar       = localize_addr(m0.ar);
        m0.ar_ready = s1.ar_ready;
      end
    end
    else if (grant_ar_m1) begin
      if (selected_ar_s0) begin
        s0.ar_valid = m1.ar_valid;
        s0.ar       = localize_addr(m1.ar);
        m1.ar_ready = s0.ar_ready;
      end
      else if (selected_ar_s1) begin
        s1.ar_valid = m1.ar_valid;
        s1.ar       = localize_addr(m1.ar);
        m1.ar_ready = s1.ar_ready;
      end
    end
  end

  // =========================================================
  // READ OWNER TRACKING
  // =========================================================

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      read_active <= 1'b0;
      read_owner  <= 1'b0;
      read_slave  <= 1'b0;
    end
    else begin
      if (!read_active) begin
        if (grant_ar_m0 && selected_ar_s0 && s0.ar_ready) begin
          read_active <= 1'b1;
          read_owner  <= 1'b0;
          read_slave  <= 1'b0;
        end
        else if (grant_ar_m0 && selected_ar_s1 && s1.ar_ready) begin
          read_active <= 1'b1;
          read_owner  <= 1'b0;
          read_slave  <= 1'b1;
        end
        else if (grant_ar_m1 && selected_ar_s0 && s0.ar_ready) begin
          read_active <= 1'b1;
          read_owner  <= 1'b1;
          read_slave  <= 1'b0;
        end
        else if (grant_ar_m1 && selected_ar_s1 && s1.ar_ready) begin
          read_active <= 1'b1;
          read_owner  <= 1'b1;
          read_slave  <= 1'b1;
        end
      end

      if (read_active) begin
        if ((read_slave == 1'b0) && s0.r_valid && s0.r_ready && s0.r.last) begin
          read_active <= 1'b0;
        end
        else if ((read_slave == 1'b1) && s1.r_valid && s1.r_ready && s1.r.last) begin
          read_active <= 1'b0;
        end
      end
    end
  end

  // =========================================================
  // READ DATA CHANNEL: selected slave -> owner master
  // =========================================================

  always_comb begin
    m0.r_valid = 1'b0;
    m0.r       = '0;

    m1.r_valid = 1'b0;
    m1.r       = '0;

    s0.r_ready = 1'b0;
    s1.r_ready = 1'b0;

    if (read_active && read_slave == 1'b0) begin
      if (read_owner == 1'b0) begin
        m0.r_valid = s0.r_valid;
        m0.r       = s0.r;
        s0.r_ready = m0.r_ready;
      end
      else begin
        m1.r_valid = s0.r_valid;
        m1.r       = s0.r;
        s0.r_ready = m1.r_ready;
      end
    end
    else if (read_active && read_slave == 1'b1) begin
      if (read_owner == 1'b0) begin
        m0.r_valid = s1.r_valid;
        m0.r       = s1.r;
        s1.r_ready = m0.r_ready;
      end
      else begin
        m1.r_valid = s1.r_valid;
        m1.r       = s1.r;
        s1.r_ready = m1.r_ready;
      end
    end
  end

  // =========================================================
  // WRITE ADDRESS CHANNEL: M0/M1 -> S0/S1
  // =========================================================

  always_comb begin
    s0.aw_valid = 1'b0;
    s0.aw       = '0;

    s1.aw_valid = 1'b0;
    s1.aw       = '0;

    m0.aw_ready = 1'b0;
    m1.aw_ready = 1'b0;

    if (grant_aw_m0) begin
      if (selected_aw_s0) begin
        s0.aw_valid = m0.aw_valid;
        s0.aw       = localize_addr(m0.aw);
        m0.aw_ready = s0.aw_ready;
      end
      else if (selected_aw_s1) begin
        s1.aw_valid = m0.aw_valid;
        s1.aw       = localize_addr(m0.aw);
        m0.aw_ready = s1.aw_ready;
      end
    end
    else if (grant_aw_m1) begin
      if (selected_aw_s0) begin
        s0.aw_valid = m1.aw_valid;
        s0.aw       = localize_addr(m1.aw);
        m1.aw_ready = s0.aw_ready;
      end
      else if (selected_aw_s1) begin
        s1.aw_valid = m1.aw_valid;
        s1.aw       = localize_addr(m1.aw);
        m1.aw_ready = s1.aw_ready;
      end
    end
  end

  // =========================================================
  // WRITE OWNER TRACKING
  // =========================================================

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      write_active <= 1'b0;
      write_owner  <= 1'b0;
      write_slave  <= 1'b0;
    end
    else begin
      if (!write_active) begin
        if (grant_aw_m0 && selected_aw_s0 && s0.aw_ready) begin
          write_active <= 1'b1;
          write_owner  <= 1'b0;
          write_slave  <= 1'b0;
        end
        else if (grant_aw_m0 && selected_aw_s1 && s1.aw_ready) begin
          write_active <= 1'b1;
          write_owner  <= 1'b0;
          write_slave  <= 1'b1;
        end
        else if (grant_aw_m1 && selected_aw_s0 && s0.aw_ready) begin
          write_active <= 1'b1;
          write_owner  <= 1'b1;
          write_slave  <= 1'b0;
        end
        else if (grant_aw_m1 && selected_aw_s1 && s1.aw_ready) begin
          write_active <= 1'b1;
          write_owner  <= 1'b1;
          write_slave  <= 1'b1;
        end
      end

      if (write_active) begin
        if ((write_slave == 1'b0) && s0.b_valid && s0.b_ready) begin
          write_active <= 1'b0;
        end
        else if ((write_slave == 1'b1) && s1.b_valid && s1.b_ready) begin
          write_active <= 1'b0;
        end
      end
    end
  end

  // =========================================================
  // WRITE DATA CHANNEL: owner master -> selected slave
  // =========================================================

  always_comb begin
    s0.w_valid = 1'b0;
    s0.w       = '0;

    s1.w_valid = 1'b0;
    s1.w       = '0;

    m0.w_ready = 1'b0;
    m1.w_ready = 1'b0;

    if (write_active && write_slave == 1'b0) begin
      if (write_owner == 1'b0) begin
        s0.w_valid = m0.w_valid;
        s0.w       = m0.w;
        m0.w_ready = s0.w_ready;
      end
      else begin
        s0.w_valid = m1.w_valid;
        s0.w       = m1.w;
        m1.w_ready = s0.w_ready;
      end
    end
    else if (write_active && write_slave == 1'b1) begin
      if (write_owner == 1'b0) begin
        s1.w_valid = m0.w_valid;
        s1.w       = m0.w;
        m0.w_ready = s1.w_ready;
      end
      else begin
        s1.w_valid = m1.w_valid;
        s1.w       = m1.w;
        m1.w_ready = s1.w_ready;
      end
    end
  end

  // =========================================================
  // WRITE RESPONSE CHANNEL: selected slave -> owner master
  // =========================================================

  always_comb begin
    m0.b_valid = 1'b0;
    m0.b       = '0;

    m1.b_valid = 1'b0;
    m1.b       = '0;

    s0.b_ready = 1'b0;
    s1.b_ready = 1'b0;

    if (write_active && write_slave == 1'b0) begin
      if (write_owner == 1'b0) begin
        m0.b_valid = s0.b_valid;
        m0.b       = s0.b;
        s0.b_ready = m0.b_ready;
      end
      else begin
        m1.b_valid = s0.b_valid;
        m1.b       = s0.b;
        s0.b_ready = m1.b_ready;
      end
    end
    else if (write_active && write_slave == 1'b1) begin
      if (write_owner == 1'b0) begin
        m0.b_valid = s1.b_valid;
        m0.b       = s1.b;
        s1.b_ready = m0.b_ready;
      end
      else begin
        m1.b_valid = s1.b_valid;
        m1.b       = s1.b;
        s1.b_ready = m1.b_ready;
      end
    end
  end

endmodule
