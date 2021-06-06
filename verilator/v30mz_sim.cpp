#include "Vv30mz.h"
#include "verilated.h"
#include "verilated_vcd_c.h"

int main(int argc, char** argv, char** env)
{
    Verilated::commandArgs(argc, argv);

    Vv30mz* v30mz = new Vv30mz;
    v30mz->clk = 0;
    v30mz->readyb = 0;
    v30mz->reset = 1;

    Verilated::traceEverOn(true);
    VerilatedVcdC* tfp = new VerilatedVcdC;
    v30mz->trace(tfp, 99);  // Trace 99 levels of hierarchy
    tfp->open("sim.vcd");

    uint8_t instructions[] = 
    {
        0x8b,0x00,
        0x8b,0x08,
        0x8b,0x10,
        0x8b,0x00,
        0x8b,0x08,
        0x8b,0x10,
        0x8b,0x00,
        0x8b,0x00,
        0x8b,0x00,
        0x8b,0x00,
        0x8b,0x00
    };

    int mem_counter = 0;

    int timestamp = 0;
    bool data_sent = false;
    while (timestamp < 50 && !Verilated::gotFinish())
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
        else if(v30mz->bus_status == 0x9)
        {
            v30mz->data_in = (v30mz->address_out == 0)?
                0xbeef:
                *(uint16_t*)(instructions + 2*mem_counter++);

            v30mz->readyb  = 0;
            data_sent = true;
        }
    }

    tfp->close();
    delete v30mz;

    return 0;
}
