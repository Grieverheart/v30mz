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
        micro_mov_none   = 5'h00,
        micro_mov_r      = 5'h01,
        micro_mov_rm     = 5'h02,
        micro_mov_imm    = 5'h03;

    initial
    begin
        rom[0] = {1'b1, 7'd0, 3'b001, micro_mov_r, micro_mov_rm};
        rom[1] = {1'b1, 7'd0, 3'b001, micro_mov_rm, micro_mov_r};

        for (int i = 0; i < 512; i++)
            rom[i] = 0;

        for (int i = 0; i < 256; i++)
            translation_rom[i] = 0;

        for (int i = 0; i < 2; i++)
            translation_rom[{7'b1000101, i[0]}] = 9'd0; // mem -> reg

    end

    reg register_we;
    wire [2:0] register_write_id;
    wire [1:0] register_write_part;
    wire [15:0] register_write_data;
    wire [15:0] registers[0:7];

    // Latched mov info for performing mov on next posedge clk.
    reg [2:0] mov_source_register;
    reg [2:0] mov_destination_register;
    reg       mov_from_memory;

    assign register_write_id   = mov_destination_register;
    assign register_write_data = mov_from_memory? data_in: registers[mov_source_register];
    // @todo: assign register_write_part = ...;

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
        .we(register_we),
        .write_part(register_write_part),
        .write_id(register_write_id),
        .write_data(register_write_data),
        .registers(registers)
    );

    wire [19:0] physical_address;
    physical_address_calculator pac
    (
        .physical_address(physical_address),
        .factors({ea_base_reg[3], ea_index_reg[3], &mod}),
        .segment(registers[8 + {2'd0, ea_segment_reg}]),
        .base(registers[ea_base_reg[2:0]]),
        .index(registers[ea_index_reg[2:0]]),
        .displacement((disp_size == 1)? disp: {{8{disp[7]}}, disp[7:0]}) // Sign extend
    );

    // @todo: Make this smaller
    reg [3:0] microprogram_counter;
    wire [20:0] micro_op;
    wire [8:0] address;

    wire [4:0] reg_source;
    assign reg_source = micro_op[4:0];

    wire [2:0] reg_destination;
    assign reg_destination = micro_op[5:3];

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
                // @important: If the bus command is not done, it is
                // important to keep 'register_we = 1' so that the register
                // eventually gets written to when the data is ready.
                register_we          <= 0;
                microprogram_counter <= microprogram_counter + 1;

                // Handle move command
                if(reg_source == micro_mov_rm && mod != 2'b11)
                begin
                    // Source is memory, destination is register.
                    bus_address <= physical_address;
                    bus_command <= BUS_COMMAND_READ;
                    state       <= STATE_RW_WAIT;

                    mov_destination_register <= dst_operand[2:0];
                    mov_from_memory          <= 1;
                    register_we              <= 1;
                end
                else if(reg_source == micro_mov_rm || reg_source == micro_mov_r)
                begin
                    // Source is register.
                end
                else
                begin
                end

                // Handle other commands
                case(micro_op[9:7])

                    // short jump
                    3'b000, 3'b100:
                    begin
                    end

                    // alu
                    3'b010, 3'b110:
                    begin
                        aluop <= micro_op[7:3];
                        instruction_nearly_done <= micro_op[0];
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
