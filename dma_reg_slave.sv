import axi_pkg::*;

module dma_reg_slave #(
  parameter ID_W   = 4,
  parameter ADDR_W = 32,
  parameter DATA_W = 32
)(
  input logic clk,
  input logic rst_n,

  // AXI slave interface
  axi_if.slave intf,

  // DMA control outputs
  output logic        dma_start_pulse,
  output logic [31:0] dma_src_addr,
  output logic [31:0] dma_dst_addr,
  output logic [15:0] dma_length,

  // DMA status inputs
  input  logic        dma_busy,
  input  logic        dma_done,
  input  logic        dma_error
);

  // =========================================================
  // Register map
  // =========================================================
  //
  // 0x00 CONTROL
  //      bit[0] = START, write 1 to start DMA
  //
  // 0x04 STATUS
  //      bit[0] = DONE
  //      bit[1] = BUSY
  //      bit[2] = ERROR
  //
  // 0x08 SRC_ADDR
  // 0x0C DST_ADDR
  // 0x10 LENGTH

  localparam logic [ADDR_W-1:0] REG_CONTROL  = 32'h0000_0000;
  localparam logic [ADDR_W-1:0] REG_STATUS   = 32'h0000_0004;
  localparam logic [ADDR_W-1:0] REG_SRC_ADDR = 32'h0000_0008;
  localparam logic [ADDR_W-1:0] REG_DST_ADDR = 32'h0000_000C;
  localparam logic [ADDR_W-1:0] REG_LENGTH   = 32'h0000_0010;

  logic [31:0] control_reg;
  logic [31:0] src_addr_reg;
  logic [31:0] dst_addr_reg;
  logic [31:0] length_reg;

  logic done_sticky;
  logic error_sticky;

  // Assign DMA control outputs
  assign dma_src_addr = src_addr_reg;
  assign dma_dst_addr = dst_addr_reg;
  assign dma_length   = length_reg[15:0];

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

  logic [ID_W-1:0]   rd_id_reg;
  logic [31:0]       rd_data_reg;

  // =========================================================
  // Status register helper
  // =========================================================

  function automatic logic [31:0] status_word;
    begin
      status_word = 32'h0000_0000;
      status_word[0] = done_sticky;
      status_word[1] = dma_busy;
      status_word[2] = error_sticky;
    end
  endfunction

  // =========================================================
  // Write helper
  // =========================================================

  task automatic write_register(
    input logic [ADDR_W-1:0] addr,
    input logic [DATA_W-1:0] data
  );
    begin
      case (addr)

        REG_CONTROL: begin
          control_reg <= data;

          // Write 1 to CONTROL[0] generates one-cycle start pulse.
          if (data[0]) begin
            dma_start_pulse <= 1'b1;
            done_sticky     <= 1'b0;
            error_sticky    <= 1'b0;
          end
        end

        REG_STATUS: begin
          // Write 1 to STATUS[0] clears DONE sticky bit.
          if (data[0])
            done_sticky <= 1'b0;

          // Write 1 to STATUS[2] clears ERROR sticky bit.
          if (data[2])
            error_sticky <= 1'b0;
        end

        REG_SRC_ADDR: begin
          src_addr_reg <= data;
        end

        REG_DST_ADDR: begin
          dst_addr_reg <= data;
        end

        REG_LENGTH: begin
          length_reg <= data;
        end

        default: begin
          // Invalid writes ignored.
        end

      endcase
    end
  endtask

  // =========================================================
  // Read helper
  // =========================================================

  function automatic logic [31:0] read_register(
    input logic [ADDR_W-1:0] addr
  );
    begin
      case (addr)
        REG_CONTROL:  read_register = control_reg;
        REG_STATUS:   read_register = status_word();
        REG_SRC_ADDR: read_register = src_addr_reg;
        REG_DST_ADDR: read_register = dst_addr_reg;
        REG_LENGTH:   read_register = length_reg;
        default:      read_register = 32'h0000_0000;
      endcase
    end
  endfunction

  // =========================================================
  // Sticky status tracking
  // =========================================================

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      done_sticky  <= 1'b0;
      error_sticky <= 1'b0;
    end
    else begin
      if (dma_done)
        done_sticky <= 1'b1;

      if (dma_error)
        error_sticky <= 1'b1;
    end
  end

  // =========================================================
  // Write FSM: AW/W/B
  // =========================================================

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      w_state <= W_IDLE;

      wr_addr_reg <= '0;
      wr_id_reg   <= '0;

      control_reg     <= '0;
      src_addr_reg    <= '0;
      dst_addr_reg    <= '0;
      length_reg      <= '0;
      dma_start_pulse <= 1'b0;

      intf.aw_ready <= 1'b0;
      intf.w_ready  <= 1'b0;
      intf.b_valid  <= 1'b0;
      intf.b        <= '0;
    end
    else begin
      // Default: start pulse is one cycle only.
      dma_start_pulse <= 1'b0;

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
            write_register(wr_addr_reg, intf.w.data);

            if (!intf.w.last) begin
              $error("DMA REG ERROR: expected single-beat write with WLAST=1 @ %t",
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
  // =========================================================

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      r_state <= R_IDLE;

      rd_id_reg   <= '0;
      rd_data_reg <= '0;

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
            rd_id_reg   <= intf.ar.id;
            rd_data_reg <= read_register(intf.ar.addr);

            intf.ar_ready <= 1'b0;

            intf.r_valid <= 1'b1;
            intf.r.id    <= intf.ar.id;
            intf.r.data  <= read_register(intf.ar.addr);
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
            r_state      <= R_IDLE;
          end
        end

        default: begin
          r_state <= R_IDLE;
        end

      endcase
    end
  end

endmodule
