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

## Not yet generated

`Float` and the Float library, recursive routines, calling C, interrupt priorities other than the default, and the
library modules (`docs/LIBRARY.md`, "Device support") are not done for this core.
