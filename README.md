# V30MZ core

My first HDL project, a V30MZ core written in SystemVerilog.

# Progress

Currently stuck at OUT instruction 0xe6 at address 0xf0003. Also need to implement DI instruction, which sets the IE flag to 0.

# TODO

* Implement IN instruction.
* Implement alu and microinstruction handling.
* Implement branching microinstruction.
* Implement microassembler.
* Implement pipelining by decoupling the execution state.
