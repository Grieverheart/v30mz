# V30MZ core

My first HDL project, a V30MZ core written in SystemVerilog.

# Progress

Currently stuck at CLR1 DIR instruction 0xFC (PC = 0x5A) of bootrom.

# TODO

* Implement control flags?
* Implement block manipulation instructions (hard one).
* Set alu flags in PSW?
* Implement CLR1 DIR instruction.
* Create a reg for setting it when an error is detected, for debugging purposes. It's difficult to see if I have not implemented something.
* Handle 's' sign extension specification opcode bit in 'ALU r/m, imm' alu instructions. Note: imm8 is sign-extended to 16-bit. Also not sure if the 'W' bit is 1 or 0 in this case, but it could be tricky handling the sizing correctly.
* Handle sign extension for short-labels.
* Add testing. The most useful for now would be regression testing. Need to parse vcd file and watch a number of variables over time and perhaps write a script to compare two vcd files for the specified variables. These variables should be the most important state, like PC, normal and segment registers, microaddress, etc.
* Implement pipelining by decoupling the execution state.
* Implement even/odd address reading/writing.
