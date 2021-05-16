#include "Vmicrosequencer.h"
#include "verilated.h"
#include "verilated_vcd_c.h"

int main(int argc, char** argv, char** env)
{
    Verilated::commandArgs(argc, argv);

    Vmicrosequencer* microsequencer = new Vmicrosequencer;

    microsequencer->address = 0;
    microsequencer->clk = 0;
    microsequencer->reset = 1;
    microsequencer->eval();
    microsequencer->clk = 1;
    microsequencer->eval();

    Verilated::traceEverOn(true);
    VerilatedVcdC* tfp = new VerilatedVcdC;
    microsequencer->trace(tfp, 99);  // Trace 99 levels of hierarchy
    tfp->open("sim.vcd");

    int timestamp = 0;
    bool data_sent = false;
    while (timestamp < 200 && !Verilated::gotFinish())
    {
        microsequencer->clk = 0;
        microsequencer->eval();
        tfp->dump(timestamp++);

        microsequencer->clk = 1;
        microsequencer->eval();
        tfp->dump(timestamp++);

        // At rising edge of clock
        // pass
    }

    tfp->close();
    delete microsequencer;

    return 0;
}
