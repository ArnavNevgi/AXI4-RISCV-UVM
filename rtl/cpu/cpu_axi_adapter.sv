import axi_pkg::*;

module cpu_axi_adapter #(
  parameter ID_W   = 4,
  parameter ADDR_W = 32,
  parameter DATA_W = 32
)(
  input  logic clk,
  input  logic rst_n,

  // CPU-side memory request
  input  logic              cpu_valid,
  input  logic              cpu_write,
  input  logic [ADDR_W-1:0] cpu_addr,
  input  logic [DATA_W-1:0] cpu_wdata,
  output logic [DATA_W-1:0] cpu_rdata,
  output logic              cpu_ready,

  // AXI master interface
  axi_if.master intf
);

  typedef enum logic [2:0] {
  IDLE,
  WRITE_AW,
  WRITE_W,
  WRITE_B,
  READ_AR,
  READ_R,
  DONE
} state_t;

  state_t state;

  logic [ADDR_W-1:0] addr_reg;
  logic [DATA_W-1:0] wdata_reg;
  logic              write_reg;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state <= IDLE;

      addr_reg  <= '0;
      wdata_reg <= '0;
      write_reg <= 1'b0;

      cpu_rdata <= '0;
      cpu_ready <= 1'b0;

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
      cpu_ready <= 1'b0;

      case (state)

        // ---------------- IDLE ----------------
        IDLE: begin
          intf.b_ready <= 1'b0;
          intf.r_ready <= 1'b0;

          if (cpu_valid) begin
            addr_reg  <= cpu_addr;
            wdata_reg <= cpu_wdata;
            write_reg <= cpu_write;

            if (cpu_write) begin
              // Single-beat AXI write address
              intf.aw_valid <= 1'b1;
              intf.aw.id    <= '0;
              intf.aw.addr  <= cpu_addr;
              intf.aw.len   <= 8'd0;        // 1 beat
              intf.aw.size  <= 3'b010;      // 4 bytes
              intf.aw.burst <= AXI_BURST_INCR;

              state <= WRITE_AW;
            end
            else begin
              // Single-beat AXI read address
              intf.ar_valid <= 1'b1;
              intf.ar.id    <= '0;
              intf.ar.addr  <= cpu_addr;
              intf.ar.len   <= 8'd0;        // 1 beat
              intf.ar.size  <= 3'b010;      // 4 bytes
              intf.ar.burst <= AXI_BURST_INCR;

              state <= READ_AR;
            end
          end
        end

        // ---------------- WRITE ADDRESS ----------------
        WRITE_AW: begin
          if (intf.aw_valid && intf.aw_ready) begin
            intf.aw_valid <= 1'b0;

            intf.w_valid <= 1'b1;
            intf.w.data  <= wdata_reg;
            intf.w.strb  <= '1;
            intf.w.last  <= 1'b1;

            state <= WRITE_W;
          end
        end

        // ---------------- WRITE DATA ----------------
        WRITE_W: begin
          if (intf.w_valid && intf.w_ready) begin
            intf.w_valid <= 1'b0;
            intf.w.last  <= 1'b0;

            intf.b_ready <= 1'b1;

            state <= WRITE_B;
          end
        end

        // ---------------- WRITE RESPONSE ----------------
        WRITE_B: begin
          intf.b_ready <= 1'b1;

          if (intf.b_valid && intf.b_ready) begin
            intf.b_ready <= 1'b0;

            cpu_ready <= 1'b1;
            state     <= DONE;
            end
        end

        // ---------------- READ ADDRESS ----------------
        READ_AR: begin
          if (intf.ar_valid && intf.ar_ready) begin
            intf.ar_valid <= 1'b0;
            intf.r_ready  <= 1'b1;

            state <= READ_R;
          end
        end

        // ---------------- READ DATA ----------------
        READ_R: begin
          intf.r_ready <= 1'b1;

          if (intf.r_valid && intf.r_ready) begin
            cpu_rdata <= intf.r.data;

            if (intf.r.last) begin
                intf.r_ready <= 1'b0;

                cpu_ready <= 1'b1;
                state     <= DONE;
                end
          end
        end

        DONE: begin
        // Hold cpu_ready high until CPU drops cpu_valid.
        // This prevents accepting the same held-valid request twice.
        cpu_ready <= 1'b1;

        if (!cpu_valid) begin
            cpu_ready <= 1'b0;
            state     <= IDLE;
        end
        end

        default: begin
          state <= IDLE;
        end

      endcase
    end
  end

endmodule