#!/bin/bash
./build.sh
make -C obj_dir/ -f Vv30mz.mk
./obj_dir/Vv30mz
