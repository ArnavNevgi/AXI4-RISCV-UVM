`timescale 1ns/1ps

module alu_tb;

  logic [31:0] a;
  logic [31:0] b;
  logic [2:0]  alu_op;
  logic [31:0] y;
  logic        zero;

  localparam ALU_ADD = 3'b000;
  localparam ALU_SUB = 3'b001;

  int error_count;

  alu dut (
    .a(a),
    .b(b),
    .alu_op(alu_op),
    .y(y),
    .zero(zero)
  );

  initial begin
    error_count = 0;

    // ADD test
    a = 32'd10;
    b = 32'd20;
    alu_op = ALU_ADD;
    #1;

    if (y !== 32'd30) begin
      $error("ADD failed: expected 30 got %0d", y);
      error_count++;
    end

    if (zero !== 1'b0) begin
      $error("ADD zero failed: expected 0 got %0b", zero);
      error_count++;
    end

    // SUB test
    a = 32'd50;
    b = 32'd20;
    alu_op = ALU_SUB;
    #1;

    if (y !== 32'd30) begin
      $error("SUB failed: expected 30 got %0d", y);
      error_count++;
    end

    // zero flag test
    a = 32'd25;
    b = 32'd25;
    alu_op = ALU_SUB;
    #1;

    if (y !== 32'd0) begin
      $error("SUB zero result failed: expected 0 got %0d", y);
      error_count++;
    end

    if (zero !== 1'b1) begin
      $error("zero flag failed: expected 1 got %0b", zero);
      error_count++;
    end

    // default op test
    a = 32'hFFFF_FFFF;
    b = 32'h1234_5678;
    alu_op = 3'b111;
    #1;

    if (y !== 32'h0000_0000) begin
      $error("default op failed: expected 0 got %h", y);
      error_count++;
    end

    if (error_count == 0) begin
      $display("========================================");
      $display("ALU TB PASS");
      $display("ADD/SUB/zero/default verified");
      $display("========================================");
    end
    else begin
      $error("ALU TB FAILED: error_count=%0d", error_count);
    end

    #10;
    $finish;
  end

endmodule