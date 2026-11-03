# Simulator facts (`crates/picsim`)

Each rule the simulator relies on, with its source. Rules marked `[A#]` are assumptions to be measured against MDB.

## PIC18 core (S1)

* Instruction encodings, flags affected and cycle counts: DS40002214G Table 45-2 (PDF pp.805-808). Cycles: 1; a
  taken skip adds the length in words of the skipped instruction (so 1-4); a taken branch, BRA, RCALL, CALL, GOTO,
  RETURN, RETFIE, RETLW, CALLW, MOVFF, LFSR, TBLRD, TBLWT take 2; MOVFFL takes 3.
* MOVFFL: source = word1<3:0>:word2<11:2>, destination = word2<1:0>:word3<11:0> (Table 45-2 field layout, read as
  most significant bits first) `[A1]`.
* LFSR literal: 14 bits (word1<3:0>:word2<9:0>) when FSRnH implements more than 4 bits (Q41), else 12 bits.
* When an instruction writes STATUS and also affects flags, the flags win (write happens first).
* A read-modify-write through `POSTINC/POSTDEC/PREINC/PLUSW` steps the FSR once (found by the `tests/exec` array
  programs, `addwf POSTINC0, f`).
* Access Bank: `f` below the length of `access_ram` maps to `access_ram.start + f`, above it to `access_sfr.start +
  (f - len)` (device file; matches the compiler's `Target`).
* The pack's `access` letters (`n r w c s -`) are **not decoded yet**: their meaning is not recorded in a data sheet
  here. Only the `implemented` mask is applied (unimplemented bits read 0 and ignore writes).
* Not modelled yet (milestone): reset values after MCLR/WDT, configuration words (S3 remainder), TBLWT / flash and
  EEPROM writes (S5), ports/UART/ADC (S4). SFRs without a model act as latches and are listed at the end of a run.

## Interrupts and timers (S3)

Code: `crates/picsim/src/pic18.rs` (`irq_check`, `retfie`), `periph.rs` (Timer0/1/2). Cites are in the module comments.

* Sources are every PIRn/PIEn/IPRn triple of the part. `IPEN = 0`: GIE (and PEIE for PIR1 and up on the Q10; PIR0 is
  ungated `[A5]`; the Q41 has no PEIE) enables all, vector 0008h. `IPEN = 1`: high needs GIEH, low needs GIEH and GIEL,
  vectors 0008h/0018h. DS40002043F 15.1-15.3 p.193-194; DS40002214G 11.5-11.8.
* Q10 entry clears GIE/GIEH (GIEL for low) and saves W/STATUS/BSR in the fast stack; `RETFIE` sets GIE/GIEH, or GIEL
  when leaving a low handler (p.194). Q41 (`SHADCON` present) leaves GIE alone, tracks the level itself, saves
  W, STATUS, BSR, FSR0-2, PROD, PCLATH/U per level and `RETFIE 1` restores them (FACTS-18F-Q41.md section 4).
* Entry timing, measured against MDB: the vector is reached 3 cycles after the cycle the flag was set, never less
  than 2 after the instruction `[A4]`. isr_single's first 27 entries and all `lib_timer*` cycle counts match MDB exactly.
* Timer0 8-bit compares TMR0L with the *live* TMR0H (a write right after the flag applies to the period that has just
  started; measured, MDB), period TMR0H+1 clocks; 16-bit buffers TMR0H. Timer1: FOSC/4 and FOSC, RD16 buffer.
  Timer2: free-running and software one-shot (MODE 00000 / 01000). Other clock sources, gates and hardware reset
  modes log a note and do not count/act (S4).
* Flag time agrees with MDB for software polling in all 12 probe variants (`[A1]`, `[A2]`).

### Known differences from MDB (the sim follows the data sheet)

* D-SIM-1: MDB loses part of the Timer0 prescaler count on a TMR0L *read* and on `movf T0CON0,f`. The data sheet
  clears the prescaler on writes only (DS40002043F 19.2.4 p.297), and `movf f,f` writes. Probe programs:
  `tests/hw/t0_*_sim.bas` (sim gives 402 / 401 / 500 / 401 for nowrite / readw / movf / tmr0l). `isr_single` differs by
  565 cycles because of it. Settle on silicon with the `_hw` flavours (results in EEPROM 0-1).
* D-SIM-2 (open): interrupt entry racing a `bcf INTCON,7` critical section differs from MDB by 1-8 cycles over a run
  (`bit_packed_isr` +4, `isr_dual` +2 total); MDB defers some requests the sim takes. Not yet understood.
* TMR0L read right after a TMR0H change in 8-bit mode differs by 1-2 counts.

## EUSART transmitter (S4, Q10 style)

Code: `periph.rs` (`Uart`), EUSART1 and EUSART2 (TXn/SPn/BAUDn names; the Q41 UART1 `U1*` registers are not modelled yet).
DS40002043F ch.29 p.503-505.

* TXREG goes to the shift register at once when that is idle, else it is held until the Stop bit ends (29.1.1.2).
  TXIF = TXEN and nothing held (29.1.1.4); TRMT = shift register idle, read only (29.1.1.5). `RCIDL`/`ABDOVF` of
  BAUDnCON are read only and keep their value on writes.
* Character time in instruction cycles (Table 29-1): BRG16 = 1 and BRGH = 1: n+1 per bit; exactly one of them: 4(n+1);
  neither: 16(n+1); 10 bits, 11 with TX9. `[A6]` the held byte starts in the cycle the Stop bit ends.
  `[A7]` clearing TXEN abandons the shift register and a held byte; a TXREG write with TXEN = 0 is dropped.
  `[A8]` TXIF does not dip for a cycle after a write that goes straight to the shift register.
* Synchronous mode is not modelled (a note is logged; nothing is sent or received).
* `basil-sim` prints the transmitted bytes as `tx1: ...` / `tx2: ...`; `Periph::tx` holds (EUSART, start cycle, byte).

### Receiver (DS40002043F 29.1.2 p.507-510, RCxSTA 29.6.4 p.529)

* Two-character FIFO. RCIF = SPEN and CREN and an unread character (read only, follows the FIFO). FERR and RX9D describe
  the top character, so they change when RCREG is read. A third complete character with the FIFO full sets OERR and is
  lost; while OERR is set nothing more is received. Clearing CREN clears OERR; clearing SPEN also empties the FIFO.
* RX9 + ADDEN: characters with the ninth bit 0 are dropped without RCIF. RCIDL (BAUDnCON bit 6) is 0 while a character
  is in flight. A character whose Start bit falls while the receiver is off is lost (the hardware waits for the next
  falling edge).
* `[A9]` A character enters the FIFO when the Stop bit has been sampled, half a bit time into it: Start + data bits +
  half a bit time after the falling edge (9.5 bit times for 8 data bits). Not measured on hardware.
* `[A10]` Reading RCREG with an empty FIFO returns the last character read again (data sheet silent).
* `[A11]` Clearing CREN keeps the characters already in the FIFO (29.1.2.5 says they can still be read) and abandons the
  one in flight.
* RCREG is read by the instruction against the state after the previous instruction (peripherals sync once per
  instruction), so a character that completes inside the reading instruction shows up one instruction later.
* Auto-baud (ABDEN), break detection and the RX pin itself (RXxPPS, TRIS, ANSEL) are not modelled: the stimulus file
  drives the receiver input directly.

## Stimulus file (`crates/picsim/src/stimulus.rs`, `basil-sim --stim FILE`)

TOML; today only `[[uart]]` entries (`port`, `at`, `bytes` or `data`, `bit`, `gap`, `nine`, `bad_stop`; documented at the
top of `stimulus.rs`). Characters of one entry go out back to back; entries follow each other on the line. `at` is an
instruction cycle, `bit` the sender's bit time in instruction cycles (default: the receiver's own rate at the time the
character starts). Tests: `cargo test --release -p picsim`, `tests/sim/run.sh` (a Basil program reading from it).

## Configuration words (S3)

Decoded by `crates/picsim/src/config.rs` from the bytes the hex puts at the `[[config]]` addresses; a byte the image
lacks keeps the register's unprogrammed default (0xFF). `basil-sim --config` prints the fields and the SFRs below.

* `RSTOSC` sets the reset values of `OSCCON1` (NOSC, NDIV), `OSCCON2` (COSC, CDIV) and `OSCFRQ`. Q10: DS40002043F
  Table 5-1 p.53; Q41: DS40002214G Table 12-1 p.175. 111 = EXTOSC, 110 = HFINTOSC 4 MHz / 4, 101 = LFINTOSC,
  100 = SOSC, 010 = EXTOSC + 4xPLL (OSCFRQ 4 MHz). **At 000 the tables differ**: NOSC/COSC = 110 with OSCFRQ 64 MHz on the
  Q10, NOSC/COSC = 000 with OSCFRQ 64 MHz on the Q41. 011 and 001 are reserved and change nothing.
* `WDTCON0` resets to PS = `WDTCPS` (01011 when `WDTCPS` = 11111), SEN = 0: DS40002043F 10.8.1 p.102, DS40002214G
  15.7.1 p.240. `WDTCON1` resets to WINDOW = `WDTCWS` and CS = `WDTCCS` (000 when `WDTCCS` = 111): DS40002043F 10.8.2
  p.103, DS40002214G 15.7.2 p.241.
* `MVECEN` = 1 on the Q41 (vector table, DS40002214G CONFIG3 p.46) is not simulated; the first interrupt taken adds a
  note and goes to the legacy vector. The compiler refuses `MVECEN = ON` (`E-CONFIG`), so only a program that leaves
  CONFIG3 out (default 0xFF = ON) and still takes an interrupt sees it.
* `WDTE` <> 0 adds a note: the watchdog does not time out yet (`CLRWDT` is a no-op). Needs reset kinds (next item).
* `LVP`, `STVREN`, `XINST`, code protection and write protection have no effect in the simulator.
* Not yet applied: `FEXTOSC`/`CSWEN` (`OSCCON1` is writable regardless of `CSWEN`), the OSCSTAT ready bits.

## Status (differential)

`scripts/exec-test.py --engine sim` (no MDB involved; the `' expect:` lines are the oracle):

* After S3, excluding the ADC/EEPROM/flash/serial/DMA programs (S4/S5): 130 pass, 1 fails (`lib_timer_hw`, Timer1
  gate value bit GVAL, needs the pin model of S4).
* Not yet run: `--engine both` (cycle counts against MDB), PIC16 parts (S2).
