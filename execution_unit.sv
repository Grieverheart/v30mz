
enum [2:0]
{
    BUS_COMMAND_IDLE      = 3'd0,
    BUS_COMMAND_MEM_READ  = 3'd1,
    BUS_COMMAND_MEM_WRITE = 3'd2,
    BUS_COMMAND_IO_READ   = 3'd3,
    BUS_COMMAND_IO_WRITE  = 3'd4
} BusCommand;

// @todo: The 8086 has a SUSP microcode action that suspends prefetching.
// That's nice, and we could also try to implement it. We probably need to
// clear SUSP whenever we flush the prefetch queue.

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
    output instruction_done,
    output instruction_nearly_done,

    // Bus
    output reg [2:0]  bus_command,
    output reg [19:0] bus_address,
    // @todo: Should we just assign this to mov_dst_size ?
    output reg bus_upper_byte_enable,
    // @todo: This is not set.
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
        READ_SRC_MEM  = 3'd5;

    //localparam [2:0]
    //    LJUMP_COND_UNC = 3'd0,
    //        ...

    reg [7:0] opcode;
    reg [7:0] modrm;
    reg [15:0] imm;
    reg [15:0] disp;

    reg [4:0] aluop;

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
        .opcode(opcode),
        .modrm(modrm),

        .need_modrm(need_modrm),

        .need_disp(need_disp),
        .disp_size(disp_size),

        .need_imm(need_imm),
        .imm_size(imm_size),

        .src(src_operand),
        .dst(dst_operand),

        .byte_word_field(byte_word_field),

        .base(ea_base_reg),
        .index(ea_index_reg),
        .seg(ea_segment_reg)
    );


    wire [1:0] mod = modrm[7:6];
    wire [2:0] rm  = modrm[2:0];

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

        (state == STATE_IMM_HIGH_READ) ? STATE_EXECUTE:
        // STATE_EXECUTE
        (instruction_done ? STATE_OPCODE_READ: STATE_EXECUTE);

    // @info: The opcode is translated directly to a rom address. This can be done by
    //creating a rom of size 256 indexed by the opcode, where the value is
    //equal to the microcode rom address.

    // @todo: Initialize roms
    reg [8:0] translation_rom[0:255];
    reg [21:0] rom[0:511];

    localparam [4:0]
        MICRO_MOV_NONE = 5'h00,
        // register specified by r field of modrm.
        MICRO_MOV_R    = 5'h01,
        // register or memory specified by rm field of modrm.
        MICRO_MOV_RM   = 5'h02,
        // disp value specified by opcode bytes. Cannot be destination.
        MICRO_MOV_DISP = 5'h03,
        // imm value specified by opcode bytes. Cannot be destination.
        MICRO_MOV_IMM  = 5'h04,

        MICRO_MOV_DO   = 5'h05,
        MICRO_MOV_DI   = 5'h06,
        MICRO_MOV_ADD  = 5'h07,

        // all registers:
        MICRO_MOV_AL   = 5'h11,
        MICRO_MOV_AH   = 5'h12,

        MICRO_MOV_AW   = 5'h13,
        MICRO_MOV_CW   = 5'h14,
        MICRO_MOV_DW   = 5'h15,
        MICRO_MOV_BW   = 5'h16,

        MICRO_MOV_SP   = 5'h17,
        MICRO_MOV_BP   = 5'h18,
        MICRO_MOV_IX   = 5'h19,
        MICRO_MOV_IY   = 5'h1a,

        MICRO_MOV_PS   = 5'h1b,
        MICRO_MOV_SS   = 5'h1c,
        MICRO_MOV_DS0  = 5'h1d,
        MICRO_MOV_DS1  = 5'h1e,

        MICRO_MOV_PC   = 5'h1f;

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

        //        type,   b,                    b                      nl/nx, destination,  source
        rom[0] = {3'b001, MICRO_MISC_OP_B_NONE, MICRO_MISC_OP_A_NONE,  2'b10, MICRO_MOV_R,  MICRO_MOV_RM};
        rom[1] = {3'b001, MICRO_MISC_OP_B_NONE, MICRO_MISC_OP_A_NONE,  2'b10, MICRO_MOV_RM, MICRO_MOV_R};
        rom[2] = {3'b001, MICRO_MISC_OP_B_NONE, MICRO_MISC_OP_A_NONE,  2'b10, MICRO_MOV_RM, MICRO_MOV_IMM};

        // BR far_label
        rom[3] = {3'b001, MICRO_MISC_OP_B_SUSP, MICRO_MISC_OP_A_NONE,  2'b00, MICRO_MOV_PS, MICRO_MOV_IMM};
        rom[4] = {3'b001, MICRO_MISC_OP_B_NONE, MICRO_MISC_OP_A_FLUSH, 2'b10, MICRO_MOV_PC, MICRO_MOV_DISP};

        // OUT acc -> imm8
        //rom[5] = {3'b001, MICRO_MISC_OP_B_NONE,   MICRO_MISC_OP_A_NONE, 2'b00, MICRO_MOV_ADD, MICRO_MOV_IMM};
        //rom[6] = {3'b011, 5'd0,                  MICRO_BUS_OP_IO_WRITE, 2'b10, MICRO_MOV_DO, MICRO_MOV_AW};

        // @todo: implement nop
        // rom[3] = {3'b001, 7'd0, 2'b10, MICRO_MOV_NONE, MICRO_MOV_NONE};

        for (int i = 5; i < 512; i++)
            rom[i] = 0;

        for (int i = 0; i < 256; i++)
            translation_rom[i] = 0;

        for (int i = 0; i < 2; i++)
            translation_rom[{7'b1000101, i[0]}] = 9'd0;          // MOV mem -> reg

        for (int j = 0; j < 8; j++)
            for (int i = 0; i < 2; i++)
                translation_rom[{4'b1011, i[0], j[2:0]}] = 9'd2; // MOV imm -> reg

        for (int i = 0; i < 2; i++)
            translation_rom[{7'b1100011, i[0]}] = 9'd2;          // MOV imm -> rm

        translation_rom[8'b10001100] = 9'd1;                     // MOV sreg -> rm
        translation_rom[8'b10001110] = 9'd0;                     // MOV rm -> sreg
        translation_rom[8'b11101010] = 9'd3;                     // BR far_label

    end

    reg regfile_we;
    wire [2:0] regfile_write_id;
    wire [15:0] regfile_write_data;
    wire [15:0] regfile_write_data_temp;
    wire [15:0] registers[0:7];

    // Latched mov info for performing mov on next posedge clk.
    reg [2:0] reg_src;
    reg [2:0] reg_dst;

    // @important: mov_src_size and mov_dst_size should be the same!
    reg mov_src_size;
    reg mov_dst_size;
    reg [2:0] mov_from;
    // @todo: We should also latch the imm value, otherwise we're going to
    // have problems when we implement pipelining.

    wire [15:0] reg_read = 
         (mov_from == READ_SRC_SREG)  ? segment_registers[reg_src[1:0]]:
        ((mov_from == READ_SRC_PC) ? PC:
        ((mov_src_size == 1) ? registers[reg_src]:
        ((reg_src[2]   == 0) ? {8'd0, registers[{1'd0, reg_src[1:0]}][7:0]}:
                               {8'd0, registers[{1'd0, reg_src[1:0]}][15:8]})));

    assign regfile_write_data_temp =
         (mov_from == READ_SRC_MEM)  ? data_in:
        ((mov_from == READ_SRC_IMM)  ? imm:
        ((mov_from == READ_SRC_DISP) ? disp:
                                       reg_read));

    assign regfile_write_id = (mov_src_size == 1) ? reg_dst: {1'd0, reg_dst[1:0]};
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
        .clk(clk),
        .reset(reset),
        .we(regfile_we),
        .write_id(regfile_write_id),
        .write_data(regfile_write_data),
        .registers(registers)
    );

    wire [19:0] physical_address;
    physical_address_calculator pac
    (
        .physical_address(physical_address),
        .factors({ea_base_reg[3], ea_index_reg[3], &mod}),
        .segment(segment_registers[ea_segment_reg]),
        .base(registers[ea_base_reg[2:0]]),
        .index(registers[ea_index_reg[2:0]]),
        .displacement((disp_size == 1)? disp: {{8{disp[7]}}, disp[7:0]}) // Sign extend
    );

    // @note: This might play a more important role later, e.g. we might have
    // a microinstruction flag telling us if we should we for the read/write
    // before running the next microinstruction.
    reg read_write_wait;
    // @todo: Make this smaller
    reg [3:0] microprogram_counter;
    wire [21:0] micro_op;
    wire [8:0] address;

    wire [4:0] micro_mov_src;
    assign micro_mov_src = micro_op[4:0];

    wire [4:0] micro_mov_dst;
    assign micro_mov_dst = micro_op[9:5];

    assign address = translation_rom[opcode];
    assign micro_op = rom[address + {5'd0, microprogram_counter}];

    assign instruction_nearly_done = micro_op[10];
    assign instruction_done = micro_op[11];

    wire [3:0] micro_misc_op_a = micro_op[15:12];
    wire [2:0] micro_misc_op_b = micro_op[18:16];
    wire [2:0] micro_op_type   = micro_op[21:19];
    wire [1:0] micro_bus_op    = micro_op[13:12];

    //assign queue_flush   = (micro_op_type == 3'b001) && (micro_misc_op_a == MICRO_MISC_OP_A_FLUSH);
    //assign queue_suspend = (micro_op_type == 3'b001) && (micro_misc_op_b == MICRO_MISC_OP_B_SUSP);

    always_latch
    begin

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
                mov_from  <= READ_SRC_IMM;
                mov_src_size <= imm_size;
            end
            else if(micro_mov_src == MICRO_MOV_DISP)
            begin
                // @todo:
                // Source is immediate.
                mov_from  <= READ_SRC_DISP;
                mov_src_size <= disp_size;
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
                else if(micro_mov_src >= MICRO_MOV_PS)
                begin
                    mov_from <= READ_SRC_SREG;
                    reg_src  <= {micro_mov_src - MICRO_MOV_PS}[2:0];
                end
                else
                begin
                    mov_from <= READ_SRC_REG;
                    reg_src  <= {micro_mov_src - MICRO_MOV_AW}[2:0];
                end
            end
            else
            begin
                // Source is byte register
                reg_src <= {micro_mov_src - MICRO_MOV_AL}[2:0];
                mov_src_size <= 0;
            end

            // @todo: Handle these:
            //
            // MICRO_MOV_DO
            // MICRO_MOV_DI
            // MICRO_MOV_ADD
            //

            // ** Handle move destination writing **
            if(micro_mov_dst == MICRO_MOV_RM && need_modrm && mod != 2'b11)
            begin
                // Destination is memory
                bus_address     <= physical_address;
                bus_command     <= BUS_COMMAND_MEM_WRITE;
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
            else if(micro_mov_dst >= MICRO_MOV_AW)
            begin
                // Destination is word register
                mov_dst_size <= 1;

                if(micro_mov_dst == MICRO_MOV_PC)
                begin
                    // @note: Assume we are always moving from word registers.
                    reg_dst <= 0;
                end
                else if(micro_mov_dst >= MICRO_MOV_PS)
                begin
                    sregfile_we <= 1;
                    reg_dst     <= {micro_mov_dst - MICRO_MOV_PS}[2:0];
                end
                else
                begin
                    regfile_we <= 1;
                    reg_dst    <= {micro_mov_dst - MICRO_MOV_AW}[2:0];
                end
            end
            else
            begin
                // Destination is byte register
                regfile_we   <= 1;
                reg_dst      <= {micro_mov_dst - MICRO_MOV_AL}[2:0];
                mov_dst_size <= 0;
            end

            // Bus operation
            if(micro_op_type == 3'b011)
            begin
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
        end
    end

    always_ff @ (posedge clk)
    begin
        if(reset)
        begin
            microprogram_counter <= 0;
            PC                   <= 16'h0000;
            state                <= STATE_OPCODE_READ;
        end
        else
        begin
            queue_flush   <= 0;
            queue_suspend <= 0;

            // @todo: Allow reading when instruction is done or nearly done.
            // Perhaps we can achieve this by removing the execute state,
            // making the current states only for reading the opcode bytes,
            // and having a separate reg enabled when executing. The reg is
            // enabled when next_state == STATE_OPCODE_READ. The state of the
            // opcode reader is then set to next_state only when
            // instruction_done or instruction_nearly_done. The following
            // should work, but I think it will only give benefits when we
            // have instructions that set instruction_nearly_done.
            //
            // if(!queue_empty && (instruction_done || instruction_nearly_done))
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
                state <= next_state;

                if(micro_mov_dst == MICRO_MOV_PC)
                    PC <= regfile_write_data_temp;

                microprogram_counter <= (instruction_done == 1) ? 0: microprogram_counter + 1;

                // Handle other commands
                // @note: Not sure if I need to handle all these types of
                // microcode instructions. Certain jumps were introduced in
                // 8086 to reduce the microcode size, but this is not a huge
                // problem here.
                case(micro_op_type)

                    // short jump
                    3'b000, 3'b100:
                    begin
                    end

                    // alu
                    3'b010, 3'b110:
                    begin
                    end

                    // misc
                    3'b001:
                    begin
                        if(micro_misc_op_a == MICRO_MISC_OP_A_FLUSH)
                            queue_flush <= 1;

                        if(micro_misc_op_b == MICRO_MISC_OP_B_SUSP)
                            queue_suspend <= 1;
                    end

                    // long jump
                    3'b101:
                    begin
                    end

                    // bus operation
                    3'b011:
                    begin
                    end

                    // long call
                    3'b111:
                    begin
                    end

                endcase
            end
        end
    end

endmodule;
