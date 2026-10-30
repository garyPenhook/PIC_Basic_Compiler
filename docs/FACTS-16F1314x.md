# Facts: PIC16F13113 / 13114 / 13115 / 13123 / 13124 / 13125 / 13143 / 13144 / 13145 (enhanced mid-range core)

Read from DS40002519D (PIC16F13145 family data sheet) and DS80001115F (silicon errata) through the pic-docs server. Page numbers are PDF pages.
The core, the instruction set, the interrupt and the stack are those of the PIC16F17126/46 (`docs/FACTS-16F1714x.md`); this file lists
what differs. The code generator is the same one (`pic16e`).

## Parts (Table 1 p.1, Table 9-1 p.34)

| Part | Pins | I/O | Program flash | SRAM | Ports |
|---|---|---|---|---|---|
| PIC16F13113 / 13114 / 13115 | 8 | 6 | 2K / 4K / 8K words | 256 / 512 / 1024 bytes | A (RA0-RA2, RA4, RA5; RA3 is MCLR, input only) |
| PIC16F13123 / 13124 / 13125 | 14 | 12 | 2K / 4K / 8K words | 256 / 512 / 1024 bytes | A, C (RC0-RC5) |
| PIC16F13143 / 13144 / 13145 | 20 | 18 | 2K / 4K / 8K words | 256 / 512 / 1024 bytes | A, B (RB4-RB7), C (RC0-RC7) |

- No data EEPROM, no DMA, one EUSART, one MSSP, two CCP, two 10-bit PWM, two comparators, one 8-bit DAC, a 10-bit ADC with computation,
  four CLC and the CLB (32 logic elements). Reset vector 0000h, interrupt vector 0004h, 16-level stack (p.20, p.34). Five configuration words
  at 8007h-800Bh, four user ID words at 8000h-8003h, device ID at 8006h (p.22); PIC16F13145 reads 3129h.
- RAM is 80 bytes of GPR in each of the first banks plus 16 bytes of common RAM (p.44).
- `_ram` and `_eeprom` in `#if` give the usable RAM and the data EEPROM of the part in bytes (`_eeprom` is 0 here).

## Peripherals as the library uses them

- PPS (Table 18-1 p.187, Table 18-2 p.188): TX1/CK1 = 13h, DT1 = 15h, SCL1/SCK1 = 1Bh, SDA1/SDO1 = 1Ch, CCP1 = 09h, CCP2 = 0Ah, PWM1 = 2Ch, PWM2 = 2Dh.
  Input registers take `PORT[5:3] | PIN[2:0]` (A = 000, B = 001, C = 010), as on the PIC16F17126/46. Any output can go to any pin.
- OSCFRQ.FRQ (p.101): 1, 2, 4, 8, 16, 32 MHz = 0..5. NOSC 110 = HFINTOSC, NDIV up to 1001 (1:512) (p.91). PCON0 as the PIC16F17126/46 (p.79).
- Timer0 flag PIR0 bit 5; Timer1 PIR1 bit 6 (gate bit 7); Timer2 PIR2 bit 2. Timer1 clock sources (Table 22-4 p.245): pin 0, FOSC/4 1, FOSC 2,
  HFINTOSC 3, LFINTOSC 4, SFINTOSC 5, MFINTOSC 500 kHz 6, MFINTOSC 32 kHz 7, EXTOSC 9, Timer0 11 (no secondary oscillator). Gate sources (Table 22-5): the
  PIC16F17126/46 codes. Timer2 reset sources (Table 23-4): pin 0, CCP1 4, CCP2 5, comparators 14 and 15 (no Timer4).
- ADC (chapter 32): 10 bits; ADPCH (Table 32-6 p.465): RA0-RA2 0-2, RA4 and RA5 4-5, RB4-RB7 12-15, RC0-RC7 16-23, VSS 58, temperature 59, DAC1 60, FVR buffer 1 62,
  buffer 2 63. ADCLK = FOSC / (2 (n + 1)), 6 bits. TAD 0.5-9 us (AD20 p.557) but see errata 1.1.1. CPON resets to 01 (p.514).
- NVM (chapter 15): the PIC16F17126/46 scheme: 32-word rows, 32 write latches, unlock 55h/AAh in NVMCON2, then WR; NVMCON1 = RD, WR, WREN, WRERR, FREE, LWLO, NVMREGS.
- PWM (chapter 26): 10-bit, PWMxDCH:PWMxDCL[7:6], period from Timer2 (TxPR + 1) * 4 * Tosc * prescale; CCPTMRS0 and PWMTMRS0 reset to Timer2.

## Errata (DS80001115F)

- **1.1.1** (revision A2): the real minimum ADC clock period is 2 us. The `adc` module uses TAD >= 2 us on this family.
- **1.2.1** (A2): IPD up to 5 uA above the data sheet. Nothing to do in software.
- **1.3.1** (A2, A3): the first instruction fetch after power-up, a Reset, a wake-up from Sleep or entry to the interrupt handler can fail when FOSC > 16 MHz.
  Work arounds: run at 16 MHz or below; or put a NOP at address 0 and start the code at address 1; and put two NOPs after every SLEEP. **The compiler does
  not apply the NOP work around** (revision A4 is not affected); on a revision A2 or A3 part keep `Clock` at 16 or below. Revision A4 is the current silicon.
