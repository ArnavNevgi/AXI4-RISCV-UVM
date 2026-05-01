import axi_pkg::*;

module dma_controller #(
  parameter ID_W   = 4,
  parameter ADDR_W = 32,
  parameter DATA_W = 32
)(
  input  logic clk,
  input  logic rst_n,

  // Control interface
  input  logic              start,
  input  logic [ADDR_W-1:0] src_addr,
  input  logic [ADDR_W-1:0] dst_addr,
  input  logic [15:0]       length,     // number of 32-bit words

  output logic              busy,
  output logic              done,
  output logic              error,

  // AXI master interface
  axi_if.master intf
);

  typedef enum logic [2:0] {
    IDLE,
    READ_AR,
    READ_R,
    WRITE_AW,
    WRITE_W,
    WRITE_B,
    DONE
  } state_t;

  state_t state;

  logic [ADDR_W-1:0] src_addr_reg;
  logic [ADDR_W-1:0] dst_addr_reg;
  logic [15:0]       length_reg;
  logic [15:0]       word_cnt;

  logic [DATA_W-1:0] read_data_reg;

  // ---------------------------------------------------------
  // DMA FSM
  // ---------------------------------------------------------
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state <= IDLE;

      src_addr_reg  <= '0;
      dst_addr_reg  <= '0;
      length_reg    <= '0;
      word_cnt      <= '0;
      read_data_reg <= '0;

      busy  <= 1'b0;
      done  <= 1'b0;
      error <= 1'b0;

      intf.aw_valid <= 1'b0;
      intf.aw       <= '0;

      intf.w_valid  <= 1'b0;
      intf.w        <= '0;

      intf.b_ready  <= 1'b0;

      intf.ar_valid <= 1'b0;
      intf.ar       <= '0;

      intf.r_ready  <= 1'b0;
    end
    else begin
      done <= 1'b0;

      case (state)

        // ---------------------------------------------------
        // IDLE
        // ---------------------------------------------------
        IDLE: begin
          busy <= 1'b0;

          intf.aw_valid <= 1'b0;
          intf.w_valid  <= 1'b0;
          intf.b_ready  <= 1'b0;
          intf.ar_valid <= 1'b0;
          intf.r_ready  <= 1'b0;

          if (start) begin
            error <= 1'b0;

            // Ignore zero-length transfer: finish immediately
            if (length == 16'd0) begin
              done <= 1'b1;
              busy <= 1'b0;
              state <= IDLE;
            end
            else begin
              src_addr_reg <= src_addr;
              dst_addr_reg <= dst_addr;
              length_reg   <= length;
              word_cnt     <= 16'd0;

              busy <= 1'b1;

              // Issue first single-beat AXI read address
              intf.ar_valid <= 1'b1;
              intf.ar.id    <= '0;
              intf.ar.addr  <= src_addr;
              intf.ar.len   <= 8'd0;       // single beat
              intf.ar.size  <= 3'b010;     // 4 bytes
              intf.ar.burst <= AXI_BURST_INCR;

              state <= READ_AR;
            end
          end
        end

        // ---------------------------------------------------
        // READ ADDRESS
        // ---------------------------------------------------
        READ_AR: begin
          busy <= 1'b1;

          if (intf.ar_valid && intf.ar_ready) begin
            intf.ar_valid <= 1'b0;
            intf.r_ready  <= 1'b1;

            state <= READ_R;
          end
        end

        // ---------------------------------------------------
        // READ DATA
        // ---------------------------------------------------
        READ_R: begin
          busy <= 1'b1;
          intf.r_ready <= 1'b1;

          if (intf.r_valid && intf.r_ready) begin
            read_data_reg <= intf.r.data;

            if (intf.r.resp != AXI_RESP_OKAY) begin
              error <= 1'b1;
            end

            if (intf.r.last) begin
              intf.r_ready <= 1'b0;

              // Issue AXI write address for destination word
              intf.aw_valid <= 1'b1;
              intf.aw.id    <= '0;
              intf.aw.addr  <= dst_addr_reg;
              intf.aw.len   <= 8'd0;       // single beat
              intf.aw.size  <= 3'b010;     // 4 bytes
              intf.aw.burst <= AXI_BURST_INCR;

              state <= WRITE_AW;
            end
          end
        end

        // ---------------------------------------------------
        // WRITE ADDRESS
        // ---------------------------------------------------
        WRITE_AW: begin
          busy <= 1'b1;

          if (intf.aw_valid && intf.aw_ready) begin
            intf.aw_valid <= 1'b0;

            intf.w_valid <= 1'b1;
            intf.w.data  <= read_data_reg;
            intf.w.strb  <= '1;
            intf.w.last  <= 1'b1;

            state <= WRITE_W;
          end
        end

        // ---------------------------------------------------
        // WRITE DATA
        // ---------------------------------------------------
        WRITE_W: begin
          busy <= 1'b1;

          if (intf.w_valid && intf.w_ready) begin
            intf.w_valid <= 1'b0;
            intf.w.last  <= 1'b0;

            intf.b_ready <= 1'b1;

            state <= WRITE_B;
          end
        end

        // ---------------------------------------------------
        // WRITE RESPONSE
        // ---------------------------------------------------
        WRITE_B: begin
          busy <= 1'b1;
          intf.b_ready <= 1'b1;

          if (intf.b_valid && intf.b_ready) begin
            intf.b_ready <= 1'b0;

            if (intf.b.resp != AXI_RESP_OKAY) begin
              error <= 1'b1;
            end

            // Current word completed
            if (word_cnt == (length_reg - 1)) begin
              done <= 1'b1;
              busy <= 1'b0;
              state <= DONE;
            end
            else begin
              word_cnt     <= word_cnt + 1;
              src_addr_reg <= src_addr_reg + 4;
              dst_addr_reg <= dst_addr_reg + 4;

              // Issue next single-beat AXI read
              intf.ar_valid <= 1'b1;
              intf.ar.id    <= '0;
              intf.ar.addr  <= src_addr_reg + 4;
              intf.ar.len   <= 8'd0;
              intf.ar.size  <= 3'b010;
              intf.ar.burst <= AXI_BURST_INCR;

              state <= READ_AR;
            end
          end
        end

        // ---------------------------------------------------
        // DONE
        // ---------------------------------------------------
        DONE: begin
          // done is a one-cycle pulse generated when entering DONE.
          // Return to IDLE after completion.
          busy <= 1'b0;
          state <= IDLE;
        end

        default: begin
          state <= IDLE;
        end

      endcase
    end
  end

endmodule