module control_unit (
  input  logic [31:0] instr,

  output logic        reg_write,
  output logic        mem_read,
  output logic        mem_write,
  output logic        mem_to_reg,
  output logic        imm_to_reg,
  output logic        alu_src,

  output logic [2:0]  alu_op,

  output logic [4:0]  rs1,
  output logic [4:0]  rs2,
  output logic [4:0]  rd,

  output logic [31:0] imm
);

  // Opcodes
  localparam OPCODE_RTYPE = 7'b0110011;
  localparam OPCODE_ITYPE = 7'b0010011; // ADDI
  localparam OPCODE_LW    = 7'b0000011;
  localparam OPCODE_SW    = 7'b0100011;
  localparam OPCODE_LUI   = 7'b0110111;

  // ALU ops
  localparam ALU_ADD = 3'b000;
  localparam ALU_SUB = 3'b001;

  logic [6:0] opcode;
  logic [2:0] funct3;
  logic [6:0] funct7;

  always_comb begin
    opcode = instr[6:0];
    rd     = instr[11:7];
    funct3 = instr[14:12];
    rs1    = instr[19:15];
    rs2    = instr[24:20];
    funct7 = instr[31:25];

    // Defaults = NOP behavior
    reg_write = 1'b0;
    mem_read  = 1'b0;
    mem_write = 1'b0;
    mem_to_reg = 1'b0;
    imm_to_reg = 1'b0;
    alu_src   = 1'b0;
    alu_op    = ALU_ADD;
    imm       = 32'h0000_0000;

    case (opcode)

      // ADD/SUB
      OPCODE_RTYPE: begin
        reg_write  = 1'b1;
        alu_src    = 1'b0;
        mem_to_reg = 1'b0;
        imm_to_reg = 1'b0;

        if (funct3 == 3'b000 && funct7 == 7'b0000000) begin
          alu_op = ALU_ADD; // ADD
        end
        else if (funct3 == 3'b000 && funct7 == 7'b0100000) begin
          alu_op = ALU_SUB; // SUB
        end
        else begin
          reg_write = 1'b0; // unsupported R-type
        end
      end

      // ADDI
      OPCODE_ITYPE: begin
        if (funct3 == 3'b000) begin
          reg_write  = 1'b1;
          mem_read   = 1'b0;
          mem_write  = 1'b0;
          mem_to_reg = 1'b0;
          imm_to_reg = 1'b0;
          alu_src    = 1'b1;
          alu_op     = ALU_ADD;

          // I-type immediate
          imm = {{20{instr[31]}}, instr[31:20]};
        end
      end

      // LUI
      OPCODE_LUI: begin
        reg_write  = 1'b1;
        mem_read   = 1'b0;
        mem_write  = 1'b0;
        mem_to_reg = 1'b0;
        imm_to_reg = 1'b1;
        alu_src    = 1'b0;
        alu_op     = ALU_ADD;

        // U-type immediate
        imm = {instr[31:12], 12'h000};
      end

      // LW
      OPCODE_LW: begin
        if (funct3 == 3'b010) begin
          reg_write  = 1'b1;
          mem_read   = 1'b1;
          mem_write  = 1'b0;
          mem_to_reg = 1'b1;
          imm_to_reg = 1'b0;
          alu_src    = 1'b1;
          alu_op     = ALU_ADD;

          // I-type immediate
          imm = {{20{instr[31]}}, instr[31:20]};
        end
      end

      // SW
      OPCODE_SW: begin
        if (funct3 == 3'b010) begin
          reg_write  = 1'b0;
          mem_read   = 1'b0;
          mem_write  = 1'b1;
          mem_to_reg = 1'b0;
          imm_to_reg = 1'b0;
          alu_src    = 1'b1;
          alu_op     = ALU_ADD;

          // S-type immediate
          imm = {{20{instr[31]}}, instr[31:25], instr[11:7]};
        end
      end

      default: begin
        reg_write  = 1'b0;
        mem_read   = 1'b0;
        mem_write  = 1'b0;
        mem_to_reg = 1'b0;
        imm_to_reg = 1'b0;
        alu_src    = 1'b0;
        alu_op     = ALU_ADD;
        imm        = 32'h0000_0000;
      end

    endcase
  end

endmodule