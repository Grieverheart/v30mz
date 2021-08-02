# V30MZ core

My first HDL project, a V30MZ core written in SystemVerilog.

# Progress

It seems evident that we need to handle EEPROM commands to progress.

# TODO

* Handle EEPROM commands in verilator simulation.
* Find a way to get a known waveform for the BIOS.
* I often do the check `mod != 2'b11`, but modrm is not always present. We should add a check for need_modrm just to be sure.
* Set alu flags in PSW?
* Handle 's' sign extension specification opcode bit in 'ALU r/m, imm' alu instructions. Note: imm8 is sign-extended to 16-bit. Also not sure if the 'W' bit is 1 or 0 in this case, but it could be tricky handling the sizing correctly.
* Add testing. The most useful for now would be regression testing. Need to parse vcd file and watch a number of variables over time and perhaps write a script to compare two vcd files for the specified variables. These variables should be the most important state, like PC, normal and segment registers, microaddress, etc.
* Implement pipelining by decoupling the execution state.
* Implement even/odd address reading/writing.
* Do we always have to wait for write bus operation to finish? In some sense I guess we do, e.g. if for some reason it takes more time to write than expected.
* Implement more block manipulation instructions.
