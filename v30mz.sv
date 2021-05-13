
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

module v30mz_disassembler
(
    input clk,
    input reset,
    input readyb,
    input [15:0] data_in,

    output logic [19:0] address_out,
    output logic [3:0] bus_status,

    // Debug output
    output reg [2:0] state,
    output reg prefetch_request,
    output [7:0] prefetch_data,
    output queue_full,
    output queue_empty,
    output reg push_queue,
    output pop_queue
);

    localparam [2:0]
        state_opcode_read = 3'd0,
        state_modrm_read  = 3'd1,
        state_disp_read   = 3'd2,
        state_imm_read    = 3'd3,
        state_execute     = 3'd4;

    // General purpose registers
    // There are four 16-bit registers. These can be not only used
    // as 16-bit registers, but also accessed as 8-bit registers
    // (AH, AL, BH, BL, CH, CL, DH, DL) by dividing each register
    // into the higher 8 bits and the lower 8 bits.
    reg [15:0] AW, BW, CW, DW;

    // Segment registers
    // The V30MZ can divide the memory space into logical segments
    // in 64 K-byte units and control up to 4 segments
    // simultaneously (segment system). The V30MZ can distinguish
    // 4 kinds of segment (program, stack, data 0, data 1). The
    // start address of each segment is specified by the following
    // 4 segment registers.
    reg [15:0] PS, SS, DS0, DS1;

    // Pointer
    // The pointer consists of two 16-bit registers (stack pointer
    // (SP) and base pointer (BP)).
    reg [15:0] SP, BP;

    // Program counter
    // The PC is a 16-bit binary counter that holds the offset
    // information of the memory address of the program that the
    // execution unit (EXU) is about to execute.
    reg [15:0] PC;

    // Program status word
    // The PSW consists of 6 kinds of status flag and 4 kinds of
    // control flag.
    // @todo: Probably easier to separate flags.
    reg [15:0] PSW;

    // Index registers
    // This consists of two 16-bit registers (IX, IY). In a
    // memory data reference, it is used as an index register to
    // generate effective addresses (each register can also be
    // referenced in an instruction).
    reg [15:0] IX, IY;


    reg [1:0] reset_counter;

    wire [15:0] PFP;
    assign address_out = (reset_counter == 0)? 20'hfffff: {PS, 4'd0} + {4'd0, PFP};
    assign pop_queue = !reset && (state != state_execute) && !queue_empty;

    prefetch_queue prefetch_inst
    (
        .clk(clk),
        .reset(reset_counter == 0),
        .pop(pop_queue),
        .push(push_queue),
        .data_in(data_in),

        .PFP(PFP),
        .data_out(prefetch_data),
        .empty(queue_empty),
        .full(queue_full)
    );

    reg [7:0] opcode;
    reg [7:0] modrm;
    wire has_prefix;
    wire need_modrm;
    wire need_disp;
    wire need_imm;
    wire imm_size;
    wire disp_size;
    wire [3:0] src;
    wire [3:0] dst;

    always_latch
    begin
        // @todo: check prefix.
        if(state == state_opcode_read)     opcode = prefetch_data;
        else if(state == state_modrm_read) modrm  = prefetch_data;
    end

    // It also makes it easier at initialization, as the opcode takes the
    // value in prefetch_data, at least if it's not empty.

    decode decode_inst
    (
        .opcode(opcode),
        .modrm(modrm),

        .need_modrm(need_modrm),

        .need_disp(need_disp),
        .disp_size(disp_size),

        .need_imm(need_imm),
        .imm_size(imm_size),

        .src(src),
        .dst(dst)
    );

    wire [2:0] next_state;

    assign next_state =
        (state == state_opcode_read) ?
            (need_modrm ? state_modrm_read:
            (need_disp  ? state_disp_read:
            (need_imm   ? state_imm_read:
                          state_opcode_read))):
        (state == state_modrm_read) ?
            (need_disp  ? state_disp_read:
            (need_imm   ? state_imm_read:
                          state_opcode_read)):
        (state == state_disp_read) ?
            (need_imm   ? state_imm_read:
                          state_opcode_read):
                          state_opcode_read;

    reg reset_initiated;
    always_ff @ (posedge clk)
    begin
        if(reset)
        begin
            if(!reset_initiated)
            begin
                reset_initiated = 1'b1;
            end
            else
            begin
                if(reset_counter != 0)
                    reset_counter <= reset_counter - 1;
                else
                begin
                    reset_counter <= 2'd3;

                    bus_status <= 4'hf;

                    PC  <= 16'h0000;
                    PS  <= 16'hFFFF;
                    SS  <= 16'h0000;
                    DS0 <= 16'h0000;
                    DS1 <= 16'h0000;
                    PSW <= 16'b1111000000000010;

                    state <= state_opcode_read;

                    // Reset queue
                    push_queue <= 0;
                    prefetch_request <= 0;
                end
            end
        end
        else
        begin
            // Bus control unit

            // @note: This commented out block reads without returning the bus
            // status back to 4'b1111, unless we stop reading, which in this
            // case happens when the queue is full.
            push_queue <= 0;
            //if(!queue_full)
            //begin
            //    prefetch_request <= 1;
            //    bus_status <= 4'b1001;
            //end
            //else
            //begin
            //    prefetch_request <= 0;
            //    bus_status <= 4'b1111;
            //end

            //if(prefetch_request && !readyb)
            //begin
            //    push_queue <= 1;
            //end

            // Data read request, get prefetch data from data bus.
            if(prefetch_request && !readyb)
            begin
                push_queue <= 1;
                prefetch_request <= 0;
                bus_status <= 4'b1111;
            end
            else if(!prefetch_request && !queue_full)
            begin
                // Prefetch instruction if not full, or waiting for memory.
                prefetch_request <= 1;
                bus_status <= 4'b1001;
            end

            // Fetch instruction bytes
            case(state)

                state_opcode_read:
                begin
                    // Get instruction from queue_buffer if it's not empty.
                    if(!queue_empty)
                    begin
                        PC <= PC + 1;
                        state <= next_state;
                    end

                end

                default: state <= next_state;

            endcase
        end
    end

endmodule;

