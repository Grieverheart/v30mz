# V30MZ core

My first HDL project, a V30MZ core written in SystemVerilog.

# Progress

Alu instructions are not correctly implemented it seems. See e.g. instruction 0x83 at 0x11A. src_operand and dst_operand are a bit mixed up.
Need to correctly and consequently set the source and destination of the alu operation, preferrably the same convention as mov microinstructions,
source at least significant operand, and destination at most significant operand. Then we probably only need to change the order in the
microinstructions. For example, 

```c
rom[16] = {MICRO_TYPE_ALU, 5'd0, MICRO_ALU_USE_RESULT, 2'd0, MICRO_ALU_OP_XI,  2'b10, MICRO_MOV_IMM, MICRO_MOV_AW};
```
would become

```c
rom[16] = {MICRO_TYPE_ALU, 5'd0, MICRO_ALU_USE_RESULT, 2'd0, MICRO_ALU_OP_XI,  2'b10, MICRO_MOV_AW, MICRO_MOV_IMM};
```
Also when doing alu writeback, we need to use the correct operand.

# TODO

* Need to implement upper byte enable (UBE) bit when writing to bus.
* Find a way to get a known waveform for the BIOS.
* Set alu flags in PSW?
* Handle 's' sign extension specification opcode bit in 'ALU r/m, imm' alu instructions. Note: imm8 is sign-extended to 16-bit. Also not sure if the 'W' bit is 1 or 0 in this case, but it could be tricky handling the sizing correctly.
* Add testing. The most useful for now would be regression testing. Need to parse vcd file and watch a number of variables over time and perhaps write a script to compare two vcd files for the specified variables. These variables should be the most important state, like PC, normal and segment registers, microaddress, etc.
* Implement pipelining by decoupling the execution state.
* Implement even/odd address reading/writing.
* Do we always have to wait for write bus operation to finish? In some sense I guess we do, e.g. if for some reason it takes more time to write than expected.
* Implement more block manipulation instructions.
