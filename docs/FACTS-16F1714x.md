# Facts: PIC16F17126 / PIC16F17146 (enhanced mid-range core)

Everything here was read from DS40002343F (PIC16F17126/46 data sheet) through the pic-docs server. Page numbers are PDF pages.
Facts the generator relies on and have not been confirmed yet are in the last section.

## Instruction set (Chapter 41, p.591-607)

- 50 instructions, 14-bit words. All take one cycle except: `call`, `callw` (2); `return`, `retlw`, `retfie` (2);
  `goto`, `bra`, `brw` (2); a skip instruction that skips (2). An access through an INDF whose FSR points at program memory
  costs one more cycle (p.591, p.594 note 2).
- File register operand is 7 bits (`f` = 0..127): the bank comes from BSR, set by `movlb` (p.593). No access bank, no `movff`,
  no hardware multiply, no `rcall`, no `cpfseq`, no `N`/`OV` flags (STATUS has C, DC, Z, PD, TO).
- Byte ops (p.592-593): `addwf addwfc andwf asrf lslf lsrf clrf clrw comf decf incf iorwf movf movwf rlf rrf subwf subwfb swapf xorwf`,
  skip forms `decfsz incfsz`. `subwf f,d` = f - W, C = 1 when W <= f (no borrow) (p.606). `lslf`/`lsrf`/`asrf` shift through carry.
- Literal ops (p.593): `addlw andlw iorlw movlb movlp movlw sublw xorlw`. `sublw k` = k - W.
- Control (p.594): `bra` (-256..255 words, p.596), `brw`, `call` (11-bit target, PC[14:11] from PCLATH[6:3], p.597), `callw`
  (PC[7:0] = W, PC[14:8] = PCLATH, p.597), `goto` (11-bit, p.599), `retfie`, `retlw`, `return`.
- `moviw`/`movwi` (p.594, p.601, p.603): `++FSRn --FSRn FSRn++ FSRn--` and `k[FSRn]` with -32 <= k <= 31; `moviw` sets Z, FSR
  increments change no flags. `addfsr n,k` -32..31 (p.595).
- `retlw` tables: `brw` + `retlw` (Example 9-1, p.37). `retfie` sets GIE (p.604).

## Program memory (Section 9.1, p.36-38)

- 15-bit PC, 16K words on the 17126/17146 (Table 9-1). Reset vector 0000h, interrupt vector 0004h.
- A constant can be read through an FSR with bit 7 of FSRnH set: the address is the word address, and `moviw` returns the low 8
  bits of the word (p.38, Example 9-2; the `high` directive sets bit 7 for a program label). `retlw k` words therefore serve as
  byte tables for both `call` and FSR reads.
- PCL write loads PC[14:8] from PCLATH (p.51). `call`/`goto` keep PC[10:0] from the opcode: a 2K-word page; a program over 2K
  words must `movlp` before a far `call`/`goto` (p.52 for `call`; `bra` is relative and needs no PCLATH).

## Stack (Section 9.5, p.52-55)

- 16 levels. Return addresses only; PCLATH is not touched by push/pop. An interrupt uses one level. `STVREN` resets on
  over/underflow.

## Data memory and indirect addressing (Sections 9.2, 9.6, p.42-58)

- FSR address space (p.55-58): 0000h-1FFFh banked data memory (BSR-style addresses), 2000h-2FEFh linear data memory (the
  80-byte GPR blocks of banks 0, 1, 2 ... joined: bank n starts at 2000h + 80n), 8000h-FFFFh program flash (low 8 bits of each
  word), 7000h-70FFh data EEPROM (read only).
- GPR is 20h-6Fh of each bank (80 bytes); 70h-7Fh is common RAM visible from every bank; 00h-0Bh are core registers
  (INDF0, INDF1, PCL, STATUS, FSR0L/H, FSR1L/H, BSR, WREG, PCLATH, INTCON) visible from every bank. Device description:
  banks 0-25, bank 25 has 32 bytes, common RAM 16 bytes, 2048 bytes in all.

## Interrupts (Chapter 12, p.110-113)

- One vector (0004h). Enabled by GIE, PEIE (for the PIE registers) and the source's enable bit. On entry GIE is cleared,
  the PC is pushed, and hardware saves WREG, STATUS (except TO, PD), BSR, FSR0/FSR1 and PCLATH in shadow registers; `retfie`
  restores them and sets GIE (p.111, p.113). Nothing else is saved: the compiler's scratch registers (common RAM) must be.

## Confirmed by running (MPLAB X simulator, `tests/exec_p16` and the portable `tests/exec` programs)

- `subwfb f,d` is f - W - (1 - C): the multi-byte subtract, compare and divide tests of every width pass (`arith_*`), as does the
  signed compare by flipping the sign bits. The data sheet's text for `SUBWFB` on p.607 ("(W) - (f) - (B)") is not what the core does.
- `INTCON`: `PEIE` bit 6, `GIE` bit 7 (device description from the pack; the handler test enables with both).
- `ORG` in a `delta=2` psect counts words; `movwf` with a data address above 7Fh is accepted and keeps the low 7 bits, so the
  generator selects the bank itself (`movlb`) and writes plain addresses.
- Timer0 interrupt in 8-bit mode: `PIR0.5` (TMR0IF), `PIE0.5` (TMR0IE); the period is `TMR0H + 1` counts of the prescaled clock.
- PPS: `RC4PPS = 19` is TX1/CK1 (Table 18-2, p.202); `RX1PPS = 21` selects RC5 (Table 18-1, p.201).
- `OSCFRQ.FRQ` (p.105): 000 1 MHz, 001 2, 010 4, 011 8, 100 16, 101 32 MHz.

## Peripherals and memory the library modules use (read from DS40002343F in 0.1.51)

- **PPS** (Tables 18-1, 18-2, p.201-202): outputs `0x1B` SCL1/SCK1, `0x1C` SDA1/SDO1, `0x13` TX1/CK1, `0x16` TX2/CK2, `0x15` DT1, `0x18` DT2,
  `0x0B`..`0x0E` PWM1S1P1, PWM1S1P2, PWM2S1P1, PWM2S1P2 (outputs). Input registers hold PORT[5:3] | PIN[2:0] (RA = 0..5, RB = 8..15, RC = 16..23);
  reset selections `SSP1CLKPPS` = RC0 (14-pin) or RB6 (20-pin), `SSP1DATPPS` = RC1 or RB4, `RX2PPS` = RC1, `CK2PPS` = RC0. SCL and SDA are bidirectional:
  the output and the input must name the same pin.
- **MSSP1** (chapter 31, p.444-452): `SSP1STAT` (SMP 7, CKE 6, BF 0), `SSP1CON1` (WCOL 7, SSPOV 6, SSPEN 5, CKP 4, SSPM 3:0: `0000` SPI host
  FOSC/4, `1010` SPI host FOSC/(4 * (SSPxADD + 1)), `1000` I2C host, FOSC/(4 * (SSPxADD + 1)), SSPxADD 0..2 not valid for I2C), `SSP1CON2` (ACKSTAT 6,
  ACKDT 5, ACKEN 4, RCEN 3, PEN 2, RSEN 1, SEN 0), `SSP1CON3`. Same layout as the PIC18F27/47Q10. `SSP1IF` is `PIR5` bit 2, `BCL1IF` bit 3 (p.132).
- **EUSART2**: `TX2IF` `PIR5` bit 0, `RC2IF` bit 1 (p.132); registers `TX2STA`, `RC2STA`, `BAUD2CON`, `SP2BRG` as for EUSART1.
- **NVM** (chapter 15): `NVMCON1` (NVMREGS 6, LWLO 5, FREE 4, WRERR 3, WREN 2, WR 1, RD 0; p.175), `NVMCON2` unlock 55h then AAh then `WR` with the CPU
  stalled until the operation ends (p.157, p.169), `NVMIF` is `PIR1` bit 0. Program flash: 32-word rows (`NVMADRL[4:0]` picks the write latch; write latches
  are reset to 3FFFh at the end of every write, an erase leaves them alone, p.159 and p.161-162; they are one array shared by all rows), `FREE` = 1 erases the row, `LWLO` = 1 loads a latch only, `LWLO` = 0 writes the latches (p.158-164, Table 15-3,
  Example 15-4); the last write of a row loads `NVMDAT` first (Example 15-4) while Table 15-3 says `NVMDAT` is ignored with `LWLO` = 0, so the library loads
  the latch with `LWLO` = 1 and then writes with `LWLO` = 0. Data EEPROM: `NVMREGS` = 1, `NVMADRH` = 70h, `NVMADRL` = byte address, 256 bytes, byte write
  erases first, `NVMDATL` (p.167-172; Table 15-2 gives it as 0xF000..0xF0FF in the NVMREG address space).
- **PWM1, PWM2** (chapter 29, p.355-363): `PWMxCLK` = 2 is FOSC, `PWMxCPRE` = prescale - 1, `PWMxCON` EN bit 7 and LD bit 2 (hardware cleared),
  `PWMxS1CFG` POL2 bit 7, POL1 bit 6, MODE 2:0 (write only while EN = 0), 16-bit `PWMxPR`, `PWMxS1P1`, `PWMxS1P2`; same layout as the PIC18-Q41.
- **Charge pump** `CPCON` (p.589): `CPON[1:0]` bits 7:6, `01` = on while the ADC is enabled and VDD < 4.6 V. Errata DS80001009E 1.6.1: it resets to `00`.
- **Errata DS80001009E** (E, 06/2026) reviewed in full: ADC 1.1.1 (double sample) and 1.1.2 (acquisition time; `Adc` unaffected, documented), MSSP 1.2.1 (I2C
  start/stop flags on enable, silicon B0 only; the I2c module clears `SSP1IF` itself), CONFIG 1.3.1 (do not use `SLEEP`, B0), DAC 1.4.1, FVR 1.5.1,
  charge pump 1.6.1 (worked around in `AdcInit`), Timer1 1.7.1 (clear `TMRxGIF` after writing the gate source `GSS`). No NVM, EUSART, PWM or CCP erratum.

## Confirmed by running (library, 0.1.51)

- The simulator models the data EEPROM and the program flash write (row erase to 3FFFh, the latches, the row write, reads through `RD`), so
  `tests/exec_p16/lib_eeprom.bas` and `lib_flashwrite.bas` check the stored values, not just the registers. It does not model the ADC (`ADGO` never
  clears). It clears `FREE` and `WR` itself when an operation ends.
- `NVMADR` is 15 bits wide (bit 15 is not implemented, so Table 15-2's 0xF000 for the EEPROM is 7000h, the `NVMADRH` = 70h of the examples). A row
  erase at word 7F80h, past the end of the 16K-word flash, stalled the simulated CPU for good, so the library refuses word addresses at or above the flash
  size (16384) before it starts an operation.

## Not confirmed yet

- Config word layout and the oscillator/clock set-up beyond what the library modules already assume; Reset value of BSR.
