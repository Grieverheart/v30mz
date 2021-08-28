const char* io_map[] = {
    "REG_DISP_CTRL",
    "REG_BACK_COLOR",
    "REG_LINE_CUR",
    "REG_LINE_CMP",
    "REG_SPR_BASE",
    "REG_SPR_FIRST",
    "REG_SPR_COUNT",
    "REG_MAP_BASE",
    "REG_SCR2_WIN_X0",
    "REG_SCR2_WIN_Y0",
    "REG_SCR2_WIN_X1",
    "REG_SCR2_WIN_Y1",
    "REG_SPR_WIN_X0",
    "REG_SPR_WIN_Y0",
    "REG_SPR_WIN_X1",
    "REG_SPR_WIN_Y1",
    "REG_SCR1_X",
    "REG_SCR1_Y",
    "REG_SCR2_X",
    "REG_SCR2_Y",
    "REG_LCD_CTRL",
    "REG_LCD_ICON",
    "REG_LCD_VTOTAL",
    "REG_LCD_VSYNC",
    "---",
    "---",
    "???",
    "---",
    "REG_PALMONO_POOL_0",
    "REG_PALMONO_POOL_1",
    "REG_PALMONO_POOL_2",
    "REG_PALMONO_POOL_3",
    "REG_PALMONO_0 (Low)",
    "REG_PALMONO_0 (High)",
    "REG_PALMONO_1 (Low)",
    "REG_PALMONO_1 (High)",
    "REG_PALMONO_2 (Low)",
    "REG_PALMONO_2 (High)",
    "REG_PALMONO_3 (Low)",
    "REG_PALMONO_3 (High)",
    "REG_PALMONO_4 (Low)",
    "REG_PALMONO_4 (High)",
    "REG_PALMONO_5 (Low)",
    "REG_PALMONO_5 (High)",
    "REG_PALMONO_6 (Low)",
    "REG_PALMONO_6 (High)",
    "REG_PALMONO_7 (Low)",
    "REG_PALMONO_7 (High)",
    "REG_PALMONO_8 (Low)",
    "REG_PALMONO_8 (High)",
    "REG_PALMONO_9 (Low)",
    "REG_PALMONO_9 (High)",
    "REG_PALMONO_A (Low)",
    "REG_PALMONO_A (High)",
    "REG_PALMONO_B (Low)",
    "REG_PALMONO_B (High)",
    "REG_PALMONO_C (Low)",
    "REG_PALMONO_C (High)",
    "REG_PALMONO_D (Low)",
    "REG_PALMONO_D (High)",
    "REG_PALMONO_E (Low)",
    "REG_PALMONO_E (High)",
    "REG_PALMONO_F (Low)",
    "REG_PALMONO_F (High)",
    "REG_DMA_SRC (Low)",
    "REG_DMA_SRC (Mid)",
    "REG_DMA_SRC_HI",
    "---",
    "REG_DMA_DST (Low)",
    "REG_DMA_DST (High)",
    "REG_DMA_LEN (Low)",
    "REG_DMA_LEN (High)",
    "REG_DMA_CTRL",
    "---",
    "REG_SDMA_SRC (Low)",
    "REG_SDMA_SRC (Mid)",
    "REG_SDMA_SRC_HI",
    "---",
    "REG_SDMA_LEN (Low)",
    "REG_SDMA_LEN (Mid)",
    "REG_SDMA_LEN (High)",
    "---",
    "REG_SDMA_CTRL",
    "---",
    "---",
    "---",
    "---",
    "---",
    "---",
    "---",
    "---",
    "---",
    "---",
    "---",
    "---",
    "---",
    "REG_DISP_MODE",
    "---",
    "REG_WSC_SYSTEM",
    "---",
    "---",
    "---",
    "---",
    "---",
    "---",
    "---",
    "REG_HYPER_CTRL",
    "REG_HYPER_CHAN_CTRL",
    "---",
    "---",
    "---",
    "---",
    "REG_UNK_70",
    "REG_UNK_71",
    "REG_UNK_72",
    "REG_UNK_73",
    "REG_UNK_74",
    "REG_UNK_75",
    "REG_UNK_76",
    "REG_UNK_77",
    "---",
    "---",
    "---",
    "---",
    "---",
    "---",
    "---",
    "---",
    "REG_SND_CH1_PITCH (Low)",
    "REG_SND_CH1_PITCH (High)",
    "REG_SND_CH2_PITCH (Low)",
    "REG_SND_CH2_PITCH (High)",
    "REG_SND_CH3_PITCH (Low)",
    "REG_SND_CH3_PITCH (High)",
    "REG_SND_CH4_PITCH (Low)",
    "REG_SND_CH4_PITCH (High)",
    "REG_SND_CH1_VOL",
    "REG_SND_CH2_VOL",
    "REG_SND_CH3_VOL",
    "REG_SND_CH4_VOL",
    "REG_SND_SWEEP_VALUE",
    "REG_SND_SWEEP_TIME",
    "REG_SND_NOISE",
    "REG_SND_WAVE_BASE",
    "REG_SND_CTRL",
    "REG_SND_OUTPUT",
    "REG_SND_RANDOM (Low)",
    "REG_SND_RANDOM (High)",
    "REG_SND_VOICE_CTRL",
    "REG_SND_HYPERVOICE",
    "REG_SND_9697 (Low)",
    "REG_SND_9697 (High)",
    "REG_SND_9899 (Low)",
    "REG_SND_9899 (High)",
    "REG_SND_9A",
    "REG_SND_9B",
    "REG_SND_9C",
    "REG_SND_9D",
    "REG_SND_9E",
    "---",
    "REG_HW_FLAGS",
    "---",
    "REG_TMR_CTRL",
    "???",
    "REG_HTMR_FREQ (Low)",
    "REG_HTMR_FREQ (High)",
    "REG_VTMR_FREQ (Low)",
    "REG_VTMR_FREQ (High)",
    "REG_HTMR_CTR (Low)",
    "REG_HTMR_CTR (High)",
    "REG_VTMR_CTR (Low)",
    "REG_VTMR_CTR (High)",
    "???",
    "---",
    "---",
    "---",
    "REG_INT_BASE",
    "REG_SER_DATA",
    "REG_INT_ENABLE",
    "REG_SER_STATUS",
    "REG_INT_STATUS",
    "REG_KEYPAD",
    "REG_INT_ACK",
    "???",
    "---",
    "---",
    "REG_IEEP_DATA (Low)",
    "REG_IEEP_DATA (High)",
    "REG_IEEP_ADDR (Low)",
    "REG_IEEP_ADDR (High)",
    "REG_IEEP_STATUS",
    "REG_IEEP_CMD",
    "???",
    "REG_BANK_ROM2",
    "REG_BANK_SRAM",
    "REG_BANK_ROM0",
    "REG_BANK_ROM1",
    "REG_EEP_DATA (Low)",
    "REG_EEP_DATA (High)",
    "REG_EEP_ADDR (Low)",
    "REG_EEP_ADDR (High)",
    "REG_EEP_STATUS",
    "REG_EEP_CMD",
    "???",
    "REG_RTC_STATUS",
    "REG_RTC_CMD",
    "REG_RTC_DATA",
    "REG_GPO_EN",
    "REG_GPO_DATA",
    "REG_WW_FLASH_CE"
};