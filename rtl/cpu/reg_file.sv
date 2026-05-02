module reg_file (
  input  logic        clk,
  input  logic        rst_n,

  input  logic [4:0]  rs1_addr,
  input  logic [4:0]  rs2_addr,
  input  logic [4:0]  rd_addr,

  input  logic [31:0] rd_wdata,
  input  logic        rd_we,

  output logic [31:0] rs1_rdata,
  output logic [31:0] rs2_rdata
);

  logic [31:0] regs [0:31];

  integer i;

  // Write / reset logic
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (i = 0; i < 32; i = i + 1) begin
        regs[i] <= 32'h0000_0000;
      end
    end
    else begin
      if (rd_we && (rd_addr != 5'd0)) begin
        regs[rd_addr] <= rd_wdata;
      end
    end
  end

  // Async read ports
  always_comb begin
    if (rs1_addr == 5'd0)
      rs1_rdata = 32'h0000_0000;
    else
      rs1_rdata = regs[rs1_addr];

    if (rs2_addr == 5'd0)
      rs2_rdata = 32'h0000_0000;
    else
      rs2_rdata = regs[rs2_addr];
  end

endmodule