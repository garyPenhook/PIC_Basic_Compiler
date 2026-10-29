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

## Not confirmed yet

- Config word layout and the oscillator/clock set-up beyond what the library modules already assume; Reset value of BSR.
