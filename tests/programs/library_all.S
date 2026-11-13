; basil output for PIC18F27Q10
#include <xc.inc>

CONFIG CONFIG1L = 0x8C
CONFIG CONFIG1H = 0xFF
CONFIG CONFIG2L = 0xFF
CONFIG CONFIG2H = 0xFF
CONFIG CONFIG3L = 0x9F
CONFIG CONFIG3H = 0xFF
CONFIG CONFIG4L = 0xFF
CONFIG CONFIG4H = 0xFF
CONFIG CONFIG5L = 0xFF
CONFIG CONFIG6L = 0xFF
CONFIG CONFIG6H = 0xFF

; ---- data (addresses chosen by the compiler)
ADC_LASTCH equ 0x066  ; lastCh (1 byte)
PINIO_DADDR equ 0x052  ; dAddr (2 bytes)
PINIO_DMASK equ 0x067  ; dMask (1 byte)
PINIO_CADDR equ 0x05A  ; cAddr (2 bytes)
PINIO_CMASK equ 0x06A  ; cMask (1 byte)
PWM_STEPS equ 0x054  ; steps (2 bytes)
PWM_PERIOD equ 0x06B  ; period (1 byte)
PWM_CKPS equ 0x06C  ; ckps (1 byte)
PWM_NACT equ 0x056  ; nact (1 byte)
PWM_FREQ equ 0x04D  ; freq (4 bytes)
PWM_PINS equ 0x048  ; pins (4 bytes)
PWM_POLV equ 0x05C  ; polv (4 bytes)
PWM_READY equ 0x060  ; ready (1 byte)
I2C_READY equ 0x051  ; ready (1 byte)
I2C_LASTSTATUS equ 0x035  ; lastStatus (1 byte)
I2C_I2CBUF equ 0x023  ; I2cBuf (8 bytes)
SPI_READY equ 0x068  ; ready (1 byte)
SPI_LASTSTATUS equ 0x03C  ; lastStatus (1 byte)
LCD_PINS equ 0x036  ; pins (6 bytes)
LCD_TWOLINES equ 0x069  ; twoLines (1 byte)
LCD_READY equ 0x061  ; ready (1 byte)
OLED_MODE equ 0x03D  ; mode (1 byte)
OLED_ADDR7 equ 0x06D  ; addr7 (1 byte)
OLED_PDC equ 0x06E  ; pDc (1 byte)
OLED_PCS equ 0x057  ; pCs (1 byte)
OLED_ERR equ 0x047  ; err (1 byte)
AHT30_FRAME equ 0x03E  ; frame (7 bytes)
RTCC_FRAME equ 0x076  ; frame (7 bytes)
RTCCSPI_FRAME equ 0x07D  ; frame (8 bytes)
RTCCSPI_BUF equ 0x01A  ; buf (8 bytes)
RTCCSPI_CSPIN equ 0x04C  ; csPin (1 byte)
RTCCSPI_READY equ 0x058  ; ready (1 byte)
T_X equ 0x02B  ; x (2 bytes)
T_X10OK equ 0x06F  ; x10ok (1 byte)
T_R equ 0x022  ; r (1 byte)
T_TI equ 0x070  ; ti (2 bytes)
T_RHW equ 0x072  ; rhw (2 bytes)
DELAY_DELAYSECONDS__S equ 0x00F  ; s (1 byte)
TIMER_TIMER0READ__RESULT equ 0x00F  ; Result (2 bytes)
TIMER_TIMER1START__PRESCALE equ 0x00F  ; prescale (1 byte)
TIMER_TIMER1READ__RESULT equ 0x00F  ; Result (2 bytes)
TIMER_TIMER2READ__RESULT equ 0x00F  ; Result (1 byte)
SERIAL_SERIALWRITEWORD__V equ 0x011  ; v (2 bytes)
SERIAL_SERIALWRITEHEX__V equ 0x010  ; v (1 byte)
SERIAL_SERIALREAD__RESULT equ 0x00F  ; Result (1 byte)
SERIAL2_SERIAL2WRITEWORD__V equ 0x011  ; v (2 bytes)
SERIAL2_SERIAL2WRITEHEX__V equ 0x010  ; v (1 byte)
SERIAL2_SERIAL2READ__RESULT equ 0x00F  ; Result (1 byte)
ADC_ADCPIN__CH equ 0x00F  ; ch (1 byte)
ADC_ADCREAD__CH equ 0x016  ; ch (1 byte)
ADC_ADCREADAVG__RESULT equ 0x014  ; Result (2 bytes)
ADC_ADCMILLIVOLTS__RAW equ 0x00F  ; raw (2 bytes)
ADC_ADCMILLIVOLTS__RESULT equ 0x011  ; Result (2 bytes)
ADC_ADCREFFVR__GAIN equ 0x00F  ; gain (1 byte)
EEPROM_EEPROMREAD__ADDR equ 0x00F  ; addr (2 bytes)
EEPROM_EEPROMREAD__RESULT equ 0x013  ; Result (1 byte)
EEPROM_EEPROMWRITE__ADDR equ 0x011  ; addr (2 bytes)
EEPROM_EEPROMWRITE__VALUE equ 0x014  ; value (1 byte)
EEPROM_EEPROMWRITE__RESULT equ 0x015  ; Result (1 byte)
EEPROM_EEPROMREADWORD__RESULT equ 0x011  ; Result (2 bytes)
EEPROM_EEPROMWRITEWORD__VALUE equ 0x016  ; value (2 bytes)
EEPROM_EEPROMWRITEWORD__RESULT equ 0x018  ; Result (1 byte)
FLASHWRITE_FLASHREADWORD__ADDR equ 0x011  ; addr (2 bytes)
FLASHWRITE_FLASHREADWORD__RESULT equ 0x013  ; Result (2 bytes)
FLASHWRITE_FLASHSECTORADDR__RESULT equ 0x00F  ; Result (2 bytes)
FLASHWRITE_FLASHERASESECTOR__SECTOR equ 0x00F  ; sector (2 bytes)
FLASHWRITE_FLASHERASESECTOR__RESULT equ 0x011  ; Result (1 byte)
FLASHWRITE_FLASHWRITEWORD__ADDR equ 0x02D  ; addr (2 bytes)
FLASHWRITE_FLASHWRITEWORD__VALUE equ 0x02F  ; value (2 bytes)
FLASHWRITE_FLASHWRITEWORD__RESULT equ 0x033  ; Result (1 byte)
FLASHWRITE_FLASHUPDATEWORD__ADDR equ 0x00F  ; addr (2 bytes)
FLASHWRITE_FLASHUPDATEWORD__VALUE equ 0x015  ; value (2 bytes)
FLASHWRITE_FLASHUPDATEWORD__RESULT equ 0x019  ; Result (1 byte)
PWM_PWMINIT__RESULT equ 0x00F  ; Result (1 byte)
PWM_PWMSTART__CH equ 0x010  ; ch (1 byte)
PWM_PWMSTART__PIN equ 0x012  ; pin (1 byte)
PWM_PWMSTART__DUTY equ 0x016  ; duty (2 bytes)
PWM_PWMSTART__RESULT equ 0x02E  ; Result (1 byte)
PWM_PWMINVERT__RESULT equ 0x00F  ; Result (1 byte)
PWM_PWMDUTY__CH equ 0x011  ; ch (1 byte)
PWM_PWMDUTY__DUTY equ 0x00F  ; duty (2 bytes)
PWM_PWMPERCENT__PCT equ 0x012  ; pct (1 byte)
PWM_PWMFREQUENCY__RESULT equ 0x00F  ; Result (4 bytes)
PWM_PWMSTEPS__RESULT equ 0x00F  ; Result (2 bytes)
PWM_PWMSTOP__CH equ 0x00F  ; ch (1 byte)
I2C_I2CINIT__RESULT equ 0x013  ; Result (1 byte)
I2C_I2CSTART__RESULT equ 0x014  ; Result (1 byte)
I2C_I2CSEND__B equ 0x059  ; b (1 byte)
I2C_I2CSEND__RESULT equ 0x014  ; Result (1 byte)
I2C_I2CRECEIVE__ACK equ 0x074  ; ack (1 byte)
I2C_I2CRECEIVE__RESULT equ 0x014  ; Result (1 byte)
I2C_I2CRESTART__RESULT equ 0x014  ; Result (1 byte)
I2C_I2CSTOP__RESULT equ 0x014  ; Result (1 byte)
I2C_I2CSTATUS__RESULT equ 0x014  ; Result (1 byte)
I2C_I2CPING__ADDR equ 0x011  ; addr (1 byte)
I2C_I2CPING__RESULT equ 0x010  ; Result (1 byte)
I2C_I2CWRITEREG__RESULT equ 0x00F  ; Result (1 byte)
I2C_I2CREADREG__RESULT equ 0x011  ; Result (1 byte)
SPI_SPIINIT__RESULT equ 0x012  ; Result (1 byte)
SPI_SPITRANSFER__B equ 0x018  ; b (1 byte)
SPI_SPITRANSFER__RESULT equ 0x016  ; Result (1 byte)
SPI_SPIWRITE__B equ 0x033  ; b (1 byte)
SPI_SPIREAD__RESULT equ 0x017  ; Result (1 byte)
SPI_SPISTATUS__RESULT equ 0x014  ; Result (1 byte)
SYSTEM_SYSRESETCAUSE__RESULT equ 0x00F  ; Result (1 byte)
SYSTEM_SYSRESETFLAGS__RESULT equ 0x00F  ; Result (1 byte)
SYSTEM_SYSCLOCKOK__RESULT equ 0x019  ; Result (1 byte)
LCD_LCDINIT__RESULT equ 0x012  ; Result (1 byte)
LCD_LCDSETADDRESS__ADDR equ 0x011  ; addr (1 byte)
LCD_LCDGOTO__COL equ 0x00F  ; col (1 byte)
LCD_LCDWRITECHAR__CH equ 0x02E  ; ch (1 byte)
LCD_LCDWRITEWORD__V equ 0x011  ; v (2 bytes)
LCD_LCDWRITEHEX__V equ 0x00F  ; v (1 byte)
LCD_LCDCOMMAND__C equ 0x010  ; c (1 byte)
OLED_OLEDINITI2C__RESULT equ 0x02E  ; Result (1 byte)
OLED_OLEDINITSPI__RESULT equ 0x02E  ; Result (1 byte)
OLED_OLEDSTATUS__RESULT equ 0x00F  ; Result (1 byte)
OLED_OLEDON__ISON equ 0x00F  ; isOn (1 byte)
OLED_OLEDCONTRAST__LEVEL equ 0x00F  ; level (1 byte)
OLED_OLEDINVERT__INVERSE equ 0x00F  ; inverse (1 byte)
OLED_OLEDALLON__ALLON equ 0x00F  ; allOn (1 byte)
OLED_OLEDFLIP__ROTATED equ 0x00F  ; rotated (1 byte)
OLED_OLEDGOTO__PAGE equ 0x019  ; page (1 byte)
OLED_OLEDDATA__B equ 0x00F  ; b (1 byte)
OLED_OLEDFILL__PATTERN equ 0x02D  ; pattern (1 byte)
OLED_OLEDWRITECHAR__CH equ 0x030  ; ch (1 byte)
OLED_OLEDWRITEWORD__V equ 0x011  ; v (2 bytes)
OLED_OLEDWRITEHEX__V equ 0x00F  ; v (1 byte)
OLED_FONTBYTE__IDX equ 0x014  ; idx (2 bytes)
OLED_FONTBYTE__RESULT equ 0x016  ; Result (1 byte)
AHT30_AHT30START__RESULT equ 0x00F  ; Result (1 byte)
AHT30_AHT30FETCH__TEMP equ 0x033  ; temp (2 bytes)
AHT30_AHT30FETCH__RH equ 0x045  ; rh (2 bytes)
AHT30_AHT30FETCH__RESULT equ 0x017  ; Result (1 byte)
AHT30_AHT30MEASURE__TEMP equ 0x062  ; temp (2 bytes)
AHT30_AHT30MEASURE__RH equ 0x064  ; rh (2 bytes)
AHT30_AHT30MEASURE__RESULT equ 0x019  ; Result (1 byte)
RTCC_RTCCSET__RESULT equ 0x00F  ; Result (1 byte)
RTCC_RTCCREAD__RESULT equ 0x013  ; Result (1 byte)
RTCC_RTCCALARM__RESULT equ 0x00F  ; Result (1 byte)
RTCC_RTCCEEWRITE__VALUE equ 0x02E  ; value (1 byte)
RTCC_RTCCEEWRITE__RESULT equ 0x019  ; Result (1 byte)
RTCCSPI_RTCCSPIINIT__CS equ 0x010  ; cs (1 byte)
RTCCSPI_RTCCSPIINIT__RESULT equ 0x00F  ; Result (1 byte)
RTCCSPI_RTCCSPISET__RESULT equ 0x00F  ; Result (1 byte)
RTCCSPI_RTCCSPIREAD__RESULT equ 0x012  ; Result (1 byte)
RTCCSPI_RTCCSPIALARM__RESULT equ 0x00F  ; Result (1 byte)
RTCCSPI_RTCCSPIEEWRITE__VALUE equ 0x019  ; value (1 byte)
RTCCSPI_RTCCSPIEEWRITE__RESULT equ 0x013  ; Result (1 byte)
PULSE_PULSEIN__RESULT equ 0x012  ; Result (2 bytes)
PULSE_RCIN__RESULT equ 0x012  ; Result (2 bytes)
PULSE_POT__RESULT equ 0x014  ; Result (1 byte)
IRREMOTE_SONYIN__PIN equ 0x062  ; pin (1 byte)
IRREMOTE_SONYIN__RESULT equ 0x045  ; Result (2 bytes)
IRREMOTE_RC5IN__PIN equ 0x02E  ; pin (1 byte)
IRREMOTE_RC5IN__RESULT equ 0x030  ; Result (2 bytes)
X10_XOUT__REPS equ 0x02F  ; reps (1 byte)
X10_XOUT__RESULT equ 0x046  ; Result (1 byte)
X10_XIN__VALUE equ 0x062  ; value (2 bytes)
X10_XIN__RESULT equ 0x034  ; Result (1 byte)
X10_XIN__HIST equ 0x014  ; hist (1 byte)
X10_XIN__N equ 0x016  ; n (2 bytes)
X10_XIN__I equ 0x018  ; i (1 byte)
X10_XIN__A equ 0x011  ; a (1 byte)
X10_XIN__B equ 0x02E  ; b (1 byte)
X10_XIN__H equ 0x019  ; h (1 byte)
X10_XIN__K equ 0x02D  ; k (1 byte)
X10_XIN__F equ 0x02F  ; f (1 byte)
X10_XIN__GOOD equ 0x00F  ; good (1 byte)
PINIO_PINOK__PIN equ 0x059  ; pin (1 byte)
PINIO_PINOK__RESULT equ 0x015  ; Result (1 byte)
PINIO_PININPUT__PIN equ 0x059  ; pin (1 byte)
X10_ZERO__ZPIN equ 0x032  ; zpin (1 byte)
X10_ZERO__RESULT equ 0x010  ; Result (1 byte)
PINIO_PINGET__PIN equ 0x059  ; pin (1 byte)
PINIO_PINGET__RESULT equ 0x015  ; Result (1 byte)
X10_NUMBEROF__CODE equ 0x015  ; code (1 byte)
X10_NUMBEROF__RESULT equ 0x012  ; Result (1 byte)
X10_NUMBEROF__I equ 0x010  ; i (1 byte)
X10_CODEOF__N equ 0x059  ; n (1 byte)
X10_CODEOF__RESULT equ 0x013  ; Result (1 byte)
X10_CODEOF__T equ 0x030  ; t (4 bytes)
X10_ZERO__N equ 0x012  ; n (2 bytes)
PINIO_PININPUT__M equ 0x015  ; m (1 byte)
X10_XOUT__N equ 0x017  ; n (1 byte)
X10_XOUT__SENT equ 0x00F  ; sent (1 byte)
PINIO_PINSET__PIN equ 0x015  ; pin (1 byte)
PINIO_PINSET__LEVEL equ 0x018  ; level (1 byte)
PINIO_PINOUTPUT__PIN equ 0x02D  ; pin (1 byte)
X10_XOUT__H1 equ 0x02E  ; (hidden) (1 byte)
X10_FRAME__RESULT equ 0x016  ; Result (1 byte)
X10_XOUT__H2 equ 0x011  ; (hidden) (1 byte)
X10_FRAME__I equ 0x014  ; i (1 byte)
X10_FRAME__H equ 0x034  ; h (1 byte)
X10_FRAME__K equ 0x045  ; k (1 byte)
X10_HALF__BURST equ 0x031  ; burst (1 byte)
X10_HALF__RESULT equ 0x030  ; Result (1 byte)
X10_SENDBIT__B equ 0x019  ; b (1 byte)
X10_SENDBIT__RESULT equ 0x02D  ; Result (1 byte)
PINIO_PINOUTPUT__M equ 0x030  ; m (1 byte)
PINIO_PINOUTPUT__N equ 0x015  ; n (1 byte)
IRREMOTE_RC5IN__V equ 0x011  ; v (2 bytes)
IRREMOTE_WIDTH__LEVEL equ 0x02F  ; level (1 byte)
IRREMOTE_WIDTH__LIMIT equ 0x016  ; limit (2 bytes)
IRREMOTE_WIDTH__RESULT equ 0x013  ; Result (2 bytes)
PULSE_WAITUS__US equ 0x00F  ; us (2 bytes)
IRREMOTE_RC5IN__H3 equ 0x02D  ; (hidden) (1 byte)
IRREMOTE_WIDTH__N equ 0x018  ; n (2 bytes)
IRREMOTE_SONYIN__HEADER equ 0x033  ; header (2 bytes)
IRREMOTE_SONYIN__W equ 0x02D  ; w (2 bytes)
IRREMOTE_SONYIN__V equ 0x031  ; v (2 bytes)
IRREMOTE_SONYIN__I equ 0x030  ; i (1 byte)
PULSE_SOUND2__H1 equ 0x018  ; h1 (1 byte)
PULSE_SOUND2__H2 equ 0x019  ; h2 (1 byte)
PULSE_SOUND2__C1 equ 0x013  ; c1 (1 byte)
PULSE_SOUND2__C2 equ 0x014  ; c2 (1 byte)
PULSE_SOUND2__L1 equ 0x016  ; l1 (1 byte)
PULSE_SOUND2__L2 equ 0x017  ; l2 (1 byte)
PULSE_SOUND2__TICKS equ 0x00F  ; ticks (4 bytes)
PINIO_BINDDATA__PIN equ 0x015  ; pin (1 byte)
PINIO_BINDCLK__PIN equ 0x015  ; pin (1 byte)
PINIO_DATAPUT__LEVEL equ 0x015  ; level (1 byte)
PINIO_CLKPUT__LEVEL equ 0x015  ; level (1 byte)
PINIO_PINADDR__PIN equ 0x02F  ; pin (1 byte)
PINIO_PINADDR__RESULT equ 0x02D  ; Result (2 bytes)
PULSE_SOUND__HALF equ 0x017  ; half (2 bytes)
PULSE_SOUND__COUNT equ 0x011  ; count (4 bytes)
PULSE_SOUND__LFSR equ 0x031  ; lfsr (2 bytes)
PULSE_SOUND__N equ 0x019  ; n (1 byte)
PULSE_SOUND__LEVEL equ 0x016  ; level (1 byte)
PULSE_PWMPIN__I equ 0x00F  ; i (1 byte)
PULSE_PWMPIN__C equ 0x011  ; c (1 byte)
PULSE_PWMPIN__H6 equ 0x010  ; (hidden) (1 byte)
PULSE_POT__T equ 0x016  ; t (4 bytes)
PULSE_RCIN__N equ 0x00F  ; n (2 bytes)
PINIO_DATAREAD__RESULT equ 0x011  ; Result (1 byte)
PULSE_PULSEIN__N equ 0x00F  ; n (2 bytes)
PULSE_PULSEOUT_2__PERIOD equ 0x00F  ; period (2 bytes)
PULSE_PULSEOUT_2__LEVEL equ 0x011  ; level (1 byte)
RTCCSPI_WRENABLE__RESULT equ 0x012  ; Result (1 byte)
RTCCSPI_WRITEBLOCK__C equ 0x02E  ; c (1 byte)
RTCCSPI_WRITEBLOCK__A equ 0x02F  ; a (1 byte)
RTCCSPI_WRITEBLOCK__N equ 0x012  ; n (1 byte)
RTCCSPI_WRITEBLOCK__RESULT equ 0x02D  ; Result (1 byte)
RTCCSPI_WRITEBLOCK__I equ 0x011  ; i (1 byte)
RTCCSPI_EEREADY__RESULT equ 0x00F  ; Result (1 byte)
RTCCSPI_CMD1__C equ 0x010  ; c (1 byte)
RTCCSPI_CMD1__RESULT equ 0x00F  ; Result (1 byte)
RTCCSPI_EEREADY__N equ 0x010  ; n (1 byte)
RTCCSPI_STATUSREAD__RESULT equ 0x011  ; Result (1 byte)
RTCCSPI_RTCCSPIALARM__PIN equ 0x030  ; pin (1 byte)
RTCCSPI_RTCCSPIALARM__TWELVE equ 0x031  ; twelve (1 byte)
RTCCSPI_RDREG__REG equ 0x02F  ; reg (1 byte)
RTCCSPI_RDREG__RESULT equ 0x012  ; Result (1 byte)
RTCCSPI_TOBCD__V equ 0x013  ; v (1 byte)
RTCCSPI_TOBCD__RESULT equ 0x011  ; Result (1 byte)
RTCCSPI_ENCHOUR__H equ 0x010  ; h (1 byte)
RTCCSPI_ENCHOUR__TWELVE equ 0x014  ; twelve (1 byte)
RTCCSPI_ENCHOUR__RESULT equ 0x012  ; Result (1 byte)
RTCCSPI_READBLOCK__A equ 0x02E  ; a (1 byte)
RTCCSPI_READBLOCK__N equ 0x019  ; n (1 byte)
RTCCSPI_READBLOCK__RESULT equ 0x02D  ; Result (1 byte)
RTCCSPI_READBLOCK__I equ 0x011  ; i (1 byte)
RTCCSPI_RTCCSPIREAD__I equ 0x00F  ; i (1 byte)
RTCCSPI_RTCCSPISET__CTL equ 0x030  ; ctl (1 byte)
RTCCSPI_RTCCSPISET__VB equ 0x031  ; vb (1 byte)
RTCCSPI_RTCCSPISET__TS equ 0x032  ; ts (1 byte)
RTCCSPI_RTCCSPISET__N equ 0x010  ; n (1 byte)
RTCCSPI_DAYSIN__RESULT equ 0x011  ; Result (1 byte)
RTCCSPI_WRREG__REG equ 0x013  ; reg (1 byte)
RTCCSPI_WRREG__V equ 0x017  ; v (1 byte)
RTCCSPI_WRREG__RESULT equ 0x019  ; Result (1 byte)
RTCC_EEPUT__VALUE equ 0x033  ; value (1 byte)
RTCC_EEPUT__RESULT equ 0x017  ; Result (1 byte)
RTCC_EEREADY__RESULT equ 0x010  ; Result (1 byte)
RTCC_WRITEBLOCK__CTL equ 0x02F  ; ctl (1 byte)
RTCC_WRITEBLOCK__REG equ 0x030  ; reg (1 byte)
RTCC_WRITEBLOCK__N equ 0x013  ; n (1 byte)
RTCC_WRITEBLOCK__RESULT equ 0x012  ; Result (1 byte)
RTCC_WRITEBLOCK__I equ 0x011  ; i (1 byte)
RTCC_WRITEBLOCK__S equ 0x062  ; s (1 byte)
RTCC_OPEN__CTL equ 0x034  ; ctl (1 byte)
RTCC_OPEN__REG equ 0x045  ; reg (1 byte)
RTCC_OPEN__RESULT equ 0x02D  ; Result (1 byte)
RTCC_EEREADY__N equ 0x011  ; n (1 byte)
RTCC_EEREADY__S equ 0x00F  ; s (1 byte)
RTCC_RTCCALARM__POL equ 0x033  ; pol (1 byte)
RTCC_RDREG__REG equ 0x02F  ; reg (1 byte)
RTCC_RDREG__RESULT equ 0x013  ; Result (1 byte)
RTCC_ENCHOUR__H equ 0x010  ; h (1 byte)
RTCC_ENCHOUR__TWELVE equ 0x014  ; twelve (1 byte)
RTCC_ENCHOUR__RESULT equ 0x012  ; Result (1 byte)
RTCC_TOBCD__V equ 0x013  ; v (1 byte)
RTCC_TOBCD__RESULT equ 0x011  ; Result (1 byte)
RTCC_READBLOCK__REG equ 0x02E  ; reg (1 byte)
RTCC_READBLOCK__N equ 0x017  ; n (1 byte)
RTCC_READBLOCK__RESULT equ 0x012  ; Result (1 byte)
RTCC_READBLOCK__I equ 0x011  ; i (1 byte)
RTCC_READBLOCK__S equ 0x030  ; s (1 byte)
RTCC_RTCCREAD__I equ 0x00F  ; i (1 byte)
RTCC_RTCCSET__CTL equ 0x033  ; ctl (1 byte)
RTCC_RTCCSET__VB equ 0x046  ; vb (1 byte)
RTCC_RTCCSET__N equ 0x010  ; n (1 byte)
RTCC_DAYSIN__RESULT equ 0x011  ; Result (1 byte)
RTCC_WRREG__REG equ 0x017  ; reg (1 byte)
RTCC_WRREG__V equ 0x019  ; v (1 byte)
RTCC_WRREG__RESULT equ 0x02E  ; Result (1 byte)
AHT30_AHT30FETCH__S equ 0x075  ; s (1 byte)
AHT30_AHT30FETCH__I equ 0x011  ; i (1 byte)
AHT30_AHT30FETCH__RAW equ 0x02D  ; raw (4 bytes)
AHT30_CRC8__I equ 0x014  ; i (1 byte)
AHT30_CRC8__K equ 0x010  ; k (1 byte)
AHT30_CRC8__C equ 0x00F  ; c (1 byte)
AHT30_AHT30START__S equ 0x010  ; s (1 byte)
OLED_OLEDWRITEWORD__STARTED equ 0x019  ; started (1 byte)
OLED_OLEDWRITEWORD__D equ 0x00F  ; d (2 bytes)
OLED_OLEDWRITEWORD__DIGIT equ 0x013  ; digit (1 byte)
OLED_OLEDWRITE__I equ 0x00F  ; i (1 byte)
OLED_OLEDWRITECHAR__BASE equ 0x02D  ; base (2 bytes)
OLED_OLEDWRITECHAR__I equ 0x017  ; i (1 byte)
OLED_BEGIN__ISDATA equ 0x033  ; isData (1 byte)
OLED_PUT__B equ 0x02F  ; b (1 byte)
OLED_FINISH__S equ 0x02F  ; s (1 byte)
OLED_PUT__S equ 0x032  ; s (1 byte)
OLED_BEGIN__S equ 0x02F  ; s (1 byte)
OLED_OLEDFILL__N equ 0x00F  ; n (2 bytes)
OLED_CMD__N equ 0x011  ; n (1 byte)
OLED_CMD__C equ 0x012  ; c (1 byte)
OLED_CMD__A equ 0x013  ; a (1 byte)
OLED_CMD__B equ 0x017  ; b (1 byte)
OLED_RESET__RES equ 0x00F  ; res (1 byte)
LCD_SEND__B equ 0x019  ; b (1 byte)
LCD_SEND__RS equ 0x02D  ; rs (1 byte)
LCD_NIBBLE__NIB equ 0x014  ; nib (1 byte)
LCD_NIBBLE__I equ 0x016  ; i (1 byte)
LCD_LCDWRITEWORD__STARTED equ 0x017  ; started (1 byte)
LCD_LCDWRITEWORD__D equ 0x00F  ; d (2 bytes)
LCD_LCDWRITEWORD__DIGIT equ 0x013  ; digit (1 byte)
LCD_LCDWRITE__I equ 0x00F  ; i (1 byte)
LCD_LCDINIT__I equ 0x010  ; i (1 byte)
LCD_LCDINIT__J equ 0x00F  ; j (1 byte)
SYSTEM_SYSCLOCKFROM__COSC equ 0x02D  ; cosc (1 byte)
SYSTEM_SYSCLOCKFROM__CDIV equ 0x018  ; cdiv (1 byte)
SYSTEM_SYSCLOCKFROM__HFFRQ equ 0x02E  ; hffrq (1 byte)
SYSTEM_SYSCLOCKFROM__RESULT equ 0x00F  ; Result (4 bytes)
SYSTEM_SYSCLOCKFROM__MHZ equ 0x013  ; mhz (1 byte)
SYSTEM_SYSRESETCAUSE__F equ 0x010  ; f (1 byte)
SPI_PPSOFF__PIN equ 0x011  ; pin (1 byte)
SPI_PPSOFF__SL equ 0x00F  ; sl (1 byte)
SPI_PPSOFF__SH equ 0x010  ; sh (1 byte)
SPI_SPIWRITE__R equ 0x045  ; r (1 byte)
SPI_SPITRANSFER__N equ 0x014  ; n (2 bytes)
SPI_PINSETUP__PIN equ 0x010  ; pin (1 byte)
SPI_PINSETUP__ASINPUT equ 0x011  ; asInput (1 byte)
SPI_SETPPS__PIN equ 0x010  ; pin (1 byte)
SPI_SETPPS__CODE equ 0x00F  ; code (1 byte)
SPI_PINSETUP__M equ 0x00F  ; m (1 byte)
I2C_SETPPS__PIN equ 0x00F  ; pin (1 byte)
I2C_SETPPS__CODE equ 0x010  ; code (1 byte)
I2C_SETPPS__SL equ 0x011  ; sl (1 byte)
I2C_SETPPS__SH equ 0x012  ; sh (1 byte)
I2C_I2CREADREG__S equ 0x012  ; s (1 byte)
I2C_I2CREADREG__E equ 0x00F  ; e (1 byte)
I2C_OPEN__RESULT equ 0x010  ; Result (1 byte)
I2C_I2CWRITEREG__S equ 0x011  ; s (1 byte)
I2C_I2CPROBE__ADDR equ 0x012  ; addr (1 byte)
I2C_I2CPROBE__RESULT equ 0x00F  ; Result (1 byte)
I2C_CONDITION__MSK equ 0x059  ; msk (1 byte)
I2C_CONDITION__RESULT equ 0x032  ; Result (1 byte)
I2C_WAITIDLE__MSK equ 0x031  ; msk (1 byte)
I2C_WAITIDLE__RESULT equ 0x018  ; Result (1 byte)
I2C_WAITIDLE__N equ 0x015  ; n (2 bytes)
I2C_WAITIF__RESULT equ 0x018  ; Result (1 byte)
I2C_WAITIF__N equ 0x015  ; n (2 bytes)
I2C_PINSETUP__PIN equ 0x010  ; pin (1 byte)
I2C_PINSETUP__M equ 0x00F  ; m (1 byte)
PWM_SETCON__CH equ 0x014  ; ch (1 byte)
PWM_SETCON__V equ 0x013  ; v (1 byte)
PWM_SETPPS__PIN equ 0x013  ; pin (1 byte)
PWM_SETPPS__CODE equ 0x014  ; code (1 byte)
PWM_SETPPS__SL equ 0x015  ; sl (1 byte)
PWM_SETPPS__SH equ 0x019  ; sh (1 byte)
PWM_PWMPERCENT__D equ 0x016  ; d (2 bytes)
PWM_SETDUTY__CH equ 0x015  ; ch (1 byte)
PWM_SETDUTY__D equ 0x013  ; d (2 bytes)
PWM_SETDUTY__HI equ 0x019  ; hi (1 byte)
PWM_SETDUTY__LO equ 0x02D  ; lo (1 byte)
PWM_PWMSTART__OLD equ 0x018  ; old (1 byte)
PWM_PWMSTART__C equ 0x00F  ; c (1 byte)
PWM_PINOK__CH equ 0x013  ; ch (1 byte)
PWM_PINOK__PIN equ 0x014  ; pin (1 byte)
PWM_PINOK__RESULT equ 0x015  ; Result (1 byte)
FLASHWRITE_FLASHUPDATEWORD__CUR equ 0x031  ; cur (2 bytes)
FLASHWRITE_FLASHUPDATEWORD__IE equ 0x034  ; ie (1 byte)
FLASHWRITE_SETADDR__ADDR equ 0x017  ; addr (2 bytes)
FLASHWRITE_FLASHWRITEWORD__IE equ 0x045  ; ie (1 byte)
FLASHWRITE_FLASHERASESECTOR__IE equ 0x012  ; ie (1 byte)
EEPROM_EEPROMWRITE__IE equ 0x019  ; ie (1 byte)
ADC_ADCREADAVG__SUM equ 0x011  ; sum (2 bytes)
ADC_ADCREADAVG__I equ 0x013  ; i (1 byte)
ADC_CONVERT__RESULT equ 0x00F  ; Result (2 bytes)
SERIAL2_SERIAL2WRITEBYTE__B equ 0x016  ; b (1 byte)
SERIAL2_SERIAL2WRITEHEX__H equ 0x00F  ; h (1 byte)
SERIAL2_SERIAL2WRITEHEX__H7 equ 0x011  ; (hidden) (1 byte)
SERIAL2_SERIAL2WRITEWORD__STARTED equ 0x015  ; started (1 byte)
SERIAL2_SERIAL2WRITEWORD__K equ 0x014  ; k (1 byte)
SERIAL2_SERIAL2WRITEWORD__DIGIT equ 0x013  ; digit (1 byte)
SERIAL2_SERIAL2WRITEWORD__D equ 0x00F  ; d (2 bytes)
SERIAL2_SERIAL2WRITE__I equ 0x00F  ; i (1 byte)
SERIAL_SERIALWRITEBYTE__B equ 0x016  ; b (1 byte)
SERIAL_SERIALWRITEHEX__H equ 0x00F  ; h (1 byte)
SERIAL_SERIALWRITEHEX__H8 equ 0x011  ; (hidden) (1 byte)
SERIAL_SERIALWRITEWORD__STARTED equ 0x015  ; started (1 byte)
SERIAL_SERIALWRITEWORD__K equ 0x014  ; k (1 byte)
SERIAL_SERIALWRITEWORD__DIGIT equ 0x013  ; digit (1 byte)
SERIAL_SERIALWRITEWORD__D equ 0x00F  ; d (2 bytes)
SERIAL_SERIALWRITE__C equ 0x00F  ; c (1 byte)
__A0 equ 0x000
__A1 equ 0x001
__A2 equ 0x002
__A3 equ 0x003
__B0 equ 0x004
__B1 equ 0x005
__B2 equ 0x006
__B3 equ 0x007
__C0 equ 0x008
__C1 equ 0x009
__C2 equ 0x00A
__C3 equ 0x00B
__D0 equ 0x00C
__D1 equ 0x00D
__D2 equ 0x00E
PWM_PWMSTART__TMP equ 0x011
LCD_LCDINIT__TMP equ 0x011
AHT30_AHT30FETCH__TMP equ 0x012
RTCC_RTCCSET__TMP equ 0x063
RTCC_RTCCREAD__TMP equ 0x010
RTCCSPI_RTCCSPISET__TMP equ 0x034
RTCCSPI_RTCCSPIREAD__TMP equ 0x010
IRREMOTE_SONYIN__TMP equ 0x00F
IRREMOTE_RC5IN__TMP equ 0x032
X10_XIN__TMP equ 0x045
RTCCSPI_TOBCD__TMP equ 0x015
RTCCSPI_READBLOCK__TMP equ 0x013
RTCC_TOBCD__TMP equ 0x015
RTCC_READBLOCK__TMP equ 0x019
SYSTEM_SYSCLOCKFROM__TMP equ 0x014
PWM_SETDUTY__TMP equ 0x02F
FLASHWRITE_SETADDR__TMP equ 0x046

PSECT code,class=CODE,abs,delta=1
    ORG 0x0000
__reset:
    lfsr 0, 0x01A
    movlw 107
_L1:
    clrf POSTINC0, c
    decfsz WREG, f, c
    bra _L1
    movlb 15
    clrf ANSELA, b
    clrf ANSELB, b
    clrf ANSELC, b
    clrf WPUA, b
    movlw 0x03
    movwf WPUB, b
    clrf WPUC, b
    movlw 0x01
    movwf DELAY_DELAYSECONDS__S, c
    bra _L7
_L6:
    clrf __D0, c
_L9:
    clrf __D1, c
_L10:
    movlw 80
    movwf __D2, c
_L11:
    decfsz __D2, f, c
    bra _L11
    decfsz __D1, f, c
    bra _L10
    movlw 10
    movwf __D1, c
_L12:
    decfsz __D1, f, c
    bra _L12
    bra _L13
_L13:
    decfsz __D0, f, c
    bra _L9
    decf DELAY_DELAYSECONDS__S, f, c
_L7:
    movf DELAY_DELAYSECONDS__S, f, c
    bnz _L6
    clrf T0CON0, c
    movlw 0x41
    movwf T0CON1, c
    movlw 0x63
    movwf TMR0H, c
    clrf TMR0L, c
    movlb 14
    bcf PIR0, 5, b
    movlw 0x80
    movwf T0CON0, c
    movff TMR0L, TIMER_TIMER0READ__RESULT
    movff TMR0H, TIMER_TIMER0READ__RESULT+1
    clrf T1CON, c
    movlw 0x01
    movwf T1CLK, c
    clrf T1GCON, c
    clrf TMR1L, c
    clrf TMR1H, c
    bcf PIR4, 0, b
    movlw 0x03
    movwf T1CON, c
    movff TMR1L, TIMER_TIMER1READ__RESULT
    movff TMR1H, TIMER_TIMER1READ__RESULT+1
    movff TIMER_TIMER1READ__RESULT, T_X
    movff TIMER_TIMER1READ__RESULT+1, T_X+1
    clrf T2CON, c
    movlw 0x01
    movwf T2CLKCON, c
    clrf T2HLT, c
    clrf T2RST, c
    movlw 0x63
    movwf T2PR, c
    clrf T2TMR, c
    bcf PIR4, 1, b
    movlw 0x80
    movwf T2CON, c
    movff T2TMR, TIMER_TIMER2READ__RESULT
    movf TIMER_TIMER2READ__RESULT, w, c
    movwf T_R, c
    movlb 15
    bcf ANSELC, 7, b
    bsf TRISC, 7, c
    bcf TRISC, 6, c
    movlw 0x09
    movlb 14
    movwf RC6PPS, b
    movlw 0x17
    movwf RX1PPS, b
    movlw 0x8A
    movwf SP1BRGL, c
    clrf SP1BRGH, c
    movlw 0x08
    movwf BAUD1CON, c
    movlw 0x24
    movwf TX1STA, c
    movlw 0x90
    movwf RC1STA, c
    movlw low(__SLIT3)
    movwf TBLPTRL, c
    movlw high(__SLIT3)
    movwf TBLPTRH, c
    movlw highword(__SLIT3)
    movwf TBLPTRU, c
_L14:
    tblrd*+
    movf TABLAT, w, c
    bz _Lr10
    call SERIAL_SERIALWRITEBYTE
    bra _L14
_Lr10:
    movlw 0xD2
    movwf SERIAL_SERIALWRITEWORD__V, c
    movlw 0x04
    movwf SERIAL_SERIALWRITEWORD__V+1, c
    clrf SERIAL_SERIALWRITEWORD__STARTED, c
    clrf SERIAL_SERIALWRITEWORD__K, c
_L19:
    movf SERIAL_SERIALWRITEWORD__K, w, c
    addwf WREG, w, c
    addlw low(__CA2)
    movwf TBLPTRL, c
    movlw high(__CA2)
    movwf TBLPTRH, c
    movlw 0
    addwfc TBLPTRH, f, c
    clrf TBLPTRU, c
    tblrd*+
    movff TABLAT, SERIAL_SERIALWRITEWORD__D
    tblrd*+
    movff TABLAT, SERIAL_SERIALWRITEWORD__D+1
    movlw 0x30
    movwf SERIAL_SERIALWRITEWORD__DIGIT, c
    bra _L23
_L22:
    movf SERIAL_SERIALWRITEWORD__D, w, c
    subwf SERIAL_SERIALWRITEWORD__V, f, c
    movf SERIAL_SERIALWRITEWORD__D+1, w, c
    subwfb SERIAL_SERIALWRITEWORD__V+1, f, c
    incf SERIAL_SERIALWRITEWORD__DIGIT, f, c
_L23:
    movf SERIAL_SERIALWRITEWORD__D, w, c
    subwf SERIAL_SERIALWRITEWORD__V, w, c
    movf SERIAL_SERIALWRITEWORD__D+1, w, c
    subwfb SERIAL_SERIALWRITEWORD__V+1, w, c
    bc _L22
    movlw 0x31
    subwf SERIAL_SERIALWRITEWORD__DIGIT, w, c
    bc _L27
    movf SERIAL_SERIALWRITEWORD__STARTED, f, c
    bz _L26
_L27:
    movf SERIAL_SERIALWRITEWORD__DIGIT, w, c
    call SERIAL_SERIALWRITEBYTE
    movlw 0x01
    movwf SERIAL_SERIALWRITEWORD__STARTED, c
_L26:
    movf SERIAL_SERIALWRITEWORD__K, w, c
    incf SERIAL_SERIALWRITEWORD__K, f, c
    xorlw 0x03
    bnz _L19
    movf SERIAL_SERIALWRITEWORD__V, w, c
    addlw 0x30
    call SERIAL_SERIALWRITEBYTE
    movlw 0xAB
    movwf SERIAL_SERIALWRITEHEX__V, c
    movlw 0x02
    movwf SERIAL_SERIALWRITEHEX__H8, c
_L28:
    movf SERIAL_SERIALWRITEHEX__V, w, c
    swapf WREG, w, c
    andlw 0x0F
    movwf SERIAL_SERIALWRITEHEX__H, c
    movf SERIAL_SERIALWRITEHEX__V, w, c
    mullw 16
    movf PRODL, w, c
    movwf SERIAL_SERIALWRITEHEX__V, c
    movlw 0x0A
    subwf SERIAL_SERIALWRITEHEX__H, w, c
    bnc _L32
    movlw 0x07
    addwf SERIAL_SERIALWRITEHEX__H, f, c
_L32:
    movf SERIAL_SERIALWRITEHEX__H, w, c
    addlw 0x30
    call SERIAL_SERIALWRITEBYTE
    decfsz SERIAL_SERIALWRITEHEX__H8, f, c
    bra _L28
    movlw 0x0D
    call SERIAL_SERIALWRITEBYTE
    movlw 0x0A
    call SERIAL_SERIALWRITEBYTE
_L33:
    btfss TX1STA, 1, c
    bra _L33
    bra _L37
_L36:
    btfss RC1STA, 1, c
    bra _L40
    bcf RC1STA, 4, c
    bsf RC1STA, 4, c
_L40:
_L37:
    btfss PIR3, 5, b
    bra _L36
    movff RC1REG, SERIAL_SERIALREAD__RESULT
    movf SERIAL_SERIALREAD__RESULT, w, c
    movwf T_R, c
    movlb 15
    bcf ANSELB, 7, b
    bsf TRISB, 7, c
    bcf TRISB, 6, c
    movlw 0x0B
    movlb 14
    movwf RB6PPS, b
    movlw 0x0F
    movwf RX2PPS, b
    movlw 0x8A
    movwf SP2BRGL, b
    clrf SP2BRGH, b
    movlw 0x08
    movwf BAUD2CON, b
    movlw 0x24
    movwf TX2STA, b
    movlw 0x90
    movwf RC2STA, b
    clrf SERIAL2_SERIAL2WRITE__I, c
    bra _L42
_L41:
    movf SERIAL2_SERIAL2WRITE__I, w, c
    addlw low(__SLIT4)
    movwf TBLPTRL, c
    movlw high(__SLIT4)
    movwf TBLPTRH, c
    movlw 0
    addwfc TBLPTRH, f, c
    clrf TBLPTRU, c
    tblrd*+
    movf TABLAT, w, c
    call SERIAL2_SERIAL2WRITEBYTE
    incf SERIAL2_SERIAL2WRITE__I, f, c
_L42:
    movf SERIAL2_SERIAL2WRITE__I, w, c
    addlw low(__SLIT4)
    movwf TBLPTRL, c
    movlw high(__SLIT4)
    movwf TBLPTRH, c
    movlw 0
    addwfc TBLPTRH, f, c
    clrf TBLPTRU, c
    tblrd*+
    movf TABLAT, w, c
    bnz _L41
    movlw 0xD2
    movwf SERIAL2_SERIAL2WRITEWORD__V, c
    movlw 0x04
    movwf SERIAL2_SERIAL2WRITEWORD__V+1, c
    clrf SERIAL2_SERIAL2WRITEWORD__STARTED, c
    clrf SERIAL2_SERIAL2WRITEWORD__K, c
_L44:
    movf SERIAL2_SERIAL2WRITEWORD__K, w, c
    addwf WREG, w, c
    addlw low(__CA1)
    movwf TBLPTRL, c
    movlw high(__CA1)
    movwf TBLPTRH, c
    movlw 0
    addwfc TBLPTRH, f, c
    clrf TBLPTRU, c
    tblrd*+
    movff TABLAT, SERIAL2_SERIAL2WRITEWORD__D
    tblrd*+
    movff TABLAT, SERIAL2_SERIAL2WRITEWORD__D+1
    movlw 0x30
    movwf SERIAL2_SERIAL2WRITEWORD__DIGIT, c
    bra _L48
_L47:
    movf SERIAL2_SERIAL2WRITEWORD__D, w, c
    subwf SERIAL2_SERIAL2WRITEWORD__V, f, c
    movf SERIAL2_SERIAL2WRITEWORD__D+1, w, c
    subwfb SERIAL2_SERIAL2WRITEWORD__V+1, f, c
    incf SERIAL2_SERIAL2WRITEWORD__DIGIT, f, c
_L48:
    movf SERIAL2_SERIAL2WRITEWORD__D, w, c
    subwf SERIAL2_SERIAL2WRITEWORD__V, w, c
    movf SERIAL2_SERIAL2WRITEWORD__D+1, w, c
    subwfb SERIAL2_SERIAL2WRITEWORD__V+1, w, c
    bc _L47
    movlw 0x31
    subwf SERIAL2_SERIAL2WRITEWORD__DIGIT, w, c
    bc _L52
    movf SERIAL2_SERIAL2WRITEWORD__STARTED, f, c
    bz _L51
_L52:
    movf SERIAL2_SERIAL2WRITEWORD__DIGIT, w, c
    call SERIAL2_SERIAL2WRITEBYTE
    movlw 0x01
    movwf SERIAL2_SERIAL2WRITEWORD__STARTED, c
_L51:
    movf SERIAL2_SERIAL2WRITEWORD__K, w, c
    incf SERIAL2_SERIAL2WRITEWORD__K, f, c
    xorlw 0x03
    bnz _L44
    movf SERIAL2_SERIAL2WRITEWORD__V, w, c
    addlw 0x30
    call SERIAL2_SERIAL2WRITEBYTE
    movlw 0xAB
    movwf SERIAL2_SERIAL2WRITEHEX__V, c
    movlw 0x02
    movwf SERIAL2_SERIAL2WRITEHEX__H7, c
_L53:
    movf SERIAL2_SERIAL2WRITEHEX__V, w, c
    swapf WREG, w, c
    andlw 0x0F
    movwf SERIAL2_SERIAL2WRITEHEX__H, c
    movf SERIAL2_SERIAL2WRITEHEX__V, w, c
    mullw 16
    movf PRODL, w, c
    movwf SERIAL2_SERIAL2WRITEHEX__V, c
    movlw 0x0A
    subwf SERIAL2_SERIAL2WRITEHEX__H, w, c
    bnc _L57
    movlw 0x07
    addwf SERIAL2_SERIAL2WRITEHEX__H, f, c
_L57:
    movf SERIAL2_SERIAL2WRITEHEX__H, w, c
    addlw 0x30
    call SERIAL2_SERIAL2WRITEBYTE
    decfsz SERIAL2_SERIAL2WRITEHEX__H7, f, c
    bra _L53
    movlw 0x0D
    call SERIAL2_SERIAL2WRITEBYTE
    movlw 0x0A
    call SERIAL2_SERIAL2WRITEBYTE
_L58:
    btfss TX2STA, 1, b
    bra _L58
    bra _L62
_L61:
    btfss RC2STA, 1, b
    bra _L65
    bcf RC2STA, 4, b
    bsf RC2STA, 4, b
_L65:
_L62:
    btfss PIR3, 7, b
    bra _L61
    movff RC2REG, SERIAL2_SERIAL2READ__RESULT
    movf SERIAL2_SERIAL2READ__RESULT, w, c
    movwf T_R, c
    movlb 15
    clrf ADCON0, b
    clrf ADCON1, b
    clrf ADCON2, b
    clrf ADCON3, b
    clrf ADCAP, b
    clrf ADPRE, b
    clrf ADACT, b
    clrf ADREF, b
    call ADC_SETCLOCK
    movlb 0
    setf ADC_LASTCH, b
    movlw 0x84
    movlb 15
    movwf ADCON0, b
    movlw 0x01
    iorwf TRISA, f, c
    iorwf ANSELA, f, b
    clrf ADREF, b
    movlw 0xFC
    andwf FVRCON, f, b
    call ADC_SETCLOCK
    movlw 0x00
    call ADC_ADCREAD
    movff ADC_CONVERT__RESULT, T_X
    movff ADC_CONVERT__RESULT+1, T_X+1
    clrf ADC_ADCREADAVG__SUM, c
    clrf ADC_ADCREADAVG__SUM+1, c
    clrf ADC_ADCREADAVG__I, c
    bra _L69
_L68:
    movlw 0x00
    call ADC_ADCREAD
    movf ADC_CONVERT__RESULT, w, c
    addwf ADC_ADCREADAVG__SUM, f, c
    movf ADC_CONVERT__RESULT+1, w, c
    addwfc ADC_ADCREADAVG__SUM+1, f, c
    incf ADC_ADCREADAVG__I, f, c
_L69:
    movlw 0x08
    subwf ADC_ADCREADAVG__I, w, c
    bnc _L68
    clrf ADC_ADCREADAVG__RESULT, c
    clrf ADC_ADCREADAVG__RESULT+1, c
    movff ADC_ADCREADAVG__SUM, __A0
    movff ADC_ADCREADAVG__SUM+1, __A0+1
    movlw 0x08
    movwf __B0, c
    clrf __B0+1, c
    call __div2
    movff __A0, ADC_ADCREADAVG__RESULT
    movff __A1, ADC_ADCREADAVG__RESULT+1
    movff ADC_ADCREADAVG__RESULT, T_X
    movff ADC_ADCREADAVG__RESULT+1, T_X+1
    movf T_X, w, c
    mullw 0xE4
    movff PRODL, __A0
    movff PRODH, __A1
    clrf __A2, c
    clrf __A3, c
    movf T_X+1, w, c
    mullw 0xE4
    movf PRODL, w, c
    addwf __A1, f, c
    movf PRODH, w, c
    addwfc __A2, f, c
    movlw 0
    addwfc __A3, f, c
    movf T_X, w, c
    mullw 0x0C
    movf PRODL, w, c
    addwf __A1, f, c
    movf PRODH, w, c
    addwfc __A2, f, c
    movlw 0
    addwfc __A3, f, c
    movf T_X+1, w, c
    mullw 0x0C
    movf PRODL, w, c
    addwf __A2, f, c
    movf PRODH, w, c
    addwfc __A3, f, c
    setf __B0, c
    movlw 0x03
    movwf __B0+1, c
    clrf __B0+2, c
    clrf __B0+3, c
    call __div4
    movff __A0, ADC_ADCMILLIVOLTS__RESULT
    movff __A1, ADC_ADCMILLIVOLTS__RESULT+1
    movff ADC_ADCMILLIVOLTS__RESULT, T_X
    movff ADC_ADCMILLIVOLTS__RESULT+1, T_X+1
    movlw 0x01
    movwf ADC_ADCREFFVR__GAIN, c
    movlw 0x04
    subwf ADC_ADCREFFVR__GAIN, w, c
    bnc _L73
    movlw 0x03
    movwf ADC_ADCREFFVR__GAIN, c
_L73:
    movf ADC_ADCREFFVR__GAIN, f, c
    bnz _L75
    movlw 0x01
    movwf ADC_ADCREFFVR__GAIN, c
_L75:
    movlb 15
    movf FVRCON, w, b
    andlw 0xFC
    iorwf ADC_ADCREFFVR__GAIN, w, c
    iorlw 0x80
    movwf FVRCON, b
_L76:
    btfss FVRCON, 6, b
    bra _L76
    movlw 0x03
    movwf ADREF, b
    movlw 0x3F
    movwf ADCLK, b
    movlw 0x03
    movwf ADACQ, b
    clrf EEPROM_EEPROMREAD__ADDR, c
    clrf EEPROM_EEPROMREAD__ADDR+1, c
    call EEPROM_EEPROMREAD
    movf EEPROM_EEPROMREAD__RESULT, w, c
    movwf T_R, c
    clrf EEPROM_EEPROMWRITE__ADDR, c
    clrf EEPROM_EEPROMWRITE__ADDR+1, c
    movff T_R, EEPROM_EEPROMWRITE__VALUE
    call EEPROM_EEPROMWRITE
    movf EEPROM_EEPROMWRITE__RESULT, w, c
    movwf T_R, c
    movlw 0x02
    movwf EEPROM_EEPROMREAD__ADDR, c
    clrf EEPROM_EEPROMREAD__ADDR+1, c
    call EEPROM_EEPROMREAD
    movf EEPROM_EEPROMREAD__RESULT, w, c
    movwf EEPROM_EEPROMREADWORD__RESULT, c
    clrf EEPROM_EEPROMREADWORD__RESULT+1, c
    movlw 0x03
    movwf EEPROM_EEPROMREAD__ADDR, c
    clrf EEPROM_EEPROMREAD__ADDR+1, c
    call EEPROM_EEPROMREAD
    movf EEPROM_EEPROMREAD__RESULT, w, c
    movwf EEPROM_EEPROMREADWORD__RESULT+1, c
    movff EEPROM_EEPROMREADWORD__RESULT, T_X
    movff EEPROM_EEPROMREADWORD__RESULT+1, T_X+1
    movff T_X, EEPROM_EEPROMWRITEWORD__VALUE
    movff T_X+1, EEPROM_EEPROMWRITEWORD__VALUE+1
    movlw 0x02
    movwf EEPROM_EEPROMWRITE__ADDR, c
    clrf EEPROM_EEPROMWRITE__ADDR+1, c
    movff EEPROM_EEPROMWRITEWORD__VALUE, EEPROM_EEPROMWRITE__VALUE
    call EEPROM_EEPROMWRITE
    movf EEPROM_EEPROMWRITE__RESULT, w, c
    movwf EEPROM_EEPROMWRITEWORD__RESULT, c
    movlw 0x03
    movwf EEPROM_EEPROMWRITE__ADDR, c
    clrf EEPROM_EEPROMWRITE__ADDR+1, c
    movff EEPROM_EEPROMWRITEWORD__VALUE+1, EEPROM_EEPROMWRITE__VALUE
    call EEPROM_EEPROMWRITE
    movf EEPROM_EEPROMWRITE__RESULT, w, c
    andwf EEPROM_EEPROMWRITEWORD__RESULT, f, c
    movf EEPROM_EEPROMWRITEWORD__RESULT, w, c
    movwf T_R, c
    movlw 0x80
    movwf FLASHWRITE_FLASHSECTORADDR__RESULT, c
    setf FLASHWRITE_FLASHSECTORADDR__RESULT+1, c
    movff FLASHWRITE_FLASHSECTORADDR__RESULT, FLASHWRITE_FLASHREADWORD__ADDR
    movff FLASHWRITE_FLASHSECTORADDR__RESULT+1, FLASHWRITE_FLASHREADWORD__ADDR+1
    call FLASHWRITE_FLASHREADWORD
    movff FLASHWRITE_FLASHREADWORD__RESULT, T_X
    movff FLASHWRITE_FLASHREADWORD__RESULT+1, T_X+1
    setf FLASHWRITE_FLASHERASESECTOR__SECTOR, c
    movlw 0x01
    movwf FLASHWRITE_FLASHERASESECTOR__SECTOR+1, c
    call FLASHWRITE_FLASHERASESECTOR
    movf FLASHWRITE_FLASHERASESECTOR__RESULT, w, c
    movwf T_R, c
    movlw 0x80
    movwf FLASHWRITE_FLASHWRITEWORD__ADDR, c
    setf FLASHWRITE_FLASHWRITEWORD__ADDR+1, c
    movff T_X, FLASHWRITE_FLASHWRITEWORD__VALUE
    movff T_X+1, FLASHWRITE_FLASHWRITEWORD__VALUE+1
    call FLASHWRITE_FLASHWRITEWORD
    movf FLASHWRITE_FLASHWRITEWORD__RESULT, w, c
    movwf T_R, c
    movlw 0x80
    movwf FLASHWRITE_FLASHUPDATEWORD__ADDR, c
    setf FLASHWRITE_FLASHUPDATEWORD__ADDR+1, c
    movff T_X, FLASHWRITE_FLASHUPDATEWORD__VALUE
    movff T_X+1, FLASHWRITE_FLASHUPDATEWORD__VALUE+1
    call FLASHWRITE_FLASHUPDATEWORD
    movf FLASHWRITE_FLASHUPDATEWORD__RESULT, w, c
    movwf T_R, c
    clrf PWM_PWMINIT__RESULT, c
    movf PWM_NACT, f, c
    bnz _Lr32
    movlw 0x04
    movlb 0
    movwf PWM_CKPS, b
    movlw 0xC7
    movwf PWM_PERIOD, b
    movlw 0x20
    movwf PWM_STEPS, c
    movlw 0x03
    movwf PWM_STEPS+1, c
    movlw 0x88
    movwf PWM_FREQ, c
    movlw 0x13
    movwf PWM_FREQ+1, c
    clrf PWM_FREQ+2, c
    clrf PWM_FREQ+3, c
    movlw 0x01
    movwf PWM_READY, b
    movwf PWM_PWMINIT__RESULT, c
_Lr32:
    movf PWM_PWMINIT__RESULT, w, c
    movwf T_R, c
    movlw 0x01
    movwf PWM_PWMSTART__CH, c
    movlw 0x12
    movwf PWM_PWMSTART__PIN, c
    movlw 0x64
    movwf PWM_PWMSTART__DUTY, c
    clrf PWM_PWMSTART__DUTY+1, c
    call PWM_PWMSTART
    movf PWM_PWMSTART__RESULT, w, c
    movwf T_R, c
    movlw 0x03
    movwf PWM_PWMSTART__CH, c
    clrf PWM_PWMSTART__PIN, c
    movlw 0xC8
    movwf PWM_PWMSTART__DUTY, c
    clrf PWM_PWMSTART__DUTY+1, c
    call PWM_PWMSTART
    movf PWM_PWMSTART__RESULT, w, c
    movwf T_R, c
    clrf PWM_PWMINVERT__RESULT, c
    movlw 0x02
    movwf __A0, c
    clrf __A0+1, c
    movlw low(PWM_POLV)
    addwf __A0, f, c
    movlw high(PWM_POLV)
    addwfc __A1, f, c
    movff __A0, FSR0L
    movff __A1, FSR0H
    movlw 0x10
    movwf INDF0, c
    movlw 0x02
    movwf __A0, c
    clrf __A0+1, c
    movlw low(PWM_PINS)
    addwf __A0, f, c
    movlw high(PWM_PINS)
    addwfc __A1, f, c
    movff __A0, FSR0L
    movff __A1, FSR0H
    movf INDF0, w, c
    bz _L156
    movlw 0x03
    movwf PWM_SETCON__CH, c
    movlw 0x02
    movwf __A0, c
    clrf __A0+1, c
    movlw low(PWM_POLV)
    addwf __A0, f, c
    movlw high(PWM_POLV)
    addwfc __A1, f, c
    movff __A0, FSR0L
    movff __A1, FSR0H
    movf INDF0, w, c
    addlw 0x80
    movwf PWM_SETCON__V, c
    call PWM_SETCON
_L156:
    movlw 0x01
    movwf T_R, c
    movwf PWM_PWMDUTY__CH, c
    movlw 0x2C
    movwf PWM_PWMDUTY__DUTY, c
    movlw 0x01
    movwf PWM_PWMDUTY__DUTY+1, c
    call PWM_PWMDUTY
    movlw 0x19
    movwf PWM_PWMPERCENT__PCT, c
    movlw 0x65
    subwf PWM_PWMPERCENT__PCT, w, c
    bnc _L162
    movlw 0x64
    movwf PWM_PWMPERCENT__PCT, c
_L162:
    movff PWM_STEPS, __A0
    movff PWM_STEPS+1, __A0+1
    bcf STATUS, 0, c
    rrcf __A1, f, c
    rrcf __A0, f, c
    bcf STATUS, 0, c
    rrcf __A1, f, c
    rrcf __A0, f, c
    movf PWM_PWMPERCENT__PCT, w, c
    mulwf __A0+1, c
    movff PRODL, __A1
    mulwf __A0, c
    movff PRODL, __A0
    movf PRODH, w, c
    addwf __A1, f, c
    movlw 0x19
    movwf __B0, c
    clrf __B0+1, c
    call __div2
    movff __A0, PWM_PWMPERCENT__D
    movff __A1, PWM_PWMPERCENT__D+1
    movlw 0x03
    movwf PWM_PWMDUTY__CH, c
    movff PWM_PWMPERCENT__D, PWM_PWMDUTY__DUTY
    movff PWM_PWMPERCENT__D+1, PWM_PWMDUTY__DUTY+1
    call PWM_PWMDUTY
    clrf PWM_PWMFREQUENCY__RESULT, c
    clrf PWM_PWMFREQUENCY__RESULT+1, c
    clrf PWM_PWMFREQUENCY__RESULT+2, c
    clrf PWM_PWMFREQUENCY__RESULT+3, c
    movlb 0
    movf PWM_READY, f, b
    bz _L164
    movff PWM_FREQ, PWM_PWMFREQUENCY__RESULT
    movff PWM_FREQ+1, PWM_PWMFREQUENCY__RESULT+1
    movff PWM_FREQ+2, PWM_PWMFREQUENCY__RESULT+2
    movff PWM_FREQ+3, PWM_PWMFREQUENCY__RESULT+3
_L164:
    movff PWM_PWMFREQUENCY__RESULT, T_X
    movff PWM_PWMFREQUENCY__RESULT+1, T_X+1
    clrf PWM_PWMSTEPS__RESULT, c
    clrf PWM_PWMSTEPS__RESULT+1, c
    movf PWM_READY, f, b
    bz _L166
    movff PWM_STEPS, PWM_PWMSTEPS__RESULT
    movff PWM_STEPS+1, PWM_PWMSTEPS__RESULT+1
_L166:
    movff PWM_PWMSTEPS__RESULT, T_X
    movff PWM_PWMSTEPS__RESULT+1, T_X+1
    movlw 0x01
    call PWM_PWMSTOP
    movlw 0x03
    call PWM_PWMSTOP
    clrf I2C_I2CINIT__RESULT, c
    clrf SSP1CON1, c
    movlw 0x13
    call I2C_PINSETUP
    movlw 0x14
    call I2C_PINSETUP
    movlw 0x13
    movlb 14
    movwf SSP1CLKPPS, b
    movlw 0x14
    movwf SSP1DATPPS, b
    movlw 0x13
    movwf I2C_SETPPS__PIN, c
    movlw 0x0F
    movwf I2C_SETPPS__CODE, c
    call I2C_SETPPS
    movlw 0x14
    movwf I2C_SETPPS__PIN, c
    movlw 0x10
    movwf I2C_SETPPS__CODE, c
    call I2C_SETPPS
    movlw 0x9F
    movwf SSP1ADD, c
    clrf SSP1CON2, c
    clrf SSP1CON3, c
    movlw 0x80
    movwf SSP1STAT, c
    movlb 14
    bcf PIR3, 0, b
    bcf PIR3, 1, b
    movlw 0x28
    movwf SSP1CON1, c
    movlw 0x01
    movwf I2C_READY, c
    clrf I2C_LASTSTATUS, c
    movwf I2C_I2CINIT__RESULT, c
    movwf T_R, c
    call I2C_I2CSTART
    movf I2C_I2CSTART__RESULT, w, c
    movwf T_R, c
    movlw 0xA0
    call I2C_I2CSEND
    movf I2C_I2CSEND__RESULT, w, c
    movwf T_R, c
    movlw 0x01
    call I2C_I2CRECEIVE
    movf I2C_I2CRECEIVE__RESULT, w, c
    movwf T_R, c
    call I2C_I2CRESTART
    movf I2C_I2CRESTART__RESULT, w, c
    movwf T_R, c
    call I2C_I2CSTOP
    movf I2C_I2CSTOP__RESULT, w, c
    movwf T_R, c
    call I2C_I2CSTATUS
    movf I2C_I2CSTATUS__RESULT, w, c
    movwf T_R, c
    call I2C_I2CSTART
    movf I2C_I2CSTART__RESULT, w, c
    movwf I2C_I2CPROBE__RESULT, c
    bnz _L986
    movlw 0xA0
    call I2C_I2CSEND
    movf I2C_I2CSEND__RESULT, w, c
    movwf I2C_I2CPROBE__RESULT, c
_L986:
    call I2C_I2CSTOP
    movff I2C_I2CPROBE__RESULT, I2C_LASTSTATUS
    movf I2C_I2CPROBE__RESULT, w, c
    movlw 0
    btfsc STATUS, 2, c
    movlw 1
    movwf I2C_I2CPING__RESULT, c
    movf I2C_I2CPING__RESULT, w, c
    bz _L3
    call I2C_OPEN
    movf I2C_OPEN__RESULT, w, c
    movwf I2C_I2CWRITEREG__RESULT, c
    bnz _L199
    movlw 0x02
    call I2C_I2CSEND
    movf I2C_I2CSEND__RESULT, w, c
    movwf I2C_I2CWRITEREG__RESULT, c
_L199:
    call I2C_I2CSTOP
    movf I2C_I2CWRITEREG__RESULT, f, c
    bnz _L201
    movff I2C_I2CSTOP__RESULT, I2C_I2CWRITEREG__RESULT
_L201:
    movff I2C_I2CWRITEREG__RESULT, I2C_LASTSTATUS
    movf I2C_I2CWRITEREG__RESULT, w, c
    movwf T_R, c
    clrf I2C_I2CREADREG__RESULT, c
    call I2C_OPEN
    movf I2C_OPEN__RESULT, w, c
    movwf I2C_I2CREADREG__E, c
    bnz _L203
    call I2C_I2CRESTART
    movf I2C_I2CRESTART__RESULT, w, c
    movwf I2C_I2CREADREG__E, c
_L203:
    movf I2C_I2CREADREG__E, f, c
    bnz _L205
    movlw 0xA1
    call I2C_I2CSEND
    movf I2C_I2CSEND__RESULT, w, c
    movwf I2C_I2CREADREG__E, c
_L205:
    movf I2C_I2CREADREG__E, f, c
    bnz _L207
    movlw 0x00
    call I2C_I2CRECEIVE
    movf I2C_I2CRECEIVE__RESULT, w, c
    movwf I2C_I2CREADREG__RESULT, c
    movff I2C_LASTSTATUS, I2C_I2CREADREG__E
_L207:
    call I2C_I2CSTOP
    movf I2C_I2CREADREG__E, f, c
    bnz _L209
    movff I2C_I2CSTOP__RESULT, I2C_I2CREADREG__E
_L209:
    movf I2C_I2CREADREG__E, f, c
    bz _L211
    clrf I2C_I2CREADREG__RESULT, c
_L211:
    movff I2C_I2CREADREG__E, I2C_LASTSTATUS
    movf I2C_I2CREADREG__RESULT, w, c
    movwf T_R, c
_L3:
    clrf SSP1CON1, c
    movlw 0x13
    movwf I2C_SETPPS__PIN, c
    clrf I2C_SETPPS__CODE, c
    call I2C_SETPPS
    movlw 0x14
    movwf I2C_SETPPS__PIN, c
    clrf I2C_SETPPS__CODE, c
    call I2C_SETPPS
    clrf I2C_READY, c
    clrf SPI_SPIINIT__RESULT, c
    clrf SSP1CON1, c
    movlw 0x13
    movwf SPI_PINSETUP__PIN, c
    clrf SPI_PINSETUP__ASINPUT, c
    call SPI_PINSETUP
    movlw 0x15
    movwf SPI_PINSETUP__PIN, c
    movlw 0x01
    movwf SPI_PINSETUP__ASINPUT, c
    call SPI_PINSETUP
    movlw 0x13
    movlb 14
    movwf SSP1CLKPPS, b
    movlw 0x15
    movwf SSP1DATPPS, b
    movlw 0x13
    movwf SPI_SETPPS__PIN, c
    movlw 0x0F
    movwf SPI_SETPPS__CODE, c
    call SPI_SETPPS
    movlw 0x14
    movwf SPI_PINSETUP__PIN, c
    clrf SPI_PINSETUP__ASINPUT, c
    call SPI_PINSETUP
    movlw 0x14
    movwf SPI_SETPPS__PIN, c
    movlw 0x10
    movwf SPI_SETPPS__CODE, c
    call SPI_SETPPS
    movlw 0x0F
    movwf SSP1ADD, c
    clrf SSP1STAT, c
    movlw 0x40
    movwf SSP1STAT, c
    clrf SSP1CON3, c
    movlw 0x0A
    movwf SSP1CON1, c
    movlw 0x2A
    movwf SSP1CON1, c
    movlw 0x01
    movlb 0
    movwf SPI_READY, b
    clrf SPI_LASTSTATUS, c
    movwf SPI_SPIINIT__RESULT, c
    movwf T_R, c
    call SPI_SPITRANSFER
    movf SPI_SPITRANSFER__RESULT, w, c
    movwf T_R, c
    movlw 0x02
    call SPI_SPIWRITE
    call SPI_SPIREAD
    movf SPI_SPIREAD__RESULT, w, c
    movwf T_R, c
    call SPI_SPISTATUS
    movf SPI_SPISTATUS__RESULT, w, c
    movwf T_R, c
    clrf SSP1CON1, c
    movlw 0x13
    call SPI_PPSOFF
    movlw 0x14
    call SPI_PPSOFF
    movlb 0
    clrf SPI_READY, b
    movff PCON0, SYSTEM_SYSRESETCAUSE__F
    clrf SYSTEM_SYSRESETCAUSE__RESULT, c
    btfsc SYSTEM_SYSRESETCAUSE__F, 1, c
    bra _L225
    movlw 0x01
    movwf SYSTEM_SYSRESETCAUSE__RESULT, c
    bra _L224
_L225:
    btfsc SYSTEM_SYSRESETCAUSE__F, 0, c
    bra _L227
    movlw 0x02
    movwf SYSTEM_SYSRESETCAUSE__RESULT, c
    bra _L224
_L227:
    btfss SYSTEM_SYSRESETCAUSE__F, 7, c
    bra _L229
    movlw 0x07
    movwf SYSTEM_SYSRESETCAUSE__RESULT, c
    bra _L224
_L229:
    btfss SYSTEM_SYSRESETCAUSE__F, 6, c
    bra _L231
    movlw 0x08
    movwf SYSTEM_SYSRESETCAUSE__RESULT, c
    bra _L224
_L231:
    btfsc SYSTEM_SYSRESETCAUSE__F, 5, c
    bra _L233
    movlw 0x05
    movwf SYSTEM_SYSRESETCAUSE__RESULT, c
    bra _L224
_L233:
    btfsc SYSTEM_SYSRESETCAUSE__F, 4, c
    bra _L235
    movlw 0x04
    movwf SYSTEM_SYSRESETCAUSE__RESULT, c
    bra _L224
_L235:
    btfsc SYSTEM_SYSRESETCAUSE__F, 3, c
    bra _L237
    movlw 0x03
    movwf SYSTEM_SYSRESETCAUSE__RESULT, c
    bra _L224
_L237:
    btfsc SYSTEM_SYSRESETCAUSE__F, 2, c
    bra _L239
_L239:
_L224:
    movff PCON0, SYSTEM_SYSRESETFLAGS__RESULT
    movf SYSTEM_SYSRESETFLAGS__RESULT, w, c
    movwf T_R, c
    movlw 0x3F
    movwf PCON0, c
    call SYSTEM_SYSCLOCKHZ
    movff SYSTEM_SYSCLOCKFROM__RESULT, __A0
    movff SYSTEM_SYSCLOCKFROM__RESULT+1, __A1
    movff SYSTEM_SYSCLOCKFROM__RESULT+2, __A2
    movff SYSTEM_SYSCLOCKFROM__RESULT+3, __A3
    movf SYSTEM_SYSCLOCKFROM__RESULT, w, c
    bnz _L5
    movf __A0+1, w, c
    xorlw 0x90
    bnz _L5
    movf __A0+2, w, c
    xorlw 0xD0
    bnz _L5
    movf __A0+3, w, c
    xorlw 0x03
    bnz _L5
    movlw 1
    call SYSTEM_SYSCLOCKHZ
    movff SYSTEM_SYSCLOCKFROM__RESULT, __A0
    movff SYSTEM_SYSCLOCKFROM__RESULT+1, __A1
    movff SYSTEM_SYSCLOCKFROM__RESULT+2, __A2
    movff SYSTEM_SYSCLOCKFROM__RESULT+3, __A3
    movlw 0xE8
    movwf __B0, c
    movlw 0x03
    movwf __B0+1, c
    clrf __B0+2, c
    clrf __B0+3, c
    call __div4
    movff __A0, T_X
    movff __A1, T_X+1
_L5:
    clrf LCD_LCDINIT__RESULT, c
    movlb 0
    clrf LCD_READY, b
    movlw 0x10
    movwf LCD_PINS, c
    movlw 0x11
    movwf LCD_PINS+1, c
    movlw 0x12
    movwf LCD_PINS+2, c
    movlw 0x13
    movwf LCD_PINS+3, c
    movlw 0x14
    movwf LCD_PINS+4, c
    movlw 0x15
    movwf LCD_PINS+5, c
    clrf LCD_LCDINIT__I, c
_L245:
    movf LCD_LCDINIT__I, w, c
    lfsr 0, LCD_PINS
    movf PLUSW0, w, c
    call PINIO_PINOK
    movf PINIO_PINOK__RESULT, w, c
    bnz __skip1
    bra _Lr48
__skip1:
    clrf LCD_LCDINIT__J, c
    bra _L251
_L250:
    movf LCD_LCDINIT__J, w, c
    lfsr 0, LCD_PINS
    movf PLUSW0, w, c
    movwf LCD_LCDINIT__TMP, c
    movf LCD_LCDINIT__I, w, c
    movf PLUSW0, w, c
    xorwf LCD_LCDINIT__TMP, w, c
    bnz __skip2
    bra _Lr48
__skip2:
    incf LCD_LCDINIT__J, f, c
_L251:
    movf LCD_LCDINIT__I, w, c
    subwf LCD_LCDINIT__J, w, c
    bnc _L250
    movf LCD_LCDINIT__I, w, c
    incf LCD_LCDINIT__I, f, c
    xorlw 0x05
    bnz _L245
    movlw 0x01
    movlb 0
    movwf LCD_TWOLINES, b
    clrf LCD_LCDINIT__I, c
_L255:
    movf LCD_LCDINIT__I, w, c
    lfsr 0, LCD_PINS
    movf PLUSW0, w, c
    movwf PINIO_PINSET__PIN, c
    clrf PINIO_PINSET__LEVEL, c
    call PINIO_PINSET
    movf LCD_LCDINIT__I, w, c
    lfsr 0, LCD_PINS
    movf PLUSW0, w, c
    call PINIO_PINOUTPUT
    movf LCD_LCDINIT__I, w, c
    incf LCD_LCDINIT__I, f, c
    xorlw 0x05
    bnz _L255
    clrf __D0, c
_L258:
    clrf __D1, c
_L259:
    bra _L260
_L260:
    bra _L261
_L261:
    bra _L262
_L262:
    bra _L263
_L263:
    nop
    decfsz __D1, f, c
    bra _L259
    movlw 16
    movwf __D1, c
_L264:
    decfsz __D1, f, c
    bra _L264
    nop
    decfsz __D0, f, c
    bra _L258
    movlw 0x03
    call LCD_NIBBLE
    clrf __D0, c
_L265:
    movlw 102
    movwf __D1, c
_L266:
    decfsz __D1, f, c
    bra _L266
    bra _L267
_L267:
    decfsz __D0, f, c
    bra _L265
    movlw 42
    movwf __D0, c
_L268:
    decfsz __D0, f, c
    bra _L268
    nop
    movlw 0x03
    call LCD_NIBBLE
    clrf __D0, c
_L269:
    bra _L270
_L270:
    bra _L271
_L271:
    bra _L272
_L272:
    decfsz __D0, f, c
    bra _L269
    movlw 31
    movwf __D0, c
_L273:
    decfsz __D0, f, c
    bra _L273
    bra _L274
_L274:
    movlw 0x03
    call LCD_NIBBLE
    clrf __D0, c
_L275:
    bra _L276
_L276:
    bra _L277
_L277:
    bra _L278
_L278:
    decfsz __D0, f, c
    bra _L275
    movlw 31
    movwf __D0, c
_L279:
    decfsz __D0, f, c
    bra _L279
    bra _L280
_L280:
    movlw 0x02
    call LCD_NIBBLE
    clrf __D0, c
_L281:
    bra _L282
_L282:
    bra _L283
_L283:
    bra _L284
_L284:
    decfsz __D0, f, c
    bra _L281
    movlw 31
    movwf __D0, c
_L285:
    decfsz __D0, f, c
    bra _L285
    bra _L286
_L286:
    movlb 0
    movf LCD_TWOLINES, f, b
    bz _L288
    movlw 0x28
    movwf LCD_SEND__B, c
    clrf LCD_SEND__RS, c
    call LCD_SEND
    bra _L287
_L288:
    movlw 0x20
    movwf LCD_SEND__B, c
    clrf LCD_SEND__RS, c
    call LCD_SEND
_L287:
    movlw 0x08
    movwf LCD_SEND__B, c
    clrf LCD_SEND__RS, c
    call LCD_SEND
    movlw 0x01
    movwf LCD_SEND__B, c
    clrf LCD_SEND__RS, c
    call LCD_SEND
    clrf __D0, c
_L289:
    movlw 40
    movwf __D1, c
_L290:
    decfsz __D1, f, c
    bra _L290
    nop
    decfsz __D0, f, c
    bra _L289
    movlw 0x06
    movwf LCD_SEND__B, c
    clrf LCD_SEND__RS, c
    call LCD_SEND
    movlw 0x0C
    movwf LCD_SEND__B, c
    clrf LCD_SEND__RS, c
    call LCD_SEND
    movlw 0x01
    movlb 0
    movwf LCD_READY, b
    movwf LCD_LCDINIT__RESULT, c
_Lr48:
    movf LCD_LCDINIT__RESULT, w, c
    movwf T_R, c
    movlw 0x01
    call LCD_LCDCOMMAND
    movlw 0x02
    call LCD_LCDCOMMAND
    movlw 0x0C
    call LCD_LCDCOMMAND
    movlw 0x14
    call LCD_LCDCOMMAND
    movlw 0x00
    call LCD_LCDSETADDRESS
    clrf LCD_LCDGOTO__COL, c
    movlb 0
    movf LCD_TWOLINES, f, b
    bz _L292
    movlw 0x28
    subwf LCD_LCDGOTO__COL, w, c
    bc _Lr53
    movlw 0x40
    addwf LCD_LCDGOTO__COL, f, c
    bra _L291
_L292:
    movlw 0x50
    subwf LCD_LCDGOTO__COL, w, c
    bc _Lr53
    bra _Lr53
_L291:
    movf LCD_LCDGOTO__COL, w, c
    call LCD_LCDSETADDRESS
_Lr53:
    clrf LCD_LCDWRITE__I, c
    bra _L301
_L300:
    movf LCD_LCDWRITE__I, w, c
    addlw low(__SLIT5)
    movwf TBLPTRL, c
    movlw high(__SLIT5)
    movwf TBLPTRH, c
    movlw 0
    addwfc TBLPTRH, f, c
    clrf TBLPTRU, c
    tblrd*+
    movf TABLAT, w, c
    call LCD_LCDWRITECHAR
    incf LCD_LCDWRITE__I, f, c
_L301:
    movf LCD_LCDWRITE__I, w, c
    addlw low(__SLIT5)
    movwf TBLPTRL, c
    movlw high(__SLIT5)
    movwf TBLPTRH, c
    movlw 0
    addwfc TBLPTRH, f, c
    clrf TBLPTRU, c
    tblrd*+
    movf TABLAT, w, c
    bnz _L300
    movlw 0x41
    call LCD_LCDWRITECHAR
    movlw 0x7B
    movwf LCD_LCDWRITEWORD__V, c
    clrf LCD_LCDWRITEWORD__V+1, c
    clrf LCD_LCDWRITEWORD__STARTED, c
    movlw 0x10
    movwf LCD_LCDWRITEWORD__D, c
    movlw 0x27
    movwf LCD_LCDWRITEWORD__D+1, c
    bra _L306
_L305:
    clrf LCD_LCDWRITEWORD__DIGIT, c
    bra _L309
_L308:
    movf LCD_LCDWRITEWORD__D, w, c
    subwf LCD_LCDWRITEWORD__V, f, c
    movf LCD_LCDWRITEWORD__D+1, w, c
    subwfb LCD_LCDWRITEWORD__V+1, f, c
    incf LCD_LCDWRITEWORD__DIGIT, f, c
_L309:
    movf LCD_LCDWRITEWORD__D, w, c
    subwf LCD_LCDWRITEWORD__V, w, c
    movf LCD_LCDWRITEWORD__D+1, w, c
    subwfb LCD_LCDWRITEWORD__V+1, w, c
    bc _L308
    movf LCD_LCDWRITEWORD__DIGIT, f, c
    bnz _L313
    movf LCD_LCDWRITEWORD__STARTED, f, c
    bnz _L313
    decf LCD_LCDWRITEWORD__D, w, c
    bnz _L312
    movf LCD_LCDWRITEWORD__D+1, w, c
    bnz _L312
_L313:
    movf LCD_LCDWRITEWORD__DIGIT, w, c
    addlw 0x30
    call LCD_LCDWRITECHAR
    movlw 0x01
    movwf LCD_LCDWRITEWORD__STARTED, c
_L312:
    movf LCD_LCDWRITEWORD__D, w, c
    xorlw 0x10
    bnz _L316
    movf LCD_LCDWRITEWORD__D+1, w, c
    xorlw 0x27
    bnz _L316
    movlw 0xE8
    movwf LCD_LCDWRITEWORD__D, c
    movlw 0x03
    movwf LCD_LCDWRITEWORD__D+1, c
    bra _L315
_L316:
    movf LCD_LCDWRITEWORD__D, w, c
    xorlw 0xE8
    bnz _L318
    movf LCD_LCDWRITEWORD__D+1, w, c
    xorlw 0x03
    bnz _L318
    movlw 0x64
    movwf LCD_LCDWRITEWORD__D, c
    clrf LCD_LCDWRITEWORD__D+1, c
    bra _L315
_L318:
    movf LCD_LCDWRITEWORD__D, w, c
    xorlw 0x64
    bnz _L320
    movf LCD_LCDWRITEWORD__D+1, w, c
    bnz _L320
    movlw 0x0A
    movwf LCD_LCDWRITEWORD__D, c
    clrf LCD_LCDWRITEWORD__D+1, c
    bra _L315
_L320:
    movf LCD_LCDWRITEWORD__D, w, c
    xorlw 0x0A
    bnz _L322
    movf LCD_LCDWRITEWORD__D+1, w, c
    bnz _L322
    movlw 0x01
    movwf LCD_LCDWRITEWORD__D, c
    clrf LCD_LCDWRITEWORD__D+1, c
    bra _L315
_L322:
    clrf LCD_LCDWRITEWORD__D, c
    clrf LCD_LCDWRITEWORD__D+1, c
_L315:
_L306:
    movf LCD_LCDWRITEWORD__D, w, c
    iorwf LCD_LCDWRITEWORD__D+1, w, c
    bnz _L305
    movlw 0x41
    call LCD_LCDWRITECHAR
    movlw 0x42
    call LCD_LCDWRITECHAR
    movlw 0x40
    call LCD_LCDCOMMAND
    movlw 0x1F
    movwf LCD_SEND__B, c
    movlw 0x01
    movwf LCD_SEND__RS, c
    call LCD_SEND
    movlw 0x01
    call LCD_LCDCOMMAND
    clrf OLED_OLEDINITI2C__RESULT, c
    clrf OLED_ERR, c
    movlw 0x3C
    movlb 0
    movwf OLED_ADDR7, b
    movlw 0x01
    movwf OLED_MODE, c
    movlw 0xFF
    call OLED_RESET
    call OLED_SETUP
    movf OLED_ERR, f, c
    bnz _L333
    movlw 0x01
    movwf OLED_OLEDINITI2C__RESULT, c
_L333:
    movf OLED_OLEDINITI2C__RESULT, w, c
    movwf T_R, c
    clrf OLED_OLEDINITSPI__RESULT, c
    clrf OLED_ERR, c
    movlw 0x10
    movlb 0
    movwf OLED_PDC, b
    movlw 0x11
    movwf OLED_PCS, c
    movlw 0x02
    movwf OLED_MODE, c
    movlw 0x10
    call PINIO_PINOUTPUT
    movlw 0x11
    movwf PINIO_PINSET__PIN, c
    movlw 0x01
    movwf PINIO_PINSET__LEVEL, c
    call PINIO_PINSET
    movlw 0x11
    call PINIO_PINOUTPUT
    movlw 0x12
    call OLED_RESET
    call OLED_SETUP
    movlw 0x01
    movwf OLED_OLEDINITSPI__RESULT, c
    movf OLED_ERR, w, c
    movwf T_R, c
    clrf OLED_ERR, c
    movlw 0x01
    movwf OLED_CMD__N, c
    movlw 0xAF
    movwf OLED_CMD__C, c
    clrf OLED_CMD__A, c
    clrf OLED_CMD__B, c
    call OLED_CMD
    movlw 0x02
    movwf OLED_CMD__N, c
    movlw 0x81
    movwf OLED_CMD__C, c
    movlw 0x64
    movwf OLED_CMD__A, c
    clrf OLED_CMD__B, c
    call OLED_CMD
    movlw 0x01
    movwf OLED_CMD__N, c
    movlw 0xA6
    movwf OLED_CMD__C, c
    clrf OLED_CMD__A, c
    clrf OLED_CMD__B, c
    call OLED_CMD
    movlw 0x01
    movwf OLED_CMD__N, c
    movlw 0xA4
    movwf OLED_CMD__C, c
    clrf OLED_CMD__A, c
    clrf OLED_CMD__B, c
    call OLED_CMD
    movlw 0x01
    movwf OLED_CMD__N, c
    movlw 0xA0
    movwf OLED_CMD__C, c
    clrf OLED_CMD__A, c
    clrf OLED_CMD__B, c
    call OLED_CMD
    movlw 0x01
    movwf OLED_CMD__N, c
    movlw 0xC0
    movwf OLED_CMD__C, c
    clrf OLED_CMD__A, c
    clrf OLED_CMD__B, c
    call OLED_CMD
    clrf OLED_OLEDGOTO__PAGE, c
    call OLED_OLEDGOTO
    movlw 0x01
    movwf OLED_OLEDGOTO__PAGE, c
    call OLED_OLEDGOTO
    movf OLED_MODE, f, c
    bz _Lr68
    movlw 0x01
    call OLED_BEGIN
    movlw 0x01
    call OLED_PUT
    call OLED_FINISH
_Lr68:
    call OLED_OLEDFILL
    call OLED_OLEDFILL
    movlw 0x41
    call OLED_OLEDWRITECHAR
    clrf OLED_OLEDWRITE__I, c
    bra _L360
_L359:
    movf OLED_OLEDWRITE__I, w, c
    addlw low(__SLIT6)
    movwf TBLPTRL, c
    movlw high(__SLIT6)
    movwf TBLPTRH, c
    movlw 0
    addwfc TBLPTRH, f, c
    clrf TBLPTRU, c
    tblrd*+
    movf TABLAT, w, c
    call OLED_OLEDWRITECHAR
    incf OLED_OLEDWRITE__I, f, c
_L360:
    movf OLED_OLEDWRITE__I, w, c
    addlw low(__SLIT6)
    movwf TBLPTRL, c
    movlw high(__SLIT6)
    movwf TBLPTRH, c
    movlw 0
    addwfc TBLPTRH, f, c
    clrf TBLPTRU, c
    tblrd*+
    movf TABLAT, w, c
    bnz _L359
    movlw 0x7B
    movwf OLED_OLEDWRITEWORD__V, c
    clrf OLED_OLEDWRITEWORD__V+1, c
    clrf OLED_OLEDWRITEWORD__STARTED, c
    movlw 0x10
    movwf OLED_OLEDWRITEWORD__D, c
    movlw 0x27
    movwf OLED_OLEDWRITEWORD__D+1, c
    bra _L363
_L362:
    clrf OLED_OLEDWRITEWORD__DIGIT, c
    bra _L366
_L365:
    movf OLED_OLEDWRITEWORD__D, w, c
    subwf OLED_OLEDWRITEWORD__V, f, c
    movf OLED_OLEDWRITEWORD__D+1, w, c
    subwfb OLED_OLEDWRITEWORD__V+1, f, c
    incf OLED_OLEDWRITEWORD__DIGIT, f, c
_L366:
    movf OLED_OLEDWRITEWORD__D, w, c
    subwf OLED_OLEDWRITEWORD__V, w, c
    movf OLED_OLEDWRITEWORD__D+1, w, c
    subwfb OLED_OLEDWRITEWORD__V+1, w, c
    bc _L365
    movf OLED_OLEDWRITEWORD__DIGIT, f, c
    bnz _L370
    movf OLED_OLEDWRITEWORD__STARTED, f, c
    bnz _L370
    decf OLED_OLEDWRITEWORD__D, w, c
    bnz _L369
    movf OLED_OLEDWRITEWORD__D+1, w, c
    bnz _L369
_L370:
    movf OLED_OLEDWRITEWORD__DIGIT, w, c
    addlw 0x30
    call OLED_OLEDWRITECHAR
    movlw 0x01
    movwf OLED_OLEDWRITEWORD__STARTED, c
_L369:
    movf OLED_OLEDWRITEWORD__D, w, c
    xorlw 0x10
    bnz _L373
    movf OLED_OLEDWRITEWORD__D+1, w, c
    xorlw 0x27
    bnz _L373
    movlw 0xE8
    movwf OLED_OLEDWRITEWORD__D, c
    movlw 0x03
    movwf OLED_OLEDWRITEWORD__D+1, c
    bra _L372
_L373:
    movf OLED_OLEDWRITEWORD__D, w, c
    xorlw 0xE8
    bnz _L375
    movf OLED_OLEDWRITEWORD__D+1, w, c
    xorlw 0x03
    bnz _L375
    movlw 0x64
    movwf OLED_OLEDWRITEWORD__D, c
    clrf OLED_OLEDWRITEWORD__D+1, c
    bra _L372
_L375:
    movf OLED_OLEDWRITEWORD__D, w, c
    xorlw 0x64
    bnz _L377
    movf OLED_OLEDWRITEWORD__D+1, w, c
    bnz _L377
    movlw 0x0A
    movwf OLED_OLEDWRITEWORD__D, c
    clrf OLED_OLEDWRITEWORD__D+1, c
    bra _L372
_L377:
    movf OLED_OLEDWRITEWORD__D, w, c
    xorlw 0x0A
    bnz _L379
    movf OLED_OLEDWRITEWORD__D+1, w, c
    bnz _L379
    movlw 0x01
    movwf OLED_OLEDWRITEWORD__D, c
    clrf OLED_OLEDWRITEWORD__D+1, c
    bra _L372
_L379:
    clrf OLED_OLEDWRITEWORD__D, c
    clrf OLED_OLEDWRITEWORD__D+1, c
_L372:
_L363:
    movf OLED_OLEDWRITEWORD__D, w, c
    iorwf OLED_OLEDWRITEWORD__D+1, w, c
    bnz _L362
    movlw 0x41
    call OLED_OLEDWRITECHAR
    movlw 0x42
    call OLED_OLEDWRITECHAR
    clrf OLED_FONTBYTE__IDX, c
    clrf OLED_FONTBYTE__IDX+1, c
    call OLED_FONTBYTE
    movf OLED_FONTBYTE__RESULT, w, c
    movwf T_R, c
    clrf __D0, c
_L381:
    movlw 102
    movwf __D1, c
_L382:
    decfsz __D1, f, c
    bra _L382
    bra _L383
_L383:
    decfsz __D0, f, c
    bra _L381
    movlw 42
    movwf __D0, c
_L384:
    decfsz __D0, f, c
    bra _L384
    nop
    call AHT30_AHT30START
    movf AHT30_AHT30START__RESULT, w, c
    movwf T_R, c
    movlw low(T_TI)
    movwf AHT30_AHT30FETCH__TEMP, c
    movlw high(T_TI)
    movwf AHT30_AHT30FETCH__TEMP+1, c
    movlw low(T_RHW)
    movwf AHT30_AHT30FETCH__RH, c
    movlw high(T_RHW)
    movwf AHT30_AHT30FETCH__RH+1, c
    call AHT30_AHT30FETCH
    movf AHT30_AHT30FETCH__RESULT, w, c
    movwf T_R, c
    movlw low(T_TI)
    movwf AHT30_AHT30MEASURE__TEMP, b
    movlw high(T_TI)
    movwf AHT30_AHT30MEASURE__TEMP+1, b
    movlw low(T_RHW)
    movwf AHT30_AHT30MEASURE__RH, b
    movlw high(T_RHW)
    movwf AHT30_AHT30MEASURE__RH+1, b
    call AHT30_AHT30START
    movf AHT30_AHT30START__RESULT, w, c
    movwf AHT30_AHT30MEASURE__RESULT, c
    bnz _L414
    clrf __D0, c
_L415:
    clrf __D1, c
_L416:
    movlw 5
    movwf __D2, c
_L417:
    decfsz __D2, f, c
    bra _L417
    decfsz __D1, f, c
    bra _L416
    movlw 44
    movwf __D1, c
_L418:
    decfsz __D1, f, c
    bra _L418
    decfsz __D0, f, c
    bra _L415
    movff AHT30_AHT30MEASURE__TEMP, FSR0L
    movff AHT30_AHT30MEASURE__TEMP+1, FSR0H
    movff AHT30_AHT30MEASURE__TEMP, AHT30_AHT30FETCH__TEMP
    movff AHT30_AHT30MEASURE__TEMP+1, AHT30_AHT30FETCH__TEMP+1
    movff AHT30_AHT30MEASURE__RH, FSR0L
    movff AHT30_AHT30MEASURE__RH+1, FSR0H
    movff AHT30_AHT30MEASURE__RH, AHT30_AHT30FETCH__RH
    movff AHT30_AHT30MEASURE__RH+1, AHT30_AHT30FETCH__RH+1
    call AHT30_AHT30FETCH
    movf AHT30_AHT30FETCH__RESULT, w, c
    movwf AHT30_AHT30MEASURE__RESULT, c
_L414:
    movf AHT30_AHT30MEASURE__RESULT, w, c
    movwf T_R, c
    movlw 0x05
    movwf RTCC_RTCCSET__RESULT, c
    movlw 0x1F
    movlb 0
    movwf RTCC_RTCCSET__TMP, b
    subwf RTCC_RTCCSET__TMP, w, b
    bc __skip3
    bra _Lr75
__skip3:
    movlw 0x03
    movwf RTCC_READBLOCK__REG, c
    movlw 0x05
    movwf RTCC_READBLOCK__N, c
    call RTCC_READBLOCK
    movf RTCC_READBLOCK__RESULT, w, c
    movwf RTCC_RTCCSET__RESULT, c
    bz __skip4
    bra _Lr75
__skip4:
    movf I2C_I2CBUF, w, c
    andlw 0x08
    movwf RTCC_RTCCSET__VB, c
    movff I2C_I2CBUF+4, RTCC_RTCCSET__CTL
    movlw 0x07
    movwf RTCC_WRREG__REG, c
    movf RTCC_RTCCSET__CTL, w, c
    andlw 0xF7
    movwf RTCC_WRREG__V, c
    call RTCC_WRREG
    movf RTCC_WRREG__RESULT, w, c
    movwf RTCC_RTCCSET__RESULT, c
    bnz _L425
    clrf RTCC_WRREG__REG, c
    clrf RTCC_WRREG__V, c
    call RTCC_WRREG
    movf RTCC_WRREG__RESULT, w, c
    movwf RTCC_RTCCSET__RESULT, c
_L425:
    clrf RTCC_RTCCSET__N, c
    bra _L427
_L426:
    movlw 0x03
    call RTCC_RDREG
    movf RTCC_RDREG__RESULT, w, c
    movwf RTCC_RTCCSET__RESULT, c
    bnz _L430
    btfsc I2C_I2CBUF, 5, c
    bra _L432
    bra _L428
_L432:
    clrf __D0, c
_L434:
    movlw 19
    movwf __D1, c
_L435:
    decfsz __D1, f, c
    bra _L435
    nop
    decfsz __D0, f, c
    bra _L434
    movlw 42
    movwf __D0, c
_L436:
    decfsz __D0, f, c
    bra _L436
    nop
_L430:
    incf RTCC_RTCCSET__N, f, c
_L427:
    movf RTCC_RTCCSET__RESULT, f, c
    bnz _L437
    movlw 0x64
    subwf RTCC_RTCCSET__N, w, c
    bnc _L426
_L437:
_L428:
    movf RTCC_RTCCSET__RESULT, f, c
    bnz _Lr75
    btfss I2C_I2CBUF, 5, c
    bra _L441
    movlw 0x06
    movwf RTCC_RTCCSET__RESULT, c
    bra _Lr75
_L441:
    movlw 0x0F
    call RTCC_TOBCD
    movf RTCC_TOBCD__RESULT, w, c
    movwf I2C_I2CBUF, c
    movlw 0x1E
    call RTCC_TOBCD
    movf RTCC_TOBCD__RESULT, w, c
    movwf I2C_I2CBUF+1, c
    movlw 0x0E
    call RTCC_TOBCD
    movwf I2C_I2CBUF+2, c
    movf RTCC_RTCCSET__VB, w, c
    iorlw 0x05
    movwf I2C_I2CBUF+3, c
    movlw 0x1F
    call RTCC_TOBCD
    movf RTCC_TOBCD__RESULT, w, c
    movwf I2C_I2CBUF+4, c
    movlw 0x0A
    call RTCC_TOBCD
    movf RTCC_TOBCD__RESULT, w, c
    movwf I2C_I2CBUF+5, c
    movlw 0x18
    call RTCC_TOBCD
    movf RTCC_TOBCD__RESULT, w, c
    movwf I2C_I2CBUF+6, c
    movlw 0xDE
    movwf RTCC_WRITEBLOCK__CTL, c
    clrf RTCC_WRITEBLOCK__REG, c
    movlw 0x07
    movwf RTCC_WRITEBLOCK__N, c
    call RTCC_WRITEBLOCK
    movf RTCC_WRITEBLOCK__RESULT, w, c
    movwf RTCC_RTCCSET__RESULT, c
    bnz _L444
    movlw 0x1F
    call RTCC_TOBCD
    movf RTCC_TOBCD__RESULT, w, c
    movwf RTCC_WRREG__V, c
    movlw 0x04
    movwf RTCC_WRREG__REG, c
    call RTCC_WRREG
    movf RTCC_WRREG__RESULT, w, c
    movwf RTCC_RTCCSET__RESULT, c
_L444:
    movf RTCC_RTCCSET__RESULT, f, c
    bnz _L446
    btfss RTCC_RTCCSET__CTL, 3, c
    bra _L448
    movlw 0x07
    movwf RTCC_WRREG__REG, c
    movff RTCC_RTCCSET__CTL, RTCC_WRREG__V
    call RTCC_WRREG
    movf RTCC_WRREG__RESULT, w, c
    movwf RTCC_RTCCSET__RESULT, c
    bra _L447
_L448:
    movlw 0x0F
    call RTCC_TOBCD
    iorlw 0x80
    movwf RTCC_WRREG__V, c
    clrf RTCC_WRREG__REG, c
    call RTCC_WRREG
    movf RTCC_WRREG__RESULT, w, c
    movwf RTCC_RTCCSET__RESULT, c
_L447:
_L446:
    clrf RTCC_RTCCSET__N, c
    bra _L451
_L450:
    movlw 0x03
    call RTCC_RDREG
    movf RTCC_RDREG__RESULT, w, c
    movwf RTCC_RTCCSET__RESULT, c
    bnz _L454
    btfss I2C_I2CBUF, 5, c
    bra _L456
    bra _L452
_L456:
    clrf __D0, c
_L458:
    movlw 207
    movwf __D1, c
_L459:
    decfsz __D1, f, c
    bra _L459
    decfsz __D0, f, c
    bra _L458
_L454:
    incf RTCC_RTCCSET__N, f, c
_L451:
    movf RTCC_RTCCSET__RESULT, f, c
    bnz _L460
    movlw 0xC8
    subwf RTCC_RTCCSET__N, w, c
    bnc _L450
_L460:
_L452:
    movf RTCC_RTCCSET__RESULT, f, c
    bnz _L462
    btfsc I2C_I2CBUF, 5, c
    bra _L464
    movlw 0x06
    movwf RTCC_RTCCSET__RESULT, c
    bra _L463
_L464:
    movlw 0x03
    movwf RTCC_WRREG__REG, c
    movf RTCC_RTCCSET__VB, w, c
    iorlw 0x05
    movwf RTCC_WRREG__V, c
    call RTCC_WRREG
    movf RTCC_WRREG__RESULT, w, c
    movwf RTCC_RTCCSET__RESULT, c
_L463:
_L462:
_Lr75:
    movf RTCC_RTCCSET__RESULT, w, c
    movwf T_R, c
    clrf RTCC_READBLOCK__REG, c
    movlw 0x07
    movwf RTCC_READBLOCK__N, c
    call RTCC_READBLOCK
    movf RTCC_READBLOCK__RESULT, w, c
    bnz _L467
    clrf RTCC_RTCCREAD__I, c
    bra _L469
_L468:
    movf RTCC_RTCCREAD__I, w, c
    lfsr 0, I2C_I2CBUF
    movf PLUSW0, w, c
    movwf RTCC_RTCCREAD__TMP, c
    movf RTCC_RTCCREAD__I, w, c
    lfsr 0, RTCC_FRAME
    movff RTCC_RTCCREAD__TMP, PLUSW0
    incf RTCC_RTCCREAD__I, f, c
_L469:
    movlw 0x07
    subwf RTCC_RTCCREAD__I, w, c
    bnc _L468
_L467:
    movf RTCC_READBLOCK__RESULT, w, c
    movwf T_R, c
    movlw 0x05
    movwf RTCC_RTCCALARM__RESULT, c
    clrf RTCC_RTCCALARM__POL, c
    movlw 0x0D
    call RTCC_RDREG
    movf RTCC_RDREG__RESULT, w, c
    movwf RTCC_RTCCALARM__RESULT, c
    bnz _Lr77
    movf I2C_I2CBUF, w, c
    andlw 0x80
    movwf RTCC_RTCCALARM__POL, c
    movlw 0x02
    call RTCC_RDREG
    movf RTCC_RDREG__RESULT, w, c
    movwf RTCC_RTCCALARM__RESULT, c
    bnz _Lr77
    movlw 0x07
    movwf RTCC_ENCHOUR__H, c
    movlw 0
    btfsc I2C_I2CBUF, 6, c
    movlw 1
    movwf RTCC_ENCHOUR__TWELVE, c
    movf RTCC_ENCHOUR__TWELVE, f, c
    bnz _L863
    movf RTCC_ENCHOUR__H, w, c
    call RTCC_TOBCD
    movf RTCC_TOBCD__RESULT, w, c
    movwf RTCC_ENCHOUR__RESULT, c
    bra _L862
_L863:
    movlw 0x40
    movwf RTCC_ENCHOUR__RESULT, c
    movlw 0x0C
    subwf RTCC_ENCHOUR__H, w, c
    bnc _L865
    movlw 0x20
    iorwf RTCC_ENCHOUR__RESULT, f, c
    movlw 0x0C
    subwf RTCC_ENCHOUR__H, f, c
_L865:
    movf RTCC_ENCHOUR__H, f, c
    bnz _L867
    movlw 0x0C
    movwf RTCC_ENCHOUR__H, c
_L867:
    movf RTCC_ENCHOUR__H, w, c
    call RTCC_TOBCD
    iorwf RTCC_ENCHOUR__RESULT, f, c
_L862:
    movf RTCC_ENCHOUR__RESULT, w, c
    movwf I2C_I2CBUF+2, c
    movlw 0x00
    call RTCC_TOBCD
    movf RTCC_TOBCD__RESULT, w, c
    movwf I2C_I2CBUF, c
    movlw 0x00
    call RTCC_TOBCD
    movwf I2C_I2CBUF+1, c
    movf RTCC_RTCCALARM__POL, w, c
    iorlw 0x20
    iorlw 0x01
    movwf I2C_I2CBUF+3, c
    movlw 0x01
    call RTCC_TOBCD
    movf RTCC_TOBCD__RESULT, w, c
    movwf I2C_I2CBUF+4, c
    movlw 0x01
    call RTCC_TOBCD
    movf RTCC_TOBCD__RESULT, w, c
    movwf I2C_I2CBUF+5, c
    movlw 0xDE
    movwf RTCC_WRITEBLOCK__CTL, c
    movlw 0x0A
    movwf RTCC_WRITEBLOCK__REG, c
    movlw 0x06
    movwf RTCC_WRITEBLOCK__N, c
    call RTCC_WRITEBLOCK
    movf RTCC_WRITEBLOCK__RESULT, w, c
    movwf RTCC_RTCCALARM__RESULT, c
_Lr77:
    movf RTCC_RTCCALARM__RESULT, w, c
    movwf T_R, c
    movff T_R, RTCC_EEPUT__VALUE
    movlw 0x06
    movwf RTCC_EEREADY__RESULT, c
    clrf RTCC_EEREADY__N, c
    bra _L841
_L840:
    call I2C_I2CSTART
    movf I2C_I2CSTART__RESULT, w, c
    movwf RTCC_EEREADY__S, c
    bnz _L844
    movlw 0xAE
    call I2C_I2CSEND
    movf I2C_I2CSEND__RESULT, w, c
    movwf RTCC_EEREADY__S, c
_L844:
    call I2C_I2CSTOP
    movf RTCC_EEREADY__S, f, c
    bnz _L846
    clrf RTCC_EEREADY__RESULT, c
    bra _Lr105
_L846:
    movf RTCC_EEREADY__S, w, c
    xorlw 0x03
    bz _L848
    movff RTCC_EEREADY__S, RTCC_EEREADY__RESULT
    bra _Lr105
_L848:
    clrf __D0, c
_L849:
    movlw 19
    movwf __D1, c
_L850:
    decfsz __D1, f, c
    bra _L850
    nop
    decfsz __D0, f, c
    bra _L849
    movlw 42
    movwf __D0, c
_L851:
    decfsz __D0, f, c
    bra _L851
    nop
    incf RTCC_EEREADY__N, f, c
_L841:
    movlw 0x14
    subwf RTCC_EEREADY__N, w, c
    bnc _L840
_Lr105:
    movf RTCC_EEREADY__RESULT, w, c
    movwf RTCC_EEPUT__RESULT, c
    bnz _L839
    movff RTCC_EEPUT__VALUE, I2C_I2CBUF
    movlw 0xAE
    movwf RTCC_WRITEBLOCK__CTL, c
    clrf RTCC_WRITEBLOCK__REG, c
    movlw 0x01
    movwf RTCC_WRITEBLOCK__N, c
    call RTCC_WRITEBLOCK
    movf RTCC_WRITEBLOCK__RESULT, w, c
    movwf RTCC_EEPUT__RESULT, c
_L839:
    movf RTCC_EEPUT__RESULT, w, c
    movwf T_R, c
    clrf RTCCSPI_RTCCSPIINIT__RESULT, c
    movlw 0x10
    call PINIO_PINOK
    movf PINIO_PINOK__RESULT, w, c
    bz _Lr79
    movlw 0x10
    movwf RTCCSPI_CSPIN, c
    movwf PINIO_PINSET__PIN, c
    movlw 0x01
    movwf PINIO_PINSET__LEVEL, c
    call PINIO_PINSET
    movlw 0x10
    call PINIO_PINOUTPUT
    movlw 0x01
    movwf RTCCSPI_READY, c
    movwf RTCCSPI_RTCCSPIINIT__RESULT, c
_Lr79:
    movf RTCCSPI_RTCCSPIINIT__RESULT, w, c
    movwf T_R, c
    movlw 0x05
    movwf RTCCSPI_RTCCSPISET__RESULT, c
    movlw 0x1F
    movwf RTCCSPI_DAYSIN__RESULT, c
    subwf RTCCSPI_DAYSIN__RESULT, w, c
    bc __skip5
    bra _Lr80
__skip5:
    movlw 0x03
    movwf RTCCSPI_READBLOCK__A, c
    movlw 0x06
    movwf RTCCSPI_READBLOCK__N, c
    call RTCCSPI_READBLOCK
    movf RTCCSPI_READBLOCK__RESULT, w, c
    movwf RTCCSPI_RTCCSPISET__RESULT, c
    bz __skip6
    bra _Lr80
__skip6:
_L486:
    movf RTCCSPI_BUF, w, c
    andlw 0x80
    movwf RTCCSPI_RTCCSPISET__TS, c
    movf RTCCSPI_BUF+1, w, c
    andlw 0x08
    movwf RTCCSPI_RTCCSPISET__VB, c
    movff RTCCSPI_BUF+5, RTCCSPI_RTCCSPISET__CTL
    movlw 0x08
    movwf RTCCSPI_WRREG__REG, c
    movf RTCCSPI_RTCCSPISET__CTL, w, c
    andlw 0xF7
    movwf RTCCSPI_WRREG__V, c
    call RTCCSPI_WRREG
    movf RTCCSPI_WRREG__RESULT, w, c
    movwf RTCCSPI_RTCCSPISET__RESULT, c
    bnz _L488
    movlw 0x01
    movwf RTCCSPI_WRREG__REG, c
    clrf RTCCSPI_WRREG__V, c
    call RTCCSPI_WRREG
    movf RTCCSPI_WRREG__RESULT, w, c
    movwf RTCCSPI_RTCCSPISET__RESULT, c
_L488:
    clrf RTCCSPI_RTCCSPISET__N, c
    bra _L490
_L489:
    movlw 0x04
    call RTCCSPI_RDREG
    movf RTCCSPI_RDREG__RESULT, w, c
    movwf RTCCSPI_RTCCSPISET__RESULT, c
    bnz _L493
    btfsc RTCCSPI_BUF, 5, c
    bra _L495
    bra _L491
_L495:
    clrf __D0, c
_L497:
    movlw 19
    movwf __D1, c
_L498:
    decfsz __D1, f, c
    bra _L498
    nop
    decfsz __D0, f, c
    bra _L497
    movlw 42
    movwf __D0, c
_L499:
    decfsz __D0, f, c
    bra _L499
    nop
_L493:
    incf RTCCSPI_RTCCSPISET__N, f, c
_L490:
    movf RTCCSPI_RTCCSPISET__RESULT, f, c
    bnz _L500
    movlw 0x64
    subwf RTCCSPI_RTCCSPISET__N, w, c
    bnc _L489
_L500:
_L491:
    movf RTCCSPI_RTCCSPISET__RESULT, f, c
    bz _L502
    bra _Lr80
_L502:
    btfss RTCCSPI_BUF, 5, c
    bra _L504
    movlw 0x06
    movwf RTCCSPI_RTCCSPISET__RESULT, c
    bra _Lr80
_L504:
    clrf RTCCSPI_BUF, c
    movlw 0x0F
    call RTCCSPI_TOBCD
    movf RTCCSPI_TOBCD__RESULT, w, c
    movwf RTCCSPI_BUF+1, c
    movlw 0x1E
    call RTCCSPI_TOBCD
    movf RTCCSPI_TOBCD__RESULT, w, c
    movwf RTCCSPI_BUF+2, c
    movlw 0x0E
    call RTCCSPI_TOBCD
    iorwf RTCCSPI_RTCCSPISET__TS, w, c
    movwf RTCCSPI_BUF+3, c
    movf RTCCSPI_RTCCSPISET__VB, w, c
    iorlw 0x05
    movwf RTCCSPI_BUF+4, c
    movlw 0x1F
    call RTCCSPI_TOBCD
    movf RTCCSPI_TOBCD__RESULT, w, c
    movwf RTCCSPI_BUF+5, c
    movlw 0x0A
    call RTCCSPI_TOBCD
    movf RTCCSPI_TOBCD__RESULT, w, c
    movwf RTCCSPI_BUF+6, c
    movlw 0x18
    call RTCCSPI_TOBCD
    movf RTCCSPI_TOBCD__RESULT, w, c
    movwf RTCCSPI_BUF+7, c
    movlw 0x12
    movwf RTCCSPI_WRITEBLOCK__C, c
    clrf RTCCSPI_WRITEBLOCK__A, c
    movlw 0x08
    movwf RTCCSPI_WRITEBLOCK__N, c
    call RTCCSPI_WRITEBLOCK
    movf RTCCSPI_WRITEBLOCK__RESULT, w, c
    movwf RTCCSPI_RTCCSPISET__RESULT, c
    bnz _L507
    movlw 0x1F
    call RTCCSPI_TOBCD
    movf RTCCSPI_TOBCD__RESULT, w, c
    movwf RTCCSPI_WRREG__V, c
    movlw 0x05
    movwf RTCCSPI_WRREG__REG, c
    call RTCCSPI_WRREG
    movf RTCCSPI_WRREG__RESULT, w, c
    movwf RTCCSPI_RTCCSPISET__RESULT, c
_L507:
    movf RTCCSPI_RTCCSPISET__RESULT, f, c
    bnz _L509
    btfss RTCCSPI_RTCCSPISET__CTL, 3, c
    bra _L511
    movlw 0x08
    movwf RTCCSPI_WRREG__REG, c
    movff RTCCSPI_RTCCSPISET__CTL, RTCCSPI_WRREG__V
    call RTCCSPI_WRREG
    movf RTCCSPI_WRREG__RESULT, w, c
    movwf RTCCSPI_RTCCSPISET__RESULT, c
    bra _L510
_L511:
    movlw 0x0F
    call RTCCSPI_TOBCD
    iorlw 0x80
    movwf RTCCSPI_WRREG__V, c
    movlw 0x01
    movwf RTCCSPI_WRREG__REG, c
    call RTCCSPI_WRREG
    movf RTCCSPI_WRREG__RESULT, w, c
    movwf RTCCSPI_RTCCSPISET__RESULT, c
_L510:
_L509:
    clrf RTCCSPI_RTCCSPISET__N, c
    bra _L514
_L513:
    movlw 0x04
    call RTCCSPI_RDREG
    movf RTCCSPI_RDREG__RESULT, w, c
    movwf RTCCSPI_RTCCSPISET__RESULT, c
    bnz _L517
    btfss RTCCSPI_BUF, 5, c
    bra _L519
    bra _L515
_L519:
    clrf __D0, c
_L521:
    movlw 207
    movwf __D1, c
_L522:
    decfsz __D1, f, c
    bra _L522
    decfsz __D0, f, c
    bra _L521
_L517:
    incf RTCCSPI_RTCCSPISET__N, f, c
_L514:
    movf RTCCSPI_RTCCSPISET__RESULT, f, c
    bnz _L523
    movlw 0xC8
    subwf RTCCSPI_RTCCSPISET__N, w, c
    bnc _L513
_L523:
_L515:
    movf RTCCSPI_RTCCSPISET__RESULT, f, c
    bnz _L525
    btfsc RTCCSPI_BUF, 5, c
    bra _L527
    movlw 0x06
    movwf RTCCSPI_RTCCSPISET__RESULT, c
    bra _L526
_L527:
    movlw 0x04
    movwf RTCCSPI_WRREG__REG, c
    movf RTCCSPI_RTCCSPISET__VB, w, c
    iorlw 0x05
    movwf RTCCSPI_WRREG__V, c
    call RTCCSPI_WRREG
    movf RTCCSPI_WRREG__RESULT, w, c
    movwf RTCCSPI_RTCCSPISET__RESULT, c
_L526:
_L525:
_Lr80:
    movf RTCCSPI_RTCCSPISET__RESULT, w, c
    movwf T_R, c
    clrf RTCCSPI_READBLOCK__A, c
    movlw 0x08
    movwf RTCCSPI_READBLOCK__N, c
    call RTCCSPI_READBLOCK
    movf RTCCSPI_READBLOCK__RESULT, w, c
    bnz _L530
    clrf RTCCSPI_RTCCSPIREAD__I, c
    bra _L532
_L531:
    movf RTCCSPI_RTCCSPIREAD__I, w, c
    lfsr 0, RTCCSPI_BUF
    movf PLUSW0, w, c
    movwf RTCCSPI_RTCCSPIREAD__TMP, c
    movf RTCCSPI_RTCCSPIREAD__I, w, c
    lfsr 0, RTCCSPI_FRAME
    movff RTCCSPI_RTCCSPIREAD__TMP, PLUSW0
    incf RTCCSPI_RTCCSPIREAD__I, f, c
_L532:
    movlw 0x08
    subwf RTCCSPI_RTCCSPIREAD__I, w, c
    bnc _L531
_L530:
    movf RTCCSPI_READBLOCK__RESULT, w, c
    movwf T_R, c
    movlw 0x05
    movwf RTCCSPI_RTCCSPIALARM__RESULT, c
    movlw 0x03
    call RTCCSPI_RDREG
    movf RTCCSPI_RDREG__RESULT, w, c
    movwf RTCCSPI_RTCCSPIALARM__RESULT, c
    bz _L537
    bra _Lr82
_L537:
    movlw 0
    btfsc RTCCSPI_BUF, 6, c
    movlw 1
    movwf RTCCSPI_RTCCSPIALARM__TWELVE, c
    movlw 0x16
    call RTCCSPI_RDREG
    movf RTCCSPI_RDREG__RESULT, w, c
    movwf RTCCSPI_RTCCSPIALARM__RESULT, c
    bz _L543
    bra _Lr82
_L543:
    movf RTCCSPI_BUF, w, c
    andlw 0x80
    movwf RTCCSPI_RTCCSPIALARM__PIN, c
    movlw 0x00
    call RTCCSPI_TOBCD
    movf RTCCSPI_TOBCD__RESULT, w, c
    movwf RTCCSPI_BUF, c
    movlw 0x00
    call RTCCSPI_TOBCD
    movf RTCCSPI_TOBCD__RESULT, w, c
    movwf RTCCSPI_BUF+1, c
    movlw 0x00
    call RTCCSPI_TOBCD
    movwf RTCCSPI_BUF+2, c
    movlw 0x07
    movwf RTCCSPI_ENCHOUR__H, c
    movff RTCCSPI_RTCCSPIALARM__TWELVE, RTCCSPI_ENCHOUR__TWELVE
    movf RTCCSPI_ENCHOUR__TWELVE, f, c
    bnz _L827
    call RTCCSPI_TOBCD
    movf RTCCSPI_TOBCD__RESULT, w, c
    movwf RTCCSPI_ENCHOUR__RESULT, c
    bra _L826
_L827:
    movlw 0x40
    movwf RTCCSPI_ENCHOUR__RESULT, c
    movlw 0x0C
    subwf RTCCSPI_ENCHOUR__H, w, c
    bnc _L829
    movlw 0x20
    iorwf RTCCSPI_ENCHOUR__RESULT, f, c
    movlw 0x0C
    subwf RTCCSPI_ENCHOUR__H, f, c
_L829:
    movf RTCCSPI_ENCHOUR__H, f, c
    bnz _L831
    movlw 0x0C
    movwf RTCCSPI_ENCHOUR__H, c
_L831:
    movf RTCCSPI_ENCHOUR__H, w, c
    call RTCCSPI_TOBCD
    iorwf RTCCSPI_ENCHOUR__RESULT, f, c
_L826:
    movf RTCCSPI_ENCHOUR__RESULT, w, c
    movwf RTCCSPI_BUF+3, c
    movf RTCCSPI_RTCCSPIALARM__PIN, w, c
    iorlw 0x50
    iorlw 0x01
    movwf RTCCSPI_BUF+4, c
    movlw 0x01
    call RTCCSPI_TOBCD
    movf RTCCSPI_TOBCD__RESULT, w, c
    movwf RTCCSPI_BUF+5, c
    movlw 0x12
    movwf RTCCSPI_WRITEBLOCK__C, c
    movwf RTCCSPI_WRITEBLOCK__A, c
    movlw 0x06
    movwf RTCCSPI_WRITEBLOCK__N, c
    call RTCCSPI_WRITEBLOCK
    movf RTCCSPI_WRITEBLOCK__RESULT, w, c
    movwf RTCCSPI_RTCCSPIALARM__RESULT, c
_Lr82:
    movf RTCCSPI_RTCCSPIALARM__RESULT, w, c
    movwf T_R, c
    movff T_R, RTCCSPI_RTCCSPIEEWRITE__VALUE
    movlw 0x06
    movwf RTCCSPI_EEREADY__RESULT, c
    clrf RTCCSPI_EEREADY__N, c
    bra _L812
_L811:
    movlw 0x04
    movwf RTCCSPI_STATUSREAD__RESULT, c
    movf RTCCSPI_READY, f, c
    bnz _L825
    bra _Lr101
_L825:
    movff RTCCSPI_CSPIN, PINIO_PINSET__PIN
    clrf PINIO_PINSET__LEVEL, c
    call PINIO_PINSET
    movlw 0x05
    call SPI_SPIWRITE
    call SPI_SPIREAD
    movf SPI_SPIREAD__RESULT, w, c
    movwf RTCCSPI_BUF, c
    call SPI_SPISTATUS
    movf SPI_SPISTATUS__RESULT, w, c
    movwf RTCCSPI_STATUSREAD__RESULT, c
    movff RTCCSPI_CSPIN, PINIO_PINSET__PIN
    movlw 0x01
    movwf PINIO_PINSET__LEVEL, c
    call PINIO_PINSET
_Lr101:
    movf RTCCSPI_STATUSREAD__RESULT, w, c
    movwf RTCCSPI_EEREADY__RESULT, c
    bz _L815
    bra _Lr99
_L815:
    btfsc RTCCSPI_BUF, 0, c
    bra _L817
    bra _Lr99
_L817:
    movlw 0x06
    movwf RTCCSPI_EEREADY__RESULT, c
    clrf __D0, c
_L819:
    movlw 19
    movwf __D1, c
_L820:
    decfsz __D1, f, c
    bra _L820
    nop
    decfsz __D0, f, c
    bra _L819
    movlw 42
    movwf __D0, c
_L821:
    decfsz __D0, f, c
    bra _L821
    nop
    incf RTCCSPI_EEREADY__N, f, c
_L812:
    movlw 0x14
    subwf RTCCSPI_EEREADY__N, w, c
    bnc _L811
_Lr99:
    movf RTCCSPI_EEREADY__RESULT, w, c
    movwf RTCCSPI_WRENABLE__RESULT, c
    bnz _L805
    movwf RTCCSPI_CMD1__C, c
    movlw 0x04
    movwf RTCCSPI_CMD1__RESULT, c
    movf RTCCSPI_READY, f, c
    bnz _L823
    bra _Lr100
_L823:
    movff RTCCSPI_CSPIN, PINIO_PINSET__PIN
    clrf PINIO_PINSET__LEVEL, c
    call PINIO_PINSET
    movlw 0x06
    call SPI_SPIWRITE
    call SPI_SPISTATUS
    movf SPI_SPISTATUS__RESULT, w, c
    movwf RTCCSPI_CMD1__RESULT, c
    movff RTCCSPI_CSPIN, PINIO_PINSET__PIN
    movlw 0x01
    movwf PINIO_PINSET__LEVEL, c
    call PINIO_PINSET
_Lr100:
    movf RTCCSPI_CMD1__RESULT, w, c
    movwf RTCCSPI_WRENABLE__RESULT, c
_L805:
    movf RTCCSPI_WRENABLE__RESULT, w, c
    movwf RTCCSPI_RTCCSPIEEWRITE__RESULT, c
    bnz _L546
    movff RTCCSPI_RTCCSPIEEWRITE__VALUE, RTCCSPI_BUF
    movlw 0x02
    movwf RTCCSPI_WRITEBLOCK__C, c
    clrf RTCCSPI_WRITEBLOCK__A, c
    movlw 0x01
    movwf RTCCSPI_WRITEBLOCK__N, c
    call RTCCSPI_WRITEBLOCK
    movf RTCCSPI_WRITEBLOCK__RESULT, w, c
    movwf RTCCSPI_RTCCSPIEEWRITE__RESULT, c
_L546:
    movf RTCCSPI_RTCCSPIEEWRITE__RESULT, w, c
    movwf T_R, c
    movlw 0x08
    call PINIO_PINOK
    movf PINIO_PINOK__RESULT, w, c
    bnz _L548
    bra _Lr84
_L548:
    movlw 0x08
    call PINIO_BINDDATA
    call PINIO_DATAREAD
    movf PINIO_DATAREAD__RESULT, w, c
    movlw 0
    btfsc STATUS, 2, c
    movlw 1
    movwf PULSE_PULSEOUT_2__LEVEL, c
    movlw 0x05
    movwf PULSE_PULSEOUT_2__PERIOD, c
    clrf PULSE_PULSEOUT_2__PERIOD+1, c
    movlw 0x08
    call PINIO_PINOK
    movf PINIO_PINOK__RESULT, w, c
    bnz _L799
    bra _Lr97
_L799:
    movlw 0x08
    call PINIO_BINDDATA
    movf PULSE_PULSEOUT_2__LEVEL, w, c
    call PINIO_DATAPUT
    movlw 0x08
    call PINIO_PINOUTPUT
    bra _L801
_L800:
    movlw 53
    movwf __D0, c
_L803:
    decfsz __D0, f, c
    bra _L803
    decf PULSE_PULSEOUT_2__PERIOD, f, c
    btfss STATUS, 0, c
    decf PULSE_PULSEOUT_2__PERIOD+1, f, c
_L801:
    movf PULSE_PULSEOUT_2__PERIOD, w, c
    iorwf PULSE_PULSEOUT_2__PERIOD+1, w, c
    bnz _L800
    movf PULSE_PULSEOUT_2__LEVEL, w, c
    xorlw 1
    call PINIO_DATAPUT
_Lr97:
_Lr84:
    clrf PULSE_PULSEIN__RESULT, c
    clrf PULSE_PULSEIN__RESULT+1, c
    movlw 0x09
    call PINIO_PINOK
    movf PINIO_PINOK__RESULT, w, c
    bnz _L552
    bra _Lr85
_L552:
    movlw 0x09
    call PINIO_BINDDATA
    movlw 0x09
    call PINIO_PININPUT
    clrf PULSE_PULSEIN__N, c
    clrf PULSE_PULSEIN__N+1, c
    bra _L554
_L553:
    movlw 53
    movwf __D0, c
_L556:
    decfsz __D0, f, c
    bra _L556
    infsnz PULSE_PULSEIN__N, f, c
    incf PULSE_PULSEIN__N+1, f, c
    movf PULSE_PULSEIN__N, w, c
    iorwf PULSE_PULSEIN__N+1, w, c
    bnz _L558
    bra _Lr85
_L558:
_L554:
    call PINIO_DATAREAD
    movf PINIO_DATAREAD__RESULT, w, c
    xorlw 0x01
    bz _L553
    clrf PULSE_PULSEIN__N, c
    clrf PULSE_PULSEIN__N+1, c
    bra _L560
_L559:
    movlw 53
    movwf __D0, c
_L562:
    decfsz __D0, f, c
    bra _L562
    infsnz PULSE_PULSEIN__N, f, c
    incf PULSE_PULSEIN__N+1, f, c
    movf PULSE_PULSEIN__N, w, c
    iorwf PULSE_PULSEIN__N+1, w, c
    bnz _L564
    bra _Lr85
_L564:
_L560:
    call PINIO_DATAREAD
    movf PINIO_DATAREAD__RESULT, w, c
    xorlw 0x01
    bnz _L559
    clrf PULSE_PULSEIN__N, c
    clrf PULSE_PULSEIN__N+1, c
    bra _L566
_L565:
    movlw 53
    movwf __D0, c
_L568:
    decfsz __D0, f, c
    bra _L568
    infsnz PULSE_PULSEIN__N, f, c
    incf PULSE_PULSEIN__N+1, f, c
    movf PULSE_PULSEIN__N, w, c
    iorwf PULSE_PULSEIN__N+1, w, c
    bnz _L570
    bra _Lr85
_L570:
_L566:
    call PINIO_DATAREAD
    movf PINIO_DATAREAD__RESULT, w, c
    xorlw 0x01
    bz _L565
    movff PULSE_PULSEIN__N, PULSE_PULSEIN__RESULT
    movff PULSE_PULSEIN__N+1, PULSE_PULSEIN__RESULT+1
_Lr85:
    movff PULSE_PULSEIN__RESULT, T_X
    movff PULSE_PULSEIN__RESULT+1, T_X+1
    call PULSE_RCIN
    movff PULSE_RCIN__RESULT, T_X
    movff PULSE_RCIN__RESULT+1, T_X+1
    clrf PULSE_POT__RESULT, c
    movlw 0x09
    call PINIO_PINOK
    movf PINIO_PINOK__RESULT, w, c
    bnz _L580
    bra _Lr86
_L580:
    movlw 0x09
    call PINIO_BINDDATA
    movlw 0x00
    call PINIO_DATAPUT
    movlw 0x09
    call PINIO_PINOUTPUT
    clrf __D0, c
_L581:
    movlw 19
    movwf __D1, c
_L582:
    decfsz __D1, f, c
    bra _L582
    nop
    decfsz __D0, f, c
    bra _L581
    movlw 42
    movwf __D0, c
_L583:
    decfsz __D0, f, c
    bra _L583
    nop
    call PULSE_RCIN
    movff PULSE_RCIN__RESULT, PULSE_POT__T
    movff PULSE_RCIN__RESULT+1, PULSE_POT__T+1
    clrf PULSE_POT__T+2, c
    clrf PULSE_POT__T+3, c
    movf PULSE_POT__T, w, c
    mullw 0xFF
    movff PRODH, PULSE_POT__T
    clrf __A2, c
    clrf __A3, c
    movf PULSE_POT__T+1, w, c
    mullw 0xFF
    movf PRODL, w, c
    addwf PULSE_POT__T, f, c
    movf PRODH, w, c
    addwfc __A2, f, c
    movlw 0
    addwfc __A3, f, c
    movf PULSE_POT__T+2, w, c
    mullw 0xFF
    movf PRODL, w, c
    addwf __A2, f, c
    movf PRODH, w, c
    addwfc __A3, f, c
    movf PULSE_POT__T+3, w, c
    mullw 0xFF
    movf PRODL, w, c
    addwf __A3, f, c
    movff __A2, PULSE_POT__T+1
    movff __A3, PULSE_POT__T+2
    clrf PULSE_POT__T+3, c
    movlw 0x01
    subwf PULSE_POT__T+1, w, c
    movlw 0x00
    subwfb PULSE_POT__T+2, w, c
    movlw 0x00
    subwfb PULSE_POT__T+3, w, c
    bnc _L585
    setf PULSE_POT__T, c
    clrf PULSE_POT__T+1, c
    clrf PULSE_POT__T+2, c
    clrf PULSE_POT__T+3, c
_L585:
    movff PULSE_POT__T, PULSE_POT__RESULT
_Lr86:
    movf PULSE_POT__RESULT, w, c
    movwf T_R, c
    movlw 0x0A
    call PINIO_PINOK
    movf PINIO_PINOK__RESULT, w, c
    bnz _L587
    bra _Lr87
_L587:
    movlw 0x0A
    call PINIO_BINDDATA
    movlw 0x00
    call PINIO_DATAPUT
    movlw 0x0A
    call PINIO_PINOUTPUT
    movlw 0x01
    call PINIO_DATAPUT
    movlw 0xDC
    movwf PULSE_WAITUS__US, c
    movlw 0x05
    movwf PULSE_WAITUS__US+1, c
    call PULSE_WAITUS
    movlw 0x00
    call PINIO_DATAPUT
_Lr87:
    movlw 0x0A
    call PINIO_PINOK
    movf PINIO_PINOK__RESULT, w, c
    bnz _L589
    bra _Lr88
_L589:
    movlw 0x0A
    call PINIO_BINDDATA
    movlw 0x0A
    call PINIO_PINOUTPUT
    movlw 0x01
    movwf PULSE_PWMPIN__C, c
_L590:
    movlw 0x01
    call PINIO_DATAPUT
    movlw 0x80
    movwf PULSE_PWMPIN__H6, c
    movlw 0x01
    movwf PULSE_PWMPIN__I, c
    subwf PULSE_PWMPIN__H6, w, c
    bnc _L596
_L594:
    movlw 53
    movwf __D0, c
_L597:
    decfsz __D0, f, c
    bra _L597
    movf PULSE_PWMPIN__I, w, c
    incf PULSE_PWMPIN__I, f, c
    xorwf PULSE_PWMPIN__H6, w, c
    bnz _L594
_L596:
    movlw 0x00
    call PINIO_DATAPUT
    movlw 0x80
    movwf PULSE_PWMPIN__I, c
_L599:
    movlw 53
    movwf __D0, c
_L602:
    decfsz __D0, f, c
    bra _L602
    movf PULSE_PWMPIN__I, w, c
    incf PULSE_PWMPIN__I, f, c
    xorlw 0xFE
    bnz _L599
    movf PULSE_PWMPIN__C, w, c
    incf PULSE_PWMPIN__C, f, c
    xorlw 0x04
    bnz _L590
    movlw 0x0A
    call PINIO_PININPUT
_Lr88:
    movlw 0x0B
    call PINIO_PINOK
    movf PINIO_PINOK__RESULT, w, c
    bnz _L604
    bra _Lr89
_L604:
    movlw 0x0B
    call PINIO_BINDDATA
    movlw 0x00
    call PINIO_DATAPUT
    movlw 0x0B
    call PINIO_PINOUTPUT
    movlw 0x69
    movwf PULSE_SOUND__HALF, c
    clrf PULSE_SOUND__HALF+1, c
    movlw 0xB1
    movwf PULSE_SOUND__COUNT, c
    movlw 0x03
    movwf PULSE_SOUND__COUNT+1, c
    clrf PULSE_SOUND__COUNT+2, c
    clrf PULSE_SOUND__COUNT+3, c
    movlw 0x01
    movwf PULSE_SOUND__LFSR, c
    clrf PULSE_SOUND__LFSR+1, c
    clrf PULSE_SOUND__LEVEL, c
    bra _L607
_L606:
    movf PULSE_SOUND__LEVEL, w, c
    xorlw 1
    movwf PULSE_SOUND__LEVEL, c
    call PINIO_DATAPUT
    movff PULSE_SOUND__HALF, PULSE_WAITUS__US
    movff PULSE_SOUND__HALF+1, PULSE_WAITUS__US+1
    call PULSE_WAITUS
    movlw 0x01
    subwf PULSE_SOUND__COUNT, f, c
    movlw 0x00
    subwfb PULSE_SOUND__COUNT+1, f, c
    subwfb PULSE_SOUND__COUNT+2, f, c
    subwfb PULSE_SOUND__COUNT+3, f, c
_L607:
    movf PULSE_SOUND__COUNT, w, c
    iorwf PULSE_SOUND__COUNT+1, w, c
    iorwf PULSE_SOUND__COUNT+2, w, c
    iorwf PULSE_SOUND__COUNT+3, w, c
    bnz _L606
    movlw 0x00
    call PINIO_DATAPUT
_Lr89:
    movlw 0x0B
    call PINIO_PINOK
    movf PINIO_PINOK__RESULT, w, c
    bz _Lr90
    movlw 0x0C
    call PINIO_PINOK
    movf PINIO_PINOK__RESULT, w, c
    bz _Lr90
    movlw 0x0B
    call PINIO_BINDDATA
    movwf PINIO_BINDCLK__PIN, c
    movlw 0x0C
    call PINIO_PINADDR
    movff PINIO_PINADDR__RESULT, PINIO_CADDR
    movff PINIO_PINADDR__RESULT+1, PINIO_CADDR+1
    movlw 0x10
    movlb 0
    movwf PINIO_CMASK, b
    movlw 0x00
    call PINIO_DATAPUT
    movlw 0x00
    call PINIO_CLKPUT
    movlw 0x0B
    call PINIO_PINOUTPUT
    movlw 0x0C
    call PINIO_PINOUTPUT
    movlw 0x71
    movwf PULSE_SOUND2__H1, c
    movlw 0x38
    movwf PULSE_SOUND2__H2, c
    clrf PULSE_SOUND2__C1, c
    clrf PULSE_SOUND2__C2, c
    clrf PULSE_SOUND2__L1, c
    clrf PULSE_SOUND2__L2, c
    movlw 0x10
    movwf PULSE_SOUND2__TICKS, c
    movlw 0x27
    movwf PULSE_SOUND2__TICKS+1, c
    clrf PULSE_SOUND2__TICKS+2, c
    clrf PULSE_SOUND2__TICKS+3, c
    bra _L614
_L613:
    movlw 53
    movwf __D0, c
_L616:
    decfsz __D0, f, c
    bra _L616
    movf PULSE_SOUND2__H1, f, c
    bz _L618
    incf PULSE_SOUND2__C1, f, c
    movf PULSE_SOUND2__H1, w, c
    subwf PULSE_SOUND2__C1, w, c
    bnc _L620
    clrf PULSE_SOUND2__C1, c
    movf PULSE_SOUND2__L1, w, c
    xorlw 1
    movwf PULSE_SOUND2__L1, c
    call PINIO_DATAPUT
_L620:
_L618:
    movf PULSE_SOUND2__H2, f, c
    bz _L622
    incf PULSE_SOUND2__C2, f, c
    movf PULSE_SOUND2__H2, w, c
    subwf PULSE_SOUND2__C2, w, c
    bnc _L624
    clrf PULSE_SOUND2__C2, c
    movf PULSE_SOUND2__L2, w, c
    xorlw 1
    movwf PULSE_SOUND2__L2, c
    call PINIO_CLKPUT
_L624:
_L622:
    movlw 0x01
    subwf PULSE_SOUND2__TICKS, f, c
    movlw 0x00
    subwfb PULSE_SOUND2__TICKS+1, f, c
    subwfb PULSE_SOUND2__TICKS+2, f, c
    subwfb PULSE_SOUND2__TICKS+3, f, c
_L614:
    movf PULSE_SOUND2__TICKS, w, c
    iorwf PULSE_SOUND2__TICKS+1, w, c
    iorwf PULSE_SOUND2__TICKS+2, w, c
    iorwf PULSE_SOUND2__TICKS+3, w, c
    bnz _L613
    movlw 0x00
    call PINIO_DATAPUT
    movlw 0x00
    call PINIO_CLKPUT
_Lr90:
    movlb 0
    movwf IRREMOTE_SONYIN__PIN, b
    setf IRREMOTE_SONYIN__RESULT, c
    setf IRREMOTE_SONYIN__RESULT+1, c
    movlw 0x09
    call PINIO_PINOK
    movf PINIO_PINOK__RESULT, w, c
    bnz _L626
    bra _Lr91
_L626:
    movlw 0x09
    call PINIO_PININPUT
    clrf IRREMOTE_WIDTH__LEVEL, c
    movlw 0xE8
    movwf IRREMOTE_WIDTH__LIMIT, c
    movlw 0x03
    movwf IRREMOTE_WIDTH__LIMIT+1, c
    call IRREMOTE_WIDTH
    movff IRREMOTE_WIDTH__RESULT, __A0
    movff IRREMOTE_WIDTH__RESULT+1, __A1
    movlw 0xE9
    subwf IRREMOTE_WIDTH__RESULT, w, c
    movlw 0x03
    subwfb IRREMOTE_WIDTH__RESULT+1, w, c
    bnc _L628
    bra _Lr91
_L628:
    movlw 0x01
    movwf IRREMOTE_WIDTH__LEVEL, c
    movlw 0xE8
    movwf IRREMOTE_WIDTH__LIMIT, c
    movlw 0xFD
    movwf IRREMOTE_WIDTH__LIMIT+1, c
    call IRREMOTE_WIDTH
    movff IRREMOTE_WIDTH__RESULT, __A0
    movff IRREMOTE_WIDTH__RESULT+1, __A1
    movlw 0xE9
    subwf IRREMOTE_WIDTH__RESULT, w, c
    movlw 0xFD
    subwfb IRREMOTE_WIDTH__RESULT+1, w, c
    bnc _L630
    bra _Lr91
_L630:
    clrf IRREMOTE_WIDTH__LEVEL, c
    movlw 0xE8
    movwf IRREMOTE_WIDTH__LIMIT, c
    movlw 0x03
    movwf IRREMOTE_WIDTH__LIMIT+1, c
    call IRREMOTE_WIDTH
    movff IRREMOTE_WIDTH__RESULT, IRREMOTE_SONYIN__HEADER
    movff IRREMOTE_WIDTH__RESULT+1, IRREMOTE_SONYIN__HEADER+1
    movff IRREMOTE_SONYIN__HEADER, __A0
    movff IRREMOTE_SONYIN__HEADER+1, __A0+1
    movlw 0x8C
    subwf __A0, f, c
    movlw 0x00
    subwfb __A1, f, c
    movlw 0xDD
    subwf __A0, w, c
    movlw 0x00
    subwfb __A0+1, w, c
    bnc _L632
    bra _Lr91
_L632:
    clrf IRREMOTE_SONYIN__V, c
    clrf IRREMOTE_SONYIN__V+1, c
    clrf IRREMOTE_SONYIN__I, c
_L633:
    movlw 0x01
    movwf IRREMOTE_WIDTH__LEVEL, c
    movlw 0xC8
    movwf IRREMOTE_WIDTH__LIMIT, c
    clrf IRREMOTE_WIDTH__LIMIT+1, c
    call IRREMOTE_WIDTH
    movff IRREMOTE_WIDTH__RESULT, __A0
    movff IRREMOTE_WIDTH__RESULT+1, __A1
    movlw 0xC9
    subwf IRREMOTE_WIDTH__RESULT, w, c
    movlw 0x00
    subwfb IRREMOTE_WIDTH__RESULT+1, w, c
    bnc _L637
    bra _Lr91
_L637:
    clrf IRREMOTE_WIDTH__LEVEL, c
    movlw 0xE8
    movwf IRREMOTE_WIDTH__LIMIT, c
    movlw 0x03
    movwf IRREMOTE_WIDTH__LIMIT+1, c
    call IRREMOTE_WIDTH
    movff IRREMOTE_WIDTH__RESULT, __A0
    movff IRREMOTE_WIDTH__RESULT+1, __A0+1
    movlw 3
    movwf __D0, c
_L640:
    bcf STATUS, 0, c
    rlcf __A0, f, c
    rlcf __A1, f, c
    decfsz __D0, f, c
    bra _L640
    movff __A0, IRREMOTE_SONYIN__TMP
    movff __A1, IRREMOTE_SONYIN__TMP+1
    movf IRREMOTE_SONYIN__HEADER+1, w, c
    mullw 0x03
    movff PRODL, __A1
    movf IRREMOTE_SONYIN__HEADER, w, c
    mullw 0x03
    movff PRODL, __A0
    movf PRODH, w, c
    addwf __A1, f, c
    movff PRODL, IRREMOTE_SONYIN__TMP+2
    movff __A1, IRREMOTE_SONYIN__TMP+2+1
    movf IRREMOTE_SONYIN__TMP, w, c
    subwf IRREMOTE_SONYIN__TMP+2, w, c
    movf IRREMOTE_SONYIN__TMP+1, w, c
    subwfb IRREMOTE_SONYIN__TMP+2+1, w, c
    bc _L639
    movf IRREMOTE_SONYIN__I, w, c
    movwf __D1, c
    movlw 0x01
    movwf __A0, c
    clrf __A0+1, c
    call __shl2
    movf __A0, w, c
    iorwf IRREMOTE_SONYIN__V, f, c
    movf __A0+1, w, c
    iorwf IRREMOTE_SONYIN__V+1, f, c
_L639:
    movf IRREMOTE_SONYIN__I, w, c
    incf IRREMOTE_SONYIN__I, f, c
    xorlw 0x0B
    bnz _L633
    movff IRREMOTE_SONYIN__V, __A0
    movff IRREMOTE_SONYIN__V+1, __A0+1
    movlw 7
    movwf __D0, c
_L641:
    bcf STATUS, 0, c
    rrcf __A1, f, c
    rrcf __A0, f, c
    decfsz __D0, f, c
    bra _L641
    movff __A0, IRREMOTE_SONYIN__TMP+1
    clrf IRREMOTE_SONYIN__TMP, c
    movff IRREMOTE_SONYIN__V, IRREMOTE_SONYIN__RESULT
    movlw 0x7F
    andwf IRREMOTE_SONYIN__RESULT, f, c
    clrf IRREMOTE_SONYIN__RESULT+1, c
    movf IRREMOTE_SONYIN__TMP, w, c
    iorwf IRREMOTE_SONYIN__RESULT, f, c
    movf IRREMOTE_SONYIN__TMP+1, w, c
    iorwf IRREMOTE_SONYIN__RESULT+1, f, c
_Lr91:
    movff IRREMOTE_SONYIN__RESULT, T_X
    movff IRREMOTE_SONYIN__RESULT+1, T_X+1
    movwf IRREMOTE_RC5IN__PIN, c
    setf IRREMOTE_RC5IN__RESULT, c
    setf IRREMOTE_RC5IN__RESULT+1, c
    movlw 0x09
    call PINIO_PINOK
    movf PINIO_PINOK__RESULT, w, c
    bnz _L643
    bra _Lr92
_L643:
    movlw 0x09
    call PINIO_PININPUT
    clrf IRREMOTE_WIDTH__LEVEL, c
    movlw 0xE8
    movwf IRREMOTE_WIDTH__LIMIT, c
    movlw 0x03
    movwf IRREMOTE_WIDTH__LIMIT+1, c
    call IRREMOTE_WIDTH
    movff IRREMOTE_WIDTH__RESULT, __A0
    movff IRREMOTE_WIDTH__RESULT+1, __A1
    movlw 0xE9
    subwf IRREMOTE_WIDTH__RESULT, w, c
    movlw 0x03
    subwfb IRREMOTE_WIDTH__RESULT+1, w, c
    bnc _L645
    bra _Lr92
_L645:
    movlw 0x01
    movwf IRREMOTE_WIDTH__LEVEL, c
    movlw 0xE8
    movwf IRREMOTE_WIDTH__LIMIT, c
    movlw 0xFD
    movwf IRREMOTE_WIDTH__LIMIT+1, c
    call IRREMOTE_WIDTH
    movff IRREMOTE_WIDTH__RESULT, __A0
    movff IRREMOTE_WIDTH__RESULT+1, __A1
    movlw 0xE9
    subwf IRREMOTE_WIDTH__RESULT, w, c
    movlw 0xFD
    subwfb IRREMOTE_WIDTH__RESULT+1, w, c
    bnc _L647
    bra _Lr92
_L647:
    movlw 0x66
    movwf PULSE_WAITUS__US, c
    movlw 0x08
    movwf PULSE_WAITUS__US+1, c
    call PULSE_WAITUS
    clrf IRREMOTE_RC5IN__V, c
    clrf IRREMOTE_RC5IN__V+1, c
    movlw 0x0D
    movwf IRREMOTE_RC5IN__H3, c
_L648:
    bcf STATUS, 0, c
    rlcf IRREMOTE_RC5IN__V, f, c
    rlcf IRREMOTE_RC5IN__V+1, f, c
    movlw 0x09
    call PINIO_PINGET
    movf PINIO_PINGET__RESULT, w, c
    bnz _L652
    movlw 0x01
    iorwf IRREMOTE_RC5IN__V, f, c
_L652:
    movlw 0xEA
    movwf PULSE_WAITUS__US, c
    movlw 0x06
    movwf PULSE_WAITUS__US+1, c
    call PULSE_WAITUS
    decfsz IRREMOTE_RC5IN__H3, f, c
    bra _L648
    movff IRREMOTE_RC5IN__V, __A0
    movff IRREMOTE_RC5IN__V+1, __A0+1
    movlw 6
    movwf __D0, c
_L653:
    bcf STATUS, 0, c
    rrcf __A1, f, c
    rrcf __A0, f, c
    decfsz __D0, f, c
    bra _L653
    movlw 0x1F
    andwf __A0, f, c
    movff __A0, IRREMOTE_RC5IN__TMP+1
    clrf IRREMOTE_RC5IN__TMP, c
    movff IRREMOTE_RC5IN__V, IRREMOTE_RC5IN__RESULT
    movlw 0x3F
    andwf IRREMOTE_RC5IN__RESULT, f, c
    clrf IRREMOTE_RC5IN__RESULT+1, c
    movf IRREMOTE_RC5IN__TMP, w, c
    iorwf IRREMOTE_RC5IN__RESULT, f, c
    movf IRREMOTE_RC5IN__TMP+1, w, c
    iorwf IRREMOTE_RC5IN__RESULT+1, f, c
    btfsc IRREMOTE_RC5IN__V+1, 4, c
    bra _L655
    movlw 0x40
    iorwf IRREMOTE_RC5IN__RESULT, f, c
_L655:
_Lr92:
    movff IRREMOTE_RC5IN__RESULT, T_X
    movff IRREMOTE_RC5IN__RESULT+1, T_X+1
    movlw 0x02
    movwf X10_XOUT__REPS, c
    clrf X10_XOUT__RESULT, c
    movlw 0x01
    movwf X10_XOUT__SENT, c
    movlw 0x08
    call PINIO_PINOK
    movf PINIO_PINOK__RESULT, w, c
    bnz __skip7
    bra _Lr93
__skip7:
    movlw 0x09
    call PINIO_PINOK
    movf PINIO_PINOK__RESULT, w, c
    bnz __skip8
    bra _Lr93
__skip8:
    movlw 0x02
    subwf X10_XOUT__REPS, w, c
    bc _L661
    movlw 0x02
    movwf X10_XOUT__REPS, c
_L661:
    movlw 0x08
    movwf PINIO_PINSET__PIN, c
    clrf PINIO_PINSET__LEVEL, c
    call PINIO_PINSET
    movlw 0x08
    call PINIO_PINOUTPUT
    movlw 0x09
    call PINIO_PININPUT
    movff X10_XOUT__REPS, X10_XOUT__H1
    movlw 0x01
    movwf X10_XOUT__N, c
    subwf X10_XOUT__H1, w, c
    bnc _L664
_L662:
    movf X10_XOUT__SENT, f, c
    bz _L666
    movlw 0x00
    call X10_CODEOF
    movf X10_CODEOF__RESULT, w, c
    movwf X10_FRAME__H, c
    movlw 0x12
    call X10_CODEOF
    movf X10_CODEOF__RESULT, w, c
    movwf X10_FRAME__K, c
    movlw 0x01
    movwf X10_HALF__BURST, c
    call X10_HALF
    movf X10_HALF__RESULT, w, c
    bz _L753
    movlw 0x01
    movwf X10_HALF__BURST, c
    call X10_HALF
    movf X10_HALF__RESULT, w, c
    bz _L753
    movlw 0x01
    movwf X10_HALF__BURST, c
    call X10_HALF
    movf X10_HALF__RESULT, w, c
    bz _L753
    clrf X10_HALF__BURST, c
    call X10_HALF
    movf X10_HALF__RESULT, w, c
    bz _L753
    movlw 1
    bra _L754
_L753:
    movlw 0
_L754:
    movwf X10_FRAME__RESULT, c
    clrf X10_FRAME__I, c
_L755:
    movf X10_FRAME__RESULT, f, c
    bz _L758
    movf X10_FRAME__I, w, c
    movwf __D1, c
    movlw 0x08
    movwf __A0, c
    call __shr1
    movf __A0, w, c
    andwf X10_FRAME__H, w, c
    movlw 0
    btfss STATUS, 2, c
    movlw 1
    movwf X10_SENDBIT__B, c
    call X10_SENDBIT
    movf X10_SENDBIT__RESULT, w, c
    bz _L758
    movlw 1
    bra _L759
_L758:
    movlw 0
_L759:
    movwf X10_FRAME__RESULT, c
    movf X10_FRAME__I, w, c
    incf X10_FRAME__I, f, c
    xorlw 0x03
    bnz _L755
    clrf X10_FRAME__I, c
_L762:
    movf X10_FRAME__RESULT, f, c
    bz _L765
    movf X10_FRAME__I, w, c
    movwf __D1, c
    movlw 0x08
    movwf __A0, c
    call __shr1
    movf __A0, w, c
    andwf X10_FRAME__K, w, c
    movlw 0
    btfss STATUS, 2, c
    movlw 1
    movwf X10_SENDBIT__B, c
    call X10_SENDBIT
    movf X10_SENDBIT__RESULT, w, c
    bz _L765
    movlw 1
    bra _L766
_L765:
    movlw 0
_L766:
    movwf X10_FRAME__RESULT, c
    movf X10_FRAME__I, w, c
    incf X10_FRAME__I, f, c
    xorlw 0x03
    bnz _L762
    movf X10_FRAME__RESULT, f, c
    bz _L769
    movlw 0x01
    movwf X10_SENDBIT__B, c
    call X10_SENDBIT
    movf X10_SENDBIT__RESULT, w, c
    bz _L769
    movlw 1
    bra _L770
_L769:
    movlw 0
_L770:
    movwf X10_FRAME__RESULT, c
    movwf X10_XOUT__SENT, c
_L666:
    movf X10_XOUT__SENT, f, c
    bz _L668
    btfsc X10_XOUT__N, 0, c
    bra _L668
    movf X10_XOUT__REPS, w, c
    subwf X10_XOUT__N, w, c
    bc _L668
    movlw 0x06
    movwf X10_XOUT__H2, c
_L670:
    movf X10_XOUT__SENT, f, c
    bz _L674
    call X10_ZERO
    movf X10_ZERO__RESULT, w, c
    movwf X10_XOUT__SENT, c
_L674:
    decfsz X10_XOUT__H2, f, c
    bra _L670
_L668:
    movf X10_XOUT__N, w, c
    incf X10_XOUT__N, f, c
    xorwf X10_XOUT__H1, w, c
    bnz _L662
_L664:
    movff X10_XOUT__SENT, X10_XOUT__RESULT
_Lr93:
    movlb 0
    movlw low(T_X)
    movwf X10_XIN__VALUE, b
    movlw high(T_X)
    movwf X10_XIN__VALUE+1, b
    clrf X10_XIN__RESULT, c
    movlw 0x08
    call PINIO_PINOK
    movf PINIO_PINOK__RESULT, w, c
    bnz __skip9
    bra _Lr94
__skip9:
    movlw 0x09
    call PINIO_PINOK
    movf PINIO_PINOK__RESULT, w, c
    bnz __skip10
    bra _Lr94
__skip10:
    movlw 0x08
    call PINIO_PININPUT
    movlw 0x09
    call PINIO_PININPUT
    clrf X10_XIN__HIST, c
    clrf X10_XIN__N, c
    clrf X10_XIN__N+1, c
    bra _L679
_L678:
    call X10_ZERO
    movf X10_ZERO__RESULT, w, c
    bnz _L682
    bra _Lr94
_L682:
    clrf __D0, c
_L683:
    movlw 9
    movwf __D1, c
_L684:
    decfsz __D1, f, c
    bra _L684
    decfsz __D0, f, c
    bra _L683
    movlw 21
    movwf __D0, c
_L685:
    decfsz __D0, f, c
    bra _L685
    movf X10_XIN__HIST, w, c
    addwf WREG, w, c
    andlw 0x0F
    movwf X10_XIN__HIST, c
    movlw 0x08
    call PINIO_PINGET
    movf PINIO_PINGET__RESULT, w, c
    bnz _L687
    movlw 0x01
    iorwf X10_XIN__HIST, f, c
_L687:
    infsnz X10_XIN__N, f, c
    incf X10_XIN__N+1, f, c
    movlw 0x0A
    subwf X10_XIN__N, w, c
    movlw 0x00
    subwfb X10_XIN__N+1, w, c
    bnc _L689
    bra _Lr94
_L689:
_L679:
    movf X10_XIN__HIST, w, c
    xorlw 0x0E
    bnz _L678
    movf X10_XIN__HIST, w, c
    xorlw 0x0E
    bz _L691
    bra _Lr94
_L691:
    clrf X10_XIN__H, c
    clrf X10_XIN__K, c
    clrf X10_XIN__F, c
    movlw 0x01
    movwf X10_XIN__GOOD, c
    clrf X10_XIN__I, c
_L692:
    movf X10_XIN__GOOD, f, c
    bz _L696
    call X10_ZERO
    movf X10_ZERO__RESULT, w, c
    movwf X10_XIN__GOOD, c
_L696:
    clrf __D0, c
_L697:
    movlw 9
    movwf __D1, c
_L698:
    decfsz __D1, f, c
    bra _L698
    decfsz __D0, f, c
    bra _L697
    movlw 21
    movwf __D0, c
_L699:
    decfsz __D0, f, c
    bra _L699
    movlw 0x08
    call PINIO_PINGET
    movf PINIO_PINGET__RESULT, w, c
    movlw 0
    btfsc STATUS, 2, c
    movlw 1
    movwf X10_XIN__A, c
    movf X10_XIN__GOOD, f, c
    bz _L703
    call X10_ZERO
    movf X10_ZERO__RESULT, w, c
    movwf X10_XIN__GOOD, c
_L703:
    clrf __D0, c
_L704:
    movlw 9
    movwf __D1, c
_L705:
    decfsz __D1, f, c
    bra _L705
    decfsz __D0, f, c
    bra _L704
    movlw 21
    movwf __D0, c
_L706:
    decfsz __D0, f, c
    bra _L706
    movlw 0x08
    call PINIO_PINGET
    movf PINIO_PINGET__RESULT, w, c
    movlw 0
    btfsc STATUS, 2, c
    movlw 1
    movwf X10_XIN__B, c
    movf X10_XIN__A, w, c
    xorwf X10_XIN__B, w, c
    bnz _L710
    clrf X10_XIN__GOOD, c
_L710:
    movlw 0x04
    subwf X10_XIN__I, w, c
    bc _L712
    movf X10_XIN__H, w, c
    addwf X10_XIN__H, f, c
    movf X10_XIN__A, f, c
    bz _L711
    movlw 0x01
    iorwf X10_XIN__H, f, c
    bra _L711
_L712:
    movlw 0x08
    subwf X10_XIN__I, w, c
    bc _L715
    movf X10_XIN__K, w, c
    addwf X10_XIN__K, f, c
    movf X10_XIN__A, f, c
    bz _L711
    movlw 0x01
    iorwf X10_XIN__K, f, c
    bra _L711
_L715:
    movf X10_XIN__A, f, c
    bz _L718
    movlw 0x01
    movwf X10_XIN__F, c
_L718:
_L711:
    movf X10_XIN__I, w, c
    incf X10_XIN__I, f, c
    xorlw 0x08
    bnz _L692
    movf X10_XIN__GOOD, f, c
    bnz _L720
    bra _Lr94
_L720:
    movf X10_XIN__H, w, c
    call X10_NUMBEROF
    movwf X10_XIN__TMP+1, c
    clrf X10_XIN__TMP, c
    movf X10_XIN__K, w, c
    call X10_NUMBEROF
    movwf __A0, c
    clrf __A1, c
    movf X10_XIN__TMP, w, c
    iorwf __A0, f, c
    movf X10_XIN__TMP+1, w, c
    iorwf __A1, f, c
    movff __A0, X10_XIN__TMP
    movff __A1, X10_XIN__TMP+1
    movff X10_XIN__F, __A0
    clrf __A0+1, c
    movlw 4
    movwf __D0, c
_L721:
    bcf STATUS, 0, c
    rlcf __A0, f, c
    rlcf __A1, f, c
    decfsz __D0, f, c
    bra _L721
    movf X10_XIN__TMP, w, c
    iorwf __A0, f, c
    movf X10_XIN__TMP+1, w, c
    iorwf __A1, f, c
    movff __A0, X10_XIN__TMP
    movff __A1, X10_XIN__TMP+1
    movff X10_XIN__VALUE, FSR0L
    movff X10_XIN__VALUE+1, FSR0H
    movff X10_XIN__TMP, POSTINC0
    movff X10_XIN__TMP+1, INDF0
    movlw 0x01
    movwf X10_XIN__RESULT, c
_Lr94:
    movf X10_XIN__RESULT, w, c
    movlb 0
__halt:
    bra __halt
    ; Sub/Function AdcRead
ADC_ADCREAD:
    movwf ADC_ADCREAD__CH, c
    movlw 0x3F
    andwf ADC_ADCREAD__CH, f, c
    movf ADC_ADCREAD__CH, w, c
    movlb 0
    xorwf ADC_LASTCH, w, b
    bnz __skip11
    goto ADC_CONVERT
__skip11:
    movf ADC_ADCREAD__CH, w, c
    movlb 15
    movwf ADPCH, b
    call ADC_CONVERT
    movff ADC_ADCREAD__CH, ADC_LASTCH
    goto ADC_CONVERT
    ; Sub/Function EepromRead
EEPROM_EEPROMREAD:
    setf EEPROM_EEPROMREAD__RESULT, c
    movlw 4
    subwf EEPROM_EEPROMREAD__ADDR+1, w, c
    bc _L80
    movlw 0x31
    movwf NVMADRU, c
    movf EEPROM_EEPROMREAD__ADDR+1, w, c
    movwf NVMADRH, c
    movf EEPROM_EEPROMREAD__ADDR, w, c
    movwf NVMADRL, c
    bsf NVMCON1, 0, c
_L81:
    btfsc NVMCON1, 0, c
    bra _L81
    movff NVMDATL, EEPROM_EEPROMREAD__RESULT
_L80:
    movf EEPROM_EEPROMREAD__RESULT, w, c
    return
    ; Sub/Function EepromWrite
EEPROM_EEPROMWRITE:
    clrf EEPROM_EEPROMWRITE__RESULT, c
    movlw 4
    subwf EEPROM_EEPROMWRITE__ADDR+1, w, c
    bc _L85
    movlw 0x01
    movwf EEPROM_EEPROMWRITE__RESULT, c
    movff EEPROM_EEPROMWRITE__ADDR, EEPROM_EEPROMREAD__ADDR
    movff EEPROM_EEPROMWRITE__ADDR+1, EEPROM_EEPROMREAD__ADDR+1
    rcall EEPROM_EEPROMREAD
    xorwf EEPROM_EEPROMWRITE__VALUE, w, c
    bz _L87
    movf EEPROM_EEPROMWRITE__VALUE, w, c
    movwf NVMDATL, c
    movlw 0
    btfsc INTCON, 7, c
    movlw 1
    movwf EEPROM_EEPROMWRITE__IE, c
    bcf INTCON, 7, c
    bsf NVMCON0, 7, c
    movlw 0x55
    movwf NVMCON2, c
    movlw 0xAA
    movwf NVMCON2, c
    bsf NVMCON1, 4, c
    decf EEPROM_EEPROMWRITE__IE, w, c
    bnz _L91
    bsf INTCON, 7, c
_L90:
_L91:
    btfsc NVMCON1, 4, c
    bra _L90
    bcf NVMCON0, 7, c
    movlb 14
    bcf PIR7, 5, b
    movff EEPROM_EEPROMWRITE__ADDR, EEPROM_EEPROMREAD__ADDR
    movff EEPROM_EEPROMWRITE__ADDR+1, EEPROM_EEPROMREAD__ADDR+1
    rcall EEPROM_EEPROMREAD
    xorwf EEPROM_EEPROMWRITE__VALUE, w, c
    bz _L94
    clrf EEPROM_EEPROMWRITE__RESULT, c
_L94:
_L87:
    bcf NVMCON0, 4, c
_L85:
    return
    ; Sub/Function FlashReadWord
FLASHWRITE_FLASHREADWORD:
    movff FLASHWRITE_FLASHREADWORD__ADDR, FLASHWRITE_SETADDR__ADDR
    movff FLASHWRITE_FLASHREADWORD__ADDR+1, FLASHWRITE_SETADDR__ADDR+1
    call FLASHWRITE_SETADDR
    bsf NVMCON1, 0, c
_L97:
    btfsc NVMCON1, 0, c
    bra _L97
    movff NVMDAT, FLASHWRITE_FLASHREADWORD__RESULT
    movff NVMDAT+1, FLASHWRITE_FLASHREADWORD__RESULT+1
    return
    ; Sub/Function FlashEraseSector
FLASHWRITE_FLASHERASESECTOR:
    clrf FLASHWRITE_FLASHERASESECTOR__IE, c
    clrf FLASHWRITE_FLASHERASESECTOR__RESULT, c
    movlw 2
    subwf FLASHWRITE_FLASHERASESECTOR__SECTOR+1, w, c
    bc _L101
    movlw 0
    btfsc INTCON, 7, c
    movlw 1
    movwf FLASHWRITE_FLASHERASESECTOR__IE, c
    bcf INTCON, 7, c
    movf FLASHWRITE_FLASHERASESECTOR__SECTOR+1, w, c
    movwf NVMADRU, c
    movf FLASHWRITE_FLASHERASESECTOR__SECTOR, w, c
    movwf NVMADRH, c
    clrf NVMADRL, c
    bcf NVMCON0, 4, c
    bsf NVMCON0, 7, c
                movlw 0xCC
                movwf NVMCON2, c
                movlw 0x33
                movwf NVMCON2, c
                bsf NVMCON1, 6, c   ; SECER
                nop                 ; errata 1.9.1: two all-zero NOPs after the self-write instruction
                nop
    bcf NVMCON0, 7, c
    decf FLASHWRITE_FLASHERASESECTOR__IE, w, c
    bnz _L103
    bsf INTCON, 7, c
_L103:
    btfsc NVMCON0, 4, c
    bra _L105
    movlw 0x01
    movwf FLASHWRITE_FLASHERASESECTOR__RESULT, c
_L105:
    bcf NVMCON0, 4, c
_L101:
    return
    ; Sub/Function FlashWriteWord
FLASHWRITE_FLASHWRITEWORD:
    clrf FLASHWRITE_FLASHWRITEWORD__RESULT, c
    clrf FLASHWRITE_FLASHWRITEWORD__IE, c
    movlw 0
    btfsc INTCON, 7, c
    movlw 1
    movwf FLASHWRITE_FLASHWRITEWORD__IE, c
    bcf INTCON, 7, c
    movff FLASHWRITE_FLASHWRITEWORD__ADDR, FLASHWRITE_SETADDR__ADDR
    movff FLASHWRITE_FLASHWRITEWORD__ADDR+1, FLASHWRITE_SETADDR__ADDR+1
    call FLASHWRITE_SETADDR
    movf FLASHWRITE_FLASHWRITEWORD__VALUE, w, c
    movwf NVMDAT, c
    movf FLASHWRITE_FLASHWRITEWORD__VALUE+1, w, c
    movwf NVMDAT+1, c
    bcf NVMCON0, 4, c
    bsf NVMCON0, 7, c
            movlw 0x55
            movwf NVMCON2, c
            movlw 0xAA
            movwf NVMCON2, c
            bsf NVMCON1, 4, c   ; WR
            nop                 ; errata 1.9.1: two all-zero NOPs after the self-write instruction
            nop
    bcf NVMCON0, 7, c
    decf FLASHWRITE_FLASHWRITEWORD__IE, w, c
    bnz _L107
    bsf INTCON, 7, c
_L107:
    clrf FLASHWRITE_FLASHWRITEWORD__RESULT, c
    btfsc NVMCON0, 4, c
    bra _L109
    movff FLASHWRITE_FLASHWRITEWORD__ADDR, FLASHWRITE_FLASHREADWORD__ADDR
    movff FLASHWRITE_FLASHWRITEWORD__ADDR+1, FLASHWRITE_FLASHREADWORD__ADDR+1
    rcall FLASHWRITE_FLASHREADWORD
    movff FLASHWRITE_FLASHREADWORD__RESULT, __A0
    movff FLASHWRITE_FLASHREADWORD__RESULT+1, __A1
    movf FLASHWRITE_FLASHREADWORD__RESULT, w, c
    xorwf FLASHWRITE_FLASHWRITEWORD__VALUE, w, c
    bnz _L111
    movf __A0+1, w, c
    xorwf FLASHWRITE_FLASHWRITEWORD__VALUE+1, w, c
    bnz _L111
    movlw 0x01
    movwf FLASHWRITE_FLASHWRITEWORD__RESULT, c
_L111:
_L109:
    bcf NVMCON0, 4, c
    return
    ; Sub/Function FlashUpdateWord
FLASHWRITE_FLASHUPDATEWORD:
    clrf FLASHWRITE_FLASHUPDATEWORD__RESULT, c
    clrf FLASHWRITE_FLASHUPDATEWORD__CUR, c
    clrf FLASHWRITE_FLASHUPDATEWORD__CUR+1, c
    clrf FLASHWRITE_FLASHUPDATEWORD__IE, c
    movff FLASHWRITE_FLASHUPDATEWORD__ADDR, FLASHWRITE_FLASHREADWORD__ADDR
    movff FLASHWRITE_FLASHUPDATEWORD__ADDR+1, FLASHWRITE_FLASHREADWORD__ADDR+1
    rcall FLASHWRITE_FLASHREADWORD
    movff FLASHWRITE_FLASHREADWORD__RESULT, FLASHWRITE_FLASHUPDATEWORD__CUR
    movff FLASHWRITE_FLASHREADWORD__RESULT+1, FLASHWRITE_FLASHUPDATEWORD__CUR+1
    movf FLASHWRITE_FLASHUPDATEWORD__CUR, w, c
    xorwf FLASHWRITE_FLASHUPDATEWORD__VALUE, w, c
    bnz _L114
    movf FLASHWRITE_FLASHUPDATEWORD__CUR+1, w, c
    xorwf FLASHWRITE_FLASHUPDATEWORD__VALUE+1, w, c
    bnz _L114
    movlw 0x01
    movwf FLASHWRITE_FLASHUPDATEWORD__RESULT, c
    return
_L114:
    incf FLASHWRITE_FLASHUPDATEWORD__CUR, w, c
    bnz _L116
    incf FLASHWRITE_FLASHUPDATEWORD__CUR+1, w, c
    bnz _L116
    movff FLASHWRITE_FLASHUPDATEWORD__ADDR, FLASHWRITE_FLASHWRITEWORD__ADDR
    movff FLASHWRITE_FLASHUPDATEWORD__ADDR+1, FLASHWRITE_FLASHWRITEWORD__ADDR+1
    movff FLASHWRITE_FLASHUPDATEWORD__VALUE, FLASHWRITE_FLASHWRITEWORD__VALUE
    movff FLASHWRITE_FLASHUPDATEWORD__VALUE+1, FLASHWRITE_FLASHWRITEWORD__VALUE+1
    rcall FLASHWRITE_FLASHWRITEWORD
    movf FLASHWRITE_FLASHWRITEWORD__RESULT, w, c
    movwf FLASHWRITE_FLASHUPDATEWORD__RESULT, c
    return
_L116:
    clrf FLASHWRITE_FLASHUPDATEWORD__RESULT, c
    movlw 0
    btfsc INTCON, 7, c
    movlw 1
    movwf FLASHWRITE_FLASHUPDATEWORD__IE, c
    bcf INTCON, 7, c
    clrf TBLPTRU, c
    clrf TBLPTRH, c
    movf FLASHWRITE_FLASHUPDATEWORD__ADDR, w, c
    addwf WREG, w, c
    movwf TBLPTRL, c
    movff FLASHWRITE_FLASHUPDATEWORD__ADDR, FLASHWRITE_SETADDR__ADDR
    movff FLASHWRITE_FLASHUPDATEWORD__ADDR+1, FLASHWRITE_SETADDR__ADDR+1
    call FLASHWRITE_SETADDR
    bcf NVMCON0, 4, c
    bsf NVMCON0, 7, c
                movlw 0xBB
                movwf NVMCON2, c
                movlw 0x44
                movwf NVMCON2, c
                bsf NVMCON1, 1, c   ; SECRD
                nop                 ; errata 1.9.1: two all-zero NOPs after the self-write instruction
                nop
    btfsc NVMCON0, 4, c
    bra _L119
                    movlw 0xCC
                    movwf NVMCON2, c
                    movlw 0x33
                    movwf NVMCON2, c
                    bsf NVMCON1, 6, c   ; SECER
                    nop                 ; errata 1.9.1
                    nop
_L119:
    btfsc NVMCON0, 4, c
    bra _L121
    movf FLASHWRITE_FLASHUPDATEWORD__VALUE, w, c
    movwf TABLAT, c
                    tblwt*+
    movf FLASHWRITE_FLASHUPDATEWORD__VALUE+1, w, c
    movwf TABLAT, c
                    tblwt*+
                    movlw 0xDD
                    movwf NVMCON2, c
                    movlw 0x22
                    movwf NVMCON2, c
                    bsf NVMCON1, 5, c   ; SECWR
                    nop                 ; errata 1.9.1
                    nop
_L121:
    bcf NVMCON0, 7, c
    decf FLASHWRITE_FLASHUPDATEWORD__IE, w, c
    bnz _L123
    bsf INTCON, 7, c
_L123:
    btfsc NVMCON0, 4, c
    bra _L125
    movff FLASHWRITE_FLASHUPDATEWORD__ADDR, FLASHWRITE_FLASHREADWORD__ADDR
    movff FLASHWRITE_FLASHUPDATEWORD__ADDR+1, FLASHWRITE_FLASHREADWORD__ADDR+1
    rcall FLASHWRITE_FLASHREADWORD
    movff FLASHWRITE_FLASHREADWORD__RESULT, __A0
    movff FLASHWRITE_FLASHREADWORD__RESULT+1, __A1
    movf FLASHWRITE_FLASHREADWORD__RESULT, w, c
    xorwf FLASHWRITE_FLASHUPDATEWORD__VALUE, w, c
    bnz _L127
    movf __A0+1, w, c
    xorwf FLASHWRITE_FLASHUPDATEWORD__VALUE+1, w, c
    bnz _L127
    movlw 0x01
    movwf FLASHWRITE_FLASHUPDATEWORD__RESULT, c
_L127:
_L125:
    bcf NVMCON0, 4, c
    return
    ; Sub/Function PwmStart
PWM_PWMSTART:
    clrf PWM_PWMSTART__RESULT, c
    movlb 0
    movf PWM_READY, f, b
    bz _L134
    clrf PWM_PINOK__RESULT, c
    decf PWM_PWMSTART__CH, w, c
    bz _L1017
    movf PWM_PWMSTART__CH, w, c
    xorlw 0x02
    bnz _L1016
_L1017:
    movf PWM_PWMSTART__PIN, w, c
    addlw 0xF8
    sublw 0x0F
    bnc _L1015
    movlw 0x01
    movwf PWM_PINOK__RESULT, c
    bra _L1015
_L1016:
    xorlw 0x01
    bz _L1021
    movf PWM_PWMSTART__CH, w, c
    xorlw 0x04
    bnz _L1020
_L1021:
    movlw 0x08
    subwf PWM_PWMSTART__PIN, w, c
    bnc _L1024
    movf PWM_PWMSTART__PIN, w, c
    addlw 0xF0
    sublw 0x07
    bnc _L1023
_L1024:
    movlw 0x01
    movwf PWM_PINOK__RESULT, c
_L1023:
_L1020:
_L1015:
    movf PWM_PINOK__RESULT, w, c
    bnz _L133
_L134:
    return
_L133:
    movlw 0x04
    movwf PWM_PWMSTART__C, c
    bra _L136
_L135:
    movf PWM_PWMSTART__C, w, c
    xorwf PWM_PWMSTART__CH, w, c
    bz _L139
    decf PWM_PWMSTART__C, w, c
    lfsr 0, PWM_PINS
    movf PLUSW0, w, c
    movwf PWM_PWMSTART__TMP, c
    incf PWM_PWMSTART__PIN, w, c
    xorwf PWM_PWMSTART__TMP, w, c
    bnz _L139
    return
_L139:
    decf PWM_PWMSTART__C, f, c
_L136:
    movf PWM_PWMSTART__C, f, c
    bnz _L135
    decf PWM_PWMSTART__CH, w, c
    lfsr 0, PWM_PINS
    movf PLUSW0, w, c
    movwf PWM_PWMSTART__OLD, c
    bz _L141
    incf PWM_PWMSTART__PIN, w, c
    xorwf PWM_PWMSTART__OLD, w, c
    bz _L141
    decf PWM_PWMSTART__OLD, w, c
    rcall PINIO_PININPUT
    decf PWM_PWMSTART__OLD, w, c
    movwf PWM_SETPPS__PIN, c
    clrf PWM_SETPPS__CODE, c
    call PWM_SETPPS
_L141:
    movf PWM_PWMSTART__PIN, w, c
    rcall PINIO_PININPUT
    movff PWM_PWMSTART__PIN, PWM_SETPPS__PIN
    movf PWM_PWMSTART__CH, w, c
    addlw 0x04
    movwf PWM_SETPPS__CODE, c
    call PWM_SETPPS
    movlw 0x03
    subwf PWM_PWMSTART__CH, w, c
    bc _L143
    movff PWM_PWMSTART__CH, PWM_SETCON__CH
    movlw 0x9C
    movwf PWM_SETCON__V, c
    call PWM_SETCON
    bra _L142
_L143:
    movff PWM_PWMSTART__CH, PWM_SETCON__CH
    decf PWM_PWMSTART__CH, w, c
    lfsr 0, PWM_POLV
    movf PLUSW0, w, c
    movwf PWM_SETCON__V, c
    call PWM_SETCON
_L142:
    movff PWM_PWMSTART__CH, PWM_SETDUTY__CH
    movff PWM_PWMSTART__DUTY, PWM_SETDUTY__D
    movff PWM_PWMSTART__DUTY+1, PWM_SETDUTY__D+1
    call PWM_SETDUTY
    movf PWM_NACT, f, c
    bnz _L145
    clrf T2CON, c
    movlw 0x01
    movwf T2CLKCON, c
    clrf T2HLT, c
    clrf T2RST, c
    movlb 0
    movf PWM_PERIOD, w, b
    movwf T2PR, c
    clrf T2TMR, c
    movlb 14
    bcf PIR4, 1, b
    movlb 0
    movf PWM_CKPS, w, b
    mullw 0x10
    movf PRODL, w, c
    addlw 0x80
    movwf T2CON, c
    bra _L147
_L145:
    movlb 14
    bcf PIR4, 1, b
_L146:
_L147:
    movlb 14
    btfss PIR4, 1, b
    bra _L146
    bcf PIR4, 1, b
    incf PWM_PWMSTART__PIN, w, c
    movwf PWM_PWMSTART__TMP, c
    decf PWM_PWMSTART__CH, w, c
    lfsr 0, PWM_PINS
    movff PWM_PWMSTART__TMP, PLUSW0
    movf PWM_PWMSTART__OLD, f, c
    bnz _L150
    incf PWM_NACT, f, c
_L150:
    movf PWM_PWMSTART__PIN, w, c
    rcall PINIO_PINOUTPUT
    movlw 0x03
    subwf PWM_PWMSTART__CH, w, c
    bnc _L152
    movff PWM_PWMSTART__CH, PWM_SETCON__CH
    decf PWM_PWMSTART__CH, w, c
    lfsr 0, PWM_POLV
    movf PLUSW0, w, c
    addlw 0x80
    movwf PWM_SETCON__V, c
    call PWM_SETCON
_L152:
    movlw 0x01
    movwf PWM_PWMSTART__RESULT, c
    return
    ; Sub/Function PwmDuty
PWM_PWMDUTY:
    decf PWM_PWMDUTY__CH, w, c
    sublw 0x03
    bnc _L158
    decf PWM_PWMDUTY__CH, w, c
    lfsr 0, PWM_PINS
    movf PLUSW0, w, c
    bz _L160
    movff PWM_PWMDUTY__CH, PWM_SETDUTY__CH
    movff PWM_PWMDUTY__DUTY, PWM_SETDUTY__D
    movff PWM_PWMDUTY__DUTY+1, PWM_SETDUTY__D+1
    call PWM_SETDUTY
_L160:
_L158:
    return
    ; Sub/Function PwmStop
PWM_PWMSTOP:
    movwf PWM_PWMSTOP__CH, c
    addlw 0xFF
    sublw 0x03
    bnc _L168
    decf PWM_PWMSTOP__CH, w, c
    lfsr 0, PWM_PINS
    movf PLUSW0, w, c
    bz _L170
    addlw 0xFF
    rcall PINIO_PININPUT
    movff PWM_PWMSTOP__CH, PWM_SETCON__CH
    clrf PWM_SETCON__V, c
    call PWM_SETCON
    decf PWM_PWMSTOP__CH, w, c
    lfsr 0, PWM_PINS
    movf PLUSW0, w, c
    addlw 0xFF
    movwf PWM_SETPPS__PIN, c
    clrf PWM_SETPPS__CODE, c
    call PWM_SETPPS
    decf PWM_PWMSTOP__CH, w, c
    lfsr 0, PWM_PINS
    clrf PLUSW0, c
    decf PWM_NACT, f, c
    bnz _L172
    clrf T2CON, c
_L172:
_L170:
_L168:
    return
    ; Sub/Function I2cStart
I2C_I2CSTART:
    movlw 0x04
    movwf I2C_I2CSTART__RESULT, c
    movf I2C_READY, f, c
    bz _L175
    movlw 0x01
    call I2C_CONDITION
    movf I2C_CONDITION__RESULT, w, c
    movwf I2C_I2CSTART__RESULT, c
_L175:
    movff I2C_I2CSTART__RESULT, I2C_LASTSTATUS
    return
    ; Sub/Function I2cSend
I2C_I2CSEND:
    movwf I2C_I2CSEND__B, c
    movlw 0x04
    movwf I2C_I2CSEND__RESULT, c
    movf I2C_READY, f, c
    bnz _L177
    movff I2C_I2CSEND__RESULT, I2C_LASTSTATUS
    return
_L177:
    movlw 0x1F
    call I2C_WAITIDLE
    movf I2C_WAITIDLE__RESULT, w, c
    movwf I2C_I2CSEND__RESULT, c
    bnz _L179
    movlb 14
    bcf PIR3, 0, b
    bcf SSP1CON1, 7, c
    movf I2C_I2CSEND__B, w, c
    movwf SSP1BUF, c
    btfss SSP1CON1, 7, c
    bra _L181
    bcf SSP1CON1, 7, c
    movlw 0x01
    movwf I2C_I2CSEND__RESULT, c
    bra _L180
_L181:
    call I2C_WAITIF
    movf I2C_WAITIF__RESULT, w, c
    movwf I2C_I2CSEND__RESULT, c
    bnz _L183
    btfss SSP1CON2, 6, c
    bra _L183
    movlw 0x03
    movwf I2C_I2CSEND__RESULT, c
_L183:
_L180:
_L179:
    movff I2C_I2CSEND__RESULT, I2C_LASTSTATUS
    return
    ; Sub/Function I2cReceive
I2C_I2CRECEIVE:
    movlb 0
    movwf I2C_I2CRECEIVE__ACK, b
    clrf I2C_I2CRECEIVE__RESULT, c
    movlw 0x04
    movwf I2C_LASTSTATUS, c
    movf I2C_READY, f, c
    bnz _L185
    return
_L185:
    movlw 0x1F
    call I2C_WAITIDLE
    movf I2C_WAITIDLE__RESULT, w, c
    movwf I2C_LASTSTATUS, c
    bnz _L187
    movlb 14
    bcf PIR3, 0, b
    bsf SSP1CON2, 3, c
    call I2C_WAITIF
    movf I2C_WAITIF__RESULT, w, c
    movwf I2C_LASTSTATUS, c
_L187:
    movf I2C_LASTSTATUS, f, c
    bnz _L189
    movff SSP1BUF, I2C_I2CRECEIVE__RESULT
    movlb 0
    movf I2C_I2CRECEIVE__ACK, f, b
    bz _L191
    bcf SSP1CON2, 5, c
    bra _L190
_L191:
    bsf SSP1CON2, 5, c
_L190:
    movlw 0x10
    call I2C_CONDITION
    movf I2C_CONDITION__RESULT, w, c
    movwf I2C_LASTSTATUS, c
_L189:
    return
    ; Sub/Function I2cRestart
I2C_I2CRESTART:
    movlw 0x04
    movwf I2C_I2CRESTART__RESULT, c
    movf I2C_READY, f, c
    bz _L193
    movlw 0x02
    call I2C_CONDITION
    movf I2C_CONDITION__RESULT, w, c
    movwf I2C_I2CRESTART__RESULT, c
_L193:
    movff I2C_I2CRESTART__RESULT, I2C_LASTSTATUS
    return
    ; Sub/Function I2cStop
I2C_I2CSTOP:
    movlw 0x04
    movwf I2C_I2CSTOP__RESULT, c
    movf I2C_READY, f, c
    bz _L195
    call I2C_CONDITION
    movf I2C_CONDITION__RESULT, w, c
    movwf I2C_I2CSTOP__RESULT, c
_L195:
    movff I2C_I2CSTOP__RESULT, I2C_LASTSTATUS
    movf I2C_I2CSTOP__RESULT, w, c
    return
    ; Sub/Function I2cStatus
I2C_I2CSTATUS:
    movff I2C_LASTSTATUS, I2C_I2CSTATUS__RESULT
    movf I2C_I2CSTATUS__RESULT, w, c
    return
    ; Sub/Function SpiTransfer
SPI_SPITRANSFER:
    movwf SPI_SPITRANSFER__B, c
    clrf SPI_SPITRANSFER__RESULT, c
    movlw 0x04
    movwf SPI_LASTSTATUS, c
    movlb 0
    movf SPI_READY, f, b
    bnz _L216
    return
_L216:
    bcf SSP1CON1, 7, c
    movf SPI_SPITRANSFER__B, w, c
    movwf SSP1BUF, c
    movlw 0x01
    movwf SPI_LASTSTATUS, c
    clrf SPI_SPITRANSFER__N, c
    clrf SPI_SPITRANSFER__N+1, c
    bra _L218
_L217:
    btfss SSP1STAT, 0, c
    bra _L221
    movff SSP1BUF, SPI_SPITRANSFER__RESULT
    clrf SPI_LASTSTATUS, c
    return
_L221:
    infsnz SPI_SPITRANSFER__N, f, c
    incf SPI_SPITRANSFER__N+1, f, c
_L218:
    movlw 0x60
    subwf SPI_SPITRANSFER__N, w, c
    movlw 0xEA
    subwfb SPI_SPITRANSFER__N+1, w, c
    bnc _L217
    return
    ; Sub/Function SpiWrite
SPI_SPIWRITE:
    movwf SPI_SPIWRITE__B, c
    rcall SPI_SPITRANSFER
    movf SPI_SPITRANSFER__RESULT, w, c
    return
    ; Sub/Function SpiRead
SPI_SPIREAD:
    movlw 0xFF
    rcall SPI_SPITRANSFER
    movf SPI_SPITRANSFER__RESULT, w, c
    movwf SPI_SPIREAD__RESULT, c
    return
    ; Sub/Function SpiStatus
SPI_SPISTATUS:
    movff SPI_LASTSTATUS, SPI_SPISTATUS__RESULT
    return
    ; Sub/Function SysClockHz
SYSTEM_SYSCLOCKHZ:
    movlb 14
    movf OSCCON2, w, b
    swapf WREG, w, c
    andlw 0x0F
    andlw 0x07
    movwf SYSTEM_SYSCLOCKFROM__COSC, c
    movf OSCCON2, w, b
    andlw 0x0F
    movwf SYSTEM_SYSCLOCKFROM__CDIV, c
    movf OSCFRQ, w, b
    andlw 0x0F
    movwf SYSTEM_SYSCLOCKFROM__HFFRQ, c
    clrf SYSTEM_SYSCLOCKFROM__RESULT, c
    clrf SYSTEM_SYSCLOCKFROM__RESULT+1, c
    clrf SYSTEM_SYSCLOCKFROM__RESULT+2, c
    clrf SYSTEM_SYSCLOCKFROM__RESULT+3, c
    movf SYSTEM_SYSCLOCKFROM__COSC, w, c
    xorlw 0x06
    bnz _Lr110
    movlw 0x0A
    subwf SYSTEM_SYSCLOCKFROM__CDIV, w, c
    bnc _L939
    return
_L939:
    clrf SYSTEM_SYSCLOCKFROM__MHZ, c
    movf PCL, w, c
    movf SYSTEM_SYSCLOCKFROM__HFFRQ, w, c
    sublw 0x08
    bnc _L941
    rlncf WREG, w, c
    addwf PCL, f, c
    bra _L950
    bra _L949
    bra _L948
    bra _L947
    bra _L946
    bra _L945
    bra _L944
    bra _L943
    bra _L942
_L942:
    movlw 0x01
    movwf SYSTEM_SYSCLOCKFROM__MHZ, c
    bra _L941
_L943:
    movlw 0x02
    movwf SYSTEM_SYSCLOCKFROM__MHZ, c
    bra _L941
_L944:
    movlw 0x04
    movwf SYSTEM_SYSCLOCKFROM__MHZ, c
    bra _L941
_L945:
    movlw 0x08
    movwf SYSTEM_SYSCLOCKFROM__MHZ, c
    bra _L941
_L946:
    movlw 0x0C
    movwf SYSTEM_SYSCLOCKFROM__MHZ, c
    bra _L941
_L947:
    movlw 0x10
    movwf SYSTEM_SYSCLOCKFROM__MHZ, c
    bra _L941
_L948:
    movlw 0x20
    movwf SYSTEM_SYSCLOCKFROM__MHZ, c
    bra _L941
_L949:
    movlw 0x30
    movwf SYSTEM_SYSCLOCKFROM__MHZ, c
    bra _L941
_L950:
    movlw 0x40
    movwf SYSTEM_SYSCLOCKFROM__MHZ, c
_L941:
    movf SYSTEM_SYSCLOCKFROM__MHZ, f, c
    bz _L952
    movf SYSTEM_SYSCLOCKFROM__MHZ, w, c
    mullw 0x40
    movff PRODL, __A0
    movff PRODH, __A1
    clrf __A2, c
    clrf __A3, c
    mullw 0x42
    movf PRODL, w, c
    addwf __A1, f, c
    movf PRODH, w, c
    addwfc __A2, f, c
    movlw 0
    addwfc __A3, f, c
    movf SYSTEM_SYSCLOCKFROM__MHZ, w, c
    mullw 0x0F
    movf PRODL, w, c
    addwf __A2, f, c
    movf PRODH, w, c
    addwfc __A3, f, c
    movff __A0, SYSTEM_SYSCLOCKFROM__TMP
    movff __A1, SYSTEM_SYSCLOCKFROM__TMP+1
    movff __A2, SYSTEM_SYSCLOCKFROM__TMP+2
    movff __A3, SYSTEM_SYSCLOCKFROM__TMP+3
    movf SYSTEM_SYSCLOCKFROM__CDIV, w, c
    movwf __D1, c
    call __shr4
    movff __A0, SYSTEM_SYSCLOCKFROM__RESULT
    movff __A1, SYSTEM_SYSCLOCKFROM__RESULT+1
    movff __A2, SYSTEM_SYSCLOCKFROM__RESULT+2
    movff __A3, SYSTEM_SYSCLOCKFROM__RESULT+3
_L952:
_Lr110:
    return
    ; Sub/Function LcdSetAddress
LCD_LCDSETADDRESS:
    movwf LCD_LCDSETADDRESS__ADDR, c
    andlw 0x7F
    iorlw 0x80
    bra LCD_LCDCOMMAND
    ; Sub/Function LcdWriteChar
LCD_LCDWRITECHAR:
    movwf LCD_LCDWRITECHAR__CH, c
    movlb 0
    movf LCD_READY, f, b
    bz _L304
    movff LCD_LCDWRITECHAR__CH, LCD_SEND__B
    movlw 0x01
    movwf LCD_SEND__RS, c
    call LCD_SEND
_L304:
    return
    ; Sub/Function LcdCommand
LCD_LCDCOMMAND:
    movwf LCD_LCDCOMMAND__C, c
    movlb 0
    movf LCD_READY, f, b
    bnz _L326
    return
_L326:
    movff LCD_LCDCOMMAND__C, LCD_SEND__B
    clrf LCD_SEND__RS, c
    call LCD_SEND
    movlw 0x04
    subwf LCD_LCDCOMMAND__C, w, c
    bc _L328
    clrf __D0, c
_L329:
    movlw 40
    movwf __D1, c
_L330:
    decfsz __D1, f, c
    bra _L330
    nop
    decfsz __D0, f, c
    bra _L329
_L328:
    return
    ; Sub/Function OledGoto
OLED_OLEDGOTO:
    movlw 0x08
    subwf OLED_OLEDGOTO__PAGE, w, c
    bnc _L343
    return
_L343:
    movlw 0x03
    movwf OLED_CMD__N, c
    movlw 0x21
    movwf OLED_CMD__C, c
    clrf OLED_CMD__A, c
    movlw 0x7F
    movwf OLED_CMD__B, c
    call OLED_CMD
    movlw 0x03
    movwf OLED_CMD__N, c
    movlw 0x22
    movwf OLED_CMD__C, c
    movff OLED_OLEDGOTO__PAGE, OLED_CMD__A
    movlw 0x07
    movwf OLED_CMD__B, c
    goto OLED_CMD
    ; Sub/Function OledFill
OLED_OLEDFILL:
    movwf OLED_OLEDFILL__PATTERN, c
    movf OLED_MODE, f, c
    bnz _L348
    return
_L348:
    clrf OLED_OLEDGOTO__PAGE, c
    rcall OLED_OLEDGOTO
    movlw 0x01
    call OLED_BEGIN
    clrf OLED_OLEDFILL__N, c
    clrf OLED_OLEDFILL__N+1, c
    bra _L350
_L349:
    movlw 0x00
    call OLED_PUT
    infsnz OLED_OLEDFILL__N, f, c
    incf OLED_OLEDFILL__N+1, f, c
_L350:
    movlw 4
    subwf OLED_OLEDFILL__N+1, w, c
    bnc _L349
    call OLED_FINISH
    clrf OLED_OLEDGOTO__PAGE, c
    bra OLED_OLEDGOTO
    ; Sub/Function OledWriteChar
OLED_OLEDWRITECHAR:
    movwf OLED_OLEDWRITECHAR__CH, c
    movf OLED_MODE, f, c
    bnz _L353
    return
_L353:
    movf OLED_OLEDWRITECHAR__CH, w, c
    addlw 0xE0
    sublw 0x5E
    bc _L355
    movlw 0x3F
    movwf OLED_OLEDWRITECHAR__CH, c
_L355:
    movf OLED_OLEDWRITECHAR__CH, w, c
    addlw 0xE0
    mullw 0x05
    movff PRODL, OLED_OLEDWRITECHAR__BASE
    movff PRODH, OLED_OLEDWRITECHAR__BASE+1
    movlw 0x01
    rcall OLED_BEGIN
    clrf OLED_OLEDWRITECHAR__I, c
    bra _L357
_L356:
    movf OLED_OLEDWRITECHAR__BASE, w, c
    addwf OLED_OLEDWRITECHAR__I, w, c
    movwf OLED_FONTBYTE__IDX, c
    movlw 0x00
    addwfc OLED_OLEDWRITECHAR__BASE+1, w, c
    movwf OLED_FONTBYTE__IDX+1, c
    rcall OLED_FONTBYTE
    movf OLED_FONTBYTE__RESULT, w, c
    call OLED_PUT
    incf OLED_OLEDWRITECHAR__I, f, c
_L357:
    movlw 0x05
    subwf OLED_OLEDWRITECHAR__I, w, c
    bnc _L356
    movlw 0x00
    call OLED_PUT
    goto OLED_FINISH
    ; Sub/Function FontByte
OLED_FONTBYTE:
    movlw low(__CA0)
    addwf OLED_FONTBYTE__IDX, w, c
    movwf TBLPTRL, c
    movlw high(__CA0)
    addwfc OLED_FONTBYTE__IDX+1, w, c
    movwf TBLPTRH, c
    clrf TBLPTRU, c
    tblrd*+
    movf TABLAT, w, c
    movwf OLED_FONTBYTE__RESULT, c
    return
    ; Sub/Function Aht30Start
AHT30_AHT30START:
    rcall I2C_I2CSTART
    movf I2C_I2CSTART__RESULT, w, c
    movwf AHT30_AHT30START__RESULT, c
    bnz _L386
    movlw 0x70
    rcall I2C_I2CSEND
    movf I2C_I2CSEND__RESULT, w, c
    movwf AHT30_AHT30START__RESULT, c
_L386:
    movf AHT30_AHT30START__RESULT, f, c
    bnz _L388
    movlw 0xAC
    rcall I2C_I2CSEND
    movf I2C_I2CSEND__RESULT, w, c
    movwf AHT30_AHT30START__RESULT, c
_L388:
    movf AHT30_AHT30START__RESULT, f, c
    bnz _L390
    movlw 0x33
    rcall I2C_I2CSEND
    movf I2C_I2CSEND__RESULT, w, c
    movwf AHT30_AHT30START__RESULT, c
_L390:
    movf AHT30_AHT30START__RESULT, f, c
    bnz _L392
    movlw 0x00
    rcall I2C_I2CSEND
    movf I2C_I2CSEND__RESULT, w, c
    movwf AHT30_AHT30START__RESULT, c
_L392:
    rcall I2C_I2CSTOP
    movf AHT30_AHT30START__RESULT, f, c
    bnz _L394
    movff I2C_I2CSTOP__RESULT, AHT30_AHT30START__RESULT
_L394:
    return
    ; Sub/Function Aht30Fetch
AHT30_AHT30FETCH:
    clrf AHT30_AHT30FETCH__RAW, c
    clrf AHT30_AHT30FETCH__RAW+1, c
    clrf AHT30_AHT30FETCH__RAW+2, c
    clrf AHT30_AHT30FETCH__RAW+3, c
    rcall I2C_I2CSTART
    movf I2C_I2CSTART__RESULT, w, c
    movwf AHT30_AHT30FETCH__RESULT, c
    bnz _L396
    movlw 0x71
    rcall I2C_I2CSEND
    movf I2C_I2CSEND__RESULT, w, c
    movwf AHT30_AHT30FETCH__RESULT, c
_L396:
    clrf AHT30_AHT30FETCH__I, c
    bra _L398
_L397:
    movlw 0x06
    subwf AHT30_AHT30FETCH__I, w, c
    movlw 0
    btfss STATUS, 0, c
    movlw 1
    rcall I2C_I2CRECEIVE
    movf I2C_I2CRECEIVE__RESULT, w, c
    movwf AHT30_AHT30FETCH__TMP, c
    movf AHT30_AHT30FETCH__I, w, c
    lfsr 0, AHT30_FRAME
    movff AHT30_AHT30FETCH__TMP, PLUSW0
    rcall I2C_I2CSTATUS
    movwf AHT30_AHT30FETCH__RESULT, c
    incf AHT30_AHT30FETCH__I, f, c
_L398:
    movf AHT30_AHT30FETCH__RESULT, f, c
    bnz _L402
    movlw 0x07
    subwf AHT30_AHT30FETCH__I, w, c
    bnc _L397
_L402:
    rcall I2C_I2CSTOP
    movlb 0
    movwf AHT30_AHT30FETCH__S, b
    movf AHT30_AHT30FETCH__RESULT, f, c
    bnz _L404
    movff AHT30_AHT30FETCH__S, AHT30_AHT30FETCH__RESULT
_L404:
    movf AHT30_AHT30FETCH__RESULT, f, c
    bnz _L406
    btfss AHT30_FRAME, 7, c
    bra _L408
    movlw 0x05
    movwf AHT30_AHT30FETCH__RESULT, c
    bra _L407
_L408:
    setf AHT30_CRC8__C, c
    clrf AHT30_CRC8__I, c
    bra _L882
_L881:
    movf AHT30_CRC8__I, w, c
    lfsr 0, AHT30_FRAME
    movf PLUSW0, w, c
    xorwf AHT30_CRC8__C, f, c
    clrf AHT30_CRC8__K, c
    bra _L885
_L884:
    bcf STATUS, 0, c
    rlcf AHT30_CRC8__C, f, c
    bnc _L887
    movlw 0x31
    xorwf AHT30_CRC8__C, f, c
_L887:
    incf AHT30_CRC8__K, f, c
_L885:
    movlw 0x08
    subwf AHT30_CRC8__K, w, c
    bnc _L884
    incf AHT30_CRC8__I, f, c
_L882:
    movlw 0x06
    subwf AHT30_CRC8__I, w, c
    bnc _L881
    movf AHT30_CRC8__C, w, c
    xorwf AHT30_FRAME+6, w, c
    bz _L410
    movlw 0x06
    movwf AHT30_AHT30FETCH__RESULT, c
_L410:
_L407:
_L406:
    movf AHT30_AHT30FETCH__RESULT, f, c
    bz __skip12
    bra _L412
__skip12:
    clrf AHT30_AHT30FETCH__RAW+3, c
    movf AHT30_FRAME+1, w, c
    swapf WREG, w, c
    andlw 0x0F
    movwf AHT30_AHT30FETCH__RAW+2, c
    movf AHT30_FRAME+1, w, c
    mullw 16
    movf PRODL, w, c
    movwf AHT30_AHT30FETCH__TMP, c
    movf AHT30_FRAME+2, w, c
    swapf WREG, w, c
    andlw 0x0F
    iorwf AHT30_AHT30FETCH__TMP, w, c
    movwf AHT30_AHT30FETCH__RAW+1, c
    movf AHT30_FRAME+2, w, c
    mullw 16
    movf PRODL, w, c
    movwf AHT30_AHT30FETCH__TMP, c
    movf AHT30_FRAME+3, w, c
    swapf WREG, w, c
    andlw 0x0F
    iorwf AHT30_AHT30FETCH__TMP, w, c
    movwf AHT30_AHT30FETCH__RAW, c
    mullw 0x71
    movff PRODL, __A0
    movff PRODH, __A1
    clrf __A2, c
    clrf __A3, c
    movf AHT30_AHT30FETCH__RAW+1, w, c
    mullw 0x71
    movf PRODL, w, c
    addwf __A1, f, c
    movf PRODH, w, c
    addwfc __A2, f, c
    movlw 0
    addwfc __A3, f, c
    movf AHT30_AHT30FETCH__RAW, w, c
    mullw 0x02
    movf PRODL, w, c
    addwf __A1, f, c
    movf PRODH, w, c
    addwfc __A2, f, c
    movlw 0
    addwfc __A3, f, c
    movf AHT30_AHT30FETCH__RAW+2, w, c
    mullw 0x71
    movf PRODL, w, c
    addwf __A2, f, c
    movf PRODH, w, c
    addwfc __A3, f, c
    movf AHT30_AHT30FETCH__RAW+1, w, c
    mullw 0x02
    movf PRODL, w, c
    addwf __A2, f, c
    movf PRODH, w, c
    addwfc __A3, f, c
    movf AHT30_AHT30FETCH__RAW+3, w, c
    mullw 0x71
    movf PRODL, w, c
    addwf __A3, f, c
    movf AHT30_AHT30FETCH__RAW+2, w, c
    mullw 0x02
    movf PRODL, w, c
    addwf __A3, f, c
    bcf STATUS, 0, c
    movlw 0x80
    addwfc __A1, f, c
    movlw 0x00
    addwfc __A2, f, c
    addwfc __A3, f, c
    movff __A2, AHT30_AHT30FETCH__TMP
    movff __A3, AHT30_AHT30FETCH__TMP+1
    movff AHT30_AHT30FETCH__RH, FSR0L
    movff AHT30_AHT30FETCH__RH+1, FSR0H
    movff AHT30_AHT30FETCH__TMP, POSTINC0
    movff AHT30_AHT30FETCH__TMP+1, INDF0
    movf AHT30_FRAME+3, w, c
    andlw 0x0F
    movwf AHT30_AHT30FETCH__RAW+2, c
    movff AHT30_FRAME+4, AHT30_AHT30FETCH__RAW+1
    movff AHT30_FRAME+5, AHT30_AHT30FETCH__RAW
    movf AHT30_AHT30FETCH__RAW, w, c
    mullw 0xE2
    movff PRODL, __A0
    movff PRODH, __A1
    clrf __A2, c
    clrf __A3, c
    movf AHT30_AHT30FETCH__RAW+1, w, c
    mullw 0xE2
    movf PRODL, w, c
    addwf __A1, f, c
    movf PRODH, w, c
    addwfc __A2, f, c
    movlw 0
    addwfc __A3, f, c
    movf AHT30_AHT30FETCH__RAW, w, c
    mullw 0x04
    movf PRODL, w, c
    addwf __A1, f, c
    movf PRODH, w, c
    addwfc __A2, f, c
    movlw 0
    addwfc __A3, f, c
    movf AHT30_AHT30FETCH__RAW+2, w, c
    mullw 0xE2
    movf PRODL, w, c
    addwf __A2, f, c
    movf PRODH, w, c
    addwfc __A3, f, c
    movf AHT30_AHT30FETCH__RAW+1, w, c
    mullw 0x04
    movf PRODL, w, c
    addwf __A2, f, c
    movf PRODH, w, c
    addwfc __A3, f, c
    movf AHT30_AHT30FETCH__RAW+3, w, c
    mullw 0xE2
    movf PRODL, w, c
    addwf __A3, f, c
    movf AHT30_AHT30FETCH__RAW+2, w, c
    mullw 0x04
    movf PRODL, w, c
    addwf __A3, f, c
    bcf STATUS, 0, c
    movlw 0x80
    addwfc __A1, f, c
    movlw 0x00
    addwfc __A2, f, c
    addwfc __A3, f, c
    movff __A2, __A0
    movff __A3, AHT30_AHT30FETCH__TMP+1
    movlw 0x88
    subwf __A0, f, c
    movlw 0x13
    subwfb AHT30_AHT30FETCH__TMP+1, f, c
    movff AHT30_AHT30FETCH__TEMP, FSR0L
    movff AHT30_AHT30FETCH__TEMP+1, FSR0H
    movff __A0, POSTINC0
    movff AHT30_AHT30FETCH__TMP+1, INDF0
_L412:
    return
    ; Sub/Function RCin
PULSE_RCIN:
    clrf PULSE_RCIN__RESULT, c
    clrf PULSE_RCIN__RESULT+1, c
    movlw 0x09
    rcall PINIO_PINOK
    movf PINIO_PINOK__RESULT, w, c
    bnz _L572
    return
_L572:
    movlw 0x09
    rcall PINIO_BINDDATA
    movlw 0x09
    rcall PINIO_PININPUT
    movlw 0x01
    movwf PULSE_RCIN__N, c
    clrf PULSE_RCIN__N+1, c
    bra _L574
_L573:
    movlw 53
    movwf __D0, c
_L576:
    decfsz __D0, f, c
    bra _L576
    infsnz PULSE_RCIN__N, f, c
    incf PULSE_RCIN__N+1, f, c
    movf PULSE_RCIN__N, w, c
    iorwf PULSE_RCIN__N+1, w, c
    bnz _L578
    return
_L578:
_L574:
    rcall PINIO_DATAREAD
    movf PINIO_DATAREAD__RESULT, w, c
    bz _L573
    movff PULSE_RCIN__N, PULSE_RCIN__RESULT
    movff PULSE_RCIN__N+1, PULSE_RCIN__RESULT+1
    return
    ; Sub/Function PinOk
PINIO_PINOK:
    movwf PINIO_PINOK__PIN, c
    movlw 0x18
    subwf PINIO_PINOK__PIN, w, c
    movlw 0
    btfss STATUS, 0, c
    movlw 1
    movwf PINIO_PINOK__RESULT, c
    return
    ; Sub/Function PinInput
PINIO_PININPUT:
    movwf PINIO_PININPUT__PIN, c
    andlw 0x07
    movwf __D1, c
    movlw 0x01
    movwf __A0, c
    call __shl1
    movf __A0, w, c
    movwf PINIO_PININPUT__M, c
    movlw 0x08
    subwf PINIO_PININPUT__PIN, w, c
    bc _L725
    movf PINIO_PININPUT__M, w, c
    xorlw 0xFF
    movlb 15
    andwf ANSELA, f, b
    movf PINIO_PININPUT__M, w, c
    iorwf TRISA, f, c
    return
_L725:
    movlw 0x10
    subwf PINIO_PININPUT__PIN, w, c
    bc _L726
    movf PINIO_PININPUT__M, w, c
    xorlw 0xFF
    movlb 15
    andwf ANSELB, f, b
    movf PINIO_PININPUT__M, w, c
    iorwf TRISB, f, c
    return
_L726:
    movlw 0x18
    subwf PINIO_PININPUT__PIN, w, c
    bc _L727
    movf PINIO_PININPUT__M, w, c
    xorlw 0xFF
    movlb 15
    andwf ANSELC, f, b
    movf PINIO_PININPUT__M, w, c
    iorwf TRISC, f, c
_L727:
    return
    ; Sub/Function Zero
X10_ZERO:
    movwf X10_ZERO__ZPIN, c
    clrf X10_ZERO__N, c
    clrf X10_ZERO__N+1, c
    clrf X10_ZERO__RESULT, c
    bra _L729
_L728:
    movlw 53
    movwf __D0, c
_L731:
    decfsz __D0, f, c
    bra _L731
    infsnz X10_ZERO__N, f, c
    incf X10_ZERO__N+1, f, c
    movlw 0x89
    subwf X10_ZERO__N, w, c
    movlw 0x13
    subwfb X10_ZERO__N+1, w, c
    bnc _L733
    return
_L733:
_L729:
    movlw 0x09
    rcall PINIO_PINGET
    movf PINIO_PINGET__RESULT, w, c
    bz _L728
    clrf X10_ZERO__N, c
    clrf X10_ZERO__N+1, c
    bra _L735
_L734:
    movlw 53
    movwf __D0, c
_L737:
    decfsz __D0, f, c
    bra _L737
    infsnz X10_ZERO__N, f, c
    incf X10_ZERO__N+1, f, c
    movlw 0x89
    subwf X10_ZERO__N, w, c
    movlw 0x13
    subwfb X10_ZERO__N+1, w, c
    bnc _L739
    return
_L739:
_L735:
    movlw 0x09
    rcall PINIO_PINGET
    movf PINIO_PINGET__RESULT, w, c
    bnz _L734
    movlw 0x89
    subwf X10_ZERO__N, w, c
    movlw 0x13
    subwfb X10_ZERO__N+1, w, c
    movlw 0
    btfss STATUS, 0, c
    movlw 1
    movwf X10_ZERO__RESULT, c
    return
    ; Sub/Function PinGet
PINIO_PINGET:
    movwf PINIO_PINGET__PIN, c
            clrf PINIO_PINGET__RESULT, c
            movf PINIO_PINGET__PIN, w, c
            sublw 23
            bnc PINIO_PINGET_END
            lfsr 0, PORTA
            rrncf PINIO_PINGET__PIN, w, c
            rrncf WREG, w, c
            rrncf WREG, w, c
            andlw 3
            addwf FSR0L, f, c
            movlw 7
            andwf PINIO_PINGET__PIN, f, c
            movlw 1
    PINIO_PINGET_SHL:
            decf PINIO_PINGET__PIN, f, c
            bnc PINIO_PINGET_GOT
            rlncf WREG, w, c
            bra PINIO_PINGET_SHL
    PINIO_PINGET_GOT:
            andwf INDF0, w, c
            bz PINIO_PINGET_END
            incf PINIO_PINGET__RESULT, f, c
    PINIO_PINGET_END:
    return
    ; Sub/Function NumberOf
X10_NUMBEROF:
    movwf X10_NUMBEROF__CODE, c
    clrf X10_NUMBEROF__RESULT, c
    clrf X10_NUMBEROF__I, c
_L742:
    movf X10_NUMBEROF__I, w, c
    rcall X10_CODEOF
    xorwf X10_NUMBEROF__CODE, w, c
    bnz _L746
    movff X10_NUMBEROF__I, X10_NUMBEROF__RESULT
_L746:
    movf X10_NUMBEROF__I, w, c
    incf X10_NUMBEROF__I, f, c
    xorlw 0x0F
    bnz _L742
    movf X10_NUMBEROF__RESULT, w, c
    return
    ; Sub/Function CodeOf
X10_CODEOF:
    movwf X10_CODEOF__N, c
    movlw 0x0F
    andwf X10_CODEOF__N, f, c
    movlw 0x08
    subwf X10_CODEOF__N, w, c
    bc _L748
    movlw 0xE6
    movwf X10_CODEOF__T, c
    movlw 0xA2
    movwf X10_CODEOF__T+1, c
    movlw 0x91
    movwf X10_CODEOF__T+2, c
    movlw 0xD5
    movwf X10_CODEOF__T+3, c
    bra _L747
_L748:
    movlw 0xF7
    movwf X10_CODEOF__T, c
    movlw 0xB3
    movwf X10_CODEOF__T+1, c
    movlw 0x80
    movwf X10_CODEOF__T+2, c
    movlw 0xC4
    movwf X10_CODEOF__T+3, c
    movlw 0x08
    subwf X10_CODEOF__N, f, c
_L747:
    movf X10_CODEOF__N, w, c
    mullw 0x04
    movf PRODL, w, c
    movwf __D1, c
    movff X10_CODEOF__T, __A0
    movff X10_CODEOF__T+1, __A0+1
    movff X10_CODEOF__T+2, __A0+2
    movff X10_CODEOF__T+3, __A0+3
    call __shr4
    movf __A0, w, c
    andlw 0x0F
    movwf X10_CODEOF__RESULT, c
    return
    ; Sub/Function PinSet
PINIO_PINSET:
            movf PINIO_PINSET__PIN, w, c
            sublw 23
            bnc PINIO_PINSET_END
            lfsr 0, LATA
            rrncf PINIO_PINSET__PIN, w, c
            rrncf WREG, w, c
            rrncf WREG, w, c
            andlw 3
            addwf FSR0L, f, c
            movlw 7
            andwf PINIO_PINSET__PIN, f, c
            movlw 1
    PINIO_PINSET_SHL:
            decf PINIO_PINSET__PIN, f, c
            bnc PINIO_PINSET_GOT
            rlncf WREG, w, c
            bra PINIO_PINSET_SHL
    PINIO_PINSET_GOT:
            tstfsz PINIO_PINSET__LEVEL, c
            bra PINIO_PINSET_HI
            comf WREG, w, c
            andwf INDF0, f, c
            bra PINIO_PINSET_END
    PINIO_PINSET_HI:
            iorwf INDF0, f, c
    PINIO_PINSET_END:
    return
    ; Sub/Function PinOutput
PINIO_PINOUTPUT:
    movwf PINIO_PINOUTPUT__PIN, c
    andlw 0x07
    movwf __D1, c
    movlw 0x01
    movwf __A0, c
    call __shl1
    movf __A0, w, c
    xorlw 0xFF
    movwf PINIO_PINOUTPUT__N, c
    movlw 0x08
    subwf PINIO_PINOUTPUT__PIN, w, c
    bc _L750
    movf PINIO_PINOUTPUT__N, w, c
    movlb 15
    andwf ANSELA, f, b
    andwf TRISA, f, c
    return
_L750:
    movlw 0x10
    subwf PINIO_PINOUTPUT__PIN, w, c
    bc _L751
    movf PINIO_PINOUTPUT__N, w, c
    movlb 15
    andwf ANSELB, f, b
    andwf TRISB, f, c
    return
_L751:
    movlw 0x18
    subwf PINIO_PINOUTPUT__PIN, w, c
    bc _L752
    movf PINIO_PINOUTPUT__N, w, c
    movlb 15
    andwf ANSELC, f, b
    andwf TRISC, f, c
_L752:
    return
    ; Sub/Function Half
X10_HALF:
    rcall X10_ZERO
    movf X10_ZERO__RESULT, w, c
    movwf X10_HALF__RESULT, c
    bz _L772
    movf X10_HALF__BURST, f, c
    bz _L772
    movlw 0x08
    movwf PINIO_PINSET__PIN, c
    movlw 0x01
    movwf PINIO_PINSET__LEVEL, c
    rcall PINIO_PINSET
    clrf __D0, c
_L773:
    movlw 19
    movwf __D1, c
_L774:
    decfsz __D1, f, c
    bra _L774
    nop
    decfsz __D0, f, c
    bra _L773
    movlw 42
    movwf __D0, c
_L775:
    decfsz __D0, f, c
    bra _L775
    nop
    movlw 0x08
    movwf PINIO_PINSET__PIN, c
    clrf PINIO_PINSET__LEVEL, c
    rcall PINIO_PINSET
_L772:
    return
    ; Sub/Function SendBit
X10_SENDBIT:
    movff X10_SENDBIT__B, X10_HALF__BURST
    rcall X10_HALF
    movf X10_HALF__RESULT, w, c
    bz _L776
    movf X10_SENDBIT__B, w, c
    xorlw 1
    movwf X10_HALF__BURST, c
    rcall X10_HALF
    movf X10_HALF__RESULT, w, c
    bz _L776
    movlw 1
    bra _L777
_L776:
    movlw 0
_L777:
    movwf X10_SENDBIT__RESULT, c
    return
    ; Sub/Function Width
IRREMOTE_WIDTH:
    clrf IRREMOTE_WIDTH__N, c
    clrf IRREMOTE_WIDTH__N+1, c
    bra _L779
_L778:
    movf IRREMOTE_WIDTH__N, w, c
    subwf IRREMOTE_WIDTH__LIMIT, w, c
    movf IRREMOTE_WIDTH__N+1, w, c
    subwfb IRREMOTE_WIDTH__LIMIT+1, w, c
    bc _L782
    movff IRREMOTE_WIDTH__N, IRREMOTE_WIDTH__RESULT
    movff IRREMOTE_WIDTH__N+1, IRREMOTE_WIDTH__RESULT+1
    return
_L782:
    movlw 53
    movwf __D0, c
_L783:
    decfsz __D0, f, c
    bra _L783
    infsnz IRREMOTE_WIDTH__N, f, c
    incf IRREMOTE_WIDTH__N+1, f, c
_L779:
    movlw 0x09
    rcall PINIO_PINGET
    movf PINIO_PINGET__RESULT, w, c
    xorwf IRREMOTE_WIDTH__LEVEL, w, c
    bz _L778
    movff IRREMOTE_WIDTH__N, IRREMOTE_WIDTH__RESULT
    movff IRREMOTE_WIDTH__N+1, IRREMOTE_WIDTH__RESULT+1
    return
    ; Sub/Function WaitUs
PULSE_WAITUS:
    bra _L785
_L784:
    clrf __D0, c
_L787:
    bra _L788
_L788:
    nop
    decfsz __D0, f, c
    bra _L787
    movlw 21
    movwf __D0, c
_L789:
    decfsz __D0, f, c
    bra _L789
    movlw 0x64
    subwf PULSE_WAITUS__US, f, c
    movlw 0x00
    subwfb PULSE_WAITUS__US+1, f, c
_L785:
    movlw 0x64
    subwf PULSE_WAITUS__US, w, c
    movlw 0x00
    subwfb PULSE_WAITUS__US+1, w, c
    bc _L784
    bra _L791
_L790:
    movlw 53
    movwf __D0, c
_L793:
    decfsz __D0, f, c
    bra _L793
    movlw 0x0A
    subwf PULSE_WAITUS__US, f, c
    movlw 0x00
    subwfb PULSE_WAITUS__US+1, f, c
_L791:
    movlw 0x0A
    subwf PULSE_WAITUS__US, w, c
    movlw 0x00
    subwfb PULSE_WAITUS__US+1, w, c
    bc _L790
    bra _L795
_L794:
    movlw 5
    movwf __D0, c
_L797:
    decfsz __D0, f, c
    bra _L797
    decf PULSE_WAITUS__US, f, c
    btfss STATUS, 0, c
    decf PULSE_WAITUS__US+1, f, c
_L795:
    movf PULSE_WAITUS__US, w, c
    iorwf PULSE_WAITUS__US+1, w, c
    bnz _L794
    return
    ; Sub/Function BindData
PINIO_BINDDATA:
    movwf PINIO_BINDDATA__PIN, c
    rcall PINIO_PINADDR
    movff PINIO_PINADDR__RESULT, PINIO_DADDR
    movff PINIO_PINADDR__RESULT+1, PINIO_DADDR+1
    movf PINIO_BINDDATA__PIN, w, c
    andlw 0x07
    movwf __D1, c
    movlw 0x01
    movwf __A0, c
    call __shl1
    movf __A0, w, c
    movlb 0
    movwf PINIO_DMASK, b
    return
    ; Sub/Function DataPut
PINIO_DATAPUT:
    movwf PINIO_DATAPUT__LEVEL, c
            movff PINIO_DADDR, FSR0L
            movff PINIO_DADDR+1, FSR0H
            movf PINIO_DMASK, w, c
            tstfsz PINIO_DATAPUT__LEVEL, c
            bra PINIO_DATAPUT_HI
            comf WREG, w, c
            andwf INDF0, f, c
            bra PINIO_DATAPUT_END
    PINIO_DATAPUT_HI:
            iorwf INDF0, f, c
    PINIO_DATAPUT_END:
    return
    ; Sub/Function ClkPut
PINIO_CLKPUT:
    movwf PINIO_CLKPUT__LEVEL, c
            movff PINIO_CADDR, FSR0L
            movff PINIO_CADDR+1, FSR0H
            movf PINIO_CMASK, w, c
            tstfsz PINIO_CLKPUT__LEVEL, c
            bra PINIO_CLKPUT_HI
            comf WREG, w, c
            andwf INDF0, f, c
            bra PINIO_CLKPUT_END
    PINIO_CLKPUT_HI:
            iorwf INDF0, f, c
    PINIO_CLKPUT_END:
    return
    ; Sub/Function PinAddr
PINIO_PINADDR:
    movwf PINIO_PINADDR__PIN, c
            clrf PINIO_PINADDR__RESULT, c
            clrf PINIO_PINADDR__RESULT+1, c
            movf PINIO_PINADDR__PIN, w, c
            sublw 23
            bnc PINIO_PINADDR_END
            rrncf PINIO_PINADDR__PIN, w, c
            rrncf WREG, w, c
            rrncf WREG, w, c
            andlw 3
            addlw low LATA
            movwf PINIO_PINADDR__RESULT, c
            movlw high LATA
            movwf PINIO_PINADDR__RESULT+1, c
    PINIO_PINADDR_END:
    return
    ; Sub/Function DataRead
PINIO_DATAREAD:
            clrf PINIO_DATAREAD__RESULT, c
            movlw PORTA - LATA
            addwf PINIO_DADDR, w, c
            movwf FSR0L, c
            movff PINIO_DADDR+1, FSR0H
            movf PINIO_DMASK, w, c
            andwf INDF0, w, c
            bz PINIO_DATAREAD_END
            incf PINIO_DATAREAD__RESULT, f, c
    PINIO_DATAREAD_END:
    return
    ; Sub/Function WriteBlock
RTCCSPI_WRITEBLOCK:
    movlw 0x04
    movwf RTCCSPI_WRITEBLOCK__RESULT, c
    movf RTCCSPI_READY, f, c
    bnz _L807
    return
_L807:
    movff RTCCSPI_CSPIN, PINIO_PINSET__PIN
    clrf PINIO_PINSET__LEVEL, c
    rcall PINIO_PINSET
    movf RTCCSPI_WRITEBLOCK__C, w, c
    rcall SPI_SPIWRITE
    movf RTCCSPI_WRITEBLOCK__A, w, c
    rcall SPI_SPIWRITE
    clrf RTCCSPI_WRITEBLOCK__I, c
    bra _L809
_L808:
    movf RTCCSPI_WRITEBLOCK__I, w, c
    lfsr 0, RTCCSPI_BUF
    movf PLUSW0, w, c
    rcall SPI_SPIWRITE
    incf RTCCSPI_WRITEBLOCK__I, f, c
_L809:
    movf RTCCSPI_WRITEBLOCK__N, w, c
    subwf RTCCSPI_WRITEBLOCK__I, w, c
    bnc _L808
    rcall SPI_SPISTATUS
    movf SPI_SPISTATUS__RESULT, w, c
    movwf RTCCSPI_WRITEBLOCK__RESULT, c
    movff RTCCSPI_CSPIN, PINIO_PINSET__PIN
    movlw 0x01
    movwf PINIO_PINSET__LEVEL, c
    bra PINIO_PINSET
    ; Sub/Function RdReg
RTCCSPI_RDREG:
    movwf RTCCSPI_RDREG__REG, c
    movff RTCCSPI_RDREG__REG, RTCCSPI_READBLOCK__A
    movlw 0x01
    movwf RTCCSPI_READBLOCK__N, c
    rcall RTCCSPI_READBLOCK
    movf RTCCSPI_READBLOCK__RESULT, w, c
    movwf RTCCSPI_RDREG__RESULT, c
    return
    ; Sub/Function ToBcd
RTCCSPI_TOBCD:
    movwf RTCCSPI_TOBCD__V, c
    mullw 205
    rrncf PRODH, w, c
    rrncf WREG, w, c
    rrncf WREG, w, c
    andlw 0x1F
    mullw 16
    movf PRODL, w, c
    movwf RTCCSPI_TOBCD__TMP, c
    movf RTCCSPI_TOBCD__V, w, c
    mullw 205
    rrncf PRODH, w, c
    rrncf WREG, w, c
    rrncf WREG, w, c
    andlw 0x1F
    mullw 10
    movf PRODL, w, c
    subwf RTCCSPI_TOBCD__V, w, c
    iorwf RTCCSPI_TOBCD__TMP, w, c
    movwf RTCCSPI_TOBCD__RESULT, c
    return
    ; Sub/Function ReadBlock
RTCCSPI_READBLOCK:
    movlw 0x04
    movwf RTCCSPI_READBLOCK__RESULT, c
    movf RTCCSPI_READY, f, c
    bnz _L833
    return
_L833:
    movff RTCCSPI_CSPIN, PINIO_PINSET__PIN
    clrf PINIO_PINSET__LEVEL, c
    rcall PINIO_PINSET
    movlw 0x13
    call SPI_SPIWRITE
    movf RTCCSPI_READBLOCK__A, w, c
    call SPI_SPIWRITE
    clrf RTCCSPI_READBLOCK__I, c
    bra _L835
_L834:
    call SPI_SPIREAD
    movf RTCCSPI_READBLOCK__I, w, c
    lfsr 0, RTCCSPI_BUF
    movff SPI_SPIREAD__RESULT, PLUSW0
    incf RTCCSPI_READBLOCK__I, f, c
_L835:
    movf RTCCSPI_READBLOCK__N, w, c
    subwf RTCCSPI_READBLOCK__I, w, c
    bnc _L834
    call SPI_SPISTATUS
    movf SPI_SPISTATUS__RESULT, w, c
    movwf RTCCSPI_READBLOCK__RESULT, c
    movff RTCCSPI_CSPIN, PINIO_PINSET__PIN
    movlw 0x01
    movwf PINIO_PINSET__LEVEL, c
    bra PINIO_PINSET
    ; Sub/Function WrReg
RTCCSPI_WRREG:
    movff RTCCSPI_WRREG__V, RTCCSPI_BUF
    movlw 0x12
    movwf RTCCSPI_WRITEBLOCK__C, c
    movff RTCCSPI_WRREG__REG, RTCCSPI_WRITEBLOCK__A
    movlw 0x01
    movwf RTCCSPI_WRITEBLOCK__N, c
    rcall RTCCSPI_WRITEBLOCK
    movf RTCCSPI_WRITEBLOCK__RESULT, w, c
    movwf RTCCSPI_WRREG__RESULT, c
    return
    ; Sub/Function WriteBlock
RTCC_WRITEBLOCK:
    movff RTCC_WRITEBLOCK__CTL, RTCC_OPEN__CTL
    movff RTCC_WRITEBLOCK__REG, RTCC_OPEN__REG
    rcall RTCC_OPEN
    movf RTCC_OPEN__RESULT, w, c
    movwf RTCC_WRITEBLOCK__RESULT, c
    clrf RTCC_WRITEBLOCK__I, c
    bra _L853
_L852:
    movf RTCC_WRITEBLOCK__I, w, c
    lfsr 0, I2C_I2CBUF
    movf PLUSW0, w, c
    call I2C_I2CSEND
    movf I2C_I2CSEND__RESULT, w, c
    movwf RTCC_WRITEBLOCK__RESULT, c
    incf RTCC_WRITEBLOCK__I, f, c
_L853:
    movf RTCC_WRITEBLOCK__RESULT, f, c
    bnz _L855
    movf RTCC_WRITEBLOCK__N, w, c
    subwf RTCC_WRITEBLOCK__I, w, c
    bnc _L852
_L855:
    call I2C_I2CSTOP
    movlb 0
    movwf RTCC_WRITEBLOCK__S, b
    movf RTCC_WRITEBLOCK__RESULT, f, c
    bnz _L857
    movff RTCC_WRITEBLOCK__S, RTCC_WRITEBLOCK__RESULT
_L857:
    return
    ; Sub/Function Open
RTCC_OPEN:
    call I2C_I2CSTART
    movf I2C_I2CSTART__RESULT, w, c
    movwf RTCC_OPEN__RESULT, c
    bnz _L859
    movf RTCC_OPEN__CTL, w, c
    call I2C_I2CSEND
    movf I2C_I2CSEND__RESULT, w, c
    movwf RTCC_OPEN__RESULT, c
_L859:
    movf RTCC_OPEN__RESULT, f, c
    bnz _L861
    movf RTCC_OPEN__REG, w, c
    call I2C_I2CSEND
    movf I2C_I2CSEND__RESULT, w, c
    movwf RTCC_OPEN__RESULT, c
_L861:
    return
    ; Sub/Function RdReg
RTCC_RDREG:
    movwf RTCC_RDREG__REG, c
    movff RTCC_RDREG__REG, RTCC_READBLOCK__REG
    movlw 0x01
    movwf RTCC_READBLOCK__N, c
    rcall RTCC_READBLOCK
    movf RTCC_READBLOCK__RESULT, w, c
    movwf RTCC_RDREG__RESULT, c
    return
    ; Sub/Function ToBcd
RTCC_TOBCD:
    movwf RTCC_TOBCD__V, c
    mullw 205
    rrncf PRODH, w, c
    rrncf WREG, w, c
    rrncf WREG, w, c
    andlw 0x1F
    mullw 16
    movf PRODL, w, c
    movwf RTCC_TOBCD__TMP, c
    movf RTCC_TOBCD__V, w, c
    mullw 205
    rrncf PRODH, w, c
    rrncf WREG, w, c
    rrncf WREG, w, c
    andlw 0x1F
    mullw 10
    movf PRODL, w, c
    subwf RTCC_TOBCD__V, w, c
    iorwf RTCC_TOBCD__TMP, w, c
    movwf RTCC_TOBCD__RESULT, c
    return
    ; Sub/Function ReadBlock
RTCC_READBLOCK:
    movlw 0xDE
    movwf RTCC_OPEN__CTL, c
    movff RTCC_READBLOCK__REG, RTCC_OPEN__REG
    rcall RTCC_OPEN
    movf RTCC_OPEN__RESULT, w, c
    movwf RTCC_READBLOCK__RESULT, c
    bnz _L869
    call I2C_I2CRESTART
    movf I2C_I2CRESTART__RESULT, w, c
    movwf RTCC_READBLOCK__RESULT, c
_L869:
    movf RTCC_READBLOCK__RESULT, f, c
    bnz _L871
    movlw 0xDF
    call I2C_I2CSEND
    movf I2C_I2CSEND__RESULT, w, c
    movwf RTCC_READBLOCK__RESULT, c
_L871:
    clrf RTCC_READBLOCK__I, c
    bra _L873
_L872:
    decf RTCC_READBLOCK__N, w, c
    subwf RTCC_READBLOCK__I, w, c
    movlw 0
    btfss STATUS, 0, c
    movlw 1
    call I2C_I2CRECEIVE
    movf RTCC_READBLOCK__I, w, c
    lfsr 0, I2C_I2CBUF
    movff I2C_I2CRECEIVE__RESULT, PLUSW0
    call I2C_I2CSTATUS
    movwf RTCC_READBLOCK__RESULT, c
    incf RTCC_READBLOCK__I, f, c
_L873:
    movf RTCC_READBLOCK__RESULT, f, c
    bnz _L877
    movf RTCC_READBLOCK__N, w, c
    subwf RTCC_READBLOCK__I, w, c
    bnc _L872
_L877:
    call I2C_I2CSTOP
    movf RTCC_READBLOCK__RESULT, f, c
    bnz _L879
    movff I2C_I2CSTOP__RESULT, RTCC_READBLOCK__RESULT
_L879:
    return
    ; Sub/Function WrReg
RTCC_WRREG:
    movff RTCC_WRREG__V, I2C_I2CBUF
    movlw 0xDE
    movwf RTCC_WRITEBLOCK__CTL, c
    movff RTCC_WRREG__REG, RTCC_WRITEBLOCK__REG
    movlw 0x01
    movwf RTCC_WRITEBLOCK__N, c
    rcall RTCC_WRITEBLOCK
    movf RTCC_WRITEBLOCK__RESULT, w, c
    movwf RTCC_WRREG__RESULT, c
    return
    ; Sub/Function Begin
OLED_BEGIN:
    movwf OLED_BEGIN__ISDATA, c
    decf OLED_MODE, w, c
    bnz _L889
    call I2C_I2CSTART
    movf I2C_I2CSTART__RESULT, w, c
    movwf OLED_BEGIN__S, c
    bnz _L891
    movlb 0
    movf OLED_ADDR7, w, b
    addwf WREG, w, c
    call I2C_I2CSEND
    movf I2C_I2CSEND__RESULT, w, c
    movwf OLED_BEGIN__S, c
_L891:
    movf OLED_BEGIN__S, f, c
    bnz _L893
    clrf OLED_BEGIN__S, c
    movf OLED_BEGIN__ISDATA, f, c
    bz _L895
    movlw 0x40
    movwf OLED_BEGIN__S, c
_L895:
    movf OLED_BEGIN__S, w, c
    call I2C_I2CSEND
    movf I2C_I2CSEND__RESULT, w, c
    movwf OLED_BEGIN__S, c
_L893:
    movf OLED_BEGIN__S, f, c
    bz _L888
    movf OLED_ERR, f, c
    bnz _L888
    movff OLED_BEGIN__S, OLED_ERR
    return
_L889:
    movf OLED_MODE, w, c
    xorlw 0x02
    bnz _L898
    movff OLED_PDC, PINIO_PINSET__PIN
    movff OLED_BEGIN__ISDATA, PINIO_PINSET__LEVEL
    rcall PINIO_PINSET
    incf OLED_PCS, w, c
    bz _L900
    movff OLED_PCS, PINIO_PINSET__PIN
    clrf PINIO_PINSET__LEVEL, c
    rcall PINIO_PINSET
_L900:
_L898:
_L888:
    return
    ; Sub/Function Put
OLED_PUT:
    movwf OLED_PUT__B, c
    decf OLED_MODE, w, c
    bnz _L902
    movf OLED_ERR, f, c
    bnz _L901
    movf OLED_PUT__B, w, c
    call I2C_I2CSEND
    movf I2C_I2CSEND__RESULT, w, c
    bz _L901
    movff I2C_I2CSEND__RESULT, OLED_ERR
    return
_L902:
    movf OLED_MODE, w, c
    xorlw 0x02
    bnz _L907
    movf OLED_PUT__B, w, c
    call SPI_SPIWRITE
_L907:
_L901:
    return
    ; Sub/Function Finish
OLED_FINISH:
    decf OLED_MODE, w, c
    bnz _L909
    call I2C_I2CSTOP
    movf I2C_I2CSTOP__RESULT, w, c
    bz _L908
    movf OLED_ERR, f, c
    bnz _L908
    movff I2C_I2CSTOP__RESULT, OLED_ERR
    return
_L909:
    movf OLED_MODE, w, c
    xorlw 0x02
    bnz _L912
    incf OLED_PCS, w, c
    bz _L914
    movff OLED_PCS, PINIO_PINSET__PIN
    movlw 0x01
    movwf PINIO_PINSET__LEVEL, c
    rcall PINIO_PINSET
_L914:
_L912:
_L908:
    return
    ; Sub/Function Cmd
OLED_CMD:
    movf OLED_MODE, f, c
    bnz _L916
    return
_L916:
    movlw 0x00
    rcall OLED_BEGIN
    movf OLED_CMD__C, w, c
    rcall OLED_PUT
    movlw 0x02
    subwf OLED_CMD__N, w, c
    bnc _L918
    movf OLED_CMD__A, w, c
    rcall OLED_PUT
_L918:
    movlw 0x03
    subwf OLED_CMD__N, w, c
    bnc OLED_FINISH
    movf OLED_CMD__B, w, c
    rcall OLED_PUT
    bra OLED_FINISH
    ; Sub/Function Reset
OLED_RESET:
    movwf OLED_RESET__RES, c
    addlw 0x01
    bz _L922
    movff OLED_RESET__RES, PINIO_PINSET__PIN
    clrf PINIO_PINSET__LEVEL, c
    rcall PINIO_PINSET
    movf OLED_RESET__RES, w, c
    rcall PINIO_PINOUTPUT
    movlw 53
    movwf __D0, c
_L923:
    decfsz __D0, f, c
    bra _L923
    movff OLED_RESET__RES, PINIO_PINSET__PIN
    movlw 0x01
    movwf PINIO_PINSET__LEVEL, c
    rcall PINIO_PINSET
    clrf __D0, c
_L924:
    movlw 102
    movwf __D1, c
_L925:
    decfsz __D1, f, c
    bra _L925
    bra _L926
_L926:
    decfsz __D0, f, c
    bra _L924
    movlw 42
    movwf __D0, c
_L927:
    decfsz __D0, f, c
    bra _L927
    nop
_L922:
    return
    ; Sub/Function Setup
OLED_SETUP:
    movlw 0x02
    movwf OLED_CMD__N, c
    movlw 0xFD
    movwf OLED_CMD__C, c
    movlw 0x12
    movwf OLED_CMD__A, c
    clrf OLED_CMD__B, c
    rcall OLED_CMD
    movlw 0x01
    movwf OLED_CMD__N, c
    movlw 0xAE
    movwf OLED_CMD__C, c
    clrf OLED_CMD__A, c
    clrf OLED_CMD__B, c
    rcall OLED_CMD
    movlw 0x02
    movwf OLED_CMD__N, c
    movlw 0x20
    movwf OLED_CMD__C, c
    clrf OLED_CMD__A, c
    clrf OLED_CMD__B, c
    rcall OLED_CMD
    movlw 0x03
    movwf OLED_CMD__N, c
    movlw 0x21
    movwf OLED_CMD__C, c
    clrf OLED_CMD__A, c
    movlw 0x7F
    movwf OLED_CMD__B, c
    rcall OLED_CMD
    movlw 0x03
    movwf OLED_CMD__N, c
    movlw 0x22
    movwf OLED_CMD__C, c
    clrf OLED_CMD__A, c
    movlw 0x07
    movwf OLED_CMD__B, c
    rcall OLED_CMD
    movlw 0x01
    movwf OLED_CMD__N, c
    movlw 0xA4
    movwf OLED_CMD__C, c
    clrf OLED_CMD__A, c
    clrf OLED_CMD__B, c
    rcall OLED_CMD
    movlw 0x01
    movwf OLED_CMD__N, c
    movlw 0xA6
    movwf OLED_CMD__C, c
    clrf OLED_CMD__A, c
    clrf OLED_CMD__B, c
    rcall OLED_CMD
    call OLED_OLEDFILL
    movlw 0x01
    movwf OLED_CMD__N, c
    movlw 0xAF
    movwf OLED_CMD__C, c
    clrf OLED_CMD__A, c
    clrf OLED_CMD__B, c
    bra OLED_CMD
    ; Sub/Function Send
LCD_SEND:
    movff LCD_PINS, PINIO_PINSET__PIN
    movff LCD_SEND__RS, PINIO_PINSET__LEVEL
    rcall PINIO_PINSET
    movf LCD_SEND__B, w, c
    swapf WREG, w, c
    andlw 0x0F
    rcall LCD_NIBBLE
    movf LCD_SEND__B, w, c
    andlw 0x0F
    rcall LCD_NIBBLE
    clrf __D0, c
_L928:
    decfsz __D0, f, c
    bra _L928
    movlw 10
    movwf __D0, c
_L929:
    decfsz __D0, f, c
    bra _L929
    nop
    return
    ; Sub/Function Nibble
LCD_NIBBLE:
    movwf LCD_NIBBLE__NIB, c
    movlw 0x02
    movwf LCD_NIBBLE__I, c
_L930:
    movf LCD_NIBBLE__I, w, c
    lfsr 0, LCD_PINS
    movf PLUSW0, w, c
    movwf PINIO_PINSET__PIN, c
    movlw 0
    btfsc LCD_NIBBLE__NIB, 0, c
    movlw 1
    movwf PINIO_PINSET__LEVEL, c
    rcall PINIO_PINSET
    bcf STATUS, 0, c
    rrcf LCD_NIBBLE__NIB, f, c
    movf LCD_NIBBLE__I, w, c
    incf LCD_NIBBLE__I, f, c
    xorlw 0x05
    bnz _L930
    movff LCD_PINS+1, PINIO_PINSET__PIN
    movlw 0x01
    movwf PINIO_PINSET__LEVEL, c
    rcall PINIO_PINSET
    movlw 5
    movwf __D0, c
_L936:
    decfsz __D0, f, c
    bra _L936
    movff LCD_PINS+1, PINIO_PINSET__PIN
    clrf PINIO_PINSET__LEVEL, c
    rcall PINIO_PINSET
    movlw 5
    movwf __D0, c
_L937:
    decfsz __D0, f, c
    bra _L937
    return
    ; Sub/Function PpsOff
SPI_PPSOFF:
    movwf SPI_PPSOFF__PIN, c
    clrf SPI_PPSOFF__SL, c
    clrf SPI_PPSOFF__SH, c
            movff FSR2L, SPI_PPSOFF__SL
            movff FSR2H, SPI_PPSOFF__SH
            lfsr 2, RA0PPS
            movf SPI_PPSOFF__PIN, w, c
            addwf FSR2L, f, c
            clrf INDF2, c
            movff SPI_PPSOFF__SL, FSR2L
            movff SPI_PPSOFF__SH, FSR2H
    return
    ; Sub/Function PinSetup
SPI_PINSETUP:
    movf SPI_PINSETUP__PIN, w, c
    andlw 0x07
    movwf __D1, c
    movlw 0x01
    movwf __A0, c
    rcall __shl1
    movf __A0, w, c
    movwf SPI_PINSETUP__M, c
    movlw 0x10
    subwf SPI_PINSETUP__PIN, w, c
    bc _L954
    movf SPI_PINSETUP__M, w, c
    xorlw 0xFF
    movlb 15
    andwf ANSELB, f, b
    movf SPI_PINSETUP__ASINPUT, f, c
    bz _L956
    movf SPI_PINSETUP__M, w, c
    iorwf TRISB, f, c
    return
_L956:
    movf SPI_PINSETUP__M, w, c
    xorlw 0xFF
    andwf TRISB, f, c
    return
_L954:
    movf SPI_PINSETUP__M, w, c
    xorlw 0xFF
    movlb 15
    andwf ANSELC, f, b
    movf SPI_PINSETUP__ASINPUT, f, c
    bz _L958
    movf SPI_PINSETUP__M, w, c
    iorwf TRISC, f, c
    return
_L958:
    movf SPI_PINSETUP__M, w, c
    xorlw 0xFF
    andwf TRISC, f, c
    return
    ; Sub/Function SetPps
SPI_SETPPS:
    movf PCL, w, c
    movf SPI_SETPPS__PIN, w, c
    sublw 0x17
    bnc _L959
    rlncf WREG, w, c
    addwf PCL, f, c
    bra _L980
    bra _L979
    bra _L978
    bra _L977
    bra _L976
    bra _L975
    bra _L974
    bra _L973
    bra _L972
    bra _L971
    bra _L970
    bra _L969
    bra _L968
    bra _L967
    bra _L966
    bra _L965
    bra _L959
    bra _L959
    bra _L964
    bra _L963
    bra _L959
    bra _L962
    bra _L961
    bra _L960
_L960:
    movf SPI_SETPPS__CODE, w, c
    movlb 14
    movwf RA0PPS, b
    return
_L961:
    movf SPI_SETPPS__CODE, w, c
    movlb 14
    movwf RA1PPS, b
    return
_L962:
    movf SPI_SETPPS__CODE, w, c
    movlb 14
    movwf RA2PPS, b
    return
_L963:
    movf SPI_SETPPS__CODE, w, c
    movlb 14
    movwf RA4PPS, b
    return
_L964:
    movf SPI_SETPPS__CODE, w, c
    movlb 14
    movwf RA5PPS, b
    return
_L965:
    movf SPI_SETPPS__CODE, w, c
    movlb 14
    movwf RB0PPS, b
    return
_L966:
    movf SPI_SETPPS__CODE, w, c
    movlb 14
    movwf RB1PPS, b
    return
_L967:
    movf SPI_SETPPS__CODE, w, c
    movlb 14
    movwf RB2PPS, b
    return
_L968:
    movf SPI_SETPPS__CODE, w, c
    movlb 14
    movwf RB3PPS, b
    return
_L969:
    movf SPI_SETPPS__CODE, w, c
    movlb 14
    movwf RB4PPS, b
    return
_L970:
    movf SPI_SETPPS__CODE, w, c
    movlb 14
    movwf RB5PPS, b
    return
_L971:
    movf SPI_SETPPS__CODE, w, c
    movlb 14
    movwf RB6PPS, b
    return
_L972:
    movf SPI_SETPPS__CODE, w, c
    movlb 14
    movwf RB7PPS, b
    return
_L973:
    movf SPI_SETPPS__CODE, w, c
    movlb 14
    movwf RC0PPS, b
    return
_L974:
    movf SPI_SETPPS__CODE, w, c
    movlb 14
    movwf RC1PPS, b
    return
_L975:
    movf SPI_SETPPS__CODE, w, c
    movlb 14
    movwf RC2PPS, b
    return
_L976:
    movf SPI_SETPPS__CODE, w, c
    movlb 14
    movwf RC3PPS, b
    return
_L977:
    movf SPI_SETPPS__CODE, w, c
    movlb 14
    movwf RC4PPS, b
    return
_L978:
    movf SPI_SETPPS__CODE, w, c
    movlb 14
    movwf RC5PPS, b
    return
_L979:
    movf SPI_SETPPS__CODE, w, c
    movlb 14
    movwf RC6PPS, b
    return
_L980:
    movf SPI_SETPPS__CODE, w, c
    movlb 14
    movwf RC7PPS, b
_L959:
    return
    ; Sub/Function SetPps
I2C_SETPPS:
    clrf I2C_SETPPS__SL, c
    clrf I2C_SETPPS__SH, c
            movff FSR2L, I2C_SETPPS__SL
            movff FSR2H, I2C_SETPPS__SH
            lfsr 2, RA0PPS
            movf I2C_SETPPS__PIN, w, c
            addwf FSR2L, f, c
            movf I2C_SETPPS__CODE, w, c
            movwf INDF2, c
            movff I2C_SETPPS__SL, FSR2L
            movff I2C_SETPPS__SH, FSR2H
    return
    ; Sub/Function Open
I2C_OPEN:
    call I2C_I2CSTART
    movf I2C_I2CSTART__RESULT, w, c
    movwf I2C_OPEN__RESULT, c
    bnz _L982
    movlw 0xA0
    call I2C_I2CSEND
    movf I2C_I2CSEND__RESULT, w, c
    movwf I2C_OPEN__RESULT, c
_L982:
    movf I2C_OPEN__RESULT, f, c
    bnz _L984
    movlw 0x01
    call I2C_I2CSEND
    movf I2C_I2CSEND__RESULT, w, c
    movwf I2C_OPEN__RESULT, c
_L984:
    return
    ; Sub/Function Condition
I2C_CONDITION:
    movwf I2C_CONDITION__MSK, c
    movlw 0x1F
    rcall I2C_WAITIDLE
    movf I2C_WAITIDLE__RESULT, w, c
    movwf I2C_CONDITION__RESULT, c
    bnz _L988
    movlb 14
    bcf PIR3, 0, b
    movf I2C_CONDITION__MSK, w, c
    iorwf SSP1CON2, f, c
    rcall I2C_WAITIDLE
    movf I2C_WAITIDLE__RESULT, w, c
    movwf I2C_CONDITION__RESULT, c
_L988:
    return
    ; Sub/Function WaitIdle
I2C_WAITIDLE:
    movwf I2C_WAITIDLE__MSK, c
    clrf I2C_WAITIDLE__N, c
    clrf I2C_WAITIDLE__N+1, c
    movlw 0x01
    movwf I2C_WAITIDLE__RESULT, c
    bra _L990
_L989:
    movlb 14
    btfss PIR3, 1, b
    bra _L993
    bcf PIR3, 1, b
    movlw 0x02
    movwf I2C_WAITIDLE__RESULT, c
    return
_L993:
    movf SSP1CON2, w, c
    andwf I2C_WAITIDLE__MSK, w, c
    bnz _L995
    clrf I2C_WAITIDLE__RESULT, c
    return
_L995:
    infsnz I2C_WAITIDLE__N, f, c
    incf I2C_WAITIDLE__N+1, f, c
_L990:
    movlw 0x60
    subwf I2C_WAITIDLE__N, w, c
    movlw 0xEA
    subwfb I2C_WAITIDLE__N+1, w, c
    bnc _L989
    return
    ; Sub/Function WaitIf
I2C_WAITIF:
    clrf I2C_WAITIF__N, c
    clrf I2C_WAITIF__N+1, c
    movlw 0x01
    movwf I2C_WAITIF__RESULT, c
    bra _L997
_L996:
    movlb 14
    btfss PIR3, 1, b
    bra _L1000
    bcf PIR3, 1, b
    movlw 0x02
    movwf I2C_WAITIF__RESULT, c
    return
_L1000:
    btfss PIR3, 0, b
    bra _L1002
    bcf PIR3, 0, b
    clrf I2C_WAITIF__RESULT, c
    return
_L1002:
    infsnz I2C_WAITIF__N, f, c
    incf I2C_WAITIF__N+1, f, c
_L997:
    movlw 0x60
    subwf I2C_WAITIF__N, w, c
    movlw 0xEA
    subwfb I2C_WAITIF__N+1, w, c
    bnc _L996
    return
    ; Sub/Function PinSetup
I2C_PINSETUP:
    movwf I2C_PINSETUP__PIN, c
    andlw 0x07
    movwf __D1, c
    movlw 0x01
    movwf __A0, c
    rcall __shl1
    movf __A0, w, c
    movwf I2C_PINSETUP__M, c
    movlw 0x10
    subwf I2C_PINSETUP__PIN, w, c
    bc _L1004
    movf I2C_PINSETUP__M, w, c
    iorwf TRISB, f, c
    xorlw 0xFF
    movlb 15
    andwf ANSELB, f, b
    return
_L1004:
    movf I2C_PINSETUP__M, w, c
    iorwf TRISC, f, c
    xorlw 0xFF
    movlb 15
    andwf ANSELC, f, b
    return
    ; Sub/Function SetCon
PWM_SETCON:
    decf PWM_SETCON__CH, w, c
    bnz _L1006
    movf PWM_SETCON__V, w, c
    movwf CCP1CON, c
    return
_L1006:
    movf PWM_SETCON__CH, w, c
    xorlw 0x02
    bnz _L1007
    movf PWM_SETCON__V, w, c
    movwf CCP2CON, c
    return
_L1007:
    xorlw 0x01
    bnz _L1008
    movf PWM_SETCON__V, w, c
    movwf PWM3CON, c
    return
_L1008:
    movf PWM_SETCON__V, w, c
    movwf PWM4CON, c
    return
    ; Sub/Function SetPps
PWM_SETPPS:
    clrf PWM_SETPPS__SL, c
    clrf PWM_SETPPS__SH, c
            movff FSR2L, PWM_SETPPS__SL
            movff FSR2H, PWM_SETPPS__SH
            lfsr 2, RA0PPS
            movf PWM_SETPPS__PIN, w, c
            addwf FSR2L, f, c
            movf PWM_SETPPS__CODE, w, c
            movwf INDF2, c
            movff PWM_SETPPS__SL, FSR2L
            movff PWM_SETPPS__SH, FSR2H
    return
    ; Sub/Function SetDuty
PWM_SETDUTY:
    movlw 4
    subwf PWM_SETDUTY__D+1, w, c
    bnc _L1010
    setf PWM_SETDUTY__D, c
    movlw 0x03
    movwf PWM_SETDUTY__D+1, c
_L1010:
    movf PWM_SETDUTY__D+1, w, c
    mullw 64
    movf PRODL, w, c
    movwf PWM_SETDUTY__TMP, c
    movf PWM_SETDUTY__D, w, c
    rrncf WREG, w, c
    rrncf WREG, w, c
    andlw 0x3F
    iorwf PWM_SETDUTY__TMP, w, c
    movwf PWM_SETDUTY__HI, c
    movf PWM_SETDUTY__D, w, c
    mullw 64
    movf PRODL, w, c
    movwf PWM_SETDUTY__LO, c
    decf PWM_SETDUTY__CH, w, c
    bnz _L1012
    movf PWM_SETDUTY__LO, w, c
    movwf CCPR1L, c
    movf PWM_SETDUTY__HI, w, c
    movwf CCPR1H, c
    return
_L1012:
    movf PWM_SETDUTY__CH, w, c
    xorlw 0x02
    bnz _L1013
    movf PWM_SETDUTY__LO, w, c
    movwf CCPR2L, c
    movf PWM_SETDUTY__HI, w, c
    movwf CCPR2H, c
    return
_L1013:
    xorlw 0x01
    bnz _L1014
    movf PWM_SETDUTY__LO, w, c
    movwf PWM3DCL, c
    movf PWM_SETDUTY__HI, w, c
    movwf PWM3DCH, c
    return
_L1014:
    movf PWM_SETDUTY__LO, w, c
    movwf PWM4DCL, c
    movf PWM_SETDUTY__HI, w, c
    movwf PWM4DCH, c
    return
    ; Sub/Function SetAddr
FLASHWRITE_SETADDR:
    movf FLASHWRITE_SETADDR__ADDR+1, w, c
    rlncf WREG, w, c
    andlw 0x01
    movwf NVMADRU, c
    movf FLASHWRITE_SETADDR__ADDR, w, c
    rlncf WREG, w, c
    andlw 0x01
    movwf FLASHWRITE_SETADDR__TMP, c
    movf FLASHWRITE_SETADDR__ADDR+1, w, c
    addwf WREG, w, c
    iorwf FLASHWRITE_SETADDR__TMP, w, c
    movwf NVMADRH, c
    movf FLASHWRITE_SETADDR__ADDR, w, c
    addwf WREG, w, c
    movwf NVMADRL, c
    return
    ; Sub/Function Convert
ADC_CONVERT:
    movlb 15
    bsf ADCON0, 0, b
_L1025:
    btfsc ADCON0, 0, b
    bra _L1025
    movff ADRESL, ADC_CONVERT__RESULT
    movff ADRESH, ADC_CONVERT__RESULT+1
    return
    ; Sub/Function SetClock
ADC_SETCLOCK:
    movlw 0x1F
    movlb 15
    movwf ADCLK, b
    movlw 0x05
    movwf ADACQ, b
    return
    ; Sub/Function Serial2WriteByte
SERIAL2_SERIAL2WRITEBYTE:
    movwf SERIAL2_SERIAL2WRITEBYTE__B, c
    movlb 14
_L1028:
    btfss PIR3, 6, b
    bra _L1028
    movf SERIAL2_SERIAL2WRITEBYTE__B, w, c
    movwf TX2REG, b
    return
    ; Sub/Function SerialWriteByte
SERIAL_SERIALWRITEBYTE:
    movwf SERIAL_SERIALWRITEBYTE__B, c
    movlb 14
_L1031:
    btfss PIR3, 4, b
    bra _L1031
    movf SERIAL_SERIALWRITEBYTE__B, w, c
    movwf TX1REG, c
    return
    ; helper div2
__div2:
    clrf __C0, c
    clrf __C1, c
    movlw 16
    movwf __D0, c
_L1034:
    bcf STATUS, 0, c
    rlcf __A0, f, c
    rlcf __A1, f, c
    rlcf __C0, f, c
    rlcf __C1, f, c
    movf __B0, w, c
    subwf __C0, f, c
    movf __B1, w, c
    subwfb __C1, f, c
    bc _L1035
    movf __B0, w, c
    addwf __C0, f, c
    movf __B1, w, c
    addwfc __C1, f, c
    bra _L1036
_L1035:
    bsf __A0, 0, c
_L1036:
    decfsz __D0, f, c
    bra _L1034
    return
    ; helper div4
__div4:
    clrf __C0, c
    clrf __C1, c
    clrf __C2, c
    clrf __C3, c
    movlw 32
    movwf __D0, c
_L1037:
    bcf STATUS, 0, c
    rlcf __A0, f, c
    rlcf __A1, f, c
    rlcf __A2, f, c
    rlcf __A3, f, c
    rlcf __C0, f, c
    rlcf __C1, f, c
    rlcf __C2, f, c
    rlcf __C3, f, c
    movf __B0, w, c
    subwf __C0, f, c
    movf __B1, w, c
    subwfb __C1, f, c
    movf __B2, w, c
    subwfb __C2, f, c
    movf __B3, w, c
    subwfb __C3, f, c
    bc _L1038
    movf __B0, w, c
    addwf __C0, f, c
    movf __B1, w, c
    addwfc __C1, f, c
    movf __B2, w, c
    addwfc __C2, f, c
    movf __B3, w, c
    addwfc __C3, f, c
    bra _L1039
_L1038:
    bsf __A0, 0, c
_L1039:
    decfsz __D0, f, c
    bra _L1037
    return
    ; helper shl1
__shl1:
    movf __D1, f, c
    bz _L1041
_L1040:
    bcf STATUS, 0, c
    rlcf __A0, f, c
    decfsz __D1, f, c
    bra _L1040
_L1041:
    return
    ; helper shl2
__shl2:
    movf __D1, f, c
    bz _L1043
_L1042:
    bcf STATUS, 0, c
    rlcf __A0, f, c
    rlcf __A1, f, c
    decfsz __D1, f, c
    bra _L1042
_L1043:
    return
    ; helper shr1
__shr1:
    movf __D1, f, c
    bz _L1045
_L1044:
    bcf STATUS, 0, c
    rrcf __A0, f, c
    decfsz __D1, f, c
    bra _L1044
_L1045:
    return
    ; helper shr4
__shr4:
    movf __D1, f, c
    bz _L1047
_L1046:
    bcf STATUS, 0, c
    rrcf __A3, f, c
    rrcf __A2, f, c
    rrcf __A1, f, c
    rrcf __A0, f, c
    decfsz __D1, f, c
    bra _L1046
_L1047:
    return
__CA0:
    db 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x5E, 0x00, 0x00, 0x00, 0x0E, 0x00, 0x0E, 0x00, 0x28, 0x7C, 0x28, 0x7C, 0x28, 0x08, 0x54, 0x7C, 0x54, 0x20, 0x26, 0x10, 0x08, 0x64, 0x00, 0x28, 0x54, 0x28, 0x40, 0x00, 0x00, 0x00, 0x0E, 0x00, 0x00, 0x00, 0x3C, 0x42, 0x00, 0x00, 0x00, 0x42, 0x3C, 0x00, 0x00, 0x00, 0x54, 0x38, 0x54, 0x00, 0x10, 0x10, 0x7C, 0x10, 0x10, 0x00, 0x80, 0x60, 0x20, 0x00, 0x10, 0x10, 0x10, 0x10, 0x00, 0x00, 0x60, 0x60, 0x00, 0x00, 0x20, 0x10, 0x08, 0x04, 0x00, 0x00, 0x3C, 0x42, 0x3C, 0x00, 0x00, 0x44, 0x7E, 0x40, 0x00, 0x44, 0x62, 0x52, 0x4C, 0x00, 0x22, 0x4A, 0x4A, 0x36, 0x00, 0x18, 0x14, 0x7E, 0x10, 0x00, 0x2E, 0x4A, 0x4A, 0x32, 0x00, 0x3C, 0x4A, 0x4A, 0x30, 0x00, 0x02, 0x62, 0x1A, 0x06, 0x00, 0x34, 0x4A, 0x4A, 0x34, 0x00, 0x0C, 0x52, 0x52, 0x3C, 0x00, 0x00, 0x6C, 0x6C, 0x00, 0x00, 0x80, 0x6C, 0x2C, 0x00, 0x00, 0x00, 0x10, 0x28, 0x44, 0x00, 0x28, 0x28, 0x28, 0x28, 0x00, 0x00, 0x44, 0x28, 0x10, 0x00, 0x00, 0x04, 0x52, 0x0C, 0x00, 0x3C, 0x42, 0x5A, 0x1C, 0x00, 0x7C, 0x12, 0x12, 0x7C, 0x00, 0x7E, 0x4A, 0x4A, 0x34, 0x00, 0x3C, 0x42, 0x42, 0x24, 0x00, 0x7E, 0x42, 0x42, 0x3C, 0x00, 0x7E, 0x4A, 0x4A, 0x42, 0x00, 0x7E, 0x0A, 0x0A, 0x02, 0x00, 0x3C, 0x42, 0x52, 0x74, 0x00, 0x7E, 0x08, 0x08, 0x7E, 0x00, 0x00, 0x42, 0x7E, 0x42, 0x00, 0x20, 0x40, 0x40, 0x3E, 0x00, 0x7E, 0x18, 0x24, 0x42, 0x00, 0x7E, 0x40, 0x40, 0x40, 0x00, 0x7E, 0x0C, 0x0C, 0x7E, 0x00, 0x7E, 0x0C, 0x30, 0x7E, 0x00, 0x3C, 0x42, 0x42, 0x3C, 0x00, 0x7E, 0x12, 0x12, 0x0C, 0x00, 0x3C, 0x62, 0x42, 0xBC, 0x00, 0x7E, 0x12, 0x32, 0x4C, 0x00, 0x24, 0x4A, 0x52, 0x24, 0x00, 0x00, 0x02, 0x7E, 0x02, 0x00, 0x3E, 0x40, 0x40, 0x3E, 0x00, 0x1E, 0x60, 0x60, 0x1E, 0x00, 0x7E, 0x30, 0x30, 0x7E, 0x00, 0x66, 0x18, 0x18, 0x66, 0x00, 0x00, 0x0E, 0x70, 0x0E, 0x00, 0x62, 0x52, 0x4A, 0x46, 0x00, 0x00, 0x7E, 0x42, 0x42, 0x00, 0x04, 0x08, 0x10, 0x20, 0x00, 0x00, 0x42, 0x42, 0x7E, 0x00, 0x00, 0x04, 0x02, 0x04, 0x00, 0x40, 0x40, 0x40, 0x40, 0x00, 0x00, 0x02, 0x04, 0x00, 0x00, 0x30, 0x48, 0x28, 0x78, 0x00, 0x7E, 0x48, 0x48, 0x30, 0x00, 0x30, 0x48, 0x48, 0x00, 0x00, 0x30, 0x48, 0x48, 0x7E, 0x00, 0x30, 0x68, 0x58, 0x10, 0x00, 0x10, 0x7C, 0x12, 0x04, 0x00, 0x50, 0xA8, 0xA8, 0x98, 0x00, 0x7E, 0x08, 0x08, 0x70, 0x00, 0x00, 0x48, 0x7A, 0x40, 0x00, 0x00, 0x40, 0x80, 0x7A, 0x00, 0x7E, 0x10, 0x28, 0x40, 0x00, 0x00, 0x42, 0x7E, 0x40, 0x00, 0x78, 0x10, 0x18, 0x70, 0x00, 0x78, 0x08, 0x08, 0x70, 0x00, 0x30, 0x48, 0x48, 0x30, 0x00, 0xF8, 0x48, 0x48, 0x30, 0x00, 0x30, 0x48, 0x48, 0xF8, 0x00, 0x78, 0x08, 0x08, 0x10, 0x00, 0x50, 0x58, 0x68, 0x28, 0x00, 0x08, 0x3E, 0x48, 0x40, 0x00, 0x38, 0x40, 0x40, 0x78, 0x00, 0x00, 0x38, 0x40, 0x38, 0x00, 0x78, 0x60, 0x60, 0x78, 0x00, 0x48, 0x30, 0x30, 0x48, 0x00, 0x18, 0xA0, 0x40, 0x38, 0x00, 0x48, 0x68, 0x58, 0x48, 0x00, 0x00, 0x08, 0x3C, 0x42, 0x00, 0x00, 0x00, 0x7E, 0x00, 0x00, 0x00, 0x42, 0x3C, 0x08, 0x00, 0x04, 0x02, 0x04, 0x02, 0x00, 0x00
__CA1:
    db 0x10, 0x27, 0xE8, 0x03, 0x64, 0x00, 0x0A, 0x00
__CA2:
    db 0x10, 0x27, 0xE8, 0x03, 0x64, 0x00, 0x0A, 0x00
__SLIT3:
    db 0x68, 0x65, 0x6C, 0x6C, 0x6F, 0x00
__SLIT4:
    db 0x68, 0x65, 0x6C, 0x6C, 0x6F, 0x00
__SLIT5:
    db 0x68, 0x69, 0x00, 0x00
__SLIT6:
    db 0x68, 0x69, 0x00, 0x00
;SYM ADC_ADCREAD 0x1C82
;SYM ADC_CONVERT 0x3042
;SYM ADC_SETCLOCK 0x3054
;SYM AHT30_AHT30FETCH 0x23CA
;SYM AHT30_AHT30START 0x238A
;SYM EEPROM_EEPROMREAD 0x1CA6
;SYM EEPROM_EEPROMWRITE 0x1CC8
;SYM FLASHWRITE_FLASHERASESECTOR 0x1D3C
;SYM FLASHWRITE_FLASHREADWORD 0x1D20
;SYM FLASHWRITE_FLASHUPDATEWORD 0x1DE8
;SYM FLASHWRITE_FLASHWRITEWORD 0x1D80
;SYM FLASHWRITE_SETADDR 0x3022
;SYM I2C_CONDITION 0x2ECC
;SYM I2C_I2CRECEIVE 0x20CC
;SYM I2C_I2CRESTART 0x2116
;SYM I2C_I2CSEND 0x2082
;SYM I2C_I2CSTART 0x206A
;SYM I2C_I2CSTATUS 0x2146
;SYM I2C_I2CSTOP 0x212E
;SYM I2C_OPEN 0x2EA8
;SYM I2C_PINSETUP 0x2F4E
;SYM I2C_SETPPS 0x2E86
;SYM I2C_WAITIDLE 0x2EE8
;SYM I2C_WAITIF 0x2F1C
;SYM IRREMOTE_WIDTH 0x2818
;SYM LCD_LCDCOMMAND 0x229A
;SYM LCD_LCDSETADDRESS 0x227C
;SYM LCD_LCDWRITECHAR 0x2284
;SYM LCD_NIBBLE 0x2CEC
;SYM LCD_SEND 0x2CC2
;SYM OLED_BEGIN 0x2B2E
;SYM OLED_CMD 0x2BE4
;SYM OLED_FINISH 0x2BB8
;SYM OLED_FONTBYTE 0x2374
;SYM OLED_OLEDFILL 0x22F4
;SYM OLED_OLEDGOTO 0x22C6
;SYM OLED_OLEDWRITECHAR 0x2324
;SYM OLED_PUT 0x2B90
;SYM OLED_RESET 0x2C08
;SYM OLED_SETUP 0x2C48
;SYM PINIO_BINDDATA 0x28AC
;SYM PINIO_CLKPUT 0x28E8
;SYM PINIO_CLKPUT_END 0x2900
;SYM PINIO_CLKPUT_HI 0x28FE
;SYM PINIO_DATAPUT 0x28CE
;SYM PINIO_DATAPUT_END 0x28E6
;SYM PINIO_DATAPUT_HI 0x28E4
;SYM PINIO_DATAREAD 0x2920
;SYM PINIO_DATAREAD_END 0x2934
;SYM PINIO_PINADDR 0x2902
;SYM PINIO_PINADDR_END 0x291E
;SYM PINIO_PINGET 0x26A8
;SYM PINIO_PINGET_END 0x26D4
;SYM PINIO_PINGET_GOT 0x26CE
;SYM PINIO_PINGET_SHL 0x26C6
;SYM PINIO_PININPUT 0x25F8
;SYM PINIO_PINOK 0x25E8
;SYM PINIO_PINOUTPUT 0x277A
;SYM PINIO_PINSET 0x274A
;SYM PINIO_PINSET_END 0x2778
;SYM PINIO_PINSET_GOT 0x276C
;SYM PINIO_PINSET_HI 0x2776
;SYM PINIO_PINSET_SHL 0x2764
;SYM PULSE_RCIN 0x25A6
;SYM PULSE_WAITUS 0x2852
;SYM PWM_PWMDUTY 0x2006
;SYM PWM_PWMSTART 0x1ECA
;SYM PWM_PWMSTOP 0x2028
;SYM PWM_SETCON 0x2F7C
;SYM PWM_SETDUTY 0x2FC4
;SYM PWM_SETPPS 0x2FA2
;SYM RTCCSPI_RDREG 0x2976
;SYM RTCCSPI_READBLOCK 0x29B2
;SYM RTCCSPI_TOBCD 0x2988
;SYM RTCCSPI_WRITEBLOCK 0x2936
;SYM RTCCSPI_WRREG 0x29FC
;SYM RTCC_OPEN 0x2A54
;SYM RTCC_RDREG 0x2A78
;SYM RTCC_READBLOCK 0x2AB4
;SYM RTCC_TOBCD 0x2A8A
;SYM RTCC_WRITEBLOCK 0x2A14
;SYM RTCC_WRREG 0x2B16
;SYM SERIAL2_SERIAL2WRITEBYTE 0x3060
;SYM SERIAL_SERIALWRITEBYTE 0x306E
;SYM SPI_PINSETUP 0x2D58
;SYM SPI_PPSOFF 0x2D36
;SYM SPI_SETPPS 0x2DA2
;SYM SPI_SPIREAD 0x2192
;SYM SPI_SPISTATUS 0x219C
;SYM SPI_SPITRANSFER 0x214E
;SYM SPI_SPIWRITE 0x218A
;SYM SYSTEM_SYSCLOCKHZ 0x21A2
;SYM X10_CODEOF 0x26F4
;SYM X10_HALF 0x27BE
;SYM X10_NUMBEROF 0x26D6
;SYM X10_SENDBIT 0x27F8
;SYM X10_ZERO 0x2646
;SYM __CA0 0x3134
;SYM __CA1 0x3310
;SYM __CA2 0x3318
;SYM __SLIT3 0x3320
;SYM __SLIT4 0x3326
;SYM __SLIT5 0x332C
;SYM __SLIT6 0x3330
;SYM __div2 0x307C
;SYM __div4 0x30AA
;SYM __halt 0x1C80
;SYM __reset 0x0000
;SYM __shl1 0x30F4
;SYM __shl2 0x3102
;SYM __shr1 0x3112
;SYM __shr4 0x3120
    END __reset
