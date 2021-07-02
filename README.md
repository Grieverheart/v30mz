# V30MZ core

My first HDL project, a V30MZ core written in SystemVerilog.

# Progress

Currently stuck at ROL instruction 0xd0 of bootrom.

# TODO

* Implement correct alu sizing.
* Implement alu flags.
* Make sure the implemented alu produces the correct results.
* Implement alu and microinstruction handling.
* Add asserts for catching bugs.
* Implement branching microinstruction.
* Implement pipelining by decoupling the execution state.
* Implement even/odd address reading/writing.
