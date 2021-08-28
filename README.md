# V30MZ core

My first HDL project, a V30MZ core written in SystemVerilog.

# Progress

Currently stuck at rep instruction 0xA4 MOVBKB.

# TODO

* We need a way to tell if the bus operation is byte or word, or if it should e.g. check the byte_word_field. This requires 2 additional bits. Alternatively, for instructions with a W field, we can have two separate microprograms. This requires the addition of MICRO_MOV_TMPW, MICRO_MOV_TMPL, MICRO_MOV_TMPH, which is probably a good idea anyway. Otherwise we can build some random logic for finding out if the instruction actually has a 'W' bit, otherwise set to 1?
* Can we implement STMW in microcode?
* Implement alu constant (source?) operand in the unused 5 bits of the microinstruction. But 5 bits are not really enough for signed 16 constant. We do have another 2 unused microinstruction bits, although in the future we might need to use one for enabling/disabling flag updating.
* Need to implement upper byte enable (UBE) bit when writing to bus.
* Find a way to get a known waveform for the BIOS.
* Set alu flags in PSW?
* Handle 's' sign extension specification opcode bit in 'ALU r/m, imm' alu instructions. Note: imm8 is sign-extended to 16-bit. Also not sure if the 'W' bit is 1 or 0 in this case, but it could be tricky handling the sizing correctly.
* Add testing. The most useful for now would be regression testing. Need to parse vcd file and watch a number of variables over time and perhaps write a script to compare two vcd files for the specified variables. These variables should be the most important state, like PC, normal and segment registers, microaddress, etc.
* Implement pipelining by decoupling the execution state.
* Implement even/odd address reading/writing.
* Do we always have to wait for write bus operation to finish? In some sense I guess we do, e.g. if for some reason it takes more time to write than expected.
* Implement more block manipulation instructions.
