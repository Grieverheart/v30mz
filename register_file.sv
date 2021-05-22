module register_file
#(
    parameter NUM_REGISTERS=8
)
(
    input clk,
    input reset,
    input we,
    input [1:0] write_part,
    input [$clog2(NUM_REGISTERS)-1:0] write_id,
    input [15:0] write_data,

    output reg [15:0] registers[0:NUM_REGISTERS-1]
);

    always @(posedge clk)
    begin
        if(reset)
        begin
            for(int i = 0; i < 8; ++i)
                registers[i] <= 16'd0;
        end
        else
        begin
            if(we)
            begin
                if(write_part == 2'b11)
                    registers[write_id] <= write_data;
                else if(write_part == 2'b01)
                    registers[write_id][7:0] <= write_data[7:0];
                else if(write_part == 2'b10)
                    registers[write_id][15:8] <= write_data[15:8];
            end
        end
    end
endmodule;
