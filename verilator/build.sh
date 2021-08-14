#!/bin/bash
../../verilator/bin/verilator -O3 -Wno-fatal -trace --top-module 'v30mz' -I.. --cc ../v30mz.sv --exe v30mz_sim.cpp
#verilator -O3 -Wno-fatal -trace --top-module 'v30mz' -I.. --cc ../v30mz.sv --exe v30mz_sim.cpp
