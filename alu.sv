enum [4:0]
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
    ALUOP_ROR,
    ALUOP_ROLC,
    ALUOP_RORC,
    ALUOP_SHL,
    ALUOP_SHR,
    ALUOP_SHRA,
    ALUOP_SHLA // Does not exist, just ALUOP_SHL
} AluOp;

enum [2:0]
{
    ALU_FLAG_AC,  // Auxiliary carry flag
    ALU_FLAG_CY,  // Carry flag
    ALU_FLAG_V,   // Overflow flag
    ALU_FLAG_P,   // Parity flag
    ALU_FLAG_S,   // Sign flag
    ALU_FLAG_Z    // Zero flag
} AluFlags;


module alu
(
    input [4:0] alu_op,
    input size,
    input [15:0] A,
    input [15:0] B,
    output reg [15:0] R,
    output reg [5:0] flags
);
    // @question: When size == 0, do we modify the contents of the upper byte?
    // Does it matter at all if we write back only the lower byte anyway?
    // I would guess not.

    wire [3:0] msb = (size == 0)? 4'd7: 4'd15;

    always_comb
    begin
        case(alu_op)

            ALUOP_ADD:
                R = A + B;

            ALUOP_SUB:
                R = A - B;

            ALUOP_ROL:
                R = (size == 0)?
                    {A[14:0], A[7]}:
                    {A[14:0], A[7]};

            ALUOP_ROR:
                R = (size == 0)?
                    {A[15:8], A[0], A[7:1]}:
                    {A[0], A[15:1]};

            ALUOP_SHL:
                R = {A[14:0], 1'b0};

            ALUOP_SHR:
            begin
                if(B == 1)
                begin
                    R = (size == 0)?
                        {A[15:8], 1'b0, A[7:1]}:
                        {1'b0, A[15:1]};

                    flags[ALU_FLAG_CY] = A[0];

                    if(A[msb] == 0) flags[ALU_FLAG_V] = 0;
                end
                else
                begin
                    if(B != 0)
                    begin
                        R = (A >> B[4:0]);
                        flags[ALU_FLAG_CY] = A[B[4:0]-1];
                    end
                    else
                    begin
                        R = A;
                        flags[ALU_FLAG_CY] = 0;
                    end
                end
            end

            default:
                R = 16'hFACE;

        endcase
    end

endmodule
