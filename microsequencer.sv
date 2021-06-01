// @todo: Perhaps we need to move the instruction byte reading logic from
// v30mz.sv to here. The register file is going to live here, which means also
// the PC. It is this easier to be able to change it from a single place. This
// module will then actually become the whole execution unit.

module microsequencer
(
    input clk,
    input reset,
    input [7:0] opcode,

    input [3:0] src_operand,
    input [3:0] dst_operand,

    input [1:0] mod,
    input [2:0] rm,

    input [15:0] imm,
    input imm_size,

    input [15:0] disp,
    input disp_size,

    // Effective address registers
    input [3:0] ea_base_reg,
    input [3:0] ea_index_reg,
    input [1:0] ea_segment_reg,

    input [15:0] segment_registers[0:3],

    output reg [4:0] aluop,
    output reg instruction_done,
    output reg instruction_nearly_done,

    // Bus
    output reg [1:0]  bus_command,
    output reg [19:0] bus_address,
    output reg [15:0] data_out,
    input [15:0] data_in,
    input bus_command_done

    // Segment register input and output
    // @todo: We need to be able to read and write to the segment registers.
    // We know these take an additional cycle because they have to go to the
    // BCU.
);
    localparam [1:0]
        BUS_COMMAND_IDLE  = 2'd0,
        BUS_COMMAND_READ  = 2'd1,
        BUS_COMMAND_WRITE = 2'd2;

    // @info: The opcode is translated directly to a rom address. This can be done by
    //creating a rom of size 256 indexed by the opcode, where the value is
    //equal to the microcode rom address.

    // @todo: Initialize roms
    reg [8:0] translation_rom[0:255];
    reg [20:0] rom[0:511];

    localparam [4:0]
        micro_mov_none = 5'h00,
        // register specified by opcode (r field of modrm).
        micro_mov_r    = 5'h01,
        // register or memory specified by opcode (e.g. rm field of modrm).
        micro_mov_rm   = 5'h02,
        // immediate value specified by opcode bytes.
        micro_mov_imm  = 5'h03,
        // all registers:
        micro_mov_al   = 5'h04,
        micro_mov_cl   = 5'h05,
        micro_mov_dl   = 5'h06,
        micro_mov_bl   = 5'h07,

        micro_mov_ah   = 5'h08,
        micro_mov_ch   = 5'h09,
        micro_mov_dh   = 5'h0a,
        micro_mov_bh   = 5'h0b,

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

    initial
    begin
        rom[0] = {1'b1, 7'd0, 3'b001, micro_mov_r, micro_mov_rm};
        rom[1] = {1'b1, 7'd0, 3'b001, micro_mov_rm, micro_mov_r};

        for (int i = 2; i < 512; i++)
            rom[i] = 0;

        for (int i = 0; i < 256; i++)
            translation_rom[i] = 0;

        for (int i = 0; i < 2; i++)
            translation_rom[{7'b1000101, i[0]}] = 9'd0; // MOV mem -> reg

    end

    reg regfile_we;
    wire [2:0] regfile_write_id;
    wire [1:0] regfile_write_part;
    wire [15:0] regfile_write_data;
    wire [15:0] regfile_write_data_temp;
    wire [15:0] registers[0:7];

    // Latched mov info for performing mov on next posedge clk.
    reg [2:0] reg_src;
    reg [2:0] reg_dst;
    reg mov_src_size;
    reg [1:0] reg_write_part;
    reg [1:0] mov_from; // 0,3: reg, 1: mem, 2: imm
    // @todo: Maybe we should latch the imm value?

    wire [15:0] reg_read = (mov_src_size == 0)? (
        {8'd0, (reg_src[2] == 0)? registers[{1'd0, reg_src[1:0]}][7:0]:
                                  registers[{1'd0, reg_src[1:0]}][15:8]}
    ): registers[reg_src];

    assign regfile_write_id = reg_dst;
    assign regfile_write_data_temp =  (mov_from == 2'b01) ? data_in:
                                     ((mov_from == 2'b10) ? imm:
                                                            reg_read);

    assign regfile_write_data = (mov_src_size == 1) ? regfile_write_data_temp: {8'd0, regfile_write_data_temp[7:0]};
    assign regfile_write_part = reg_write_part;

    //// @refactor: Perhaps it's more legible with a combinatorial block.
    //// @todo: Perhaps we need to also latch this.
    //assign register_write_part =
    //    (micro_mov_dst == micro_mov_r || micro_mov_dst == micro_mov_rm)?
    //        ((dst_operand < 4'd4)? 2'b01:
    //         (dst_operand < 4'd8)? 2'b10:
    //                               2'b11):
    //    ((micro_mov_dst >= micro_mov_al && micro_mov_dst < micro_mov_ah)?  2'b01:
    //     ((micro_mov_dst >= micro_mov_ah && micro_mov_dst < micro_mov_aw)? 2'b10:
    //                                                                       2'b11));

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
        .write_part(regfile_write_part),
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
    wire [20:0] micro_op;
    wire [8:0] address;

    wire [4:0] micro_mov_src;
    assign micro_mov_src = micro_op[4:0];

    wire [4:0] micro_mov_dst;
    assign micro_mov_dst = micro_op[9:5];

    assign address = translation_rom[opcode];
    assign micro_op = rom[address + {5'd0, microprogram_counter}];

    // micro_op:
    // -----------------------
    // 0:4; source
    // 5:9; destination
    // 10:19; type, a, b
    // 20; next_last

    localparam
        //STATE_DECODE_WAIT = 0,
        STATE_EXECUTE = 0,
        STATE_RW_WAIT = 1;

    reg state;

    always @ (posedge clk)
    begin
        if(reset)
        begin
            microprogram_counter    <= 0;
            instruction_done        <= 0;
            instruction_nearly_done <= 0;
            state                   <= STATE_EXECUTE;
        end
        else
        begin
            instruction_done        <= 0;
            instruction_nearly_done <= 0;

            if(state == STATE_EXECUTE || bus_command_done)
            begin
                // Set the bus command to idle when done.
                bus_command <= BUS_COMMAND_IDLE;
                // @important: If the bus command is not done, it is
                // important to keep 'register_we = 1' so that the register
                // eventually gets written to when the data is ready.
                regfile_we           <= 0;
                microprogram_counter <= microprogram_counter + 1;

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
                        reg_src <= {micro_mov_src[3], micro_mov_src[1:0]};
                        mov_src_size  <= 1;
                    end
                    else
                    begin
                        reg_src <= micro_mov_src[2:0];
                        mov_src_size  <= 0;
                    end

                    mov_from <= 2'b00;
                end

                // ** Handle move destination writing **
                // @todo

                // Handle other commands
                case(micro_op[12:10])

                    // short jump
                    3'b000, 3'b100:
                    begin
                    end

                    // alu
                    3'b010, 3'b110:
                    begin
                        aluop <= micro_op[16:12];
                        instruction_nearly_done <= micro_op[20];
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
