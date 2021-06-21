# V30MZ core

My first HDL project, a V30MZ core written in SystemVerilog.

# Progress

Currently stuck at OUT instruction 0xe6 of bootrom.

# TODO

* Add bus microinstructions -- 2 bits for type of op mem read/write, io read/write.
* Implement IN/OUT instructions.
* Implement alu and microinstruction handling.
* Implement branching microinstruction.
* Implement microassembler.
* Implement pipelining by decoupling the execution state.
* Implement even/odd address reading/writing.
