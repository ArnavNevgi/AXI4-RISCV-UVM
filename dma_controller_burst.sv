import axi_pkg::*;

module dma_controller_burst #(
  parameter ID_W      = 4,
  parameter ADDR_W    = 32,
  parameter DATA_W    = 32,
  parameter MAX_BURST = 16
)(
  input  logic clk,
  input  logic rst_n,

  // Control interface
  input  logic              start,
  input  logic [ADDR_W-1:0] src_addr,
  input  logic [ADDR_W-1:0] dst_addr,
  input  logic [15:0]       length,   // number of 32-bit words, 1 to 16 for now

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

    logic [15:0]       remaining_words;
    logic [7:0]        burst_words;

    logic [7:0] read_cnt;
    logic [7:0] write_cnt;

    logic [DATA_W-1:0] buffer [0:MAX_BURST-1];

    logic [7:0] axi_len;

    assign axi_len = burst_words - 8'd1;


    function automatic logic [7:0] calc_burst_words(input logic [15:0] rem);
  begin
    if (rem >  MAX_BURST[7:0])
      calc_burst_words = 8'd16;
    else
      calc_burst_words = rem[7:0];
  end
    endfunction

  // ---------------------------------------------------------
  // DMA burst FSM
  // ---------------------------------------------------------
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state <= IDLE;

      src_addr_reg <= '0;
      dst_addr_reg <= '0;
      length_reg   <= '0;
      remaining_words <= '0;
      burst_words     <= '0;

      read_cnt  <= '0;
      write_cnt <= '0;

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

          read_cnt  <= '0;
          write_cnt <= '0;

          if (start) begin
            error <= 1'b0;

            if (length == 16'd0) begin
              done  <= 1'b1;
              busy  <= 1'b0;
              state <= IDLE;
            end
                        else begin
            src_addr_reg     <= src_addr;
            dst_addr_reg     <= dst_addr;
            length_reg       <= length;
            remaining_words  <= length;
            burst_words      <= calc_burst_words(length);

            busy <= 1'b1;

            // Issue first AXI read burst
            intf.ar_valid <= 1'b1;
            intf.ar.id    <= '0;
            intf.ar.addr  <= src_addr;
            intf.ar.len   <= calc_burst_words(length) - 8'd1;
            intf.ar.size  <= 3'b010;
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
            read_cnt      <= 0;

            state <= READ_R;
          end
        end

        // ---------------------------------------------------
        // READ DATA BURST
        // ---------------------------------------------------
        READ_R: begin
          busy <= 1'b1;
          intf.r_ready <= 1'b1;

          if (intf.r_valid && intf.r_ready) begin
            buffer[read_cnt] <= intf.r.data;

            if (intf.r.resp != AXI_RESP_OKAY) begin
              error <= 1'b1;
            end

            // RLAST must align with final expected read beat
            if ((read_cnt == axi_len) && !intf.r.last) begin
              error <= 1'b1;
            end

            if ((read_cnt != axi_len) && intf.r.last) begin
              error <= 1'b1;
            end

            if (intf.r.last) begin
              intf.r_ready <= 1'b0;

              // Issue AXI write address burst
              intf.aw_valid <= 1'b1;
              intf.aw.id    <= '0;
              intf.aw.addr  <= dst_addr_reg;
              intf.aw.len   <= axi_len;
              intf.aw.size  <= 3'b010;
              intf.aw.burst <= AXI_BURST_INCR;

              write_cnt <= 0;
              state     <= WRITE_AW;
            end
            else begin
              read_cnt <= read_cnt + 1;
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
            intf.w.data  <= buffer[0];
            intf.w.strb  <= '1;
            intf.w.last  <= (axi_len == 0);

            state <= WRITE_W;
          end
        end

        // ---------------------------------------------------
        // WRITE DATA BURST
        // ---------------------------------------------------
        WRITE_W: begin
          busy <= 1'b1;

          if (intf.w_valid && intf.w_ready) begin

            if (write_cnt == axi_len) begin
              intf.w_valid <= 1'b0;
              intf.w.last  <= 1'b0;

              intf.b_ready <= 1'b1;
              state        <= WRITE_B;
            end
            else begin
              write_cnt <= write_cnt + 1;

              intf.w.data <= buffer[write_cnt + 1];
              intf.w.strb <= '1;
              intf.w.last <= ((write_cnt + 1) == axi_len);
            end
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

            // Completed one burst. Check if full DMA transfer is done.
            if (remaining_words == burst_words) begin
              remaining_words <= 0;

              done  <= 1'b1;
              busy  <= 1'b0;
              state <= DONE;
            end
            else begin
              // More words remain. Advance addresses and issue next read burst.
              remaining_words <= remaining_words - burst_words;

              src_addr_reg <= src_addr_reg + (burst_words << 2);
              dst_addr_reg <= dst_addr_reg + (burst_words << 2);

              burst_words <= calc_burst_words(remaining_words - burst_words);

              read_cnt  <= 0;
              write_cnt <= 0;

              intf.ar_valid <= 1'b1;
              intf.ar.id    <= '0;
              intf.ar.addr  <= src_addr_reg + (burst_words << 2);
              intf.ar.len   <= calc_burst_words(remaining_words - burst_words) - 8'd1;
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
          busy  <= 1'b0;
          state <= IDLE;
        end

        default: begin
          state <= IDLE;
        end

      endcase
    end
  end

endmodule