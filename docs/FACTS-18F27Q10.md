# PIC18F27Q10 fact base (milestone M1)

Every fact below was read from a Microchip document and carries its source. Page numbers are
PDF pages.

* **DS** = PIC18F27/47Q10 Data Sheet, DS40002043F (767 pp.)
* **ES** = PIC18F27/47Q10 Silicon Errata and Data Sheet Clarifications, DS80000832G
* **PACK** = Microchip device pack `PIC18F-Q_DFP 1.31.492`, file `edc/PIC18F27Q10.PIC`
  (Microchip's own machine-readable device description, used where the data sheet's figure
  does not survive text extraction)
* **UG** = MPLAB XC8 PIC Assembler User Guide, DS50002974E

Status key: ✔ verified · ◐ verified, but the compiler decision it feeds is still open ·
→ later milestone (not needed yet).

Date verified: 2026-10-23.

---

## 1. Memory

| Fact | Value | Source |
|---|---|---|
| ✔ Program flash | 128 KB = 64 KW; byte-addressed PC `0x00_0000`–`0x01_FFFF` | DS p.4 (Table 1), p.108; PACK `CodeSector 0x0–0x20000` |
| ✔ PC width and alignment | 21-bit PC; addresses *bytes*; bit 0 of PCL fixed at 0; PC increments by 2 | DS p.110 |
| ✔ Reset / interrupt vectors | `0x0000` reset; `0x0008` high priority; `0x0018` low priority | DS p.108, p.193 |
| ✔ User IDs | `0x20_0000`–`0x20_00FF` (128 words), not code-protected | DS p.108; PACK `UserIDSector` |
| ✔ Configuration words | `0x30_0000`–`0x30_000B` (12 bytes = CONFIG1L … CONFIG6H) | DS p.108; PACK `ConfigFuseSector 0x300000–0x30000C` |
| ✔ Data EEPROM | 1024 bytes at `0x31_0000`–`0x31_03FF` | DS p.4; PACK `EEDataSector` |
| ✔ Device ID | `0x3F_FFFE`–`0x3F_FFFF`; value `0x7100` | DS p.108; PACK `DeviceIDSector` |
| ✔ Data RAM size | 3615 bytes (`0x000`–`0xE1E`), *including* 256 bytes of "SECTOR" RAM that MPLAB X does not count | DS p.4 (Table 1 note 2); PACK GPR sectors sum to `0xE1F` |
| ✔ Data memory structure | 12-bit addresses, 16 banks × 256 bytes; `BSR[3:0]`; unimplemented reads give 0, writes are ignored | DS p.116–118 |
| ✔ GPR layout | Bank 0 `0x060`–`0x0FF`; banks 1–12 `0x100`–`0xCFF`; **bank 13 (`0xD00`–`0xDFF`) is the "system" (SECTOR) RAM block**; bank 14 `0xE00`–`0xE1E` | PACK `GPRDataSector`/`SystemGPRDataSector` |
| ✔ Usable by default | `0x000`–`0xCFF` and `0xE00`–`0xE1E` = 3359 bytes (`0xD1F`) — pic-as reports exactly this data-space size | PACK; DS p.4; pic-as run on this machine |
| ◐ Bank 13 use | Treated as reserved by default; do not allocate variables there. Its purpose is read in the NVM chapter (M8) | DS p.4 note 2; → M8 |
| ✔ SFR layout | `0xE1F`–`0xEFF` (bank 14), `0xF00`–`0xF5F` (bank 15), and the access-mapped SFRs `0xF60`–`0xFFF` | PACK `SFRDataSector` |
| ✔ GPRs are not initialised by POR and are unchanged by other resets | | DS p.119 |
| ✔ Table-read instructions read program memory through a 21-bit `TBLPTR` into `TABLAT` | | DS p.623 (field table) and p.629 |

## 2. Access Bank

| Fact | Source |
|---|---|
| ✔ The Access Bank is 256 bytes: the first 96 bytes (`00h`–`5Fh`) of bank 0 (GPRs, called "Access RAM") plus the last 160 bytes (`60h`–`FFh`) of bank 15 (SFRs). The two are contiguous and addressed with an 8-bit address. | DS p.118–119; PACK `accessram 0x0–0x60`, `accesssfr 0xF60–0x1000` |
| ✔ Instruction bit `a`: `a = 0` forces the Access Bank (BSR ignored); `a = 1` uses `BSR` | DS p.119, p.625 (Fig. 38-1) |
| ✔ Only `MOVFF` carries full 12-bit addresses for both operands and ignores `BSR` | DS p.118 |
| ✔ **Only 96 bytes of GPR are reachable with no bank handling.** Hot variables go there; everything else needs `BSR` or `FSR` | DS p.119 |
| ✔ With `XINST = 1` the Access Bank mapping changes: an access-bank instruction with file address ≤ `5Fh` is interpreted as an *offset from `FSR2`* instead (Indexed Literal Offset mode) | DS p.119, p.123 |
| ◐ **Consequence:** with `XINST = 1` the low 96 bytes are no longer directly addressable as plain Access RAM. The default build therefore uses `XINST = 0`; `XINST = 1` is only for opt-in reentrant code (ABI) and then the compiler must use bank-select addressing (`a = 1`) for ordinary variables | derived from the above |

## 3. Hardware stack and calls

| Fact | Source |
|---|---|
| ✔ 31-level return-address stack, 21 bits wide, 5-bit stack pointer (35 levels / 6-bit pointer only in ICD mode) | DS p.110 |
| ✔ Pushed by `CALL`, `RCALL`, `CALLW` **and by every interrupt acknowledge**; popped by `RETURN`, `RETLW`, `RETFIE` | DS p.110–111 |
| ✔ The stack is not in program or data space; `TOSU:TOSH:TOSL` read/write the top entry; `GIE` must be cleared while manipulating it | DS p.110 |
| ✔ `STVREN` configuration bit (default on): the 32nd push sets `STKOVF` and **resets the device**; an underflow sets `STKUNF` and resets. With `STVREN` off, no reset: pointer saturates at 31 | DS p.111 |
| ✔ `PUSH` and `POP` instructions exist; `STKPTR` is readable/writable | DS p.112, p.628 |
| ✔ The stack pointer is 0 after reset; there is no RAM for pointer value 0 | DS p.110 |
| ◐ **Compiler rule:** the proven maximum depth is `call depth of main line + 1 per interrupt level entered + call depth inside each handler`. With two priorities, a high-priority interrupt can arrive while a low-priority handler runs, so both entries count. Must be ≤ 31 (or the 32nd-push reset is reachable). | derived from the above |

## 4. Interrupts

| Fact | Source |
|---|---|
| ✔ Control registers: `INTCON`, `PIRx` (flags), `PIEx` (enables), `IPRx` (priority). There are **8** each of `PIR`, `PIE`, `IPR` | DS p.193, p.195 |
| ✔ `IPEN` = 0 (default): compatibility mode — all interrupts go to `0008h`; `GIE/GIEH` is the global enable and `PEIE/GIEL` enables peripherals | DS p.193 |
| ✔ `IPEN` = 1: priority mode — `GIEH` enables high-priority, `GIEL` enables low-priority; high vector `0008h`, low vector `0018h`; a high-priority interrupt can interrupt a low-priority one, never the reverse | DS p.193 |
| ✔ `INTCON` (0xFF2): bit 7 `GIE/GIEH`, bit 6 `PEIE/GIEL`, bit 5 `IPEN`. With `IPEN = 1`, `GIEH = 0` disables **all** interrupts and `GIEL = 0` the low-priority ones; `GIEH` is cleared by hardware for a high-priority interrupt, `GIEL` for a low-priority one | DS p.198 |
| ✔ `IPRx` bits reset to `1` (high priority); `PIE0` enables are not gated by `PEIE`; flags (`PIR0.TMR0IF` ...) are cleared by software | DS p.198–199, p.207, p.215–217 |
| ✔ Fixed vectors only. This part has **no vectored-interrupt table or base register** (none exists in the data sheet) | DS p.193 (and a full-text search of the data sheet) |
| ✔ On acknowledge: the global enable is cleared and the return address is pushed. `RETFIE` sets it again | DS p.193–194 |
| ✔ Flags are set whether or not enabled; flags must be cleared **by software** before re-enabling | DS p.194 |
| ✔ **Do not use `MOVFF` to modify any interrupt control register while any interrupt is enabled** (erratic behaviour) — a hard code-generation rule | DS p.194 |
| ✔ Latency for external interrupts: three to four instruction cycles | DS p.194 |
| ✔ Three external interrupt pins `INT0/1/2`, mapped through PPS to PORTA/PORTB pins; edge set by `INTxEDG` | DS p.195 |
| ✔ TMR0 flag `TMR0IF` is set on overflow (8-bit default, or 16-bit) | DS p.195 |
| ✔ **Fast register stack**: `STATUS`, `WREG` and `BSR` are saved automatically on interrupt entry into a one-level shadow stack (TO and PD are not copied). `RETFIE, FAST` restores them. | DS p.112, p.195 |
| ✔ If both priorities are enabled, the fast register stack **cannot be relied on for the low-priority handler**: a high-priority interrupt overwrites the shadow values. The low-priority handler must save and restore `WREG/STATUS/BSR` in software. | DS p.112 |
| ✔ If priority is not used, every interrupt may use the fast return | DS p.112 |
| ✔ `CALL label, FAST` / `RETURN, FAST` can use the same shadow stack for a subroutine | DS p.112 |
| ✔ Software save example uses `MOVWF`, `MOVFF STATUS,…`, `MOVFF BSR,…` | DS p.195 (Example 15-1) |
| ◐ **Language consequence (LANGUAGE.md §8):** single handler → hardware shadow registers (`RETFIE, FAST`); two priorities → high uses shadow, low saves in software. This matches the reference language's described behaviour. `#option ISR_SHADOW = false` forces software saving everywhere. | derived |

## 5. Instruction set

The core set is 75 instructions plus 8 extended instructions; most are one 16-bit word; four are
two-word. One instruction cycle is four oscillator periods. DS p.621–622.

| Fact | Source |
|---|---|
| ✔ **The four two-word instructions are `MOVFF`, `CALL`, `GOTO`, `LFSR`** (each takes 2 cycles) | DS p.626, p.628, p.629 |
| ✔ **`MULWF` and `MULLW`: 1 cycle**, result in `PRODH:PRODL`, no status flags | DS p.626, p.629 |
| ✔ Most ALU, bit and literal instructions: 1 cycle | DS p.626–629 |
| ✔ Skip instructions (`BTFSC`, `BTFSS`, `CPFSEQ/GT/LT`, `DECFSZ`, `DCFSNZ`, `INCFSZ`, `INFSNZ`, `TSTFSZ`): 1 cycle, 2 if the skip is taken over a one-word instruction, **3 if it skips a two-word instruction** | DS p.626–627; p.116 (Fig. 11-7) |
| ✔ `BRA n`: 2 cycles, 11-bit signed word offset; `RCALL n`: 2 cycles, 11-bit offset | DS p.628, p.625 |
| ✔ Conditional branches `BC BN BNC BNN BNOV BNZ BOV BZ`: 1 cycle not taken, 2 taken; 8-bit signed offset | DS p.628, p.625 |
| ✔ `GOTO k`, `CALL k[,s]`: 2 words, 2 cycles, 20-bit word address | DS p.628 |
| ✔ `RETURN [,s]`, `RETFIE [,s]`, `RETLW k`: 2 cycles | DS p.628 |
| ✔ `TBLRD*`, `TBLRD*+`, `TBLRD*-`, `TBLRD+*`: 2 cycles; `TBLWT` likewise | DS p.629 |
| ✔ `LFSR f,k` loads a 12-bit literal into an FSR: 2 words, 2 cycles | DS p.629 |
| ✔ `MOVLB k` sets `BSR`: 1 cycle | DS p.629 |
| ✔ `SWAPF`, `RLCF`, `RLNCF`, `RRCF`, `RRNCF`, `SETF`, `CLRF`, `BTG`, `DAW`, `PUSH`, `POP`, `NOP`, `SLEEP`, `CLRWDT`, `RESET` all exist | DS p.626–629 |
| ✔ Extended set (needs `XINST = 1`): `ADDFSR, ADDULNK, CALLW, MOVSF, MOVSS, PUSHL, SUBFSR, SUBULNK` | DS p.682 |
| ◐ Exact bounds of `BRA` / `BC` ranges and the encoding of the shift/rotate forms: confirmed from the encodings; the instruction description pages are read in M4 when branch relaxation is implemented | → M4 |

## 6. Clock and configuration

| Fact | Source |
|---|---|
| ✔ Max system clock 64 MHz; minimum instruction cycle 62.5 ns | DS p.1 |
| ✔ Instruction cycle = 4 oscillator periods (so 64 MHz → 16 MIPS) | DS p.622 |
| ✔ `CONFIG1[RSTOSC]` selects the clock at reset (DS p.53, Table 5-1): `111` = EXTOSC per `FEXTOSC`; `110` = HFINTOSC divided to 1 MHz; `101` = LFINTOSC; `100` = SOSC; `010` = EXTOSC + 4×PLL; **`000` = HFINTOSC at 64 MHz**; `011`, `001` reserved | DS p.53 |
| ✔ **Every configuration word's default is `0xFF`**, so an unconfigured part has `RSTOSC = 111` (external oscillator). A program that does not set the oscillator would depend on an external clock. | PACK default `0xFF`; DS p.53 |
| ✔ **Therefore the compiler always emits the full set of config words explicitly** and (planned) refuses to compile if the oscillator is not specified. A `Clock` that contradicts `RSTOSC` is only a `W-CLOCK` warning, see `docs/CLOCK.md` | derived (PLAN §8.3) |
| ✔ Config registers `CONFIG1L … CONFIG6H` at `0x300000 … 0x30000B`, with fields: `FEXTOSC, RSTOSC` (1L); `CLKOUTEN, CSWEN, FCMEN` (1H); `MCLRE, PWRTE, LPBOREN, BOREN` (2L); `BORV, ZCD, PPS1WAY, STVREN, DEBUG, XINST` (2H); `WDTCPS, WDTE` (3L); `WDTCWS, WDTCCS` (3H); `WRT0–WRT7` (4L); `WRTC, WRTB, WRTD, SCANE, LVP` (4H); `CP, CPD` (5L); `EBTR0–EBTR7` (6L); `EBTRB` (6H) | PACK `DCRDef` |
| ✔ `RSTOSC` setting names accepted by pic-as: `HFINTOSC_64MHZ, HFINTOSC_1MHZ, EXTOSC_4PLL, EXTOSC, SOSC, LFINTOSC`; `FEXTOSC`: `LP, XT, HS, ECL, ECM, ECH, OFF` | PACK; pic-as accepted `RSTOSC = HFINTOSC_64MHZ` on this machine |
| ✔ `OSCCON1` at `0xED3`: `NOSC[2:0]`, `NDIV[3:0]` select the running source and divider; read-only when `CSWEN = 0` | DS p.53–54 |
| ✔ Oscillator modes: `LP` is for 32.768 kHz watch crystals; `XT` for 100 kHz–4 MHz resonators (but see ES 1.7.2: limited to 2 MHz); `HS` above 4 MHz; EC modes ECL < 1 MHz, ECM 1–16 MHz, ECH > 16 MHz | DS p.43; ES p.6 |
| ✔ `XINST` (extended instruction set) and `STVREN` live in `CONFIG2H` | PACK |

## 7. Errata that affect this project (ES p.2–8)

| Item | Effect | Applies to |
|---|---|---|
| 1.9.1 PFM self-write: the first instruction after a self-write may not execute. **Workaround: add two all-zero `NOP`s immediately after the self-write instruction.** | The flash-write library emits exactly two `NOP`s after the write sequence | rev A4 and B2 |
| 1.6.2 No program-flash writes above 85 °C | Library documentation only | A4, B2 |
| 1.7.2 XT mode limited to 2 MHz (use HS above) | Compiler warns when `FEXTOSC = XT` with `Clock` > 2 | A4, B2 |
| 1.7.1 HFINTOSC varies up to 5 % over voltage/temperature | Serial library documents baud-rate error for internal-oscillator designs | A4, B2 |
| 1.4.1 FVR reference → missing codes (use TAD ≥ 8 µs, or VDD reference) | ADC library default is VDD | A4, B2 |
| 1.4.4 first conversion after a large falling input step is wrong (discard it) | ADC library discards one sample after a channel change | A4, B2 |
| 1.2.1 `RMCLR` flag in `PCON0` may be cleared by POR/software reset; no workaround | Reset-cause routine documents it | A4, B2 |
| 1.8.1 No software breakpoints | None (no debugger integration) | A4, B2 |
| 1.1.1 Industrial temperature only | None | A4, B2 |

Items for peripherals not yet in the library (WWDT in Doze, CWG shutdown sources, LPBOR,
NVMERR, ADC burst mode) are recorded in the data sheet's errata and handled when that
peripheral gets library support.

There are **no data sheet clarifications** (ES p.8, section 2.1).

---

## 8. Resolved "TO VERIFY (M1)" items

| Item (where it was raised) | Resolution |
|---|---|
| Two-word instruction list (PLAN §5.3) | `MOVFF`, `CALL`, `GOTO`, `LFSR` — DS p.626–629 |
| Multiplier instructions and cost (PLAN §7A.1 #4, §7.4) | `MULWF`, `MULLW`, 1 cycle — DS p.626, p.629 |
| Access Bank split and GPR ranges (PLAN §5.3) | §1–2 above |
| Interrupt registers, vectors, context save (PLAN §5.4, LANGUAGE §8, ABI §2) | §4 above |
| `XINST` effects (PLAN §7.2) | §2 above — default build uses `XINST = 0` |
| Instruction cycle costs named in PLAN §7A | §5 above |
| Errata 1.9.1 full text (PLAN §5.5) | §7 above — two `NOP`s, not one |
| Config word layout and setting names (PLAN §8.3) | §6 above |
| Whether a vectored-interrupt scheme exists (PLAN §5.4) | It does not — fixed vectors only |

## 9. Still open (later milestones)

* `BRA`/`BC` exact range and branch-relaxation rules — M4 (read the instruction description pages).
* Purpose and rules for bank 13 "SECTOR" RAM, flash-write and EEPROM routines — M8 (NVM chapter).
* Peripheral register maps (EUSART, ADCC, timers, MSSP, PPS) — read per library module in M6/M8.
* Reset sequence, `PCON0` reset flags, clock-switch timing — M6 (`system` library).
* Whether `FSR1`/`FSR2` can be left to the programmer — M4 (ABI).
