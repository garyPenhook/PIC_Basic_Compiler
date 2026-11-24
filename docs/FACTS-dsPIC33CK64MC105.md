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
  the clock was not measured on a pin. `COSC`, `FRCDIV` and `PLLPRE` are written as register fields.
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
* `flashwrite`, chosen with `#if _has(NVMKEY)`: a word is the low 16 bits of an instruction (the module writes FFh in the high byte, so erased reads FFFFh); word addresses are instruction numbers (program address 2n).
  A sector is the erase page of 1024 instructions [DS 5.2 p.64]; page 21 holds the configuration at 0xAF00 [Figure 4-2 p.36], so `FlashLastSector` is 20 and nothing above it is touched. Programming is the
  double word (`NVMCON` = 4001h, latches at 0xFA0000 and 0xFA0002 through `TBLPAG` = 0xFA) and a page erase is `NVMCON` = 4003h with `NVMADRL`/`NVMADRH` = the page address; each is `NVMKEY` 55h, AAh, `WR`, two NOPs
  with interrupts off [Register 5-1 p.66 to 67, Figure 4-1 p.35, DS70000609F 4.4, 4.5]. The ECC covers each pair of instructions (7 parity bits, cannot be disabled, a double-bit error is a hard trap [DS 5.4 p.71]),
  so a pair is programmed once between erases: `FlashWriteWord` only into a wholly erased pair, `FlashWritePair` for both words, `FlashUpdateWord` rewrites the page from a 2048-byte RAM image when the pair is in use.
  `TBLPAG` is put back to 0. The errata (DS80000910C) list nothing for the flash. Checked in the simulator (MDB models the NVM controller): erase, word write, refusal of the partner write, pair write, update by page
  rewrite with the neighbours kept, `TBLPAG` = 0 (`tests/exec_dspic/lib_flashwrite.bas`). **Not checked:** the timing (20 us, 20 ms), write protection, and a power loss in the middle of an erase.
* `pinio` and `gpio`, chosen with `#if _has(PLLFBD)`: the ports are 16 bits wide, so the pins are numbered port * 16 + bit (RA0 = 0, RB0 = 16, RC0 = 32, RD0 = 48; `PinCount` = 64) and not 8 to a port as on the other parts. The 48-pin part has RA0..RA4, RB0..RB15,
  RC0..RC13 and RD1, RD8, RD10, RD13 [Table 5 p.8, Table 8-1 p.100]; `PinOk` is False for the others. `TRISx`, `LATx`, `PORTx` and `ANSELx` [Registers 8-1 to 8-4 p.102 to 104]; the bound pins find the port and the mask once. `GpioPullUps` and
  `GpioOpenDrain` take Word masks for ports A to C (`CNPUx` [Register 8-6 p.105], `ODCx` [Register 8-5 p.104]) and port D has `GpioPullUpsD` and `GpioOpenDriveD`. Checked in the simulator (`tests/exec_dspic/lib_pinio.bas`).
* `softserial`: the instruction clock is FOSC / 2, so a bit is `Clock` * 500000 / baud cycles (250000 on the other cores). Measured with the simulator's stopwatch (a wait pass 7 cycles, a transmitted bit 80 more, 83 at -O0; a received bit 70 (73); a poll of the start-bit loop
  52 (55); the poll that sees the start edge to the first sample 109 (119)); the sample instants and bit spacing at 2400, 4800 and 9600 baud are within 1 % (0.3 % at -O0) of ideal. The global interrupt enable is `INTCON2.GIE` (bit 15). `tests/exec_dspic/lib_softserial.bas`.
* `i2c`: the software host of the PIC18-Q41 over any two digital pins (SCL and SDA open drain through `TRISx`, the latch bit 0); the hardware I2C1 and I2C2 modules are not used. Checked in the simulator with a stimulus file that pulls the lines high: start, a byte with every bit
  read back as sent, no acknowledge (3) from an empty bus, stop, and a bus stuck low (`tests/exec_dspic/lib_i2c.bas`, `lib_i2c_busy.bas`).
* `spi`: SPI1 as host through PPS on any pin of ports B to D, 8 bits, standard buffer. SCK = RPOR code 6, SDO = 5 [Table 8-7 p.117], SDI = `RPINR20[7:0]` [Register 8-28 p.129]; the clock is Fp / (2 (`SPI1BRGL` + 1)) = FOSC / (4 (BRG + 1)), 13 bits [DS70005136B Equation 3-1 p.35],
  at most 33 MHz (SP10 15 ns [Table 31-25 p.466]). Set-up order as in DS70005136B 3.4.1 p.24. Checked in the simulator: the register values and the pin checks. **A transfer was not run:** MPLAB X's simulator has no SPI model (`SPI1BUFL` reads back what was written, `SPIRBF` never sets).
* `pwm`: the four PWM generators in independent edge mode on the pins `PWM1H/L` (RB14/RB15), `PWM2H/L` (RB12/RB13), `PWM3H/L` (RB10/RB11) and `PWM4H` (RD1 or any remappable pin, RPOR code 34); f = F(PGx_clk) / (`PGxPER` + 1), `PGxDC` = (`PGxPER` + 1) * duty, at least 33 clocks
  a period and 8 clocks a pulse [DS70005320E 4.1.2 p.56, Table 4-2 p.60]. The master clock is FOSC; MP10 (450 to 500 MHz PWM input frequency [Table 31-24 p.464]) is the high-resolution clock and does not cover it. Checked in the simulator: the register values; **no waveform** (no PWM model).
* `onewire`: the dsPIC branch needs `Clock` >= 32 MHz (16 MIPS); `SwCyc` = 31 measured with the stopwatch at the `TRISB` writes of the open-drain routines (a write 1 slot at 100 MHz held the line low 181 cycles, 150 of them the delay; a slot 75 us). The cycle window of
  `tests/exec_dspic/lib_onewire.bas` (pulled-up line, no device) holds reset and slot timing to 5 %. A device answering was not simulated.
* Simulator limits, found while testing: MDB has no ADC conversion (message W0237), no SPI, no PWM and no UART transfer model; it does model the NVM controller, the I/O pins (with an SCL stimulus file, `tests/exec_dspic/*.scl`) and cycle counts.
* Not done: `eeprom` (the part has none, the module stops with `#error`), `clc` and `dma` (the part has CLC and DMA blocks, but the modules are written for the PIC18 ones and stop with `#error`).

## Language features that were open (0.1.293 to 0.1.296)

* **`Float`**: `lib/floatlib.bas` wraps the XC-DSC soft-float routines (`___addsf3`, `___mulsf3`, `___divsf3`, `___floatsisf` ...). The first operand
  is in `W1:W0`, the second in `W3:W2`, the result in `W1:W0` [XC-DSC C Compiler User Guide 14.7.1, 14.7.2]; the wrappers flush denormals and make every
  NaN `0x7FC00000`, so the results are the same as on the other cores. Two faults were found by running the PIC18 `Float` programs on this part
  (`scripts/exec-test33.py --port`): the library's `___divsf3` (and the other routines that report an error) set `errno` to EDOM on a NaN operand, and the linker
  put `_errno` at `0x1000`, on the first variable of the program, so the program now defines `_errno` itself (a variable of its own, so the archive member is
  not linked); and `FScale` (a constant power of two, `x / 2^127`) returned a zero where `2^-127` is a denormal but `x * 2^-127` is not, so it multiplies
  twice (`2^-126`, then `2^(k+126)`). As on the other cores, Float arithmetic directly in a handler is `E-ISR-CALL` (do it in a routine
  and call that inside `Save(...) ... Restore`).
* **Recursion**: `Reentrant` routines save the caller's frame on the stack around a recursive call (`G::call`). Checked: factorial, Fibonacci, Ackermann,
  Hanoi, mutual recursion through `Declare`, a `Float`, `LongWord` and `ByRef` array in the cycle (`tests/exec_dspic/reentrant*.bas`, `forward.bas`).
  The stack is the one the generated start-up sets (to the end of RAM) or, with C, the linker's.
* **Multi-bit register fields**: a named field of one byte of a register (`OSCCON.COSC`, `CLKDIV.FRCDIV`, `IPC0.T1IP`, `T1CON.TCKPS`) reads and writes as a structure's
  `Bits(n)`: a read-modify-write of that byte (the second byte of a 16-bit register for a field above bit 7). A field wider than a byte or across the
  boundary of two (`PLLFBD.PLLFBDIV`, `SPI1BRGL`) is still `E-BACKEND`; the register itself is used. When the program has an interrupt handler the write
  runs with `INTCON2.GIE` (bit 15, the second byte's bit 7) off and put back only if it was on.
* **Interrupt priorities**: `Interrupt T1(ipLow)`, `Interrupt INT0(6)`: the argument is the priority 1 to 7 of that source (`ipLow` is 2 and `ipHigh` is 6 here, 1 and 2 on the
  PIC18). The start-up code writes it to the source's `IPCx` field (`T1IP`, `INT0IP` ...; `E-ISR-PRIO` when the handler's name has no such field). A handler without
  a priority keeps the reset value 4. A higher priority interrupts a handler of a lower one, and the interrupt latency and the handler's own context
  save (`W0..W7`, `SR`, `RCOUNT`, `W8`..`W9` with strings) already allow it. Each source has its own vector, so any number of handlers can be enabled
  at once; `Enable` and `Disable` still set and clear `INTCON2.GIE`. Checked in the simulator (`tests/exec_dspic/isr_priority*.bas`): the register values, a
  high handler running inside a low one and finishing first, and the same two handlers with the priorities swapped not nesting.
* **Calling C** (`CFile`, `Extern`, `Export`): no stub. The generated thunk of an `Extern` routine puts the arguments where XC-DSC wants them (`W0..W7` in order, the
  first free and suitably aligned register for each, a 32-bit value in an even pair; an argument that finds none goes on the stack, the last one pushed first, the
  low word of each lowest, and the caller takes them off again [User Guide 14.7.1]), calls `_name` and takes the result from `W0` or `W1:W0`. `W8` to `W14` are
  C's to preserve and the generated code keeps `W8` and `W9` for its own string work, so an `Export` thunk (which is the C symbol `_Name`) saves them when the
  program uses them. A pointer is the 16-bit data address of a `ByRef` object; a structure is laid out like the C one (fields aligned to their size, as the generator does for
  every variable). No 24-bit values (`E-EXTERN`). With C linked the build uses the C start-up code (`xc-dsc-gcc`, no `-nostartfiles`): it sets the stack
  and `SPLIM`, initialises the C data and calls `_main`, which is the generated program. The variables are in a section the linker keeps at their addresses
  (`.section .basilvars,bss,address(0x1000)`), so the C data and the stack are placed after them; the program's own RAM-use figure does not count them. A program
  without C keeps `-nostartfiles` and its own start-up. C code is compiled with `-Os`. Recursion through an `Export` is `E-RECURSION` as on the PIC18
  (an exported routine cannot be `Reentrant`). A handler may call C inside `Save` (the C function is entered by `rcall` and keeps its own frame on the stack, so
  a handler and the main line can both be in it only if the function is reentrant, as in any C program).
  Checked in the simulator: `tests/exec_dspic/c_basic`, `c_args`, `c_export`, `c_abi` (register holes, stack arguments, a float, four longs, a handler calling C).

The library modules `eeprom` (the part has none), `clc` and `dma` are still not done for this core.
