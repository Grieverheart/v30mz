# V30MZ core

My first HDL project, a V30MZ core written in SystemVerilog.

# Progress

Currently stuck at REP STM instruction 0xF3 0xAB of bootrom.

# TODO

* The addressing mode calculator in decode.sv should probably be moved to inside the physical address calculator. Then we can just set mod/rm when we want to change the addressing mode. It also greatly simplifies the needed arguments for the physical address calculator.
* Implement block manipulation instructions (hard one).
* Implement sram in simulation.
* Set alu flags in PSW?
* Handle 's' sign extension specification opcode bit in 'ALU r/m, imm' alu instructions. Note: imm8 is sign-extended to 16-bit. Also not sure if the 'W' bit is 1 or 0 in this case, but it could be tricky handling the sizing correctly.
* Add testing. The most useful for now would be regression testing. Need to parse vcd file and watch a number of variables over time and perhaps write a script to compare two vcd files for the specified variables. These variables should be the most important state, like PC, normal and segment registers, microaddress, etc.
* Implement pipelining by decoupling the execution state.
* Implement even/odd address reading/writing.
