# V30MZ core

My first HDL project, a V30MZ core written in SystemVerilog.

# Progress

Currently stuck at branch instruction 0x73 of bootrom.

# TODO

* Fix alu D0, and alu handling in general. We need to be able to specify both operands in a single microinstruction.
* Implement pipelining by decoupling the execution state.
* Implement even/odd address reading/writing.
