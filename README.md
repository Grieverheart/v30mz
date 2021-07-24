# V30MZ core

My first HDL project, a V30MZ core written in SystemVerilog.

# Progress

Currently stuck at DS1: instruction 0x26 of bootrom.

# TODO

* Memory read request don't always work properly. See e.g. instruction 0x8A at 0x67. Investigate.
* Implement more block manipulation instructions.
* Set alu flags in PSW?
* Handle 's' sign extension specification opcode bit in 'ALU r/m, imm' alu instructions. Note: imm8 is sign-extended to 16-bit. Also not sure if the 'W' bit is 1 or 0 in this case, but it could be tricky handling the sizing correctly.
* Add testing. The most useful for now would be regression testing. Need to parse vcd file and watch a number of variables over time and perhaps write a script to compare two vcd files for the specified variables. These variables should be the most important state, like PC, normal and segment registers, microaddress, etc.
* Implement pipelining by decoupling the execution state.
* Implement even/odd address reading/writing.
