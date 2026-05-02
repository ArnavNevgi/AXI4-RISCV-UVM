import axi_pkg::*;

module simple_fifo_slave #(
  parameter ID_W    = 4,
  parameter ADDR_W  = 32,
  parameter DATA_W  = 32,
  parameter FIFO_DEPTH = 16
)(
  input logic clk,
  input logic rst_n,

  axi_if.slave intf
);

  // =========================================================
  // Register map
  // =========================================================
  //
  // 0x00 CONTROL
  //      bit[0] = clear FIFO
  //
  // 0x04 STATUS
  //      bit[0] = empty
  //      bit[1] = full
  //      bit[2] = overflow
  //      bit[3] = underflow
  //
  // 0x08 TX_DATA
  //      write = push data into FIFO
  //
  // 0x0C RX_DATA
  //      read = pop data from FIFO
  //
  // 0x10 DEPTH
  //      read = FIFO depth parameter

  localparam logic [ADDR_W-1:0] REG_CONTROL = 32'h0000_0000;
  localparam logic [ADDR_W-1:0] REG_STATUS  = 32'h0000_0004;
  localparam logic [ADDR_W-1:0] REG_TX_DATA = 32'h0000_0008;
  localparam logic [ADDR_W-1:0] REG_RX_DATA = 32'h0000_000C;
  localparam logic [ADDR_W-1:0] REG_DEPTH   = 32'h0000_0010;

  // =========================================================
  // FIFO storage
  // =========================================================

  logic [DATA_W-1:0] fifo_mem [0:FIFO_DEPTH-1];

  logic [$clog2(FIFO_DEPTH)-1:0] wr_ptr;
  logic [$clog2(FIFO_DEPTH)-1:0] rd_ptr;
  logic [$clog2(FIFO_DEPTH+1)-1:0] fifo_count;

  logic overflow_flag;
  logic underflow_flag;

  logic fifo_empty;
  logic fifo_full;

  assign fifo_empty = (fifo_count == 0);
  assign fifo_full  = (fifo_count == FIFO_DEPTH);

  // =========================================================
  // Write side
  // =========================================================

  typedef enum logic [1:0] {
    W_IDLE,
    W_DATA,
    W_RESP
  } w_state_t;

  w_state_t w_state;

  logic [ADDR_W-1:0] wr_addr_reg;
  logic [ID_W-1:0]   wr_id_reg;

  // =========================================================
  // Read side
  // =========================================================

  typedef enum logic [1:0] {
    R_IDLE,
    R_RESP
  } r_state_t;

  r_state_t r_state;

  logic [ADDR_W-1:0] rd_addr_reg;
  logic [ID_W-1:0]   rd_id_reg;

  logic [DATA_W-1:0] read_data_reg;

  // =========================================================
  // Helper: status word
  // =========================================================

  function automatic logic [DATA_W-1:0] status_word;
    begin
      status_word = '0;
      status_word[0] = fifo_empty;
      status_word[1] = fifo_full;
      status_word[2] = overflow_flag;
      status_word[3] = underflow_flag;
      status_word[15:8] = fifo_count;
    end
  endfunction

  // =========================================================
  // FIFO / register write helper
  // =========================================================

  task automatic handle_write(
    input logic [ADDR_W-1:0] addr,
    input logic [DATA_W-1:0] data
  );
    begin
      case (addr)

        REG_CONTROL: begin
          if (data[0]) begin
            wr_ptr         <= '0;
            rd_ptr         <= '0;
            fifo_count     <= '0;
            overflow_flag  <= 1'b0;
            underflow_flag <= 1'b0;
          end
        end

        REG_STATUS: begin
          // Write 1 to clear sticky error flags.
          if (data[2])
            overflow_flag <= 1'b0;

          if (data[3])
            underflow_flag <= 1'b0;
        end

        REG_TX_DATA: begin
          if (!fifo_full) begin
            fifo_mem[wr_ptr] <= data;
            wr_ptr <= wr_ptr + 1'b1;
            fifo_count <= fifo_count + 1'b1;
          end
          else begin
            overflow_flag <= 1'b1;
          end
        end

        default: begin
          // Invalid writes ignored.
        end

      endcase
    end
  endtask

  // =========================================================
  // FIFO / register read helper
  // =========================================================

  task automatic handle_read(
    input  logic [ADDR_W-1:0] addr,
    output logic [DATA_W-1:0] data
  );
    begin
      data = '0;

      case (addr)

        REG_CONTROL: begin
          data = '0;
        end

        REG_STATUS: begin
          data = status_word();
        end

        REG_RX_DATA: begin
          if (!fifo_empty) begin
            data = fifo_mem[rd_ptr];
            rd_ptr <= rd_ptr + 1'b1;
            fifo_count <= fifo_count - 1'b1;
          end
          else begin
            data = '0;
            underflow_flag <= 1'b1;
          end
        end

        REG_DEPTH: begin
          data = FIFO_DEPTH;
        end

        default: begin
          data = '0;
        end

      endcase
    end
  endtask

  // =========================================================
  // Write FSM: AW/W/B
  // Single-beat AXI-Lite-style writes
  // =========================================================

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      w_state <= W_IDLE;

      wr_addr_reg <= '0;
      wr_id_reg   <= '0;

      wr_ptr         <= '0;
      fifo_count     <= '0;
      overflow_flag  <= 1'b0;

      intf.aw_ready <= 1'b0;
      intf.w_ready  <= 1'b0;
      intf.b_valid  <= 1'b0;
      intf.b        <= '0;
    end
    else begin
      case (w_state)

        W_IDLE: begin
          intf.aw_ready <= 1'b1;
          intf.w_ready  <= 1'b0;
          intf.b_valid  <= 1'b0;

          if (intf.aw_valid && intf.aw_ready) begin
            wr_addr_reg <= intf.aw.addr;
            wr_id_reg   <= intf.aw.id;

            intf.aw_ready <= 1'b0;
            intf.w_ready  <= 1'b1;

            w_state <= W_DATA;
          end
        end

        W_DATA: begin
          intf.aw_ready <= 1'b0;
          intf.w_ready  <= 1'b1;

          if (intf.w_valid && intf.w_ready) begin
            handle_write(wr_addr_reg, intf.w.data);

            if (!intf.w.last) begin
              $error("FIFO SLAVE ERROR: expected single-beat write with WLAST=1 @ %t",
                     $time);
            end

            intf.w_ready <= 1'b0;

            intf.b_valid <= 1'b1;
            intf.b.id    <= wr_id_reg;
            intf.b.resp  <= AXI_RESP_OKAY;

            w_state <= W_RESP;
          end
        end

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

  // =========================================================
  // Read FSM: AR/R
  // Single-beat AXI-Lite-style reads
  // =========================================================

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      r_state <= R_IDLE;

      rd_addr_reg   <= '0;
      rd_id_reg     <= '0;
      read_data_reg <= '0;

      rd_ptr         <= '0;
      underflow_flag <= 1'b0;

      intf.ar_ready <= 1'b0;
      intf.r_valid  <= 1'b0;
      intf.r        <= '0;
    end
    else begin
      case (r_state)

        R_IDLE: begin
          intf.ar_ready <= 1'b1;
          intf.r_valid  <= 1'b0;
          intf.r.last   <= 1'b0;

          if (intf.ar_valid && intf.ar_ready) begin
            rd_addr_reg <= intf.ar.addr;
            rd_id_reg   <= intf.ar.id;

            handle_read(intf.ar.addr, read_data_reg);

            intf.ar_ready <= 1'b0;

            intf.r_valid <= 1'b1;
            intf.r.id    <= intf.ar.id;
            intf.r.data  <= read_data_reg;
            intf.r.resp  <= AXI_RESP_OKAY;
            intf.r.last  <= 1'b1;

            r_state <= R_RESP;
          end
        end

        R_RESP: begin
          intf.ar_ready <= 1'b0;

          if (intf.r_valid && intf.r_ready) begin
            intf.r_valid <= 1'b0;
            intf.r.last  <= 1'b0;

            r_state <= R_IDLE;
          end
        end

        default: begin
          r_state <= R_IDLE;
        end

      endcase
    end
  end

endmodule