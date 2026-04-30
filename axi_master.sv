import axi_pkg::*;
module axi_master #(
  parameter ID_W   = 4,
  parameter ADDR_W = 32,
  parameter DATA_W = 32
)(
  input  logic clk,
  input  logic rst_n,

// Simple request interface
input  logic                 wr_en,
input  logic [ADDR_W-1:0]    wr_addr,
input  logic [DATA_W-1:0]    wr_data,
input  logic [7:0]           wr_len,
output logic                 wr_done,

input  logic                 rd_en,
input  logic [ADDR_W-1:0]    rd_addr,
input  logic [7:0]           rd_len,
output logic [DATA_W-1:0]    rd_data,
output logic                 rd_done,


  // AXI interface
  axi_if.master intf
);

logic [7:0] burst_len;
logic [7:0] beat_cnt;
logic [7:0] rd_cnt;
logic [DATA_W-1:0] data_reg;
logic [DATA_W-1:0] wdata_reg;
logic [DATA_W-1:0] next_wdata;


  typedef enum logic [2:0] {
    IDLE,
    AW,
    W,
    B,
    AR,
    R
  } state_t;

  state_t state;

  // ---------------- WRITE FSM ----------------
always_ff @(posedge clk or negedge rst_n) begin
  if (!rst_n) begin
    state <= IDLE;

    intf.aw_valid <= 0;
    intf.w_valid  <= 0;
    intf.b_ready  <= 0;

    intf.ar_valid <= 0;
    intf.r_ready  <= 0;

    intf.aw       <= '0;
    intf.w        <= '0;
    intf.ar       <= '0;

    wr_done <= 0;
    rd_done <= 0;

    beat_cnt <= 0;
    burst_len <= 0;
    data_reg <= 0;

  end else begin
    wr_done <= 0;
    rd_done <= 0;

    case (state)

      // ---------------- IDLE ----------------
      IDLE: begin
        intf.b_ready <= 0;

        if (wr_en) begin
          intf.aw_valid <= 1;
          intf.aw.addr  <= wr_addr;
          intf.aw.id    <= 0;
          intf.aw.len   <= wr_len;
          intf.aw.size  <= 3'b010;         // 4 bytes
          intf.aw.burst <= AXI_BURST_INCR;

          burst_len <= wr_len;;
          data_reg  <= wr_data;

          state <= AW;
        end

        else if (rd_en) begin
          intf.ar_valid <= 1;
          intf.ar.addr  <= rd_addr;
          intf.ar.id    <= 1;
          intf.ar.len   <= rd_len;
          intf.ar.size  <= 3'b010;
          intf.ar.burst <= AXI_BURST_INCR;

          burst_len <= rd_len;

          state <= AR;
        end
      end

      // ---------------- WRITE ADDRESS ----------------
      AW: begin
        if (intf.aw_valid && intf.aw_ready) begin
          intf.aw_valid <= 0;

          beat_cnt <= 0;

          intf.w_valid <= 1;
          intf.w.data  <= data_reg;
          intf.w.strb  <= '1;
          intf.w.last  <= (burst_len == 0);

          state <= W;
        end
      end

      // ---------------- WRITE DATA ----------------
      W: begin
        if (intf.w_valid && intf.w_ready) begin

          if (beat_cnt == burst_len) begin
            intf.w_valid <= 0;
            intf.w.last  <= 0;

            intf.b_ready <= 1;
            state <= B;
          end
          else begin
            beat_cnt <= beat_cnt + 1;

            intf.w.data <= data_reg + (beat_cnt + 1);
            intf.w.strb <= '1;
            intf.w.last <= ((beat_cnt + 1) == burst_len);
          end

        end
      end

      // ---------------- WRITE RESPONSE ----------------
      B: begin
        intf.b_ready <= 1;

        if (intf.b_valid && intf.b_ready) begin
          intf.b_ready <= 0;
          wr_done      <= 1;
          state        <= IDLE;
        end
      end

      AR: begin
        if (intf.ar_valid && intf.ar_ready) begin
          intf.ar_valid <= 0;

          rd_cnt <= 0;
          intf.r_ready <= 1;

          state <= R;
        end
      end

      R: begin
        if (intf.r_valid && intf.r_ready) begin
          rd_data <= intf.r.data;

          if (intf.r.last) begin
            intf.r_ready <= 0;
            rd_done <= 1;
            state <= IDLE;
          end

          rd_cnt <= rd_cnt + 1;
        end
      end

    endcase
  end
end
endmodule