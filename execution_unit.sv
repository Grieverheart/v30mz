
module execution_unit
(
    input clk,
    input reset,

    // Prefetch queue
    input [7:0] prefetch_data,
    input queue_empty,
    output queue_pop,

    // Segment register input and output
    // @todo: We need to be able to read and write to the segment registers.
    // We know these take an additional cycle because they have to go to the
    // BCU.
    input [15:0] segment_registers[0:3],

    // Execution status
    output instruction_done,
    output instruction_nearly_done,

    // Bus
    output reg [1:0]  bus_command,
    output reg [19:0] bus_address,
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
        STATE_EXECUTE        = 3'd6,
        STATE_RW_WAIT        = 3'd7;

    parameter [1:0]
        BUS_COMMAND_IDLE  = 2'd0,
        BUS_COMMAND_READ  = 2'd1,
        BUS_COMMAND_WRITE = 2'd2;

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
    wire [3:0] src;
    wire [3:0] dst;

    // Effective address registers
    wire [3:0] ea_base_reg;
    wire [3:0] ea_index_reg;
    wire [1:0] ea_segment_reg;

    wire [3:0] src_operand;
    wire [3:0] dst_operand;

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
        // @todo: Check that this logic is correct.
        // Either STATE_EXECUTE or STATE_RW_WAIT.
        instruction_done ? STATE_OPCODE_READ: state;

    // @info: The opcode is translated directly to a rom address. This can be done by
    //creating a rom of size 256 indexed by the opcode, where the value is
    //equal to the microcode rom address.

    // @todo: Initialize roms
    reg [8:0] translation_rom[0:255];
    reg [21:0] rom[0:511];

    localparam [4:0]
        micro_mov_none = 5'h00,
        // register specified by r field of modrm.
        micro_mov_r    = 5'h01,
        // register or memory specified by rm field of modrm.
        micro_mov_rm   = 5'h02,
        // imm value specified by opcode bytes. Cannot be destination.
        micro_mov_imm  = 5'h03,

        // all registers:
        micro_mov_al   = 5'h04,
        //micro_mov_cl   = 5'h05,
        //micro_mov_dl   = 5'h06,
        //micro_mov_bl   = 5'h07,

        micro_mov_ah   = 5'h08,
        //micro_mov_ch   = 5'h09,
        //micro_mov_dh   = 5'h0a,
        //micro_mov_bh   = 5'h0b,

        micro_mov_aw   = 5'h0c,
        micro_mov_cw   = 5'h0d,
        micro_mov_dw   = 5'h0e,
        micro_mov_bw   = 5'h0f,

        micro_mov_sp   = 5'h10,
        micro_mov_bp   = 5'h11,
        micro_mov_ix   = 5'h12,
        micro_mov_iy   = 5'h13,

        micro_mov_es   = 5'h14,
        micro_mov_cs   = 5'h15,
        micro_mov_ss   = 5'h16,
        micro_mov_ds   = 5'h17;

        // @note: Still need these, I think:
        //     micro_mov_psw  = 5'h18,
        //     micro_mov_ea   = 5'h19,
        //     micro_mov_pc   = 5'h1a,
        //     micro_mov_alur = 5'h1b,
        //     micro_mov_alux = 5'h1c,
        //     micro_mov_aluy = 5'h1d,
        //
        // The 8086 microcode seems to even introduce some temporary registers
        // and does not explicitly use the upper and lower half of the
        // registers b, c, and d. In total, 26 values for src and 26 values
        // for dst are used. The combined src and dst refer to a combined 33
        // unique values, so a common coding for both is not possible with 5
        // bits. I think it's best to encode the common ones, and for the
        // others, introduce combination values, e.g. micro_mov_es_or_sigma.
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

        //        type,   a/b,  nl/nx, destination,  source
        rom[0] = {3'b001, 7'd0, 2'b10, micro_mov_r,  micro_mov_rm};
        rom[1] = {3'b001, 7'd0, 2'b10, micro_mov_rm, micro_mov_r};

        for (int i = 2; i < 512; i++)
            rom[i] = 0;

        for (int i = 0; i < 256; i++)
            translation_rom[i] = 0;

        for (int i = 0; i < 2; i++)
            translation_rom[{7'b1000101, i[0]}] = 9'd0; // MOV mem -> reg

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
    reg [1:0] mov_from; // 0,3: reg, 1: mem, 2: imm
    // @todo: Maybe we should latch the imm value?

    wire [15:0] reg_read = 
         (mov_src_size == 1) ? registers[reg_src]:
        ((reg_src[2]   == 0) ? {8'd0, registers[{1'd0, reg_src[1:0]}][7:0]}:
                               {8'd0, registers[{1'd0, reg_src[1:0]}][15:8]});

    assign regfile_write_data_temp =
         (mov_from == 2'b01) ? data_in:
        ((mov_from == 2'b10) ? imm:
                               reg_read);

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

    // Program counter
    // The PC is a 16-bit binary counter that holds the offset
    // information of the memory address of the program that the
    // execution unit (EXU) is about to execute.
    reg [15:0] PC;

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
        .segment(segment_registers[ea_segment_reg]), // @todo: Get from segment registers.
        .base(registers[ea_base_reg[2:0]]),
        .index(registers[ea_index_reg[2:0]]),
        .displacement((disp_size == 1)? disp: {{8{disp[7]}}, disp[7:0]}) // Sign extend
    );

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

    always_ff @ (posedge clk)
    begin
        if(reset)
        begin
            microprogram_counter    <= 0;
            PC                      <= 16'h0000;
            state                   <= STATE_OPCODE_READ;
        end
        else
        begin

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
                if(!queue_empty)
                begin
                    // Get instruction from queue_buffer if it's not empty.
                    if(state == STATE_OPCODE_READ)
                        PC <= PC + 1;
                    state <= next_state;
                end
            end
            else if(state == STATE_EXECUTE || (state == STATE_RW_WAIT && bus_command_done))
            begin
                state <= next_state;

                // Set the bus command to idle when done.
                bus_command <= BUS_COMMAND_IDLE;
                // @important: If the bus command is not done, it is
                // important to keep 'register_we = 1' so that the register
                // eventually gets written to when the data is ready.
                regfile_we           <= 0;
                microprogram_counter <= (instruction_done == 1) ? 0: microprogram_counter + 1;

                // @note: We could also add combinational logic for reg_src,
                // and reg_dst, and just latch here. Let's see what's
                // simpler.


                // @todo: Handle segment registers separately.
                // This depends on destination.

                // * Handle move command *

                // ** Handle move source reading **
                if(micro_mov_src == micro_mov_rm && mod != 2'b11)
                begin
                    // Source is memory
                    bus_address  <= physical_address;
                    bus_command  <= BUS_COMMAND_READ;
                    state        <= STATE_RW_WAIT;

                    mov_from     <= 2'b01;
                    mov_src_size <= opcode[0];
                end
                else if(micro_mov_src == micro_mov_rm || micro_mov_src == micro_mov_r)
                begin
                    // Source is register specified by modrm.
                    reg_src      <= src_operand[2:0];
                    mov_from     <= 2'b00;
                    mov_src_size <= opcode[0];
                end
                else if(micro_mov_src == micro_mov_imm)
                begin
                    // Source is immediate.
                    mov_from  <= 2'b10;
                    mov_src_size <= imm_size;
                end
                else
                begin
                    // Source is register specified by micro_op.
                    if(micro_mov_src >= micro_mov_aw)
                    begin
                        // Source is word register
                        reg_src <= {micro_mov_src[3], micro_mov_src[1:0]};
                        mov_src_size  <= 1;
                    end
                    else
                    begin
                        // Source is byte register
                        reg_src <= micro_mov_src[2:0];
                        mov_src_size  <= 0;
                    end

                    mov_from <= 2'b00;
                end


                // ** Handle move destination writing **
                if(micro_mov_dst == micro_mov_rm && mod != 2'b11)
                begin
                    // Destination is memory
                    bus_address  <= physical_address;
                    bus_command  <= BUS_COMMAND_WRITE;
                    state        <= STATE_RW_WAIT;

                    mov_dst_size <= opcode[0];
                end
                else if(micro_mov_dst == micro_mov_rm || micro_mov_dst == micro_mov_r)
                begin
                    // Destination is register specified by modrm.
                    reg_dst      <= dst_operand[2:0];
                    mov_dst_size <= opcode[0];
                    regfile_we   <= 1;
                end
                else
                begin
                    // Destination is register specified by micro_op.
                    regfile_we <= 1;

                    if(micro_mov_dst >= micro_mov_aw)
                    begin
                        // Destination is word register
                        reg_dst <= {micro_mov_dst[3], micro_mov_dst[1:0]};
                        mov_dst_size <= 1;
                    end
                    else
                    begin
                        // Destination is byte register
                        reg_dst <= micro_mov_dst[2:0];
                        mov_dst_size <= 0;
                    end

                end

                // Handle other commands
                case(micro_op[21:19])

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
