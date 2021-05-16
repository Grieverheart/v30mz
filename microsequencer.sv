
module microsequencer
(
    input clk,
    input reset,
    input [7:0] opcode,

    input [3:0] src,
    input [3:0] dst,

    input [1:0] mod,
    input [2:0] rm,

    input [15:0] imm,
    input imm_size,

    output reg [4:0] aluop,
    output reg instruction_done,
    output reg instruction_nearly_done,

    // Bus
    output reg [1:0]  bus_command,
    output reg [19:0] bus_address,
    output reg [15:0] data_out,
    input [15:0] data_in,
    input bus_command_done
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
    reg [3:0] read_dest;

    localparam [4:0]
        micro_reg_none   = 5'h00,
        micro_reg_r      = 5'h01,
        micro_reg_rm     = 5'h02,
        micro_reg_temp_a = 5'h03;

    initial
    begin
        rom[0] = {1'b1, 7'd0, 3'b001, micro_reg_r, micro_reg_rm};
        rom[1] = {1'b1, 7'd0, 3'b001, micro_reg_rm, micro_reg_r};

        for (int i = 0; i < 512; i++)
            rom[i] = 0;

        for (int i = 0; i < 256; i++)
            translation_rom[i] = 0;

        for (int i = 0; i < 2; i++)
            translation_rom[{7'b1000101, i[0]}] = 9'd0; // mem -> reg

    end

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

    // @todo:
    reg [15:0] regfile[0:15];

    localparam
        STATE_EXECUTE = 0,
        STATE_WAIT    = 1;

    always @ (bus_command_done)
    begin
        if(bus_command_done)
            regfile[read_dest] = data_in;
    end

    always @ (posedge clk)
    begin
        if(reset)
        begin
            microprogram_counter    <= 0;
            instruction_done        <= 0;
            instruction_nearly_done <= 0;
        end
        else
        begin
            instruction_done        <= 0;
            instruction_nearly_done <= 0;

            if(bus_command_done || bus_command == BUS_COMMAND_IDLE)
            begin
                microprogram_counter <= microprogram_counter + 1;

                // Move command
                if(reg_source == micro_reg_rm && mod != 2'b11)
                begin
                    // Read from memory
                    bus_address <= 0;//...;
                    bus_command <= BUS_COMMAND_READ;
                    read_dest = dst;
                end
                else if(reg_source == micro_reg_rm || reg_source == micro_reg_r)
                begin
                    regfile[dst] <= regfile[src];
                end
                else
                begin
                end

                // Other commands
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
