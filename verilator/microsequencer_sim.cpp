#include "Vmicrosequencer.h"
#include "verilated.h"
#include "verilated_vcd_c.h"

int main(int argc, char** argv, char** env)
{
    Verilated::commandArgs(argc, argv);

    Vmicrosequencer* microsequencer = new Vmicrosequencer;

    microsequencer->clk = 0;
    microsequencer->reset = 1;
    microsequencer->bus_command_done = 0;
    microsequencer->eval();

    microsequencer->clk = 1;
    microsequencer->eval();

    Verilated::traceEverOn(true);
    VerilatedVcdC* tfp = new VerilatedVcdC;
    microsequencer->trace(tfp, 99);  // Trace 99 levels of hierarchy
    tfp->open("sim.vcd");

    microsequencer->reset = 0;
    microsequencer->opcode = 0x8b;
    microsequencer->mod = 0;
    microsequencer->rm = 2;
    microsequencer->dst_operand = 0x2;

    // Effective address registers
    microsequencer->ea_base_reg    = 0x5;
    microsequencer->ea_index_reg   = 0x6;
    microsequencer->ea_segment_reg = 0x2;

    int timestamp = 0;
    bool data_sent = false;
    while (timestamp < 20 && !Verilated::gotFinish())
    {
        microsequencer->clk = 0;
        microsequencer->eval();
        tfp->dump(timestamp++);

        microsequencer->clk = 1;
        microsequencer->eval();
        tfp->dump(timestamp++);

        // At rising edge of clock
        if(data_sent)
        {
            microsequencer->bus_command_done = 0;
            data_sent = false;
        }

        // BUS_COMMAND_READ
        if(microsequencer->bus_command == 1)
        {
            microsequencer->data_in = (timestamp < 10)? 0x6666: 0x9999;
            microsequencer->bus_command_done = 1;
            data_sent = true;
        }
    }

    tfp->close();
    delete microsequencer;

    return 0;
}
