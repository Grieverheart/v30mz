#include "Vv30mz_disassembler.h"
#include "verilated.h"
#include "verilated_vcd_c.h"

int main(int argc, char** argv, char** env)
{
    Verilated::commandArgs(argc, argv);

    Vv30mz_disassembler* v30mz_disassembler = new Vv30mz_disassembler;
    v30mz_disassembler->clk = 0;
    v30mz_disassembler->readyb = 1;
    v30mz_disassembler->reset = 1;

    Verilated::traceEverOn(true);
    VerilatedVcdC* tfp = new VerilatedVcdC;
    v30mz_disassembler->trace(tfp, 99);  // Trace 99 levels of hierarchy
    tfp->open("sim.vcd");

    int timestamp = 0;
    bool data_sent = false;
    while (timestamp < 200 && !Verilated::gotFinish())
    {
        v30mz_disassembler->clk = 0;
        v30mz_disassembler->eval();
        tfp->dump(timestamp++);

        v30mz_disassembler->clk = 1;
        v30mz_disassembler->eval();
        tfp->dump(timestamp++);

        if(timestamp >= 8)
            v30mz_disassembler->reset = 0;

        // At rising edge of clock
        if(data_sent)
        {
            v30mz_disassembler->readyb = 1;
            data_sent = false;
        }

        if(v30mz_disassembler->bus_status == 0x9)
        {
            v30mz_disassembler->data_in = 0x01 | (((timestamp/4) % 2 == 0)? 0x08: 0x10) << 8;
            v30mz_disassembler->readyb  = 0;
            data_sent = true;
        }
    }

    tfp->close();
    delete v30mz_disassembler;

    return 0;
}
