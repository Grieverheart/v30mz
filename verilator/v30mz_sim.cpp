#include "Vv30mz.h"
#include "verilated.h"
#include "verilated_vcd_c.h"
#include <cstdio>
#include <cstring>
#include <cstdint>

int main(int argc, char** argv, char** env)
{
    FILE* fp = fopen("data/boot.rom", "rb");
    fseek(fp, 0, SEEK_END);
    size_t file_size = ftell(fp);
    fseek(fp, 0, SEEK_SET);  /* same as rewind(f); */

    uint8_t* instructions = (uint8_t*) malloc(file_size);
    fread(instructions, 1, file_size, fp);
    fclose(fp);

    Verilated::commandArgs(argc, argv);

    Vv30mz* v30mz = new Vv30mz;
    v30mz->clk = 0;
    v30mz->readyb = 0;
    v30mz->reset = 1;

    Verilated::traceEverOn(true);
    VerilatedVcdC* tfp = new VerilatedVcdC;
    v30mz->trace(tfp, 99);  // Trace 99 levels of hierarchy
    tfp->open("sim.vcd");

    //uint8_t instructions[] =
    //{
    //    0xea,       // BR far-label
    //    0xef,0xbe,  // disp
    //    0xce,0xfa,  // imm

    //    0x8e,0x08,  // mov rm->s
    //    0x8e,0x10,  // mov rm->s

    //    0xb9,      // mov i->r
    //    0xef,0xbe, // imm

    //    0x8e,0xc1, // mov r->s
    //    0x8e,0xc9, // mov r->s
    //    0x8e,0xd1, // mov r->s
    //    0x8e,0xd9, // mov r->s

    //    0x8b,0x08,
    //    0x8b,0x10,
    //    0x8b,0x00,
    //    0x8b,0x08,
    //    0x8b,0x10,
    //    0x8b,0x00,
    //    0x8b,0x00,
    //    0x8b,0x00,
    //    0x8b,0x00,
    //    0x8b,0x00
    //};

    int mem_counter = 0;

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
            v30mz->data_in = *(uint16_t*)(instructions + (v30mz->address_out & (file_size - 1)));

            v30mz->readyb  = 0;
            data_sent = true;
        }
        else if(v30mz->bus_status != 0x0)
        {
            v30mz->readyb  = 0;
            data_sent = true;
        }
    }

    tfp->close();
    delete v30mz;

    return 0;
}
