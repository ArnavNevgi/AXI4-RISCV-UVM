import axi_pkg::*;

module axi_lite_reg_slave #(
  parameter ID_W   = 4,
  parameter ADDR_W = 32,
  parameter DATA_W = 32
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
  // 0x04 STATUS
  // 0x08 SRC_ADDR
  // 0x0C DST_ADDR
  // 0x10 LENGTH
  //
  // For now this is a simple readable/writable register block.
  // Later CONTROL/STATUS will connect to DMA control logic.

  localparam logic [ADDR_W-1:0] REG_CONTROL  = 32'h0000_0000;
  localparam logic [ADDR_W-1:0] REG_STATUS   = 32'h0000_0004;
  localparam logic [ADDR_W-1:0] REG_SRC_ADDR = 32'h0000_0008;
  localparam logic [ADDR_W-1:0] REG_DST_ADDR = 32'h0000_000C;
  localparam logic [ADDR_W-1:0] REG_LENGTH   = 32'h0000_0010;

  logic [DATA_W-1:0] control_reg;
  logic [DATA_W-1:0] status_reg;
  logic [DATA_W-1:0] src_addr_reg;
  logic [DATA_W-1:0] dst_addr_reg;
  logic [DATA_W-1:0] length_reg;

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

  // =========================================================
  // Register write helper
  // =========================================================

  task automatic write_register(
    input logic [ADDR_W-1:0] addr,
    input logic [DATA_W-1:0] data
  );
    begin
      case (addr)
        REG_CONTROL:  control_reg  <= data;
        REG_STATUS:   status_reg   <= data;
        REG_SRC_ADDR: src_addr_reg <= data;
        REG_DST_ADDR: dst_addr_reg <= data;
        REG_LENGTH:   length_reg   <= data;
        default: begin
          // Ignore invalid writes for now.
        end
      endcase
    end
  endtask

  // =========================================================
  // Register read helper
  // =========================================================

  function automatic logic [DATA_W-1:0] read_register(
    input logic [ADDR_W-1:0] addr
  );
    begin
      case (addr)
        REG_CONTROL:  read_register = control_reg;
        REG_STATUS:   read_register = status_reg;
        REG_SRC_ADDR: read_register = src_addr_reg;
        REG_DST_ADDR: read_register = dst_addr_reg;
        REG_LENGTH:   read_register = length_reg;
        default:      read_register = '0;
      endcase
    end
  endfunction

  // =========================================================
  // Write FSM: AW/W/B
  // Single-beat AXI-Lite-style write
  // =========================================================

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      w_state <= W_IDLE;

      wr_addr_reg <= '0;
      wr_id_reg   <= '0;

      control_reg  <= '0;
      status_reg   <= '0;
      src_addr_reg <= '0;
      dst_addr_reg <= '0;
      length_reg   <= '0;

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
            write_register(wr_addr_reg, intf.w.data);

            if (!intf.w.last) begin
              $error("AXI-LITE REG ERROR: expected single-beat write with WLAST=1 @ %t",
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
  // Single-beat AXI-Lite-style read
  // =========================================================

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      r_state <= R_IDLE;

      rd_addr_reg <= '0;
      rd_id_reg   <= '0;

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