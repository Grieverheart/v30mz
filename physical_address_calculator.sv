module physical_address_calculator
(
    input [2:0] factors,
    input [15:0] segment,
    input [15:0] base,
    input [15:0] index,
    input [15:0] displacement,
    output [19:0] physical_address
);

    assign physical_address =
        {segment, 4'd0} +
        (factors[2]? {4'd0, base}: 0) +
        (factors[1]? {4'd0, index}: 0) +
        (factors[0]? {4'd0, displacement}: 0);

endmodule
