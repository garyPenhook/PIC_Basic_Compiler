# dsPIC33CK64MC105: facts the code generator relies on

Sources: **DS70005399D** (dsPIC33CK64MC105 family data sheet, "DS"), **DS70005158C** (dsPIC33/PIC24 Enhanced CPU
family reference manual, "CPU FRM"), **DS80000910C** (silicon errata, "ES"), the device pack `dsPIC33CK-MC_DFP 1.11.412`
(`edc/DSPIC33CK64MC105.PIC`, linker script `xc16/support/dsPIC33C/gld/p33CK64MC105.gld`). Page numbers are PDF pages.
Facts marked *(simulator)* were checked in MDB (MPLAB X 6.35) with the generated code, not read from a document.

## Core

* 16-bit data path, sixteen working registers `W0..W15`, 24-bit instructions, 16-bit data addresses of **bytes**
  (a word access must be at an even address; a misaligned one is an address-error trap) [DS 4.2.1, 4.2.2 p.38].
* Instruction cycle: most instructions are one word and one cycle; `mov.d`, SFR reads and SFR bit operations take two;
  a branch or call that changes the PC flushes the prefetch and takes more [CPU FRM 9.1 to 9.3 p.36]. Up to 100 MIPS at
  3.0 to 3.6 V (`Fcy = Fosc/2`, so a 200 MHz oscillator) [DS p.1]. Cycle counts of the delay loops are checked in
  the simulator (below).
* The oscillator after reset is the internal 8 MHz FRC [DS p.1], so `Clock = 8` gives `Fcy` = 4 MHz.
* **Divide** (`div.sw`, `div.uw`, `div.sd`, `div.ud`) is iterative and must run 18 times in a `repeat #17`; quotient in
  `W0`, remainder in `W1`; a divisor of zero raises the math-error trap [CPU FRM 8.0 p.35]. The generator guards a
  run-time divisor against zero, and does a 32-bit divide in a helper loop.
* ES item 1: `div.sd` does not set the overflow bit when it overflows. The generator never uses `div.sd`/`div.ud`.

## Memory

* Program memory: user program `0x000000` to `0x00AEFE`, configuration words `0x00AF00` to `0x00AFFE`
  [DS Figure 4-2 p.36]: 22,400 instructions (the pack's `CodeSector` ends at `0xAF00`). Addresses count two per
  instruction (a lower and an upper word [DS 4.1.1 p.37]).
* `0x000000` to `0x000200` is reserved for the hard-coded vectors. A `GOTO` programmed at `0x000000` jumps to the code
  whose address is stored at `0x000002` [DS 4.1.2 p.37]. The linker script writes that `GOTO` and the vector table;
  the program only has to define `__reset` and, for an interrupt, `__<Source>Interrupt`.
* Data: 8 KB of SRAM [DS p.1], `0x1000` to `0x2FFF` (the pack's `GPRDataSector`); SFRs `0x0000` to `0x0FFF`.
  Direct (file-register) operands of byte instructions have 13 address bits, so `0x2000` and above is reached through
  a register.
* No data EEPROM.
* Program memory is read as data with `tblrdl` (`TBLPAG` is 0 at reset and every address of this part is on page 0);
  in byte mode bit 0 of the address picks the low or high byte of the lower word *(simulator)*. A constant table is
  stored two bytes to an instruction word (`.word`).

## Interrupts

* `INTCON2.GIE` is bit 15 and **resets to 1** [DS Register 7-4 p.95]; the pack's `por` string shows 0, which is wrong.
  `Enable`/`Disable` set and clear it. A source is enabled by its `IECx` bit and its flag in `IFSx` is cleared by the
  handler, as on the other parts.
* The vector table names are the pack's `__<Source>Interrupt` (`__T1Interrupt`, `__INT0Interrupt`, `__U1RXInterrupt` ...).
  A handler is declared as `Interrupt T1() ... End Interrupt`; the name must be one of the `IFSx` flag names without
  the `IF`. The handler saves `W0..W7`, `SR` and `RCOUNT` (a `repeat` can be interrupted) itself, so nested sources
  at a higher priority are safe.

## Configuration

* Configuration words are 24 bits at `0x00AF00` ...; the generator writes each as `.pword`, with the 8 unimplemented
  upper bits 1. Names and settings come from the pack (`Config FWDTEN = ON_SW`). `FWDTEN = ON` (the default) is a
  watchdog that is always on: a program that does not clear it resets itself; `ON_SW` leaves it to `WDTCON`.

## Library modules

* `serial` (UART1): chosen with `#if _has(U1MODE)`, ahead of the `RCON` test (this part has an `RCON`). TX on RB6 (RP38), RX on RB7
  (RP39), both on the 28-pin part [DS Table 2 p.4]; `RPOR3[5:0]` = 1 routes U1TX [Tables 8-6, 8-7 p.116 to 117] and `RPINR18[7:0]` = 39
  selects RP39 for U1RX [Register 8-26 p.128, Table 8-4 p.111]. The remapping registers are unlocked after a Reset (`RPCON.IOLOCK` = 0
  [Register 8-13 p.122]). Legacy baud generation, `BRGH` = 1: baud = Fp / (4 (BRG + 1)) with Fp = FOSC / 2 [DS70005288C Equation 4-2 p.24].
  Flags: `TRMT` (`U1STA` bit 7), `OERR` (`U1STA` bit 1), `UTXBF` (`U1STAH` bit 4), `URXBE` (`U1STAH` bit 1) [Registers 15-3, 15-4].
  Checked in the simulator: the register values after `SerialInit` and that the send and flush loops finish
  (`tests/exec_dspic/lib_serial.bas`); no bit was seen on a pin. RB6 is `PGC3` and RB7 `TDO`.
* `timer` (Timer1 only), chosen with `#if _has(T1CON.TCKPS)`; the other timers of the part are inside the SCCP modules, so there is no Timer0 or Timer2 here.
  `T1CON` = `TON` (15) | `TECS<1:0>` (9-8) | `TCKPS<1:0>` (5-4) | `TSYNC` (2) | `TCS` (1); prescaler 1:1, 1:8, 1:64, 1:256; `TCS` = 0 is Fp = FOSC/2;
  `TECS` 00 T1CK pin, 01 Fp, 10 FOSC, 11 FRC [Register 19-1 p.330-331, Figure 19-1 p.329]. `PR1` is FFFFh after a Reset. Flag `IFS0.T1IF` (bit 1), enable `IEC0.T1IE` (bit 1);
  T1CK is routed with `RPINR2.T1CKR`. Checked in the simulator: `Timer1StartPeriod` register values and three period flags, `Timer1StartSource` register value, and that
  `Timer1Read` counts (`tests/exec_dspic/lib_timer.bas`). Not offered: the gate, asynchronous counter mode, Sleep operation, a pin-number `FreqCount`.
* `intosc`, chosen with `#if _has(PLLFBD)`: `Clock` is FOSC (Fcy = FOSC/2 [DS 9.2 p.154]). Speeds: FRCPLL at 200, 160, 150, 120, 100, 80, 64, 60, 50, 40, 32, 25, 20 and 16 MHz
  (FVCO = 8 MHz * M, FOSC = FVCO / (2 * N2 * N3), N1 = 1; M 64 to 150 keeps FVCO inside 400 to 1600 MHz [DS 9.1 p.151, Equations 9-1 and 9-2 p.152, Registers 9-2, 9-3, 9-5 p.160 to 164]) and
  FRCDIVN at 8 down to 0.03125 MHz. The switch writes OSCCON[15:8] (NOSC) and then OSCCON[7:0] (OSWEN) each after its unlock pair, 0x78 0x9A and 0x46 0x57 back to back [DS 9.9 p.157];
  `Config FCKSM = CSECMD` is needed (the erased value 1x disables clock switching [Register 28-5 p.416]). A PLL is left through plain FRC before its dividers change [DS 9.1 p.152].
  Checked in the simulator: the registers and COSC/LOCK after start-up at 100 MHz, SetClock(200) and SetClock(8), and the refusal of an unknown speed (`tests/exec_dspic/lib_intosc.bas`);
  the clock was not measured on a pin. The multi-bit fields (`COSC`, `FRCDIV`) are masked by hand because the back end has no multi-bit field access yet.
* `system`, chosen with `#if _has(PLLFBD)`: the Reset flags are the active-high bits of `RCON` [DS Register 6-1 p.79]; a watchdog time-out in Sleep or Idle wakes the part and sets `WDTO` without a Reset
  [DS70005250C 6.1.1 p.15], so cause 4 needs `SLEEP` and `IDLE` clear. `SysClockHz` computes FOSC from `OSCCON.COSC`, `CLKDIV` and `PLLFBD`/`PLLDIV` (FRC taken as 8 MHz). Sleep is `pwrsav #0`
  [DS70000157G]. `Snooze` and `Sleep(seconds)` use the Sleep-mode watchdog, whose period is 2^`SLPDIV` ms and is fixed by `Config SWDTPS` [DS70005250C Table 3-1 p.13, DS Register 28-19 p.432].
  Checked in the simulator: the cause after power-on (1, with POR and BOR set), the cleared flags, the wake codes, `SysClockHz` = 100 MHz after `intosc` and `SysClockOk` (`tests/exec_dspic/lib_system.bas`).
  **Not run in the simulator:** the timed sleeps; MDB does not wake the part from a watchdog Sleep (the program stays in `pwrsav`), so `lib_system_sleep.bas` only assembles and links them.
* `serial2` (UART2), chosen with `#if _has(U2MODE)`, same set-up and flags as `serial`. TX on RB5 (RP37), RX on RB4 (RP36): pins of the 28-pin part [DS Table 2 p.4] clear of the RB6/RB7 pair of UART1;
  RB5 has no analog function and `ANSELB` bit 4 is cleared for RX. `RPOR2[13:8]` = 3 routes U2TX [Tables 8-6 p.116, 8-7 p.117] and `RPINR19[7:0]` = 36 selects RP36 for U2RX [Register 8-27 p.129].
  RB4 is `PGC2` and RB5 `PGD3`. Checked in the simulator: the register values after `Serial2Init` and that the send and flush loops finish (`tests/exec_dspic/lib_serial2.bas`); no bit was seen on a pin.
* `adc`, chosen with `#if _has(ADCON1L)`: one shared 12-bit SAR core [DS 12.1 p.211]. Channels are AN numbers (AN0 RA0, AN1/AN7 RB2, AN2 RB7, AN3 RA3, AN4 RA4, AN5 RB0, AN6 RB1, AN8 RB3, AN9 RA2,
  AN10 RB8, AN11 RB9, AN12 to AN15 RC0 to RC3 on the 48-pin part [Table 5 p.8]; AN16 is the temperature diode and AN17 the 1.2 V band gap [Figure 12-1 p.212]). A conversion is the individual channel software
  trigger (`ADCON3L.CNVRTCH` with `CNVCHSEL`, no `ADTRIGx` set-up) [DS70005213H 5.9.5 p.50]; the result is in `ADCBUFn` and `ANnRDY` in `ADSTATL`/`ADSTATH` clears when `ADCBUFn` is read [DS70005213H 5.13.1 p.57].
  Start-up: `WARMTIME` of at least 10 us in Fp periods, `ADON`, `SHRPWR`, wait for `SHRRDY`, `SHREN` [DS70005213H 5.7 p.49]; the pack has no `ADCALx` registers, so there is no calibration. Clock Fp/2 (`CLKSEL` 00,
  `SHRADCS` 1): at most 50 MHz against AD11 70 MHz and AD50 14.28 ns [Tables 31-30, 31-31 p.473 to 474]. Sampling 2 us (`SHRSAMC` = count - 2 [Register 12-4 p.218]). The reference is AVDD/AVSS only
  (`REFSEL` 000 [Register 12-5 p.219]), so there is no FVR reference. Checked in the simulator: the register values after `AdcInit`, `SHRRDY`, `AdcPin`, and that `AdcRead`, `AdcReadAvg`, `AdcMillivolts` and `ADin`
  run to the end (`tests/exec_dspic/lib_adc.bas`). **Not run:** an actual conversion; MDB does not model the ADC (`ANnRDY` never sets, so `AdcRead` returns 0 after its time-out). Not offered: differential inputs
  (48-pin `ANN0` only), signed or fractional results, scan, triggers from other modules, comparators and the oversampling filters.
* Not done: `eeprom` (the part has none), `flashwrite`, `spi`, `i2c`, `pwm`, `dma`.

## Not yet generated

`Float` and the Float library, recursive routines, calling C, interrupt priorities other than the default, and the
library modules listed above are not done for this core.
