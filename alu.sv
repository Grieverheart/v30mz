enum [3:0]
{
    //ALUOP_PASS_A,
    //ALUOP_PASS_B,
    ALUOP_AND,
    ALUOP_ADD,
    ALUOP_SUB,
    ALUOP_INC,
    ALUOP_DEC,
    ALUOP_NEG,
    ALUOP_ROL,
    ALUOP_ROR
} AluOp;

module alu
(
    input [3:0] alu_op,
    input [15:0] A,
    input [15:0] B,
    output reg [15:0] R
    // @todo: Flags (carry, etc)
    // @todo: input byte_or_word
);
    //wire [16:0] Ae = {A[15], A};
    //wire [16:0] Be = {B[15], B};

    always_comb
    begin
        case(alu_op)

            ALUOP_ADD:
                R = A + B;

            ALUOP_SUB:
                R = A - B;

            ALUOP_ROL:
                R = {A[14:0], A[15]};

            ALUOP_ROR:
                R = {A[0], A[15:1]};

            default:
                R = 16'hFACE;

        endcase
    end

endmodule
