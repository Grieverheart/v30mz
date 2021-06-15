#!/bin/bash
#verilator -O3 -trace --top-module 'v30mz' -I.. --cc ../v30mz.sv --exe v30mz_sim.cpp
#verilator -O3 -Wno-fatal -trace --top-module 'microsequencer' -I.. --cc ../microsequencer.sv --exe microsequencer_sim.cpp
#verilator -O3 -Wno-fatal -trace --top-module 'mover' -I.. --cc ../mover.sv --exe mover_sim.cpp
verilator -O3 -Wno-fatal -trace --top-module 'main' -I.. --cc ../segment_register_bus_test.sv --exe segment_register_bus_test.cpp
