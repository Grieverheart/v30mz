# V30MZ core

My first HDL project, a V30MZ core written in SystemVerilog.

# Progress

Currently stuck at PUSH instruction 0x53 of bootrom. The instruction runs in 1 clock cycle on the V30MZ. In current microcode I can only implement it in 3 clock cycles, as I have to first do an ALU operation, then mov the result to the bus_address, and then do the bus operation. Generally, the push operation is described as:

SP <- SP - 2
(SP + 1, SP) <- reg

But if you write it as,

(SP - 1, SP - 2) <- reg
SP <- SP - 2

then the two micro operation are independent. The first is a move and the second a decrement. I guess it's much easier to just implement in Verilog. I'm thinking that we could add an option to modify the bus_address by 2^1, 2^2, 2^3, 2^4, when doing a bus operation. I don't know what microcode you could write that can do these two operation in a single microcode instruction. Maybe the V30MZ doesn't have this implemented in microcode either. What's weird is that the V20/V30 already use 29bit-wide microinstructions and have 1024 microinstruction ROM. For comparison, I currently use 22bit-wide microinstructions. For example for the bus microinstruction we could do the same as we did with the alu microinstruction, namely use the move operands as address and data sources. This already allows us to do the first microoperation using the current 22bit-wide microinstructions. Then with the additional 7 bits, we could somehow also do the second microoperation? 1 bit for inc/dec, 3 bits for amount (0 is nothing, n>0 is 2^(n-1)). That leaves another 3 bits that could for example be used for applying this opearation to a different register.


# TODO

* Trying making the bus microop operands work like for the alu microop; first operand is address, second is data_in or data_out.
* Implement PUSH.
* Implement addition of segment in effective address when doing a bus operation.
* Implement more block manipulation instructions.
* Set alu flags in PSW?
* Handle 's' sign extension specification opcode bit in 'ALU r/m, imm' alu instructions. Note: imm8 is sign-extended to 16-bit. Also not sure if the 'W' bit is 1 or 0 in this case, but it could be tricky handling the sizing correctly.
* Add testing. The most useful for now would be regression testing. Need to parse vcd file and watch a number of variables over time and perhaps write a script to compare two vcd files for the specified variables. These variables should be the most important state, like PC, normal and segment registers, microaddress, etc.
* Implement pipelining by decoupling the execution state.
* Implement even/odd address reading/writing.
