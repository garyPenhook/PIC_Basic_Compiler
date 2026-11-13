# Next library features (from a review of the classic PIC BASIC command sets)

Source: a review of the commands that the classic PIC BASIC compilers offer and basil does not (2026-11-13).
Rules for every item: written from the *behaviour* only (PLAN §2, clean room); no other product's name in
docs, manual or library comments; **every word counts** (a routine is compiled only when called, shared work
lives in one routine, measure with `--report` before and after, prefer overloads by width to one wide
routine); a new module gets a test in `tests/exec` (`' expect:` line) and, where the part differs, a
`_has(...)` branch; bump the version with each change.

Not planned: `**`, `*/`, `Div32` (basil has 32-bit maths), a `Define` switch system (modules take arguments),
USB (no supported part has it), the 12-bit core, polled-interrupt mode (`Interrupt` and `Event` cover it).

## Status

| # | Feature | Module | State |
|---|---|---|---|
| 1 | Number formatting with width, fill, radix, sign | `format` (new) | **done 0.1.220** (`FmtDec`, `FmtSDec`, `FmtHex`, `FmtBin`; manual, `tests/exec/lib_format.bas`) |
| 2 | Receive with timeout, line, wait-for-text, decimal parse | `serial`, `serial2` | **done 0.1.221** (`SerialReadTimeout`, `SerialReadLine`, `SerialWaitFor`, `SerialReadDec`; tests `lib_serial_rx`, `lib_serial2_rx` with a `' stim:` file) |
| 3 | Software asynchronous serial on any pin | `softserial` (new) | **done 0.1.222** (`SoftInit`, `SoftWriteByte`, `SoftWrite`, `SoftNewLine`, `SoftReadByte` (-1 timeout, -2 framing error), `SoftAvailable`, `SoftHoldIrq`; `scripts/test_softserial.py`, bench program `tests/hw/softserial_echo.bas`) |
| 4 | 1-Wire: reset/presence, bit and byte transfer, ROM search, CRC8 | `onewire` (new) | **done 0.1.223** (`OwInit`, `OwReset`, `OwWriteBit/Byte`, `OwReadBit/Byte`, `OwCrc8`, `OwSearchFirst/Next`, `OwSelect`, `OwSkip`; `pinio` `BindOd`/`OdLow`/`OdRelease`/`OdRead`; `scripts/test_onewire.py`, exec `lib_onewire`). The CRC differs from the `aht30` one (reflected 0x8C, start 0), so it is not shared. Open-drain `softserial` not done |
| 5 | Pre-loaded data EEPROM image in the `.hex` | compiler (`Data` / `EData`) | planned, check no mechanism exists first |
| 6 | 8-bit integer `Sin`, `Cos`, `Atn`, `Hyp` (binary radians, quarter-wave table) | `bits` or `imath` | planned |
| 7 | `FreqCount(pin, ms)` pulse counting over a window | `timer` / `pulse` | planned |
| 8 | `DtmfOut(pin, ...)` | `pulse` (over `Sound2`) | planned |
| 9 | `ClrWdt()` intrinsic | compiler | planned |
| 10 | `LcdRead` (busy flag, RW pin) | `lcd` | later |

## 1. format

Output modules take a `String` (`SerialWrite`, `LcdWrite`, `OledWrite`, `GlcdWrite` all use `ByRefConst`), so
the formatter fills one shared buffer and the caller passes the buffer on. One shared routine replaces a
`Str` expansion at every call site (60 to 165 words each), and no output module changes.

```basic
Include "format"
FmtDec(w, 5, "0")        ' FmtBuf = "00042"      (width = minimum width; never cuts a longer number)
FmtSDec(i, 6, " ")       ' FmtBuf = "   -42"
FmtHex(b, 2)             ' FmtBuf = "2A"         (digits = exactly that many, low digits)
FmtBin(b, 8)             ' FmtBuf = "00101010"
SerialWrite(FmtBuf)
```

* `FmtBuf` is `Public Dim FmtBuf As String(33)`: 32 binary digits and the `Null`.
* `FmtDec` is overloaded on `Byte`, `Word` and `LongWord` so a byte never pays for a 32-bit divide; `FmtSDec` on
  `ShortInt`, `Integer`, `LongInt`.
* `FmtHex` and `FmtBin` take the value as it is and write the low `digits` digits (as the classic `HEXn` and
  `BINn` do), using shifts, no divide.

## 2. Serial receive helpers

`SerialReadTimeout(ms)` (a byte or -1), `SerialReadLine(ms)` (into `SerialLine`), `SerialWaitFor(text, ms)` and
`SerialReadDec(ms)` (into `SerialNumber`), on the polled receiver (there is no receive ring), with a Timer-free
wait of `DelayUs(50)` polls. Results go in public module variables and a private byte, not `ByRef` parameters:
a `ByRef` costs a pointer set-up at every access (measured: `SerialReadDec` 211 words with `ByRef`, 132 without).
Same routines for `serial2`.

## 3. softserial

`SoftInit(tx, rx, baud, inverted)`, `SoftWriteByte`, `SoftWrite(String)`, `SoftReadByte(ms)`. Bit time from `Clock`
in instruction cycles (a counting loop plus a measured fixed cost, per core); interrupts are the caller's to hold off.
Not done: open-drain output for a shared line (with item 4), parity or other than 8N1, a receive buffer (needs a pin interrupt and a timer: the hardware EUSART is the answer).

## 4. onewire

`OwReset()` (True when a device answers), `OwWriteBit/Byte`, `OwReadBit/Byte`, `OwSearch`, `OwCrc8` (shares the
Dallas CRC with the `aht30` `Crc8` if the polynomials agree; check). Timing from `Clock` at build time.

## 5-9

Small; each gets a design note here when started.
