module main
(
    input clk,
    input reset
);
    wire [15:0] segment_registers[0:3];
    reg sregfile_we;
    reg [15:0] sregfile_write_data;
    reg [1:0] sregfile_write_id;

    reg eu_sreg_write_done;
    wire [15:0] eu_sreg_write_data;
    wire [1:0] eu_sreg_write_id;
    wire eu_sreg_we;

    register_file#(4) segment_register_file_inst
    (
        .clk(clk),
        .reset(reset),

        .we(sregfile_we || eu_sreg_we),
        .write_id(sregfile_we ? sregfile_write_id: eu_sreg_write_id),
        .write_data(sregfile_we ? sregfile_write_data: eu_sreg_write_data),

        .registers(segment_registers)
    );

    execution_unit execution_unit_inst
    (
        .clk(clk),
        .reset(reset),

        .segment_registers(segment_registers),
        .sreg_write_done(eu_sreg_write_done),

        .sreg_write_data(eu_sreg_write_data),
        .sreg_write_id(eu_sreg_write_id),
        .sreg_we(eu_sreg_we)
    );

    reg [15:0] count;

    //assign sregfile_we = ~count[1];
    //assign sregfile_write_id = {count[2], count[0]};
    //assign sregfile_write_data = count;

    always_ff @(posedge clk)
    begin
        if(reset)
        begin
            count <= 0;
            eu_sreg_write_done <= 0;
            sregfile_we <= 0;
        end
        else
        begin
            count <= count + 1;
            sregfile_we <= 0;
            eu_sreg_write_done <= 0;

            if(eu_sreg_we && !sregfile_we)
            begin
                eu_sreg_write_done <= 1;
            end

            if(count[2:0] == 0)
            begin
                sregfile_we <= 1;
                sregfile_write_data <= count + 5;
                sregfile_write_id = {count[3], count[0]};
            end
        end
    end

endmodule

module execution_unit
(
    input clk,
    input reset,

    input [15:0] segment_registers[0:3],
    input sreg_write_done,

    output reg [15:0] sreg_write_data,
    output reg [1:0] sreg_write_id,
    output reg sreg_we
);
    always_latch
    begin
        if(reset)
            sreg_we <= 0;
        else if(count[1:0] == 1)
        begin
            sreg_we <= 1;
            sreg_write_data <= count;
            sreg_write_id <= count[3:2];
        end
        else if(sreg_write_done)
            sreg_we <= 0;
    end

    reg [15:0] count;
    always_ff @(posedge clk)
    begin
        if(reset)
        begin
            count <= 0;
        end
        else
        begin
            count <= count + 1;
        end
    end

endmodule

module register_file
#(
    parameter NUM_REGISTERS=8
)
(
    input clk,
    input reset,
    input we,
    input [$clog2(NUM_REGISTERS)-1:0] write_id,
    input [15:0] write_data,

    output reg [15:0] registers[0:NUM_REGISTERS-1]
);

    always_ff @(posedge clk)
    begin
        if(reset)
        begin
            for(int i = 0; i < NUM_REGISTERS; ++i)
                registers[i] <= 16'd0;
        end
        else
        begin
            if(we)
            begin
                registers[write_id] <= write_data;
            end
        end
    end
endmodule
