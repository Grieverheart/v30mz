enum [3:0]
{
    //ALUOP_PASS_A,
    //ALUOP_PASS_B,
    ALUOP_ADD,
    ALUOP_SUB,
    ALUOP_SHL,
    ALUOP_SHR,
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
);
    wire [16:0] Ae = {A[15], A};
    wire [16:0] Be = {B[15], B};

    always_comb
    begin
        case(alu_op)

            ALUOP_ADD:
                R = A + B;

            ALUOP_SUB:
                R = A - B;

            ALUOP_ROL:
                R = {{Ae << 1}[15:1], Ae[16]};

            ALUOP_ROR:
                R = {Ae[0], {Ae >> 1}[14:0]};

            ALUOP_SHL:
                R = A << 1;

            ALUOP_SHR:
                R = A >> 1;

            default:
                R = 16'hFACE;

        endcase
    end

endmodule
