module riscv_core (
  input  logic        clk,
  input  logic        rst_n,

  // Instruction memory interface
  output logic [31:0] imem_addr,
  input  logic [31:0] imem_rdata,

  // Data memory interface
  output logic        dmem_valid,
  output logic        dmem_write,
  output logic [31:0] dmem_addr,
  output logic [31:0] dmem_wdata,
  input  logic [31:0] dmem_rdata,
  input  logic        dmem_ready,

  // Debug
  output logic [31:0] debug_pc
);

  typedef enum logic [2:0] {
    FETCH,
    DECODE,
    EXECUTE,
    MEM,
    WRITEBACK
  } state_t;

  state_t state;

  logic [31:0] pc;
  logic [31:0] instr_reg;

  logic        reg_write_ctrl;
  logic        mem_read_ctrl;
  logic        mem_write_ctrl;
  logic        mem_to_reg_ctrl;
  logic        alu_src_ctrl;
  logic [2:0]  alu_op_ctrl;

  logic [4:0]  rs1;
  logic [4:0]  rs2;
  logic [4:0]  rd;
  logic [31:0] imm;

  logic [31:0] rs1_data;
  logic [31:0] rs2_data;
  logic [31:0] alu_b;
  logic [31:0] alu_y;
  logic        alu_zero;

  logic [31:0] alu_result_reg;
  logic [31:0] load_data_reg;

  logic        rf_we;
  logic [31:0] rf_wdata;

  assign imem_addr = pc;
  assign debug_pc  = pc;

  assign alu_b = alu_src_ctrl ? imm : rs2_data;

  control_unit u_control (
    .instr(instr_reg),

    .reg_write(reg_write_ctrl),
    .mem_read(mem_read_ctrl),
    .mem_write(mem_write_ctrl),
    .mem_to_reg(mem_to_reg_ctrl),
    .alu_src(alu_src_ctrl),

    .alu_op(alu_op_ctrl),

    .rs1(rs1),
    .rs2(rs2),
    .rd(rd),

    .imm(imm)
  );

  reg_file u_reg_file (
    .clk(clk),
    .rst_n(rst_n),

    .rs1_addr(rs1),
    .rs2_addr(rs2),
    .rd_addr(rd),

    .rd_wdata(rf_wdata),
    .rd_we(rf_we),

    .rs1_rdata(rs1_data),
    .rs2_rdata(rs2_data)
  );

  alu u_alu (
    .a(rs1_data),
    .b(alu_b),
    .alu_op(alu_op_ctrl),
    .y(alu_y),
    .zero(alu_zero)
  );

  always_comb begin
    rf_we    = 1'b0;
    rf_wdata = 32'h0000_0000;

    if (state == WRITEBACK && reg_write_ctrl) begin
      rf_we = 1'b1;

      if (mem_to_reg_ctrl)
        rf_wdata = load_data_reg;
      else
        rf_wdata = alu_result_reg;
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state <= FETCH;
      pc    <= 32'h0000_0000;

      instr_reg     <= 32'h0000_0000;
      alu_result_reg <= 32'h0000_0000;
      load_data_reg  <= 32'h0000_0000;

      dmem_valid <= 1'b0;
      dmem_write <= 1'b0;
      dmem_addr  <= 32'h0000_0000;
      dmem_wdata <= 32'h0000_0000;
    end
    else begin
      case (state)

        FETCH: begin
          instr_reg <= imem_rdata;
          state     <= DECODE;
        end

        DECODE: begin
          state <= EXECUTE;
        end

        EXECUTE: begin
          alu_result_reg <= alu_y;

          if (mem_read_ctrl || mem_write_ctrl) begin
            dmem_valid <= 1'b1;
            dmem_write <= mem_write_ctrl;
            dmem_addr  <= alu_y;
            dmem_wdata <= rs2_data;
            state      <= MEM;
          end
          else begin
            state <= WRITEBACK;
          end
        end

        MEM: begin
          if (dmem_valid && dmem_ready) begin
            dmem_valid <= 1'b0;

            if (mem_read_ctrl)
              load_data_reg <= dmem_rdata;

            state <= WRITEBACK;
          end
        end

        WRITEBACK: begin
          pc    <= pc + 4;
          state <= FETCH;
        end

        default: begin
          state <= FETCH;
        end

      endcase
    end
  end

endmodule