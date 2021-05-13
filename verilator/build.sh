#!/bin/bash
verilator -O3 -trace --top-module 'v30mz' -I.. --cc ../v30mz.sv --exe v30mz_sim.cpp
