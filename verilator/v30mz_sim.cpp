#include "Vv30mz.h"
#include "verilated.h"
#include "verilated_vcd_c.h"
#include <cstdio>
#include <cstring>
#include <cstdint>

enum
{
    BUS_INT_ACK    = 0x0,
    BUS_IO_READ    = 0x5,
    BUS_IO_WRITE   = 0x6,
    BUS_HALT       = 0x8,
    BUS_MEM_READ   = 0x9,
    BUS_MEM_WRITE  = 0xA,
    BUS_CODE_FETCH = 0xD, // @note: Should this be used when prefetching?
    BUS_IDLE       = 0xF
};

//struct Eeprom
//{
//    uint16_t data;
//};

int main(int argc, char** argv, char** env)
{
    FILE* fp = fopen("data/boot.rom", "rb");
    fseek(fp, 0, SEEK_END);
    size_t file_size = ftell(fp);
    fseek(fp, 0, SEEK_SET);  /* same as rewind(f); */

    uint8_t* instructions = (uint8_t*) malloc(file_size);
    fread(instructions, 1, file_size, fp);
    fclose(fp);

    uint8_t* memory = (uint8_t*) malloc(16*1024);

    Verilated::commandArgs(argc, argv);

    Vv30mz* v30mz = new Vv30mz;
    v30mz->clk = 0;
    v30mz->readyb = 0;
    v30mz->reset = 1;

    Verilated::traceEverOn(true);
    VerilatedVcdC* tfp = new VerilatedVcdC;
    v30mz->trace(tfp, 99);  // Trace 99 levels of hierarchy
    tfp->open("sim.vcd");

    uint16_t eeprom_data;
    uint16_t eeprom_address;
    uint8_t eeprom_command;
    uint8_t eeprom_status = 0;
    bool eeprom_command_start;

    int mem_counter = 0;

    int timestamp = 0;
    bool data_sent = false;
    while (timestamp < 200000 && !Verilated::gotFinish())
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

        //v30mz->eval();
        //tfp->dump(timestamp++);

        if(v30mz->bus_status == BUS_MEM_READ)
        {
            // memory read
            if(v30mz->address_out >= 0x10000)
                v30mz->data_in = *(uint16_t*)(instructions + (v30mz->address_out & (file_size - 1)));
            else
                v30mz->data_in = *(uint16_t*)(memory + (v30mz->address_out & 0x003FFF));

            v30mz->readyb = 0;
            data_sent = true;
        }
        else if(v30mz->bus_status == BUS_MEM_WRITE)
        {
            // memory write
            if(v30mz->address_out < 0x00FFFF)
            {
                uint32_t address = v30mz->address_out & 0x003FFF;
                *(uint16_t*)(memory + address) = v30mz->data_out;
            }

            v30mz->readyb  = 0;
            data_sent = true;
        }
        else if(v30mz->bus_status == BUS_IO_READ)
        {
            switch(v30mz->address_out)
            {
                case 0xA0:
                {
                    v30mz->data_in = 0x84;
                    break;
                }

                case 0xBA:
                case 0xBB:
                {
                    // REG_IEEP_DATA
                    printf("IN: REG_IEEP_DATA\n");
                    v30mz->data_in = eeprom_data;
                    break;
                }

                case 0xBC:
                case 0xBD:
                {
                    printf("IN: REG_IEEP_ADDR\n");
                    printf("Oops");
                    break;
                }

                case 0xBE:
                {
                    // REG_IEEP_STATUS
                    printf("IN: REG_IEEP_STATUS\n");
                    v30mz->data_in = eeprom_status;
                    break;
                }

                default:
                {
                    v30mz->data_in = 0x00;
                    break;
                }

            }
            v30mz->readyb  = 0;
            data_sent = true;
        }
        else if(v30mz->bus_status == BUS_IO_WRITE)
        {
            switch(v30mz->address_out)
            {
                case 0xBA:
                case 0xBB:
                {
                    // REG_IEEP_DATA
                    printf("OUT: REG_IEEP_DATA\n");
                    eeprom_data = v30mz->data_out;
                    break;
                }

                case 0xBC:
                case 0xBD:
                {
                    // REG_IEEP_ADDR
                    printf("OUT: REG_IEEP_ADDR\n");
                    eeprom_command_start = v30mz->data_out & 0x100;
                    
                    eeprom_command = (v30mz->data_out >> 6) & 0x3;
                    if(eeprom_command == 0x00)
                    {
                        eeprom_command = 3 + ((v30mz->data_out >> 4) & 0x3);
                        eeprom_address = v30mz->data_out & 0xF;
                    }
                    else
                    {
                        --eeprom_command;
                        eeprom_address = v30mz->data_out & 0x3F;
                    }

                    printf("0x%x, 0x%x, 0x%x: %u - %d / 0x%x\n", v30mz->v30mz__DOT__PC, v30mz->address_out, v30mz->data_out, eeprom_command, eeprom_command_start, eeprom_address);

                    break;
                }

                case 0xBE:
                {
                    // REG_IEEP_CMD
                    printf("OUT: REG_IEEP_CMD\n");
                    printf("0x%x, 0x%x, 0x%x\n", v30mz->v30mz__DOT__PC, v30mz->address_out, v30mz->data_out & 0xFF);
                    break;
                }

                default:
                {
                    v30mz->data_in = 0x00;
                    break;
                }

            }
            v30mz->readyb  = 0;
            data_sent = true;
        }
    }

    tfp->close();
    delete v30mz;

    return 0;
}
