module alu (
  input  logic [31:0] a,
  input  logic [31:0] b,
  input  logic [2:0]  alu_op,
  output logic [31:0] y,
  output logic        zero
);

  localparam ALU_ADD = 3'b000;
  localparam ALU_SUB = 3'b001;

  always_comb begin
    case (alu_op)
      ALU_ADD: y = a + b;
      ALU_SUB: y = a - b;
      default: y = 32'h0000_0000;
    endcase
  end

  assign zero = (y == 32'h0000_0000);

endmodule