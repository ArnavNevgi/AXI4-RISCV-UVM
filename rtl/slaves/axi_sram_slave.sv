import axi_pkg::*;

module axi_sram_slave #(
  parameter ID_W    = 4,
  parameter ADDR_W  = 32,
  parameter DATA_W  = 32,
  parameter DEPTH   = 256
)(
  input logic clk,
  input logic rst_n,

  axi_if.slave intf
);

  localparam STRB_W = DATA_W / 8;

  // ---------------------------------------------------------
  // Memory
  // ---------------------------------------------------------

  logic [DATA_W-1:0] mem [0:DEPTH-1];

  // ---------------------------------------------------------
  // Write-side state
  // ---------------------------------------------------------

  typedef enum logic [1:0] {
    W_IDLE,
    W_DATA,
    W_RESP
  } w_state_t;

  w_state_t w_state;

  logic [ADDR_W-1:0] wr_addr_reg;
  logic [ID_W-1:0]   wr_id_reg;
  logic [7:0]        wr_len_reg;
  logic [7:0]        wr_cnt;

  // ---------------------------------------------------------
  // Read-side state
  // ---------------------------------------------------------

  typedef enum logic [1:0] {
    R_IDLE,
    R_DATA
  } r_state_t;

  r_state_t r_state;

  logic [ADDR_W-1:0] rd_addr_reg;
  logic [ID_W-1:0]   rd_id_reg;
  logic [7:0]        rd_len_reg;
  logic [7:0]        rd_cnt;

  // ---------------------------------------------------------
  // Helper: word index
  // ---------------------------------------------------------

  function automatic int unsigned addr_to_index(input logic [ADDR_W-1:0] addr);
    begin
      addr_to_index = addr >> 2;
    end
  endfunction

  // ---------------------------------------------------------
  // Write FSM: AW/W/B
  // ---------------------------------------------------------

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      w_state <= W_IDLE;

      wr_addr_reg <= '0;
      wr_id_reg   <= '0;
      wr_len_reg  <= '0;
      wr_cnt      <= '0;

      intf.aw_ready <= 1'b0;
      intf.w_ready  <= 1'b0;

      intf.b_valid  <= 1'b0;
      intf.b        <= '0;
    end
    else begin
      case (w_state)

        // ---------------------------------------------------
        // Wait for AW
        // ---------------------------------------------------
        W_IDLE: begin
          intf.aw_ready <= 1'b1;
          intf.w_ready  <= 1'b0;
          intf.b_valid  <= 1'b0;

          if (intf.aw_valid && intf.aw_ready) begin
            wr_addr_reg <= intf.aw.addr;
            wr_id_reg   <= intf.aw.id;
            wr_len_reg  <= intf.aw.len;
            wr_cnt      <= 8'd0;

            intf.aw_ready <= 1'b0;
            intf.w_ready  <= 1'b1;

            w_state <= W_DATA;
          end
        end

        // ---------------------------------------------------
        // Accept W beats
        // ---------------------------------------------------
        W_DATA: begin
          intf.aw_ready <= 1'b0;
          intf.w_ready  <= 1'b1;

          if (intf.w_valid && intf.w_ready) begin
            if (addr_to_index(wr_addr_reg) < DEPTH) begin
              mem[addr_to_index(wr_addr_reg)] <= intf.w.data;
            end

            // Basic WLAST protocol checks
            if ((wr_cnt != wr_len_reg) && intf.w.last) begin
              $error("AXI SRAM ERROR: early WLAST. beat=%0d len=%0d @ %t",
                     wr_cnt, wr_len_reg, $time);
            end

            if ((wr_cnt == wr_len_reg) && !intf.w.last) begin
              $error("AXI SRAM ERROR: missing WLAST on final beat=%0d @ %t",
                     wr_cnt, $time);
            end

            if (intf.w.last) begin
              intf.w_ready <= 1'b0;

              intf.b_valid <= 1'b1;
              intf.b.id    <= wr_id_reg;
              intf.b.resp  <= AXI_RESP_OKAY;

              w_state <= W_RESP;
            end
            else begin
              wr_addr_reg <= wr_addr_reg + 4;
              wr_cnt      <= wr_cnt + 1;
            end
          end
        end

        // ---------------------------------------------------
        // Wait for BREADY
        // ---------------------------------------------------
        W_RESP: begin
          intf.aw_ready <= 1'b0;
          intf.w_ready  <= 1'b0;

          if (intf.b_valid && intf.b_ready) begin
            intf.b_valid <= 1'b0;
            w_state      <= W_IDLE;
          end
        end

        default: begin
          w_state <= W_IDLE;
        end

      endcase
    end
  end

  // ---------------------------------------------------------
  // Read FSM: AR/R
  // ---------------------------------------------------------

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      r_state <= R_IDLE;

      rd_addr_reg <= '0;
      rd_id_reg   <= '0;
      rd_len_reg  <= '0;
      rd_cnt      <= '0;

      intf.ar_ready <= 1'b0;
      intf.r_valid  <= 1'b0;
      intf.r        <= '0;
    end
    else begin
      case (r_state)

        // ---------------------------------------------------
        // Wait for AR
        // ---------------------------------------------------
        R_IDLE: begin
          intf.ar_ready <= 1'b1;
          intf.r_valid  <= 1'b0;
          intf.r.last   <= 1'b0;

          if (intf.ar_valid && intf.ar_ready) begin
            rd_addr_reg <= intf.ar.addr;
            rd_id_reg   <= intf.ar.id;
            rd_len_reg  <= intf.ar.len;
            rd_cnt      <= 8'd0;

            intf.ar_ready <= 1'b0;

            // Launch first R beat next state
            r_state <= R_DATA;
          end
        end

        // ---------------------------------------------------
        // Drive R beats
        // ---------------------------------------------------
        R_DATA: begin
          intf.ar_ready <= 1'b0;

          // If no valid beat is currently pending, drive one
          if (!intf.r_valid) begin
            intf.r_valid <= 1'b1;
            intf.r.id    <= rd_id_reg;

            if (addr_to_index(rd_addr_reg) < DEPTH)
              intf.r.data <= mem[addr_to_index(rd_addr_reg)];
            else
              intf.r.data <= '0;

            intf.r.resp <= AXI_RESP_OKAY;
            intf.r.last <= (rd_cnt == rd_len_reg);
          end

          // Beat accepted
          if (intf.r_valid && intf.r_ready) begin
            if (intf.r.last) begin
              intf.r_valid <= 1'b0;
              intf.r.last  <= 1'b0;
              r_state      <= R_IDLE;
            end
            else begin
              intf.r_valid <= 1'b0;
              intf.r.last  <= 1'b0;

              rd_addr_reg <= rd_addr_reg + 4;
              rd_cnt      <= rd_cnt + 1;
            end
          end
        end

        default: begin
          r_state <= R_IDLE;
        end

      endcase
    end
  end

endmodule