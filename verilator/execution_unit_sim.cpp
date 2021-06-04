#include "Vexecution_unit.h"
#include "verilated.h"
#include "verilated_vcd_c.h"

int main(int argc, char** argv, char** env)
{
    Verilated::commandArgs(argc, argv);

    Vexecution_unit* execution_unit = new Vexecution_unit;

    execution_unit->clk = 0;
    execution_unit->reset = 1;
    execution_unit->bus_command_done = 0;
    execution_unit->eval();

    execution_unit->clk = 1;
    execution_unit->eval();

    Verilated::traceEverOn(true);
    VerilatedVcdC* tfp = new VerilatedVcdC;
    execution_unit->trace(tfp, 99);  // Trace 99 levels of hierarchy
    tfp->open("sim.vcd");

    execution_unit->reset = 0;
    execution_unit->opcode = 0x8b;
    execution_unit->mod = 0;
    execution_unit->rm = 2;
    execution_unit->dst_operand = 0x2;

    // Effective address registers
    execution_unit->ea_base_reg    = 0x5;
    execution_unit->ea_index_reg   = 0x6;
    execution_unit->ea_segment_reg = 0x2;

    int timestamp = 0;
    bool data_sent = false;
    while (timestamp < 20 && !Verilated::gotFinish())
    {
        execution_unit->clk = 0;
        execution_unit->eval();
        tfp->dump(timestamp++);

        execution_unit->clk = 1;
        execution_unit->eval();
        tfp->dump(timestamp++);

        // At rising edge of clock
        if(data_sent)
        {
            execution_unit->bus_command_done = 0;
            data_sent = false;
        }

        // BUS_COMMAND_READ
        if(execution_unit->bus_command == 1)
        {
            execution_unit->data_in = (timestamp < 10)? 0x6666: 0x9999;
            execution_unit->bus_command_done = 1;
            data_sent = true;
        }
    }

    tfp->close();
    delete execution_unit;

    return 0;
}
