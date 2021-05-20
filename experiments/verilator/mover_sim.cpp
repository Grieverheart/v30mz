#include "Vmover.h"
#include "verilated.h"
#include "verilated_vcd_c.h"

int main(int argc, char** argv, char** env)
{
    Verilated::commandArgs(argc, argv);

    Vmover* mover = new Vmover;

    mover->clk = 0;
    mover->reset = 1;
    mover->we = 0;
    mover->ce = 0;
    mover->eval();
    mover->clk = 1;
    mover->eval();
    mover->reset = 0;

    Verilated::traceEverOn(true);
    VerilatedVcdC* tfp = new VerilatedVcdC;
    mover->trace(tfp, 99);  // Trace 99 levels of hierarchy
    tfp->open("sim.vcd");

    int timestamp = 0;
    // Write registers
    for(size_t i = 0; i < 8; ++i)
    {
        mover->clk = 0;
        mover->eval();
        tfp->dump(timestamp++);

        mover->clk = 1;
        mover->eval();
        tfp->dump(timestamp++);

        mover->we = 1;
        mover->dst = i;
        mover->data_in = i;
        // At rising edge of clock
        // pass
    }

    mover->clk = 0;
    mover->eval();
    tfp->dump(timestamp++);

    mover->clk = 1;
    mover->eval();
    tfp->dump(timestamp++);

    mover->we = 0;

    for(size_t i = 0; i < 2; ++i)
    {
        mover->clk = 0;
        mover->eval();
        tfp->dump(timestamp++);

        mover->clk = 1;
        mover->eval();
        tfp->dump(timestamp++);
    }

    for(size_t i = 0; i < 7; ++i)
    {
        mover->clk = 0;
        mover->eval();
        tfp->dump(timestamp++);

        mover->clk = 1;
        mover->eval();
        tfp->dump(timestamp++);

        mover->ce = 1;
        mover->src = 7-i;
        mover->dst = 7-i-1;
        // At rising edge of clock
        // pass
    }

    mover->clk = 0;
    mover->eval();
    tfp->dump(timestamp++);

    mover->clk = 1;
    mover->eval();
    tfp->dump(timestamp++);

    mover->ce = 0;

    for(size_t i = 0; i < 2; ++i)
    {
        mover->clk = 0;
        mover->eval();
        tfp->dump(timestamp++);

        mover->clk = 1;
        mover->eval();
        tfp->dump(timestamp++);
    }

    tfp->close();
    delete mover;

    return 0;
}
