
enum [2:0]
{
    BUS_COMMAND_IDLE      = 3'd0,
    BUS_COMMAND_MEM_READ  = 3'd1,
    BUS_COMMAND_MEM_WRITE = 3'd2,
    BUS_COMMAND_IO_READ   = 3'd3,
    BUS_COMMAND_IO_WRITE  = 3'd4
} BusCommand;

`define assert(signal, value) \
    if (signal !== value) begin \
        $display("ASSERTION FAILED in %m: signal != value"); \
        $finish; \
    end

module execution_unit
(
    input clk,
    input reset,

    // Prefetch queue
    input [7:0] prefetch_data,
    input queue_empty,
    output queue_pop,
    output reg queue_suspend,
    output reg queue_flush,

    // Program counter
    // The PC is a 16-bit binary counter that holds the offset
    // information of the memory address of the program that the
    // execution unit (EXU) is about to execute.
    output reg [15:0] PC,

    // Segment register input and output
    input [15:0] segment_registers[0:3],
    output [15:0] sregfile_write_data,
    output [1:0] sregfile_write_id,
    output reg sregfile_we,

    // Execution status
    output instruction_nearly_done,

    // Bus
    output reg [2:0]  bus_command,
    output reg [19:0] bus_address,
    // @todo: Should we just assign this to mov_dst_size ?
    output reg bus_upper_byte_enable,
    output reg [15:0] data_out,

    input [15:0] data_in,
    input bus_command_done
);

    localparam [2:0]
        STATE_OPCODE_READ    = 3'd0,
        STATE_MODRM_READ     = 3'd1,
        STATE_DISP_LOW_READ  = 3'd2,
        STATE_DISP_HIGH_READ = 3'd3,
        STATE_IMM_LOW_READ   = 3'd4,
        STATE_IMM_HIGH_READ  = 3'd5,
        STATE_EXECUTE        = 3'd6;

    localparam [2:0]
        READ_SRC_REG  = 3'd0,
        READ_SRC_SREG = 3'd1,
        READ_SRC_PC   = 3'd2,
        READ_SRC_IMM  = 3'd3,
        READ_SRC_DISP = 3'd4,
        READ_SRC_MEM  = 3'd5,
        READ_SRC_ALU  = 3'd6,
        READ_SRC_TMP  = 3'd7;

    //localparam [2:0]
    //    LJUMP_COND_UNC = 3'd0,
    //        ...

    reg [7:0] opcode;
    reg [7:0] modrm;
    reg [15:0] imm;
    reg [15:0] disp;
    reg [15:0] error;

    wire has_prefix;
    wire need_modrm;
    wire need_disp;
    wire need_imm;
    wire imm_size;
    wire disp_size;

    // Effective address registers
    wire [3:0] ea_base_reg;
    wire [3:0] ea_index_reg;
    wire [1:0] ea_segment_reg;

    wire [3:0] src_operand;
    wire [3:0] dst_operand;

    wire byte_word_field;

    reg [2:0] state;

    always_latch
    begin
        // @todo: check prefix.
        if(state == STATE_OPCODE_READ)         opcode     = prefetch_data;
        else if(state == STATE_MODRM_READ)     modrm      = prefetch_data;
        else if(state == STATE_DISP_LOW_READ)  disp[7:0]  = prefetch_data;
        else if(state == STATE_DISP_HIGH_READ) disp[15:8] = prefetch_data;
        else if(state == STATE_IMM_LOW_READ)   imm[7:0]   = prefetch_data;
        else if(state == STATE_IMM_HIGH_READ)  imm[15:8]  = prefetch_data;
    end

    // It also makes it easier at initialization, as the opcode takes the
    // value in prefetch_data, at least if it's not empty.

    // @todo: Perhaps we should have the decoder set the appropriate 'factors'
    // value for the physical address calculation.
    decode decode_inst
    (
        .opcode,
        .modrm,

        .need_modrm,

        .need_disp,
        .disp_size,

        .need_imm,
        .imm_size,

        .src(src_operand),
        .dst(dst_operand),

        .byte_word_field(byte_word_field)
    );


    wire [1:0] mod  = modrm[7:6];
    wire [2:0] regm = modrm[5:3];
    wire [2:0] rm   = modrm[2:0];

    // @todo: In principle, we should be able to overlap execution with next
    // opcode read if the last microcode is not a read/write operation.
    // Perhaps we can change state_opcode_read to being a separate wire
    // opcode_read which can be turned on if the instruction is nearly done or
    // done.

    wire [2:0] next_state =
        (state == STATE_OPCODE_READ) ?
            (need_modrm  ? STATE_MODRM_READ:
            (need_disp   ? STATE_DISP_LOW_READ:
            (need_imm    ? STATE_IMM_LOW_READ:
                           STATE_EXECUTE))):

        (state == STATE_MODRM_READ) ?
            (need_disp   ? STATE_DISP_LOW_READ:
            (need_imm    ? STATE_IMM_LOW_READ:
                           STATE_EXECUTE)):

        (state == STATE_DISP_LOW_READ) ?
            (disp_size   ? STATE_DISP_HIGH_READ:
            (need_imm    ? STATE_IMM_LOW_READ:
                           STATE_EXECUTE)):

        (state == STATE_DISP_HIGH_READ) ?
            (need_imm    ? STATE_IMM_LOW_READ:
                           STATE_EXECUTE):

        (state == STATE_IMM_LOW_READ) ?
            (imm_size    ? STATE_IMM_HIGH_READ:
                           STATE_EXECUTE):

        (state == STATE_IMM_HIGH_READ) ?
                           STATE_EXECUTE:
                           STATE_OPCODE_READ;

    // @info: The opcode is translated directly to a rom address. This can be done by
    //creating a rom of size 256 indexed by the opcode, where the value is
    //equal to the microcode rom address.

    reg [8:0] translation_rom[0:255];
    reg [8:0] jump_table[0:15];
    reg [21:0] rom[0:511];

    localparam [2:0]
        MICRO_TYPE_MISC = 3'b001,
        MICRO_TYPE_BUS  = 3'b110,
        MICRO_TYPE_JMP  = 3'b101;

    localparam [1:0]
        MICRO_TYPE_ALU = 2'b01;

    localparam [4:0]
        MICRO_MOV_NONE = 5'h00,
        // register specified by r field of modrm.
        MICRO_MOV_R    = 5'h01,
        // register or memory specified by rm field of modrm.
        MICRO_MOV_RM   = 5'h02,

        // disp value specified by opcode bytes. Cannot be destination.
        MICRO_MOV_DISP = 5'h03,
        MICRO_MOV_DO   = 5'h03,

        // imm value specified by opcode bytes. Cannot be destination.
        MICRO_MOV_IMM   = 5'h04,
        MICRO_MOV_ADD   = 5'h04,

        MICRO_MOV_DI    = 5'h05,

        MICRO_MOV_ALU_A = 5'h06,
        MICRO_MOV_ALU_R = 5'h07,
        MICRO_MOV_ZERO  = 5'h08,
        MICRO_MOV_ONES  = 5'h09,
        MICRO_MOV_TWOS  = 5'h10,

        // all registers:
        MICRO_MOV_AL    = 5'h11,
        MICRO_MOV_AH    = 5'h12,

        MICRO_MOV_AW    = 5'h13,
        MICRO_MOV_CW    = 5'h14,
        MICRO_MOV_DW    = 5'h15,
        MICRO_MOV_BW    = 5'h16,

        MICRO_MOV_SP    = 5'h17,
        MICRO_MOV_BP    = 5'h18,
        MICRO_MOV_IX    = 5'h19,
        MICRO_MOV_IY    = 5'h1a,

        MICRO_MOV_DS1   = 5'h1b,
        MICRO_MOV_PS    = 5'h1c,
        MICRO_MOV_SS    = 5'h1d,
        MICRO_MOV_DS0   = 5'h1e,

        MICRO_MOV_PC    = 5'h1f;

    localparam [3:0]
        MICRO_MISC_OP_A_NONE  = 4'h0,
        MICRO_MISC_OP_A_FLUSH = 4'h1;

    localparam [2:0]
        MICRO_MISC_OP_B_NONE  = 3'h0,
        MICRO_MISC_OP_B_SUSP  = 3'h1;

    localparam [1:0]
        MICRO_BUS_OP_MEM_READ  = 2'h0,
        MICRO_BUS_OP_MEM_WRITE = 2'h1,
        MICRO_BUS_OP_IO_READ   = 2'h2,
        MICRO_BUS_OP_IO_WRITE  = 2'h3;

    localparam
        MICRO_ALU_IGNORE_RESULT = 1'b0,
        MICRO_ALU_USE_RESULT    = 1'b1;

    localparam
        MICRO_JMP_XC = 3'd0,
        MICRO_JMP_UC = 3'd1;

    // @note:
    // Alu ops used by 8086 microcode.
    //
    // 'XI', 'AND', 'ADD', 'SUBT', 'INC', 'INC2', 'DEC', 'DEC2', 'NEG', 'LRCY', 'RRCY', 'XZC', 'COM1', 'PASS'
    //
    localparam [4:0]
        MICRO_ALU_OP_NONE = 5'h0,
        MICRO_ALU_OP_XI   = 5'h1,
        MICRO_ALU_OP_AND  = 5'h2,
        MICRO_ALU_OP_ADD  = 5'h3,
        MICRO_ALU_OP_SUB  = 5'h4,
        MICRO_ALU_OP_INC  = 5'h5,
        MICRO_ALU_OP_DEC  = 5'h6,
        MICRO_ALU_OP_NEG  = 5'h7,
        MICRO_ALU_OP_ROL  = 5'h8,
        MICRO_ALU_OP_ROR  = 5'h9;

        // @note: Still need these, I think:
        //     MICRO_MOV_PSW  = 5'h18,
        //     MICRO_MOV_EA   = 5'h19,
        //     MICRO_MOV_ALUR = 5'h1a,
        //     MICRO_MOV_ALUX = 5'h1b,
        //     MICRO_MOV_ALUY = 5'h1c,
        //
        // The 8086 microcode seems to even introduce some temporary registers
        // and does not explicitly use the upper and lower half of the
        // registers b, c, and d. In total, 26 values for src and 26 values
        // for dst are used. The combined src and dst refer to a combined 33
        // unique values, so a common coding for both is not possible with 5
        // bits. I think it's best to encode the common ones, and for the
        // others, introduce combination values, e.g. MICRO_MOV_ES_OR_SIGMA.
        // This brings the number of unique values to about 25. The move src
        // never seems to refer to bw, and bp, though. If I add them to the
        // common registers, it would increase them to 21. I could do the same
        // with the 3 remaining segment registers, making the total of 24, and
        // 5 dst and 4  src registers. With a total of 29 registers, we should
        // be then fine. That's 2 short of the 31 total.
        //
        // Note that the 8086 microcode also includes references to microcode
        // address registers, namely an address register, the microprogram
        // count register, and the subroutine register. There is also a value
        // for read byte from prefetch queue, which we'll not use in our design.
        //
        // It's also important to note that I don't know if the v30mz uses any
        // of the b, c, and d lower and upper registers.

    // Pop at any time that we are not executing and the queue is not empty.
    assign queue_pop = !reset && (state < STATE_EXECUTE) && !queue_empty;

    initial
    begin
        // micro_op:
        // -----------------------
        // 0:4; source
        // 5:9; destination
        // 10; next_last (nx)
        // 11; last (nl)
        // 12:21; type, a, b

        for (int i = 0; i < 512; i++)
            rom[i] = 0;

        //        type,    b,                    b                      nl/nx, destination,    source
        rom[0]  = {3'b001, MICRO_MISC_OP_B_NONE, MICRO_MISC_OP_A_NONE,  2'b10, MICRO_MOV_NONE, MICRO_MOV_NONE}; // NOP

        rom[1]  = {3'b001, MICRO_MISC_OP_B_NONE, MICRO_MISC_OP_A_NONE,  2'b10, MICRO_MOV_R,    MICRO_MOV_RM};
        rom[2]  = {3'b001, MICRO_MISC_OP_B_NONE, MICRO_MISC_OP_A_NONE,  2'b10, MICRO_MOV_RM,   MICRO_MOV_R};
        rom[3]  = {3'b001, MICRO_MISC_OP_B_NONE, MICRO_MISC_OP_A_NONE,  2'b10, MICRO_MOV_RM,   MICRO_MOV_IMM};

        // BR far_label
        rom[4]  = {3'b001, MICRO_MISC_OP_B_SUSP, MICRO_MISC_OP_A_NONE,  2'b00, MICRO_MOV_PS,   MICRO_MOV_IMM};
        rom[5]  = {3'b001, MICRO_MISC_OP_B_NONE, MICRO_MISC_OP_A_FLUSH, 2'b10, MICRO_MOV_PC,   MICRO_MOV_DISP};

        // OUT acc -> imm8
        rom[6]  = {3'b001, MICRO_MISC_OP_B_NONE, MICRO_MISC_OP_A_NONE,  2'b00, MICRO_MOV_ADD,  MICRO_MOV_IMM};
        rom[7]  = {3'b110, 5'd0,                 MICRO_BUS_OP_IO_WRITE, 2'b10, MICRO_MOV_DO,   MICRO_MOV_AW};

        // IN acc -> imm8
        rom[8]  = {3'b001, MICRO_MISC_OP_B_NONE,  MICRO_MISC_OP_A_NONE, 2'b00, MICRO_MOV_ADD,  MICRO_MOV_IMM};
        rom[9]  = {3'b110, 5'd0,                  MICRO_BUS_OP_IO_READ, 2'b10, MICRO_MOV_AW,   MICRO_MOV_DI};

        // @info: ALU: ttu??aaaaa (t = type, u = use alu result, a = alu op)
        // @note: If MICRO_ALU_USE_RESULT but src is memory, then don't write
        // result back this step but instead run the next microinstruction.
        rom[10] = {2'b01, MICRO_ALU_USE_RESULT, 2'd0, MICRO_ALU_OP_XI,  2'b10, MICRO_MOV_ONES, MICRO_MOV_RM};
        rom[11] = {3'b001, MICRO_MISC_OP_B_NONE, MICRO_MISC_OP_A_NONE,  2'b10, MICRO_MOV_RM,    MICRO_MOV_ALU_R};

        // @info: Long jump: tttcccdddd (t = type, c = jump condition, d = jump
        // destination)
        rom[12] = {3'b101, MICRO_JMP_XC, 4'h0,                          2'b10, MICRO_MOV_NONE, MICRO_MOV_NONE};

        // @note: Can make this 2 microinstructions, but v30mz runs in 3.
        rom[13] = {3'b001, MICRO_MISC_OP_B_SUSP, MICRO_MISC_OP_A_NONE,  2'b00, MICRO_MOV_NONE, MICRO_MOV_NONE};
        rom[14] = {2'b01, MICRO_ALU_IGNORE_RESULT, 2'd0, MICRO_ALU_OP_ADD, 2'b01, MICRO_MOV_DISP, MICRO_MOV_PC};
        rom[15] = {3'b001, MICRO_MISC_OP_B_NONE, MICRO_MISC_OP_A_FLUSH, 2'b10, MICRO_MOV_PC, MICRO_MOV_ALU_R};

        // ALU ACC IMM
        rom[16] = {2'b01, MICRO_ALU_USE_RESULT, 2'd0, MICRO_ALU_OP_XI,  2'b10, MICRO_MOV_IMM, MICRO_MOV_AW};

        // INC RM
        rom[17] = {2'b01, MICRO_ALU_USE_RESULT, 2'd0, MICRO_ALU_OP_XI,  2'b10, MICRO_MOV_ONES, MICRO_MOV_RM};

        rom[18] = {2'b01, MICRO_ALU_USE_RESULT, 2'd0, MICRO_ALU_OP_XI,  2'b10, MICRO_MOV_IMM, MICRO_MOV_RM};
        rom[19] = {3'b001, MICRO_MISC_OP_B_NONE, MICRO_MISC_OP_A_NONE,  2'b10, MICRO_MOV_RM, MICRO_MOV_ALU_R};

        // BR near/short-label
        rom[20] = {3'b101, MICRO_JMP_UC, 4'h0,                          2'b10, MICRO_MOV_NONE, MICRO_MOV_NONE};

        rom[21] = {3'b101, MICRO_JMP_UC, 4'h0,                          2'b10, MICRO_MOV_NONE, MICRO_MOV_NONE};

        rom[22] = {2'b01, MICRO_ALU_USE_RESULT, 2'd0, MICRO_ALU_OP_XI,  2'b10, MICRO_MOV_R, MICRO_MOV_RM};
        rom[23] = {2'b01, MICRO_ALU_USE_RESULT, 2'd0, MICRO_ALU_OP_XI,  2'b10, MICRO_MOV_RM, MICRO_MOV_R};

        // CALL far-proc
        rom[24] = {2'b01, MICRO_ALU_USE_RESULT, 2'd0, MICRO_ALU_OP_SUB,  2'b00, MICRO_MOV_TWOS, MICRO_MOV_SP};
        rom[25] = {3'b001, MICRO_MISC_OP_B_SUSP, MICRO_MISC_OP_A_NONE,   2'b00, MICRO_MOV_ADD,  MICRO_MOV_SP};
        rom[26] = {3'b110, 5'd0,                 MICRO_BUS_OP_MEM_WRITE, 2'b00, MICRO_MOV_DO,   MICRO_MOV_PS};
        rom[27] = {3'b001, MICRO_MISC_OP_B_NONE, MICRO_MISC_OP_A_NONE,   2'b00, MICRO_MOV_PS,   MICRO_MOV_IMM};
        rom[28] = {2'b01, MICRO_ALU_USE_RESULT, 2'd0, MICRO_ALU_OP_SUB,  2'b00, MICRO_MOV_TWOS, MICRO_MOV_SP};
        rom[29] = {3'b001, MICRO_MISC_OP_B_NONE, MICRO_MISC_OP_A_NONE,   2'b00, MICRO_MOV_ADD,  MICRO_MOV_SP};
        rom[30] = {3'b110, 5'd0,                 MICRO_BUS_OP_MEM_WRITE, 2'b00, MICRO_MOV_DO,   MICRO_MOV_PC};
        rom[31] = {3'b001, MICRO_MISC_OP_B_NONE, MICRO_MISC_OP_A_FLUSH,  2'b10, MICRO_MOV_PC,   MICRO_MOV_DISP};

        for (int i = 0; i < 256; i++)
            translation_rom[i] = 0;

        for (int i = 0; i < 2; i++)
            translation_rom[{7'b1000101, i[0]}] = 9'd1;          // MOV mem -> reg

        for (int i = 0; i < 2; i++)
            translation_rom[{7'b1000100, i[0]}] = 9'd2;          // MOV reg -> mem

        for (int j = 0; j < 8; j++)
            for (int i = 0; i < 2; i++)
                translation_rom[{4'b1011, i[0], j[2:0]}] = 9'd3; // MOV imm -> reg

        for (int i = 0; i < 2; i++)
            translation_rom[{7'b1100011, i[0]}] = 9'd3;          // MOV imm -> rm

        translation_rom[8'b10001100] = 9'd2;                     // MOV sreg -> rm
        translation_rom[8'b10001110] = 9'd1;                     // MOV rm -> sreg
        translation_rom[8'b11101010] = 9'd4;                     // BR far_label

        for (int i = 0; i < 2; i++)
            translation_rom[{7'b1110011, i[0]}] = 9'd6;          // OUT acc -> imm8

        for (int i = 0; i < 2; i++)
            translation_rom[{7'b1110010, i[0]}] = 9'd8;          // IN acc -> imm8

        for (int i = 0; i < 2; i++)
            translation_rom[{7'b1101000, i[0]}] = 9'd10;         // ROL 1 -> rm

        for (int i = 0; i < 4; i++)
            translation_rom[{6'b001000, i[1:0]}] = 9'd10;        // AND r -> rm

        for (int i = 0; i < 2; i++)
            translation_rom[{7'b0010010, i[0]}] = 9'd16;         // AND imm -> r

        for (int i = 0; i < 16; i++)
            translation_rom[{4'b0111, i[3:0]}] = 9'd12;          // BNC

        for (int i = 0; i < 16; i++)
            translation_rom[{4'b0100, i[3:0]}] = 9'd17;          // INC/DEC reg16

        for (int i = 0; i < 4; i++)
            translation_rom[{6'b1000_00, i[1:0]}] = 9'd18;       // ALU imm -> rm (Arithmetic family)

        for (int i = 0; i < 2; i++)
            translation_rom[{7'b1100_000, i[0]}] = 9'd18;        // ALU imm -> rm (Shift family)

        for (int i = 0; i < 14; i++)
            translation_rom[{2'b00, i[3:1], 2'b01, i[0]}] = 9'd22;        // XOR rm -> r

        for (int i = 0; i < 14; i++)
            translation_rom[{2'b00, i[3:1], 2'b00, i[0]}] = 9'd23;        // XOR r  -> rm

        translation_rom[8'b1110_1001] = 9'd20;                   // BR near-label
        translation_rom[8'b1110_1011] = 9'd20;                   // BR short-label

        translation_rom[8'b1001_1010] = 9'd24;                   // CALL far-proc

        for (int i = 0; i < 16; i++)
            jump_table[i] = 9'd0;

        jump_table[0] = 9'd13;

    end

    reg [15:0] reg_tmp; // temp register which can be used as read source.
    reg regfile_we;
    wire [2:0] regfile_write_id;
    wire [15:0] regfile_write_data;
    wire [15:0] mov_data;
    wire [15:0] registers[0:7];

    // Latched mov info for performing mov on next posedge clk.
    reg [2:0] reg_src;
    reg [2:0] reg_dst;

    // @important: mov_src_size and mov_dst_size should be the same!
    reg mov_src_size;
    reg mov_dst_size;
    reg [2:0] mov_from;

    wire [15:0] reg_read =
         (mov_from == READ_SRC_SREG) ? segment_registers[reg_src[1:0]]:
        ((mov_from == READ_SRC_PC) ? PC:
        ((mov_from == READ_SRC_TMP) ? reg_tmp:
        ((mov_src_size == 1) ? registers[reg_src]:
        ((reg_src[2]   == 0) ? {8'd0, registers[{1'd0, reg_src[1:0]}][7:0]}:
                               {8'd0, registers[{1'd0, reg_src[1:0]}][15:8]}))));

    // @note: We have introduced a combinatorial loop here because of
    // 'READ_SRC_ALU'. Fortunately, the loop is never triggered, at least not
    // in simulation. The only way for the loop to trigger would be when src
    // and dst of a mov are MICRO_MOV_ALU_R and MICRO_MOV_ALU_A/B
    // respectively. Now, the loop exists because we allow for explicit mov of
    // the alu result. To remove the loop, I split the mov_data to
    // mov_data_alu meant to be fed to alu_a, alu_b, and mov_data meant to be
    // fed anywhere else. The mov_data_alu has excluded the case when
    // mov_from == READ_SRC_ALU.
    // @todo: This is not a very nice way to handle mov_src_size.
    wire [15:0] mov_data_alu =
         (mov_from == READ_SRC_MEM)  ? ((mov_src_size == 1) ? data_in: {8'd0, data_in[7:0]}):
        ((mov_from == READ_SRC_IMM)  ? ((mov_src_size == 1) ? imm: {8'd0, imm[7:0]}):
        ((mov_from == READ_SRC_DISP) ? disp_sign_extended:
                                       reg_read));

    assign mov_data =
         (mov_from == READ_SRC_ALU)  ? ((mov_src_size == 1) ? alu_r: {8'd0, alu_r[7:0]}):
                                        mov_data_alu;

    assign regfile_write_id = (mov_src_size == 1) ? reg_dst: {1'd0, reg_dst[1:0]};

    wire [15:0] regfile_write_data_temp = alu_reg_wb ? alu_r: mov_data;
    assign regfile_write_data =
         (mov_src_size == 1) ? regfile_write_data_temp:
        ((reg_dst[2]   == 0) ? {
                                   registers[regfile_write_id][15:8],
                                   regfile_write_data_temp[7:0]
                               }:
                               {
                                   regfile_write_data_temp[7:0],
                                   registers[regfile_write_id][7:0]
                               });

    assign sregfile_write_id   = reg_dst[1:0];
    assign sregfile_write_data = regfile_write_data_temp;

    // The register file holds the following registers
    //
    // * General purpose registers (AW, BW, CW, DW)
    //   There are four 16-bit registers. These can be not only used
    //   as 16-bit registers, but also accessed as 8-bit registers
    //   (AH, AL, BH, BL, CH, CL, DH, DL) by dividing each register
    //   into the higher 8 bits and the lower 8 bits.
    //
    // * Pointer registers (SP, BP)
    //   The pointer consists of two 16-bit registers (stack pointer
    //   (SP) and base pointer (BP)).
    //
    // * Index registers (IX, IY)
    //   This consists of two 16-bit registers (IX, IY). In a
    //   memory data reference, it is used as an index register to
    //   generate effective addresses (each register can also be
    //   referenced in an instruction).

    register_file register_file_inst
    (
        .clk,
        .reset,
        .we(regfile_we),
        .write_id(regfile_write_id),
        .write_data(regfile_write_data),
        .registers
    );

    wire [19:0] physical_address;
    wire [15:0] disp_sign_extended = (disp_size == 1)? disp: {{8{disp[7]}}, disp[7:0]}; // Sign extend
    reg [2:0] segment_override = 0; // High bit = enable/disable override.
    physical_address_calculator pac
    (
        .physical_address(physical_address),
        .registers,
        .segment_registers,
        .segment_override(segment_override),
        .displacement(disp_sign_extended),
        .mod(mod),
        .rm(rm)
    );

    reg [15:0] alu_a, alu_b;
    reg [4:0] alu_op = 0;
    reg alu_size = 0;
    wire [15:0] alu_r;
    wire [5:0] alu_flags;
    reg [5:0] alu_flags_r;
    alu alu_inst
    (
        .alu_op,
        .size(alu_size),
        .A(alu_a), .B(alu_b), .R(alu_r),
        .flags(alu_flags)
    );

    localparam [1:0]
        CTRL_FLAG_MD  = 2'd0, // Mode flag
        CTRL_FLAG_DIR = 2'd1, // Direction flag
        CTRL_FLAG_IE  = 2'd2, // Interrupt enable flag
        CTRL_FLAG_BRK = 2'd3; // Break flag

    reg [3:0] control_flags;

    // @note: This might play a more important role later, e.g. we might have
    // a microinstruction flag telling us if we should we for the read/write
    // before running the next microinstruction.
    reg read_write_wait;
    // @todo: Make this smaller
    reg [3:0] microprogram_counter;
    wire [21:0] micro_op;
    reg [8:0] microaddress;

    wire [4:0] micro_mov_src;
    assign micro_mov_src = micro_op[4:0];

    wire [4:0] micro_mov_dst;
    assign micro_mov_dst = (micro_op_type[2:1] == 2'b01)? MICRO_MOV_ALU_A: micro_op[9:5];

    assign micro_op = rom[microaddress + {5'd0, microprogram_counter}];

    // @note: Also run next microinstruction when we have alu writeback.
    wire alu_mem_wb = (micro_op_type[2:1] == 2'b01 && (micro_alu_use == MICRO_ALU_USE_RESULT) && mod != 2'b11 && alu_op != ALUOP_CMP);
    wire alu_reg_wb = (micro_op_type[2:1] == 2'b01 && (micro_alu_use == MICRO_ALU_USE_RESULT) && mod == 2'b11 && alu_op != ALUOP_CMP);
    reg branch_taken = 0;
    assign instruction_nearly_done = micro_op[10];
    wire instruction_maybe_done = (micro_op[11] && !alu_mem_wb && !branch_taken);

    wire [3:0] micro_misc_op_a = micro_op[15:12];
    wire [2:0] micro_misc_op_b = micro_op[18:16];
    wire [2:0] micro_op_type   = micro_op[21:19];
    wire [1:0] micro_bus_op    = micro_op[13:12];

    wire       micro_alu_use   = micro_op[19];
    wire [4:0] micro_alu_op    = micro_op[16:12];

    wire [2:0] micro_jmp_condition   = micro_op[18:16];
    wire [3:0] micro_jmp_destination = micro_op[15:12];

    //assign queue_flush   = (micro_op_type == 3'b001) && (micro_misc_op_a == MICRO_MISC_OP_A_FLUSH);
    //assign queue_suspend = (micro_op_type == 3'b001) && (micro_misc_op_b == MICRO_MISC_OP_B_SUSP);

    reg [1:0] instruction_step = 0;
    reg instruction_repeat = 0;
    always_latch
    begin
        error <= 0;

        if(bus_command_done)
        begin
            read_write_wait <= 0;
            bus_command     <= BUS_COMMAND_IDLE;
            regfile_we      <= 0;
        end

        if(!read_write_wait)
        begin
            regfile_we  <= 0;
            sregfile_we <= 0;
        end

        if(reset)
        begin
            read_write_wait       <= 0;
            bus_command           <= BUS_COMMAND_IDLE;
            bus_upper_byte_enable <= 1;
            regfile_we            <= 0;
            sregfile_we           <= 0;
        end

        // @todo: I think we forgot the MICRO_MOV_NONE.

        // * Handle move command *
        if(state == STATE_EXECUTE)
        begin
            if(translation_rom[opcode] == 0)
            begin
                case(opcode)
                    8'hAA:
                        error <= `__LINE__;

                    8'hAB: // STMW
                    begin
                        modrm = 8'b00000101;

                        if(instruction_step == 0)
                        begin
                            bus_command     <= BUS_COMMAND_MEM_WRITE;
                            bus_address     <= physical_address;
                            data_out        <= registers[0];
                            read_write_wait <= 1;
                        end
                        // @todo: Check if the second check is superfluous.
                        else if(instruction_step == 1 && bus_command_done)
                        begin
                            reg_dst      <= 7;
                            mov_from     <= READ_SRC_TMP;
                            mov_src_size <= 1;
                            mov_dst_size <= 1;
                            regfile_we   <= 1;
                            reg_tmp      <= (control_flags[CTRL_FLAG_DIR] == 0)? registers[7] + 2: registers[7] - 2;
                        end
                        else if(instruction_step == 2 && instruction_repeat)
                        begin
                            // @todo: Do I need to do something with the Z-flag?

                            alu_a    <= registers[1];
                            alu_b    <= 1;
                            alu_size <= 1;
                            alu_op   <= ALUOP_DEC;

                            regfile_we   <= 1;
                            reg_dst      <= 1;
                            mov_from     <= READ_SRC_ALU;
                            mov_src_size <= 1;
                            mov_dst_size <= 1;
                        end
                    end

                    8'hFA,
                    8'hFC,
                    8'hF3:
                    begin
                    end

                    // Segment override prefix.
                    8'h26, 8'h2E, 8'h36, 8'h3E:
                    begin
                    end

                    default:
                        error <= `__LINE__;
                endcase
            end
            else
            begin
                // ** Handle move source reading **
                if(micro_mov_src == MICRO_MOV_RM && mod != 2'b11)
                begin
                    // Source is memory
                    bus_address     <= physical_address;
                    bus_command     <= BUS_COMMAND_MEM_READ;
                    read_write_wait <= 1;

                    mov_from     <= READ_SRC_MEM;
                    mov_src_size <= byte_word_field;
                end
                else if(micro_mov_src == MICRO_MOV_RM || micro_mov_src == MICRO_MOV_R)
                begin
                    // Source is register specified by modrm.
                    reg_src      <= src_operand[2:0];
                    mov_from     <= src_operand[3]? READ_SRC_SREG: READ_SRC_REG;
                    mov_src_size <= byte_word_field;
                end
                else if(micro_mov_src == MICRO_MOV_IMM)
                begin
                    // Source is immediate.
                    mov_from     <= READ_SRC_IMM;
                    mov_src_size <= imm_size;
                end
                else if(micro_mov_src == MICRO_MOV_DISP)
                begin
                    // Source is disp.
                    mov_from     <= READ_SRC_DISP;
                    mov_src_size <= 1;
                end
                else if(micro_mov_src == MICRO_MOV_DI)
                begin
                    mov_from     <= READ_SRC_MEM;
                    mov_src_size <= byte_word_field;
                end
                else if(micro_mov_src == MICRO_MOV_ALU_R)
                begin
                    mov_from     <= READ_SRC_ALU;
                    mov_src_size <= byte_word_field;
                end
                else if(micro_mov_src >= MICRO_MOV_AW)
                begin
                    // Source is word register
                    mov_src_size  <= 1;

                    if(micro_mov_src  == MICRO_MOV_PC)
                    begin
                        mov_from <= READ_SRC_PC;
                        reg_src  <= 0;
                    end
                    else if(micro_mov_src >= MICRO_MOV_DS1)
                    begin
                        mov_from <= READ_SRC_SREG;
                        reg_src  <= {micro_mov_src - MICRO_MOV_DS1}[2:0];
                    end
                    else
                    begin
                        mov_from <= READ_SRC_REG;
                        reg_src  <= {micro_mov_src - MICRO_MOV_AW}[2:0];
                    end
                end
                else if(micro_mov_src == MICRO_MOV_AL || micro_mov_src == MICRO_MOV_AH)
                begin
                    // Source is byte register
                    reg_src <= {micro_mov_src - MICRO_MOV_AL}[2:0] << 2;
                    mov_src_size <= 0;
                end

                // ** Handle move destination writing **
                if(micro_mov_dst == MICRO_MOV_RM && need_modrm && mod != 2'b11)
                begin
                    // Destination is memory
                    bus_address     <= physical_address;
                    bus_command     <= BUS_COMMAND_MEM_WRITE;
                    data_out        <= mov_data;
                    read_write_wait <= 1;
                    mov_dst_size    <= byte_word_field;
                end
                else if((micro_mov_dst == MICRO_MOV_RM) || (micro_mov_dst == MICRO_MOV_R))
                begin
                    // Destination is register specified by modrm.
                    reg_dst      <= dst_operand[2:0];
                    mov_dst_size <= byte_word_field;
                    if(dst_operand[3])
                        sregfile_we <= 1;
                    else
                        regfile_we  <= 1;
                end
                else if(micro_mov_dst == MICRO_MOV_DO)
                begin
                    data_out     <= mov_data;
                    mov_dst_size <= byte_word_field;
                end
                else if(micro_mov_dst == MICRO_MOV_ADD)
                begin
                    // @todo, @important: Add segment! Probably need an
                    // additional register as a target of MICRO_MOV_ADD, and
                    // when running a bus command, possibly add that register
                    // to the bus_address.
                    bus_address <= {4'd0, mov_data};
                    mov_dst_size <= 1;
                end
                else if(micro_mov_dst == MICRO_MOV_ALU_A)
                begin
                    mov_dst_size <= byte_word_field;
                    alu_a <= mov_data_alu;
                end
                else if(micro_mov_dst >= MICRO_MOV_AW)
                begin
                    // Destination is word register
                    mov_dst_size <= 1;

                    if(micro_mov_dst == MICRO_MOV_PC)
                    begin
                        // @note: Assume we are always moving from word registers.
                        reg_dst <= 0;
                    end
                    else if(micro_mov_dst >= MICRO_MOV_DS1)
                    begin
                        sregfile_we <= 1;
                        reg_dst     <= {micro_mov_dst - MICRO_MOV_DS1}[2:0];
                    end
                    else
                    begin
                        regfile_we <= 1;
                        reg_dst    <= {micro_mov_dst - MICRO_MOV_AW}[2:0];
                    end
                end
                else if(micro_mov_dst == MICRO_MOV_AL || micro_mov_dst == MICRO_MOV_AH)
                begin
                    // Destination is byte register
                    regfile_we   <= 1;
                    reg_dst      <= {micro_mov_dst - MICRO_MOV_AL}[2:0];
                    mov_dst_size <= 0;
                end

                if(micro_op_type[2:1] == 2'b01)
                begin
                    case(micro_op[9:5])
                        MICRO_MOV_TWOS:
                            alu_b <= 2;

                        MICRO_MOV_ONES:
                            alu_b <= 1;

                        MICRO_MOV_ZERO:
                            alu_b <= 0;

                        MICRO_MOV_R:
                        begin
                            if(byte_word_field == 1)
                                alu_b <= registers[dst_operand[2:0]];
                            else if(dst_operand[2] == 0)
                                alu_b <= {8'd0, registers[{1'd0, dst_operand[1:0]}][7:0]};
                            else
                                alu_b <= {8'd0, registers[{1'd0, dst_operand[1:0]}][15:8]};
                        end

                        MICRO_MOV_AL,
                        MICRO_MOV_AH:
                            alu_b <= {8'd0, registers[{micro_op[9:5] - MICRO_MOV_AL}[2:0]][15:8]};

                        MICRO_MOV_AW, MICRO_MOV_CW, MICRO_MOV_DW, MICRO_MOV_BW,
                        MICRO_MOV_SP, MICRO_MOV_BP, MICRO_MOV_IX, MICRO_MOV_IY:
                            alu_b <= registers[{micro_op[9:5] - MICRO_MOV_AW}[2:0]];

                        MICRO_MOV_PC:
                            alu_b <= PC;

                        MICRO_MOV_DISP:
                            alu_b <= disp_sign_extended;

                        MICRO_MOV_IMM:
                            alu_b <= imm;

                        default:
                            alu_b <= 16'hCAFE;
                    endcase
                end

                // ** Handle alu register writeback **
                if(micro_op_type[2:1] == 2'b01 && micro_alu_use == MICRO_ALU_USE_RESULT)
                begin
                    if((micro_mov_src == MICRO_MOV_RM || micro_mov_src == MICRO_MOV_R) && mod == 2'b11)
                    begin
                        // Destination is register specified by modrm.
                        reg_dst      <= src_operand[2:0];
                        mov_dst_size <= byte_word_field;
                        regfile_we   <= 1;
                    end
                    else if(micro_mov_src >= MICRO_MOV_AW)
                    begin
                        mov_dst_size <= 1;

                        if(micro_mov_src  == MICRO_MOV_PC)
                        begin
                            reg_dst <= 0;
                        end
                        else
                        begin
                            regfile_we <= 1;
                            reg_dst    <= {micro_mov_src - MICRO_MOV_AW}[2:0];
                        end
                    end
                    else if(micro_mov_src == MICRO_MOV_AL || micro_mov_src == MICRO_MOV_AH)
                    begin
                        // Destination is byte register
                        regfile_we   <= 1;
                        reg_dst      <= {micro_mov_src - MICRO_MOV_AL}[2:0];
                        mov_dst_size <= 0;
                    end
                end

                case(micro_op_type)
                    // Bus operation
                    3'b110:
                    begin
                        // @todo, @important: Add segment! Probably need an
                        // additional register as a target of MICRO_MOV_ADD, and
                        // when running a bus command, possibly add that register
                        // to the bus_address.
                        read_write_wait <= 1;

                        if(micro_bus_op == MICRO_BUS_OP_IO_WRITE)
                        begin
                            bus_command <= BUS_COMMAND_IO_WRITE;
                        end
                        else if(micro_bus_op == MICRO_BUS_OP_IO_READ)
                        begin
                            bus_command <= BUS_COMMAND_IO_READ;
                        end
                        else if(micro_bus_op == MICRO_BUS_OP_MEM_WRITE)
                        begin
                            bus_command <= BUS_COMMAND_MEM_WRITE;
                        end
                        else
                        begin
                            bus_command <= BUS_COMMAND_MEM_READ;
                        end
                    end
                    // alu operation
                    3'b010, 3'b011:
                    begin
                        alu_size    <= byte_word_field;
                        // @todo: We probably need to add flag for updating flags
                        // or not.
                        alu_flags_r <= alu_flags;

                        case(micro_alu_op)
                            MICRO_ALU_OP_XI:
                                alu_op <=
                                     (opcode[7:4] == 4'b1000)?    {2'b0, regm}:
                                    ((opcode[7:2] == 6'b110100)?  ALUOP_ROL + {2'b0, regm}:
                                    ((opcode[7:1] == 7'b1100000)? ALUOP_ROL + {2'b0, regm}:
                                    ((opcode[7:1] == 7'b1111111)? ALUOP_INC + {2'b0, regm}:
                                    ((opcode[7:3] == 5'b01000)?   ALUOP_INC + {2'b0, opcode[5:3]}:
                                                                  {2'b0, opcode[5:3]}))));

                            MICRO_ALU_OP_AND:
                                alu_op <= ALUOP_AND;

                            MICRO_ALU_OP_ADD:
                                alu_op <= ALUOP_ADD;

                            MICRO_ALU_OP_SUB:
                                alu_op <= ALUOP_SUB;

                            MICRO_ALU_OP_INC:
                                alu_op <= ALUOP_INC;

                            MICRO_ALU_OP_DEC:
                                alu_op <= ALUOP_DEC;

                            MICRO_ALU_OP_NEG:
                                alu_op <= ALUOP_NEG;

                            MICRO_ALU_OP_ROL:
                                alu_op <= ALUOP_ROL;

                            MICRO_ALU_OP_ROR:
                                alu_op <= ALUOP_ROR;

                            default:
                                alu_op <= 0;

                        endcase
                    end

                    default:;

                endcase
            end
        end
    end

    always_ff @ (posedge clk)
    begin
        if(reset)
        begin
            microprogram_counter <= 0;
            microaddress         <= 0;
            PC                   <= 16'h0000;
            state                <= STATE_OPCODE_READ;
        end
        else
        begin
            queue_flush   <= 0;
            queue_suspend <= 0;
            branch_taken  <= 0;

            // @todo: Allow reading when instruction is done or nearly done.
            // Perhaps we can achieve this by removing the execute state,
            // making the current states only for reading the opcode bytes,
            // and having a separate reg enabled when executing. The reg is
            // enabled when next_state == STATE_OPCODE_READ. The state of the
            // opcode reader is then set to next_state only when
            // instruction_maybe_done or instruction_nearly_done. The following
            // should work, but I think it will only give benefits when we
            // have instructions that set instruction_nearly_done.
            //
            // if(!queue_empty && (instruction_maybe_done || instruction_nearly_done))
            // begin
            //     // Get instruction from queue_buffer if it's not empty.
            //     if(state == STATE_OPCODE_READ)
            //         PC <= PC + 1;
            //     if(next_state == STATE_OPCODE_READ)
            //         execute <= 1;

            //     state <= next_state;
            // end

            if(state <= STATE_IMM_HIGH_READ)
            begin
                if(state == STATE_OPCODE_READ)
                    microaddress  <= translation_rom[opcode];

                // @note: I thought there might be a problem here using
                // sequential logic: If the queue is empty on this cycle but
                // receiving data the next cycle, queue_empty will be false
                // only on the next rising edge, meaning that the state will
                // move forward at the following cycle.
                //                __    __    __
                // clk           /  \__/  \__/  \
                //                ______
                // data_request  |      |________
                //               _______
                // queue_empty          |________
                //               .................
                // state         ............/....
                //
                // But, I think there is nothing we can do, as the queue is
                // updated on the positive edge of the clock anyway?

                // Make sure the queue is not empty at any of the read states.
                if(!queue_empty && !queue_flush)
                begin
                    // Get instruction from queue_buffer if it's not empty.
                    PC <= PC + 1;
                    state <= next_state;
                end
            end
            // STATE_EXECUTE
            else if(!read_write_wait || bus_command_done)
            begin
                if(instruction_maybe_done)
                begin
                    state <= next_state;
                    microprogram_counter <= 0;
                end
                else
                    microprogram_counter <= microprogram_counter + 1;

                if(micro_mov_dst == MICRO_MOV_PC)
                    PC <= mov_data;

                segment_override <= 0;

                if(translation_rom[opcode] == 0)
                begin
                    case(opcode)
                        8'hF3:
                        begin
                            if(registers[1] == 0)
                            begin
                                PC <= PC + 2;
                            end
                            else
                            begin
                                PC <= PC + 1;
                                instruction_repeat <= 1;
                            end
                        end

                        8'hFA:
                            control_flags[CTRL_FLAG_IE] <= 0;

                        8'hFC:
                            control_flags[CTRL_FLAG_DIR] <= 0;

                        8'hAB:
                        begin
                            // @todo: Check if the second check is superfluous.
                            if(instruction_step != 1 || bus_command_done)
                                instruction_step <= (instruction_step + 1) % 3;

                            // @todo: Check that we stop on time, or not
                            // a clock too late.
                            if(instruction_repeat && registers[1] != 1)
                                state <= STATE_EXECUTE;
                            else
                                instruction_repeat <= 0;
                        end

                        // Segment override prefix.
                        8'h26, 8'h2E, 8'h36, 8'h3E:
                        begin
                            segment_override <= {1'b1, opcode[4:3]};
                        end

                        default;
                    endcase
                end
                else
                begin

                    // Handle microcode commands
                    // @note: Not sure if I need to handle all these types of
                    // microcode instructions. Certain jumps were introduced in
                    // 8086 to reduce the microcode size, but this is not a huge
                    // problem here.
                    case(micro_op_type)

                        // misc
                        3'b001:
                        begin
                            if(micro_misc_op_a == MICRO_MISC_OP_A_FLUSH)
                                queue_flush <= 1;

                            if(micro_misc_op_b == MICRO_MISC_OP_B_SUSP)
                                queue_suspend <= 1;
                        end

                        // alu
                        3'b010, 3'b011:
                        begin
                        end

                        // long jump
                        3'b101:
                        begin
                            case(micro_jmp_condition)
                                MICRO_JMP_XC:
                                begin
                                    case(opcode[3:0])
                                        4'h2: // BC
                                        begin
                                            if(alu_flags_r[ALU_FLAG_CY] == 1)
                                            begin
                                                microprogram_counter <= 0;
                                                microaddress <= jump_table[micro_jmp_destination];
                                                branch_taken <= 1;
                                                state <= STATE_EXECUTE;
                                            end
                                        end

                                        4'h3: // BNC
                                        begin
                                            if(alu_flags_r[ALU_FLAG_CY] == 0)
                                            begin
                                                microprogram_counter <= 0;
                                                microaddress <= jump_table[micro_jmp_destination];
                                                branch_taken <= 1;
                                                state <= STATE_EXECUTE;
                                            end
                                        end

                                        4'h4: // BZ
                                        begin
                                            if(alu_flags_r[ALU_FLAG_Z] == 1)
                                            begin
                                                microprogram_counter <= 0;
                                                microaddress <= jump_table[micro_jmp_destination];
                                                branch_taken <= 1;
                                                state <= STATE_EXECUTE;
                                            end
                                        end

                                        4'h5: // BNZ
                                        begin
                                            if(alu_flags_r[ALU_FLAG_Z] == 0)
                                            begin
                                                microprogram_counter <= 0;
                                                microaddress <= jump_table[micro_jmp_destination];
                                                branch_taken <= 1;
                                                state <= STATE_EXECUTE;
                                            end
                                        end

                                        default:
                                        begin
                                        end
                                    endcase
                                end

                                MICRO_JMP_UC:
                                begin
                                    microprogram_counter <= 0;
                                    microaddress <= jump_table[micro_jmp_destination];
                                    branch_taken <= 1;
                                    state <= STATE_EXECUTE;
                                end

                                default:
                                begin
                                end
                            endcase
                        end

                        // bus operation
                        3'b110:
                        begin
                        end

                        // short jump
                        3'b000, 3'b100:
                        begin
                        end

                        // long call (@note: Will probably not implement)
                        3'b111:
                        begin
                        end

                    endcase
                end
            end
        end
    end

endmodule;
