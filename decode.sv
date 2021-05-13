
// Idea: Perhaps instead of things like need_modrm etc. we can create
// microinstructions like fetch_to_reg (4 bit, high bit is size 8/16 and
// lowest bits are register id). But we still need to know if for example
// there is DISP so that we can calculate the effective address.

// @note: In zet cpu, modrm is set to a specific value of 8'b0000_0110 when an
// opcode is first read. In case need_modrm is not needed, zet_memory_regs
// sets the base and index to 4'b1100. This in turn takes care of reading disp
// anyway. Thus, disp works as either disp or imm depending on the instruction.
// That is also true, in the 8086 iAPX manual 1-41 figure 1-28, we see that
// bytes 3 and 4 are either low/high disp, or data, with bytes 5 and 6 being
// pure data.
//
//      Byte 1           Byte 2
//  _______________  _______________
// |_|_|_|_|_|_|_|_||_|_|_|_|_|_|_|_|
// |___opcode__|D|W||mod|_reg_|_rm__|
//
//      Byte 3           Byte 4
//  _______________  _______________
// |_|_|_|_|_|_|_|_||_|_|_|_|_|_|_|_|
// |_disp-low/data_||disp-high/data_|
//
//      Byte 5           Byte 6
//  _______________  _______________
// |_|_|_|_|_|_|_|_||_|_|_|_|_|_|_|_|
// |______data_____||______data_____|
//
// Note that mod=00 and mem=110 also means direct address memory addressing so
// it's not really a coincidence. I'm not sure though if I like this approach.

module decode
(
    input [7:0] opcode,
    input [7:0] modrm,

    output reg need_modrm,

    output reg need_disp,
    output reg disp_size, // 0 -> 8bit, 1 -> 16bit

    output reg need_imm,
    output reg imm_size,  // 0 -> 8bit, 1 -> 16bit

    output reg [3:0] src,
    output reg [3:0] dst
);

    wire need_disp_mod, disp_size_mod;

    wire [2:0] dstm, srcm;
    wire [1:0] mod;
    wire [2:0] rm, regm;

    assign mod  = modrm[7:6];
    assign regm = modrm[5:3];
    assign rm   = modrm[2:0];

    assign dstm = opcode[1]? regm: rm;
    assign srcm = opcode[1]? rm: regm;

    assign need_disp_mod = (rm == 3'b110 && mod == 0) || ^mod;
    assign disp_size_mod = (rm == 3'b110 && mod == 0)? 1: mod[1];

    // @todo: Handle modrm assignment of correct base pointer and index
    // registers as well as the correct default segment, unless a prefix is
    // present.

    /* verilator lint_off COMBDLY  */
    always_comb
    begin
        casez(opcode)
            8'b0000_00??: // ADD R/M R
            begin
                need_modrm <= 1;
                need_disp  <= need_disp_mod;
                need_imm   <= 0;
                imm_size   <= 0;
                dst        <= { 1'b0, dstm };
                src        <= { 1'b0, srcm };
            end

            8'b0000_010?: // ADD ACC IMM
            begin
                need_modrm <= 0;
                need_disp  <= 0;
                need_imm   <= 1;
                imm_size   <= opcode[0];
                dst        <= 0;
                src        <= 0;
            end

            8'b000?_?110: // PUSH sreg
            begin
                need_modrm <= 0;
                need_disp  <= 0;
                need_imm   <= 0;
                imm_size   <= 0;
                dst        <= 0;
                src        <= 0;
            end

            8'b000?_?111: // POP sreg
            begin
                need_modrm <= 0;
                need_disp  <= 0;
                need_imm   <= 0;
                imm_size   <= 0;
                dst        <= 0;
                src        <= 0;
            end

            8'b0000_10??: // OR R/M R
            begin
                need_modrm <= 1;
                need_disp  <= need_disp_mod;
                need_imm   <= 0;
                imm_size   <= 0;
                dst        <= { 1'b0, dstm };
                src        <= { 1'b0, srcm };
            end

            8'b0000_110?: // OR ACC IMM
            begin
                need_modrm <= 0;
                need_disp  <= 0;
                need_imm   <= 1;
                imm_size   <= opcode[0];
                dst        <= 0;
                src        <= 0;
            end

            8'b0001_00??: // ADC R/M R
            begin
                need_modrm <= 1;
                need_disp  <= need_disp_mod;
                need_imm   <= 0;
                imm_size   <= 0;
                dst        <= { 1'b0, dstm };
                src        <= { 1'b0, srcm };
            end

            8'b0001_010?: // ADC ACC IMM
            begin
                need_modrm <= 0;
                need_disp  <= 0;
                need_imm   <= 1;
                imm_size   <= opcode[0];
                dst        <= 0;
                src        <= 0;
            end

            8'b0001_10??: // SBB R/M R
            begin
                need_modrm <= 1;
                need_disp  <= need_disp_mod;
                need_imm   <= 0;
                imm_size   <= 0;
                dst        <= { 1'b0, dstm };
                src        <= { 1'b0, srcm };
            end

            8'b0001_110?: // SBB ACC IMM
            begin
                need_modrm <= 0;
                need_disp  <= 0;
                need_imm   <= 1;
                imm_size   <= opcode[0];
                dst        <= 0;
                src        <= 0;
            end

            8'b0010_00??: // AND R/M R
            begin
                need_modrm <= 1;
                need_disp  <= need_disp_mod;
                need_imm   <= 0;
                imm_size   <= 0;
                dst        <= { 1'b0, dstm };
                src        <= { 1'b0, srcm };
            end

            8'b0010_010?: // AND ACC IMM
            begin
                need_modrm <= 0;
                need_disp  <= 0;
                need_imm   <= 1;
                imm_size   <= opcode[0];
                dst        <= 0;
                src        <= 0;
            end

            8'b001?_?110: // Segment override prefix
            begin
                need_modrm <= 0;
                need_disp  <= 0;
                need_imm   <= 0;
                imm_size   <= 0;
                dst        <= 0;
                src        <= 0;
            end

            8'b0010_10??: // SUB R/M R
            begin
                need_modrm <= 1;
                need_disp  <= need_disp_mod;
                need_imm   <= 0;
                imm_size   <= 0;
                dst        <= { 1'b0, dstm };
                src        <= { 1'b0, srcm };
            end

            8'b0010_110?: // SUB ACC IMM
            begin
                need_modrm <= 0;
                need_disp  <= 0;
                need_imm   <= 1;
                imm_size   <= opcode[0];
                dst        <= 0;
                src        <= 0;
            end

            8'b0011_00??: // XOR R/M R
            begin
                need_modrm <= 1;
                need_disp  <= need_disp_mod;
                need_imm   <= 0;
                imm_size   <= 0;
                dst        <= { 1'b0, dstm };
                src        <= { 1'b0, srcm };
            end

            8'b0011_010?: // XOR ACC IMM
            begin
                need_modrm <= 0;
                need_disp  <= 0;
                need_imm   <= 1;
                imm_size   <= opcode[0];
                dst        <= 0;
                src        <= 0;
            end

            8'b0011_10??: // CMP R/M R
            begin
                need_modrm <= 1;
                need_disp  <= need_disp_mod;
                need_imm   <= 0;
                imm_size   <= 0;
                dst        <= { 1'b0, dstm };
                src        <= { 1'b0, srcm };
            end

            8'b0011_110?: // CMP ACC IMM
            begin
                need_modrm <= 0;
                need_disp  <= 0;
                need_imm   <= 1;
                imm_size   <= opcode[0];
                dst        <= 0;
                src        <= 0;
            end

            8'b001?_?111: // Unpacked decimal adjustment
            begin
                need_modrm <= 0;
                need_disp  <= 0;
                need_imm   <= 0;
                imm_size   <= 0;
                dst        <= 0;
                src        <= 0;
            end

            8'b0100_0???: // INC reg16
            begin
                need_modrm <= 0;
                need_disp  <= 0;
                need_imm   <= 0;
                imm_size   <= 0;
                dst        <= 0;
                src        <= 0;
            end

            8'b0100_1???: // DEC reg16
            begin
                need_modrm <= 0;
                need_disp  <= 0;
                need_imm   <= 0;
                imm_size   <= 0;
                dst        <= 0;
                src        <= 0;
            end

            8'b0101_0???: // PUSH reg16
            begin
                need_modrm <= 0;
                need_disp  <= 0;
                need_imm   <= 0;
                imm_size   <= 0;
                dst        <= 0;
                src        <= 0;
            end

            8'b0101_1???: // POP reg16
            begin
                need_modrm <= 0;
                need_disp  <= 0;
                need_imm   <= 0;
                imm_size   <= 0;
                dst        <= 0;
                src        <= 0;
            end

            8'b0111_????: // Branch short-label
            begin
                need_modrm <= 0;
                need_disp  <= 1;
                need_imm   <= 0;
                imm_size   <= 0;
                dst        <= 0;
                src        <= 0;
            end

            8'b1000_00??: // ADD/OR/ADC/SBB/AND/SUB/XOR/CMP R/M IMM
            begin
                need_modrm <= 1;
                need_disp  <= need_disp_mod;
                need_imm   <= 1;
                imm_size   <= !opcode[1] & opcode[0];
                dst        <= { 1'b0, modrm[2:0] };
                src        <= 0;
            end

            8'b1000_010?: // TEST R/M R (@note: zet-cpu has dstm and srcm switched around here)
            begin
                need_modrm <= 1;
                need_disp  <= need_disp_mod;
                need_imm   <= 0;
                imm_size   <= 0;
                dst        <= { 1'b0, dstm };
                src        <= { 1'b0, srcm };
            end

            8'b1000_011?: // XCHG R/M R
            begin
                need_modrm <= 1;
                need_disp  <= need_disp_mod;
                need_imm   <= 0;
                imm_size   <= 0;
                dst        <= { 1'b0, dstm };
                src        <= { 1'b0, srcm };
            end

            8'b1000_10??: // MOV R/M R (@todo: missing mod=11)
            begin
                need_modrm <= 1;
                need_disp  <= need_disp_mod;
                need_imm   <= 0;
                imm_size   <= 0;
                dst        <= { 1'b0, dstm };
                src        <= { 1'b0, srcm };
            end

            8'b1000_11?0: // MOV R/M sreg (@todo)
            begin
                need_modrm <= 1;
                need_imm   <= 0;
                imm_size   <= 0;
                src        <= { 1'b1, srcm };
                if(mod == 2'b11)
                begin
                    need_disp  <= 0;
                    dst        <= { 1'b0, dstm };
                end
                else
                begin
                    need_disp  <= need_disp_mod;
                    dst        <= 0;
                end
            end

            8'b1000_1101: // LDEA R M (@todo: missing mod=11)
            begin
                need_modrm <= 1;
                need_disp  <= need_disp_mod;
                need_imm   <= 0;
                imm_size   <= 0;
                dst        <= { 1'b0, dstm };
                src        <= 0;
            end

            8'b1000_1111: // POP R16/M16
            begin
                need_modrm <= 1;
                need_disp  <= need_disp_mod;
                need_imm   <= 0;
                imm_size   <= 0;
                dst        <= {1'b0, rm};
                src        <= 0;
            end

            8'b1001_0???: // NOP/XCHG ACC
            begin
                need_modrm <= 0;
                need_disp  <= 0;
                need_imm   <= 0;
                imm_size   <= 0;
                dst        <= 0;
                src        <= {1'b0, opcode[2:0]};
            end

            8'b1001_100?: // CBW/CWD
            begin
                need_modrm <= 0;
                need_disp  <= 0;
                need_imm   <= 0;
                imm_size   <= 0;
                dst        <= 0;
                src        <= 0;
            end

            8'b1001_1010: // CALL far-proc
            begin
                need_modrm <= 0;
                need_disp  <= 1;
                need_imm   <= 1;
                imm_size   <= 1;
                dst        <= 0;
                src        <= 0;
            end

            8'b1001_1011: // WAIT
            begin
                need_modrm <= 0;
                need_disp  <= 0;
                need_imm   <= 0;
                imm_size   <= 0;
                dst        <= 0;
                src        <= 0;
            end

            8'b1001_11??: // PUSHF/POPF/SAHF/LAHF
            begin
                need_modrm <= 0;
                need_disp  <= 0;
                need_imm   <= 0;
                imm_size   <= 0;
                dst        <= 0;
                src        <= 0;
            end

            8'b1010_00??: // MOV M ACC
            begin
                need_modrm <= 0;
                need_disp  <= 1;
                need_imm   <= 0;
                imm_size   <= 0;
                dst        <= 0;
                src        <= 0;
            end

            8'b1010_01??: // MOVS/CMPS
            begin
                need_modrm <= 0;
                need_disp  <= 0;
                need_imm   <= 0;
                imm_size   <= 0;
                dst        <= 0;
                src        <= 0;
            end

            8'b1010_100?: // TEST ACC IMM
            begin
                need_modrm <= 0;
                need_disp  <= 0;
                need_imm   <= 1;
                imm_size   <= opcode[0];
                dst        <= 0;
                src        <= 0;
            end

            8'b1010_101?: // STOS
            begin
                need_modrm <= 0;
                need_disp  <= 0;
                need_imm   <= 0;
                imm_size   <= 0;
                dst        <= 0;
                src        <= 0;
            end

            8'b1010_110?: // LODS
            begin
                need_modrm <= 0;
                need_disp  <= 0;
                need_imm   <= 0;
                imm_size   <= 0;
                dst        <= 0;
                src        <= 0;
            end

            8'b1010_111?: // SCAS
            begin
                need_modrm <= 0;
                need_disp  <= 0;
                need_imm   <= 0;
                imm_size   <= 0;
                dst        <= 0;
                src        <= 0;
            end

            8'b1011_????: // MOV R IMM
            begin
                need_modrm <= 0;
                need_disp  <= 0;
                need_imm   <= 1;
                imm_size   <= opcode[3];
                dst        <= { 1'b0, opcode[2:0] };
                src        <= 0;
            end

            8'b1100_000?: // ROR/ROL/RCR/RCL/SAL/SHL/SAR/SHR IMM8/16
            begin
                need_modrm <= 1;
                need_disp  <= need_disp_mod;
                need_imm   <= 1;
                imm_size   <= 0;
                dst        <= {1'b0, rm};
                src        <= {1'b0, rm};
            end

            8'b1100_0010: // RET pop-value (segment-internal call)
            begin
                need_modrm <= 0;
                need_disp  <= 0;
                need_imm   <= 1;
                imm_size   <= 1;
                dst        <= 0;
                src        <= 0;
            end

            8'b1100_0011: // RET (segment-internal call)
            begin
                need_modrm <= 0;
                need_disp  <= 0;
                need_imm   <= 0;
                imm_size   <= 0;
                dst        <= 0;
                src        <= 0;
            end

            8'b1100_010?: // LES/LDS R16 M16
            begin
                need_modrm <= 1;
                need_disp  <= need_disp_mod;
                need_imm   <= 0;
                imm_size   <= 0;
                dst        <= 0;
                src        <= {1'b0, srcm};
            end

            8'b1100_1000: // PREPARE (ENTER)
            begin
                need_modrm <= 0;
                need_disp  <= need_disp_mod;
                need_imm   <= 1;
                imm_size   <= 0;
                dst        <= 0;
                src        <= 0;
            end

            // @todo ...

            default:
            begin
                need_modrm <= 0;
                need_disp  <= 0;
                need_imm   <= 0;
                imm_size   <= 0;
                dst        <= 0;
                src        <= 0;
            end
        endcase
    end

endmodule;
