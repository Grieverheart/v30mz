#include "Vv30mz.h"
#include "verilated.h"
#include "verilated_vcd_c.h"

int main(int argc, char** argv, char** env)
{
    Verilated::commandArgs(argc, argv);

    Vv30mz* v30mz = new Vv30mz;
    v30mz->clk = 0;
    v30mz->readyb = 1;
    v30mz->reset = 1;

    Verilated::traceEverOn(true);
    VerilatedVcdC* tfp = new VerilatedVcdC;
    v30mz->trace(tfp, 99);  // Trace 99 levels of hierarchy
    tfp->open("sim.vcd");

    int timestamp = 0;
    bool data_sent = false;
    while (timestamp < 200 && !Verilated::gotFinish())
    {
        v30mz->clk = 0;
        v30mz->eval();
        tfp->dump(timestamp++);

        v30mz->clk = 1;
        v30mz->eval();
        tfp->dump(timestamp++);

        if(timestamp >= 8)
            v30mz->reset = 0;

        // At rising edge of clock
        if(data_sent)
        {
            v30mz->readyb = 1;
            data_sent = false;
        }

        if(v30mz->bus_status == 0x9)
        {
            v30mz->data_in = 0x01 | (((timestamp/4) % 2 == 0)? 0x08: 0x10) << 8;
            v30mz->readyb  = 0;
            data_sent = true;
        }
    }

    tfp->close();
    delete v30mz;

    return 0;
}
