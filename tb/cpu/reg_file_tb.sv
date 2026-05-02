`timescale 1ns/1ps

module reg_file_tb;

  logic        clk;
  logic        rst_n;

  logic [4:0]  rs1_addr;
  logic [4:0]  rs2_addr;
  logic [4:0]  rd_addr;

  logic [31:0] rd_wdata;
  logic        rd_we;

  logic [31:0] rs1_rdata;
  logic [31:0] rs2_rdata;

  int error_count;

  reg_file dut (
    .clk(clk),
    .rst_n(rst_n),

    .rs1_addr(rs1_addr),
    .rs2_addr(rs2_addr),
    .rd_addr(rd_addr),

    .rd_wdata(rd_wdata),
    .rd_we(rd_we),

    .rs1_rdata(rs1_rdata),
    .rs2_rdata(rs2_rdata)
  );

  initial clk = 0;
  always #5 clk = ~clk;

  task automatic check_equal(
    input logic [31:0] actual,
    input logic [31:0] expected,
    input string       msg
  );
    begin
      if (actual !== expected) begin
        $error("%s failed: expected=%h got=%h", msg, expected, actual);
        error_count++;
      end
      else begin
        $display("%s passed: value=%h", msg, actual);
      end
    end
  endtask

  initial begin
    error_count = 0;

    rs1_addr = 0;
    rs2_addr = 0;
    rd_addr  = 0;
    rd_wdata = 0;
    rd_we    = 0;

    rst_n = 0;
    repeat (2) @(posedge clk);
    rst_n = 1;
    @(posedge clk);

    // After reset, all registers should read 0
    rs1_addr = 5'd1;
    rs2_addr = 5'd2;
    #1;
    check_equal(rs1_rdata, 32'h0000_0000, "reset read x1");
    check_equal(rs2_rdata, 32'h0000_0000, "reset read x2");

    // Write x1 = AAAAAAAA
    @(posedge clk);
    rd_we    <= 1;
    rd_addr  <= 5'd1;
    rd_wdata <= 32'hAAAA_AAAA;

    @(posedge clk);
    rd_we <= 0;

    rs1_addr = 5'd1;
    #1;
    check_equal(rs1_rdata, 32'hAAAA_AAAA, "write/read x1");

    // Write x2 = 12345678
    @(posedge clk);
    rd_we    <= 1;
    rd_addr  <= 5'd2;
    rd_wdata <= 32'h1234_5678;

    @(posedge clk);
    rd_we <= 0;

    rs1_addr = 5'd1;
    rs2_addr = 5'd2;
    #1;
    check_equal(rs1_rdata, 32'hAAAA_AAAA, "read port 1 x1");
    check_equal(rs2_rdata, 32'h1234_5678, "read port 2 x2");

    // Try writing x0. It must remain zero.
    @(posedge clk);
    rd_we    <= 1;
    rd_addr  <= 5'd0;
    rd_wdata <= 32'hFFFF_FFFF;

    @(posedge clk);
    rd_we <= 0;

    rs1_addr = 5'd0;
    #1;
    check_equal(rs1_rdata, 32'h0000_0000, "x0 hardwired zero");

    // Write disabled: x3 should not change
    @(posedge clk);
    rd_we    <= 0;
    rd_addr  <= 5'd3;
    rd_wdata <= 32'hDEAD_BEEF;

    @(posedge clk);

    rs1_addr = 5'd3;
    #1;
    check_equal(rs1_rdata, 32'h0000_0000, "write disabled x3");

    if (error_count == 0) begin
      $display("========================================");
      $display("REG FILE TB PASS");
      $display("reset/write/read/x0/write-disable verified");
      $display("========================================");
    end
    else begin
      $error("REG FILE TB FAILED: error_count=%0d", error_count);
    end

    #10;
    $finish;
  end

endmodule