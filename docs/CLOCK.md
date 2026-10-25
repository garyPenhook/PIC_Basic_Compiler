# Clock and oscillator set-up

This chapter is written to go into the manual unchanged. Register facts are from the PIC18F27/47Q10
data sheet (DS40002043F); the section numbers in brackets are that document's.

## 1. What `Clock` does, and what it does not

```
Device = 18F27Q10
Clock = 16
```

`Clock` is a **declaration of the speed the program expects**, in MHz (it may be fractional, e.g.
`Clock = 0.5`). The compiler uses it to time `DelayMs`, `DelayUs` and the baud-rate, period and
divider calculations of the library modules, and a program can read it back as `_Clock`.
**It does not change the hardware.** The speed the chip really runs at is set by two things in the
program's own source:

1. the **configuration word** `RSTOSC` (and `FEXTOSC`, `CSWEN`) in the `Config` line, which decides
   the speed the part starts at, and
2. **register writes** (`OSCFRQ`, `OSCCON1`) that run after start-up, either written by hand or
   by the `IntOsc` module (§3).

If the two disagree, the program still builds, but every delay and baud rate is wrong by the ratio
between them. The compiler warns about the common case (§5), and `System.SysClockOk()` tests it
while the program runs.

This is a common design for BASIC compilers (§7): the clock declaration is informational, and the
oscillator is set up in source.

## 2. What the hardware offers

The part has one high-frequency internal oscillator, **HFINTOSC**, that can run at 1, 2, 4, 8, 12,
16, 32, 48 or 64 MHz, chosen by `OSCFRQ.HFFRQ` [5.6.5]:

| HFFRQ | MHz | HFFRQ | MHz | HFFRQ | MHz |
|---|---|---|---|---|---|
| 0000 | 1 | 0011 | 8 | 0110 | 32 |
| 0001 | 2 | 0100 | 12 | 0111 | 48 |
| 0010 | 4 | 0101 | 16 | 1000 | 64 |

(`1001`–`1111` are reserved.) The output can be divided by 1, 2, 4 … 512 (`OSCCON1.NDIV`, code
0..9 for 2^code) [5.6.1, Table 5-3]. `OSCCON1.NOSC` = `110` selects HFINTOSC [Table 5-2]. The
oscillator in use now is shown, read-only, in `OSCCON2` (`COSC`, `CDIV`) [5.6.2].

At reset the part starts as `RSTOSC` says [Table 5-1]:

| `RSTOSC` | Starts at |
|---|---|
| `HFINTOSC_64MHZ` (000) | HFINTOSC 64 MHz, divider 1:1 (NOSC = 110, NDIV = 0000, OSCFRQ = 64 MHz) |
| `HFINTOSC_1MHZ` (110) | HFINTOSC 4 MHz divided by 4 = 1 MHz |
| `LFINTOSC`, `SOSC`, `EXTOSC`, `EXTOSC_4PLL` | 31 kHz, 32 kHz crystal, external clock, external clock × 4 |

Every configuration word defaults to 0xFF, so a program that leaves `RSTOSC` out starts on the
external oscillator (111). The compiler therefore wants an oscillator setting in `Config`.

`OSCCON1` can only be written when `CSWEN = ON` in the `Config` line [5.6.1 note 3]; `OSCFRQ` can be
written either way.

## 3. Setting the clock from the program: `Include "intosc"`

```
Device = 18F27Q10
Clock = 16
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, CSWEN = ON, WDTE = OFF, LVP = ON
Include "intosc"          ' first include, so everything after it runs at 16 MHz
```

Including the module is all it takes: its start-up code, which runs before the main program, writes
`OSCFRQ` and `OSCCON1` to match `Clock`. Accepted `Clock` values:

| `Clock` | OSCFRQ | NDIV | `Clock` | OSCFRQ | NDIV |
|---|---|---|---|---|---|
| 64 | 8 | 0 | 0.5 | 0 | 1 |
| 48 | 7 | 0 | 0.25 | 0 | 2 |
| 32 | 6 | 0 | 0.125 | 0 | 3 |
| 16 | 5 | 0 | 0.0625 | 0 | 4 |
| 12 | 4 | 0 | 0.03125 | 0 | 5 |
| 8 | 3 | 0 | | | |
| 4 | 2 | 0 | | | |
| 2 | 1 | 0 | | | |
| 1 | 0 | 0 | | | |

Any other `Clock` is a compile-time error naming the valid values (`E-PP-ERROR`), because the
module checks it with `#if` / `#error` (LANGUAGE.md §11).

Notes for the user:

* **`CSWEN = ON`** is needed unless `Clock` already equals what `RSTOSC` starts at. With `CSWEN = OFF`
  the `OSCCON1` write is ignored; `OSCFRQ` is still written. When something was ignored,
  `System.SysClockOk()` returns False.
* The module always selects HFINTOSC, so it also works from `RSTOSC = HFINTOSC_1MHZ` and, with
  `CSWEN = ON`, from an external or low-frequency start.
* `OSCTUNE` is left alone; `CSWHOLD` (OSCCON3, reset 0) must stay clear or a switch never finishes.
* A 31 kHz clock (`Clock = 0.03125`) is HFINTOSC at 1 MHz divided by 32, not the LFINTOSC.

### Changing the clock while the program runs

| Routine | Effect |
|---|---|
| `IntOsc.SetClock(mhz)` | HFINTOSC at `mhz` (1, 2, 4, 8, 12, 16, 32, 48 or 64), divider 1:1 |
| `IntOsc.SetClockDiv(mhz, shift)` | the same divided by 2^`shift` (`shift` 0..9) |

Both return a `Boolean`: True when the clock switched and OSCCON2 / OSCFRQ read back as written;
False, with nothing written, for a `mhz` or `shift` the part does not have; False also when the
switch did not complete (for instance `CSWEN = OFF`).

**Library timing does not follow a run-time change.** `DelayMs`, `DelayUs`, `Serial`, `Pwm`,
`I2c`, `Spi` and `Adc` compute from the compile-time `Clock`. After `SetClock(4)` in a
`Clock = 16` program they run four times too slow until the clock is put back. Use a run-time
change for phases that need none of them (for example a low-power wait on a timer-free loop), and
restore the clock before using them again. A later release could make the timing variable; it is
not planned (see PROGRESS.md, M8 system).

Interrupts: the module does not mask them. A handler that fires during a switch runs at whichever clock is
active at that moment, so its own timing is unreliable for that instant; do not call `SetClock` from a
handler (it is not reentrant, and the library timing it would affect is the program's, not the handler's).

### What the module does to the registers

1. Reads `OSCCON2.CDIV` (the divider in force now).
2. If the new divider is larger: writes `OSCCON1` (NOSC = 110, NDIV), waits for `OSCCON3.ORDY`, then
   writes `OSCFRQ`. Otherwise writes `OSCFRQ`, then `OSCCON1`. The data sheet does not give an
   order; this one keeps the clock from ever running faster than the faster of the old and the
   new setting.
3. Waits for `OSCCON3.ORDY = 1` ("the current clock is the one NOSC specifies", [5.6.3]) and
   `OSCSTAT.HFOR = 1` (HFINTOSC ready, [5.6.4]). Each wait is bounded (60000 polls in all) so a part
   that never answers cannot hang the program.
4. Reads `OSCCON2` and `OSCFRQ` back to compare.

Clock switching is described in [5.3]: a divider-only change is ready almost at once, a change of
source waits for the new source to be ready.

## 4. Setting the clock by hand

The module is a convenience. The same effect, for a program that wants only one speed, is

```
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, CSWEN = ON, WDTE = OFF, LVP = ON
OSCFRQ = 5                ' HFFRQ = 0101 = 16 MHz
```

with `Clock = 16` above. Writing `OSCFRQ` or `OSCCON1` anywhere in the program also silences the
`W-CLOCK` warning (§5). Registers named in the data sheet can be used directly; the register
definitions come from the device description.

## 5. The `W-CLOCK` warning

When `RSTOSC` is `HFINTOSC_64MHZ` or `HFINTOSC_1MHZ`, the part starts at 64 MHz or 1 MHz. If `Clock`
says something else and nothing in the program sets the oscillator, the compiler warns:

```
warning[W-CLOCK]: Clock is 16 MHz but RSTOSC starts the part at 64 MHz and nothing sets the oscillator: ...
```

"Sets the oscillator" means the program includes `intosc`, or has a statement that begins with
`OSCFRQ` or `OSCCON1` followed by `=` or `.` (a write). Other `RSTOSC` values (external, low-frequency)
are not checked, because their speed is not known to the compiler. `#option Warn.Clock = false`
turns it off.

Limits of the check: it looks at the text of the source files, not at what runs. A write inside a single-line
`If … Then OSCFRQ = x`, an `Asm` block or a `Sub` that is never called is not seen (or counts although it never
runs). The `RSTOSC` values it knows are the Q10 ones.

Limits of `#if` and `_clock` / `_device`: they come from the first plain `Clock = n` (or `Declare Xtal = n`) and
`Device = name` line of the **main** file, with `n` a number. Keep those lines out of `#if` regions and comments,
and in the main file, not in an included file.

## 6. Checking at run time

`System.SysClockHz()` reads the speed the oscillator really runs at from `OSCCON2` and `OSCFRQ`
(nominal, `OSCTUNE` ignored) and `System.SysClockOk()` compares it with `Clock`; see LIBRARY.md,
*system*. A program can test it once at start and signal an error if it is False.

## 7. Design background

Other BASIC compilers use `clock = n` or `Declare Xtal = n` as an informational declaration of the
expected frequency, with the hardware set up either by a library include (for the Q10: `RSTOSC =
HFINTOSC_64MHZ`, `FEXTOSC = OFF`, `CSWEN = ON` in the configuration, and at start-up `OSCCON1` and
`OSCFRQ` written, with `NDIV` raised for speeds below 1 MHz) or by procedures the program calls that
write `OSCCON1`, `OSCCON3`, `OSCEN`, `OSCFRQ` and `OSCTUNE` and wait on the status flag.

`IntOsc` is an include that reads `Clock`, plus a run-time call, and the configuration stays visible in
the program source. It adds the check that the divider and `OSCFRQ` really switched (read back) and
the data-sheet-ordered write sequence.

## 8. Related changes made with this feature

* **`#if` / `#elseif`** now work in the preprocessor (LANGUAGE.md §11), with `_clock` and `_device`
  taken from the program's `Clock` and `Device` lines. `IntOsc` uses them for its table and for
  the `#error`.
* **`W-CLOCK`** (§5).
* Tests: `tests/exec/lib_intosc.bas`, `lib_intosc_div.bas`, `pp_if.bas` (simulator),
  `tests/negative/intosc_bad_clock.bas`, `pp_if_bad.bas`, `pp_constant_unsupported.bas`,
  `tests/valid/clock_*.bas`.

Not yet checked on hardware (D6). The simulator does not model `ORDY`, `HFOR` or `OSCCON2`, so its
tests check the values written and the refusals; whether the switch completes needs a part.
