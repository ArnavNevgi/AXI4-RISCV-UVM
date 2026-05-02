`timescale 1ns/1ps

module control_unit_tb;

  logic [31:0] instr;

  logic        reg_write;
  logic        mem_read;
  logic        mem_write;
  logic        mem_to_reg;
  logic        alu_src;
  logic [2:0]  alu_op;
  logic [4:0]  rs1;
  logic [4:0]  rs2;
  logic [4:0]  rd;
  logic [31:0] imm;

  control_unit dut (
    .instr(instr),

    .reg_write(reg_write),
    .mem_read(mem_read),
    .mem_write(mem_write),
    .mem_to_reg(mem_to_reg),
    .alu_src(alu_src),

    .alu_op(alu_op),

    .rs1(rs1),
    .rs2(rs2),
    .rd(rd),

    .imm(imm)
  );

  localparam ALU_ADD = 3'b000;
  localparam ALU_SUB = 3'b001;

  int error_count;

  task automatic check_rtype_add;
    begin
      // add x3, x1, x2
      // funct7=0000000 rs2=2 rs1=1 funct3=000 rd=3 opcode=0110011
      instr = 32'b0000000_00010_00001_000_00011_0110011;
      #1;

      if (reg_write !== 1'b1) begin
        $error("ADD failed: reg_write expected 1 got %0b", reg_write);
        error_count++;
      end
      if (mem_read !== 1'b0) begin
        $error("ADD failed: mem_read expected 0 got %0b", mem_read);
        error_count++;
      end
      if (mem_write !== 1'b0) begin
        $error("ADD failed: mem_write expected 0 got %0b", mem_write);
        error_count++;
      end
      if (mem_to_reg !== 1'b0) begin
        $error("ADD failed: mem_to_reg expected 0 got %0b", mem_to_reg);
        error_count++;
      end
      if (alu_src !== 1'b0) begin
        $error("ADD failed: alu_src expected 0 got %0b", alu_src);
        error_count++;
      end
      if (alu_op !== ALU_ADD) begin
        $error("ADD failed: alu_op expected ADD got %0b", alu_op);
        error_count++;
      end
      if (rs1 !== 5'd1 || rs2 !== 5'd2 || rd !== 5'd3) begin
        $error("ADD failed: rs1/rs2/rd wrong. rs1=%0d rs2=%0d rd=%0d",
               rs1, rs2, rd);
        error_count++;
      end

      $display("ADD decode checked");
    end
  endtask

  task automatic check_rtype_sub;
    begin
      // sub x5, x6, x7
      // funct7=0100000 rs2=7 rs1=6 funct3=000 rd=5 opcode=0110011
      instr = 32'b0100000_00111_00110_000_00101_0110011;
      #1;

      if (reg_write !== 1'b1) begin
        $error("SUB failed: reg_write expected 1 got %0b", reg_write);
        error_count++;
      end
      if (mem_read !== 1'b0) begin
        $error("SUB failed: mem_read expected 0 got %0b", mem_read);
        error_count++;
      end
      if (mem_write !== 1'b0) begin
        $error("SUB failed: mem_write expected 0 got %0b", mem_write);
        error_count++;
      end
      if (alu_src !== 1'b0) begin
        $error("SUB failed: alu_src expected 0 got %0b", alu_src);
        error_count++;
      end
      if (alu_op !== ALU_SUB) begin
        $error("SUB failed: alu_op expected SUB got %0b", alu_op);
        error_count++;
      end
      if (rs1 !== 5'd6 || rs2 !== 5'd7 || rd !== 5'd5) begin
        $error("SUB failed: rs1/rs2/rd wrong. rs1=%0d rs2=%0d rd=%0d",
               rs1, rs2, rd);
        error_count++;
      end

      $display("SUB decode checked");
    end
  endtask

  task automatic check_lw;
    begin
      // lw x8, 16(x9)
      // imm=16 rs1=9 funct3=010 rd=8 opcode=0000011
      instr = 32'b000000010000_01001_010_01000_0000011;
      #1;

      if (reg_write !== 1'b1) begin
        $error("LW failed: reg_write expected 1 got %0b", reg_write);
        error_count++;
      end
      if (mem_read !== 1'b1) begin
        $error("LW failed: mem_read expected 1 got %0b", mem_read);
        error_count++;
      end
      if (mem_write !== 1'b0) begin
        $error("LW failed: mem_write expected 0 got %0b", mem_write);
        error_count++;
      end
      if (mem_to_reg !== 1'b1) begin
        $error("LW failed: mem_to_reg expected 1 got %0b", mem_to_reg);
        error_count++;
      end
      if (alu_src !== 1'b1) begin
        $error("LW failed: alu_src expected 1 got %0b", alu_src);
        error_count++;
      end
      if (alu_op !== ALU_ADD) begin
        $error("LW failed: alu_op expected ADD got %0b", alu_op);
        error_count++;
      end
      if (rs1 !== 5'd9 || rd !== 5'd8) begin
        $error("LW failed: rs1/rd wrong. rs1=%0d rd=%0d", rs1, rd);
        error_count++;
      end
      if (imm !== 32'd16) begin
        $error("LW failed: imm expected 16 got %0d", imm);
        error_count++;
      end

      $display("LW decode checked");
    end
  endtask

  task automatic check_sw;
    begin
      // sw x10, 20(x11)
      // imm=20 rs2=10 rs1=11 funct3=010 opcode=0100011
      // imm[11:5]=0000000, imm[4:0]=10100
      instr = 32'b0000000_01010_01011_010_10100_0100011;
      #1;

      if (reg_write !== 1'b0) begin
        $error("SW failed: reg_write expected 0 got %0b", reg_write);
        error_count++;
      end
      if (mem_read !== 1'b0) begin
        $error("SW failed: mem_read expected 0 got %0b", mem_read);
        error_count++;
      end
      if (mem_write !== 1'b1) begin
        $error("SW failed: mem_write expected 1 got %0b", mem_write);
        error_count++;
      end
      if (mem_to_reg !== 1'b0) begin
        $error("SW failed: mem_to_reg expected 0 got %0b", mem_to_reg);
        error_count++;
      end
      if (alu_src !== 1'b1) begin
        $error("SW failed: alu_src expected 1 got %0b", alu_src);
        error_count++;
      end
      if (alu_op !== ALU_ADD) begin
        $error("SW failed: alu_op expected ADD got %0b", alu_op);
        error_count++;
      end
      if (rs1 !== 5'd11 || rs2 !== 5'd10) begin
        $error("SW failed: rs1/rs2 wrong. rs1=%0d rs2=%0d", rs1, rs2);
        error_count++;
      end
      if (imm !== 32'd20) begin
        $error("SW failed: imm expected 20 got %0d", imm);
        error_count++;
      end

      $display("SW decode checked");
    end
  endtask

  initial begin
    error_count = 0;
    instr = 32'h0000_0000;
    #1;

    check_rtype_add();
    check_rtype_sub();
    check_lw();
    check_sw();

    if (error_count == 0) begin
      $display("========================================");
      $display("CONTROL UNIT TB PASS");
      $display("ADD/SUB/LW/SW decode verified");
      $display("========================================");
    end
    else begin
      $error("CONTROL UNIT TB FAILED: error_count=%0d", error_count);
    end

    #10;
    $finish;
  end

endmodule