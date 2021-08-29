#include "Vv30mz.h"
#include "v30mz_sim.h"
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

    uint16_t eeprom[64];
    uint16_t eeprom_data    = 0;
    uint16_t eeprom_address = 0;
    uint8_t eeprom_status   = 3;
    bool eeprom_write_protect   = true;
    bool eeprom_write_requested = false;
    bool eeprom_read_requested  = false;

    int mem_counter = 0;

    int timestamp = 0;
    bool data_sent = false;
    while (timestamp < 500000 && !Verilated::gotFinish())
    {
        v30mz->clk = 0;
        v30mz->eval();
        tfp->dump(timestamp++);

        v30mz->clk = 1;
        v30mz->eval();
        tfp->dump(timestamp++);

        if(timestamp >= 8)
            v30mz->reset = 0;

        if(v30mz->v30mz__DOT__execution_unit_inst__DOT__error > 0)
        {
            printf("Error at t = %d in line %d. PC = 0x%x\n", timestamp, v30mz->v30mz__DOT__execution_unit_inst__DOT__error, v30mz->v30mz__DOT__PC);
        }

        if(v30mz->v30mz__DOT__execution_unit_inst__DOT__decode_inst__DOT__instruction_not_decoded > 0)
        {
            printf("Instruction not decoded at t = %d in line %d. PC = 0x%x\n", timestamp, v30mz->v30mz__DOT__execution_unit_inst__DOT__decode_inst__DOT__instruction_not_decoded , v30mz->v30mz__DOT__PC);
        }

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
            if(v30mz->address_out < sizeof(io_map))
                printf("IN: %s\n", io_map[v30mz->address_out]);

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
                    //printf("IN: REG_IEEP_DATA\n");
                    v30mz->data_in = eeprom_data;
                    break;
                }

                case 0xBC:
                case 0xBD:
                {
                    //printf("IN: REG_IEEP_ADDR\n");
                    v30mz->data_in = eeprom_address;
                    break;
                }

                case 0xBE:
                {
                    // REG_IEEP_STATUS
                    //printf("IN: REG_IEEP_STATUS\n");
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
            if(v30mz->address_out < sizeof(io_map))
                printf("OUT: %s - 0x%x\n", io_map[v30mz->address_out], v30mz->data_out);

            switch(v30mz->address_out)
            {
                case 0xBA:
                case 0xBB:
                {
                    //printf("OUT: REG_IEEP_DATA\n");
                    eeprom_data = v30mz->data_out;
                    break;
                }

                case 0xBC:
                case 0xBD:
                {
                    eeprom_address = v30mz->data_out;
                    //printf("OUT: REG_IEEP_ADDR %x\n", eeprom_address);
                    break;
                }

                case 0xBE:
                {
                    //printf("OUT: REG_IEEP_CMD\n");
                    eeprom_read_requested  = v30mz->data_out & 0x10;
                    eeprom_write_requested = v30mz->data_out & 0x20;

                    int start = eeprom_address & (1 << 8);
                    if(start)
                    {
                        int command = (eeprom_address >> 6) & 3;
                        int special = (eeprom_address >> 4) & 3;
                        int address = eeprom_address & 0x1F;

                        // write disable
                        if(command == 0 && special == 0)
                            eeprom_write_protect = true;

                        // write all
                        if(command == 0 && special == 1 && !eeprom_write_protect)
                        {
                            //printf("write all\n");
                            for(size_t i = 0; i < 64; ++i)
                                eeprom[i] = eeprom_data;
                        }

                        // erase all
                        if(command == 0 && special == 2 && !eeprom_write_protect)
                        {
                            //printf("erase all\n");
                            for(size_t i = 0; i < 64; ++i)
                                eeprom[i] = 0xFFFF;
                        }

                        // write enable
                        if(command == 0 && special == 3)
                            eeprom_write_protect = false;

                        // write word
                        if(command == 1 && eeprom_write_requested && !eeprom_write_protect)
                        {
                            //printf("write word\n");
                            eeprom[address] = eeprom_data;
                            eeprom_write_requested = false;
                        }

                        // read word
                        if(command == 2 && eeprom_read_requested)
                        {
                            //printf("read word\n");
                            eeprom_data = eeprom[address];
                            eeprom_read_requested = false;
                        }

                        // erase word
                        if(command == 3 && eeprom_write_requested && !eeprom_write_protect)
                        {
                            //printf("erase word\n");
                            eeprom[address] = 0xFFFF;
                            eeprom_write_requested = false;
                        }
                    }

                    break;
                }

                default:
                    break;

            }
            v30mz->readyb  = 0;
            data_sent = true;
        }
    }

    tfp->close();
    delete v30mz;

    return 0;
}
