module mover
(
    input clk,
    input reset,
    input [15:0] data_in,
    input [2:0] src,
    input [2:0] dst,
    input ce,
    input we,

    // Debug
    output [15:0] registers[0:7]
);

    register_file regfile
    (
        .clk(clk),
        .reset(reset),
        .data_in(ce_last? registers[src_last]: data_in),
        .write_id(ce_last? dst_last: dst),
        .we(we | ce_last),
        .registers(registers)
    );

    reg [2:0] src_last;
    reg [2:0] dst_last;
    reg ce_last;

    always @(posedge clk)
    begin
        // Latch copy signals
        src_last <= src;
        dst_last <= dst;
        ce_last  <= ce;
    end

endmodule

module register_file
(
    input clk,
    input reset,

    input [15:0] data_in,
    input [2:0] write_id,
    input we,

    output reg [15:0] registers[0:7]
);

    always @(posedge clk)
    begin
        if(reset)
        begin
            for(int i = 0; i < 8; ++i)
                registers[i] <= 0;
        end
        else if(we)
            registers[write_id] <= data_in;
    end

endmodule
