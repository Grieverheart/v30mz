enum [3:0]
{
    //ALUOP_PASS_A,
    //ALUOP_PASS_B,
    ALUOP_ADD,
    ALUOP_SUB,
    ALUOP_SHIFT_LEFT,
    ALUOP_SHIFT_RIGHT
} AluOp;

module alu
(
    input [3:0] alu_op,
    input [15:0] A,
    input [15:0] B,
    output reg [15:0] R
    // @todo: Flags (carry, etc)
);
    always_comb
    begin
        case(alu_op)

            ALUOP_ADD:
                R = A + B;

            ALUOP_SUB:
                R = A - B;

            ALUOP_SHIFT_LEFT:
                R = A << 1;

            ALUOP_SHIFT_RIGHT:
                R = A >> 1;

            default:
                R = 16'hFACE;

        endcase
    end

endmodule
