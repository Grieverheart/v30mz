
// The V30MX can be divided roughly into 2 processing units; the
// execution unit (EXU) and bus control unit (BCU). Each unit
// operates asynchronously, independent of the other, thus improving
// bus utilization efficiency and achieving high-speed execution of
// instructions.
//
// In execution of a branch, call, return or break instruction or
// servicing of an external interrupt, the content of the queue_buffer is
// cleared and an instruction at a new location is prefetched.
//
// Normally, the V30MX performs an access (prefetch) of an operation code in
// word units. However, when a branch to an odd address takes place, only 1
// byte at that odd address is fetched and subsequent bytes are fetched again
// in word units again.

// @MVP: Make v30mz read and decode instructions but not execute them. Perhaps
// we can build a kind of disassembler by reading the decoder output.

// Ideas:
//
// 1) Can pop single bytes, and we can pop multiple bytes at once. This way,
//    we only pop everything out of the queue after we are done decoding an
//    instruction. In addition, it allows for fetching multiple bytes from the
//    queue if we know we need them, e.g. if we read modrm and it tells us we
//    definitely need to read X more bytes, we have them available in the same
//    cycle. On the other hand, this means that the queue will be fuller than
//    perhaps needed.
//
//    assign instruction_byte_size = need_modrm? ...
//
//    always_latch
//    begin
//        if(state == state_opcode_read)
//        begin
//            // prefix needs to be set back to 0 when reading a new opcode.
//            opcode = prefix? prefetch_data[15:8]: prefetch_data[7:0];
//            if(need_modrm && prefetch_queue_size > 1)
//                modrm  = prefetch_data[15:8];
//            // Here we need complicated logic to calculate the byte offsets.
//            // If e.g. modrm was needed, we need to shift one byte. Later
//            // bytes end up more complicated because need to include logic
//            // for the flags before them. That is what the 'next_state'
//            // assignment basically does.
//            if(need_disp && prefetch_queue_size > 2)
//                disp  = prefetch_data[23:16];
//        end
//    end
//
//    need_... are handled by decoder. When the opcode is read, the opcode wire
//    is updated and thus the decoder immediately updates the need_... wires
//    accordingly. When modrm is the fetched, it triggers the decoder again.
//    It's a chain reaction, or a feedback loop that ends when the whole
//    instruction is decoded. We probably also need just two states here,
//    decode and execute.
//
// 2) Can pop single bytes but instead of popping them all at once, we pop
//    everytime we fetch. This makes the logic simpler in some sense, since the
//    location of the corresponding byte that needs to be read in a specific
//    state, is at the head of the queue, if it's not empty. The problem here
//    is that we spend a whole cycle just to shift the prefetch queue while
//    the data might be available.
//
// I would like to try both methods and see what the differences are in both
// efficiency and code/logic simplicity.
//
// ** Ideas microcode ** :
//
// Currently stuck at PUSH instruction 0x53 of bootrom. The instruction runs
// in 1 clock cycle on the V30MZ. In current microcode I can only implement it
// in 3 clock cycles, as I have to first do an ALU operation, then mov the
// result to the bus_address, and then do the bus operation. Generally, the
// push operation is described as:
//
//     SP <- SP - 2
//     (SP + 1, SP) <- reg
//
// But if you write it as,
//
//     (SP - 1, SP - 2) <- reg
//     SP <- SP - 2
//
// then the two micro operation are independent. The first is a move and the
// second a decrement. I guess it's much easier to just implement in Verilog.
// I'm thinking that we could add an option to modify the bus_address by 2^1,
// 2^2, 2^3, 2^4, when doing a bus operation. I don't know what microcode you
// could write that can do these two operation in a single microcode
// instruction. Maybe the V30MZ doesn't have this implemented in microcode
// either. What's weird is that the V20/V30 already use 29bit-wide
// microinstructions and have 1024 microinstruction ROM. For comparison,
// I currently use 22bit-wide microinstructions. For example for the bus
// microinstruction we could do the same as we did with the alu
// microinstruction, namely use the move operands as address and data sources.
// This already allows us to do the first microoperation using the current
// 22bit-wide microinstructions. Then with the additional 7 bits, we could
// somehow also do the second microoperation? 1 bit for inc/dec, 3 bits for
// amount (0 is nothing, n>0 is 2^(n-1)). That leaves another 3 bits that
// could for example be used for applying this opearation to a different
// register.
//
// How could REP STMW look like in microcode?
//
//     1. jump +1 if CW == 0 (note that we passed the STMW as a modrm byte).
//     2. set repeat flag, push the microaddress, and jump to microaddress
//        given by modrm byte.
//     3. ... runs STMW (here in the last microop contains condition to run
//        next microop based on repeat flag)
//     4. pop microaddress and decrement CW.
//
// but actually I'm getting headaches trying to figure out how to design the
// microcode.
// 1. is a short jump.
// 2. is a long jump with two additional ops.
// 4. is an alu operation with the addition pop op?
//
// I think with microcode, you spend most of the time designing the microcode
// instead of writing it. Let's get the shortest way to a functioning CPU and
// we can convert stuff to microcode later.

module v30mz
(
    input clk,
    input reset,
    input readyb,
    input [15:0] data_in,
    output [15:0] data_out,

    output logic [19:0] address_out,
    output logic [3:0]  bus_status,
    output logic bus_upper_byte_enable
);

    // Segment registers
    // The V30MZ can divide the memory space into logical segments
    // in 64 K-byte units and control up to 4 segments
    // simultaneously (segment system). The V30MZ can distinguish
    // 4 kinds of segment (program, stack, data 0, data 1). The
    // start address of each segment is specified by the following
    // 4 segment registers.
    wire [15:0] segment_registers[0:3];

    // @note: For now, only the execution unit can write to this register
    // file. I don't see any reason for the bus control unit needing to write
    // to the segment registers.
    segment_register_file segment_register_file_inst
    (
        .clk(clk),
        .reset(resetn),

        .we(eu_sreg_we),
        .write_id(eu_sreg_write_id),
        .write_data(eu_sreg_write_data),

        .registers(segment_registers)
    );

    wire [15:0] DS1 = segment_registers[0];
    wire [15:0] PS  = segment_registers[1];
    wire [15:0] SS  = segment_registers[2];
    wire [15:0] DS0 = segment_registers[3];

    // Program status word
    // The PSW consists of 6 kinds of status flag and 4 kinds of
    // control flag.
    // @todo: Probably easier to separate flags.
    reg [15:0] PSW;

    wire [15:0] PFP;

    reg [1:0] reset_counter;
    wire resetn = (reset_counter == 2'd3);

    assign address_out =
        (resetn)?
            20'hfffff:
        (eu_bus_command != BUS_COMMAND_IDLE && !prefetch_request)?
            eu_bus_address:
            {PS, 4'd0} + {4'd0, PFP};

    reg prefetch_request;
    wire [7:0] prefetch_data;

    wire queue_full;
    wire queue_empty;
    wire queue_pop;
    wire queue_push;
    wire queue_suspend;
    wire queue_flush;
    wire [15:0] PC;


    prefetch_queue prefetch_inst
    (
        .clk(clk),
        .reset(resetn | queue_flush),
        .pop(queue_pop),
        .push(queue_push),
        .PC(PC),
        .data_in(data_in),

        .PFP(PFP),
        .data_out(prefetch_data),
        .empty(queue_empty),
        .full(queue_full)
    );

    wire instruction_nearly_done;

    // @todo: Use these.
    wire [2:0]  eu_bus_command;
    wire [19:0] eu_bus_address;

    // @todo: Use these.
    wire [1:0]  eu_sreg_write_id;
    wire [15:0] eu_sreg_write_data;
    wire eu_sreg_we;

    execution_unit execution_unit_inst
    (
        .clk(clk),
        .reset(resetn),

        // Prefetch queue
        .prefetch_data(prefetch_data),
        .queue_empty(queue_empty),
        .queue_pop(queue_pop),
        .queue_suspend(queue_suspend),
        .queue_flush(queue_flush),

        .PC(PC),

        // Segment register input and output
        .segment_registers(segment_registers),

        .sregfile_write_data(eu_sreg_write_data),
        .sregfile_write_id(eu_sreg_write_id),
        .sregfile_we(eu_sreg_we),

        .instruction_nearly_done(instruction_nearly_done),

        // Bus
        .bus_command(eu_bus_command),
        .bus_address(eu_bus_address),
        .bus_upper_byte_enable(bus_upper_byte_enable),
        .data_out(data_out),

        .data_in(data_in),
        // We should not route readyb to EXU when we issued a prefetch.
        .bus_command_done(prefetch_request ? 0: !readyb)
    );

    assign queue_push = (!resetn && prefetch_request && !readyb)? 1: 0;

    always_latch
    begin
        if(reset && reset_counter == 2'd3)
        begin
            prefetch_request <= 0;
            bus_status <= 4'hf;
        end
        else
        begin
            // Finish prefetch before taking care of other r/w requests.
            if(!readyb)
                prefetch_request <= 0;

            // Prefetch instruction if not full, or waiting for memory.
            if(!queue_full && !queue_suspend)
            begin
                bus_status <= 4'b1001;
                prefetch_request <= 1;
            end

            // @todo: Try and see if separating the always_latch into two,
            // one for bus_status and one for prefetch_request, fixes the
            // issue with the feedback loop.
            else if(eu_bus_command == BUS_COMMAND_MEM_READ)
                bus_status <= 4'b1001;

            else if(eu_bus_command == BUS_COMMAND_MEM_WRITE)
                bus_status <= 4'b1010;

            else if(eu_bus_command == BUS_COMMAND_IO_READ)
                bus_status <= 4'b0101;

            else if(eu_bus_command == BUS_COMMAND_IO_WRITE)
                bus_status <= 4'b0110;

        end
    end

    // @todo: Move some things to always_latch.
    always_ff @ (posedge clk)
    begin
        if(reset)
        begin
            if(reset_counter == 2'd3)
            begin
                PSW <= 16'b1111000000000010;
            end
            else
                reset_counter <= reset_counter + 1;
        end
        else
        begin
            reset_counter <= 0;
        end
    end

endmodule;

