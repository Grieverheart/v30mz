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

    always @(posedge clk)
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
endmodule;
