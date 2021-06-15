#include "Vmain.h"
#include "verilated.h"
#include "verilated_vcd_c.h"

int main(int argc, char** argv, char** env)
{
    Verilated::commandArgs(argc, argv);

    Vmain* main = new Vmain;

    main->clk = 0;
    main->reset = 1;

    Verilated::traceEverOn(true);
    VerilatedVcdC* tfp = new VerilatedVcdC;
    main->trace(tfp, 99);  // Trace 99 levels of hierarchy
    tfp->open("sim.vcd");

    int timestamp = 0;
    while (timestamp < 50 && !Verilated::gotFinish())
    {
        main->clk = 0;
        main->eval();
        tfp->dump(timestamp++);

        main->clk = 1;
        main->eval();
        tfp->dump(timestamp++);

        // At rising edge of clock
        if(timestamp >= 8)
            main->reset = 0;
    }

    tfp->close();
    delete main;

    return 0;
}
