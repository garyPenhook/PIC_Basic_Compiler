# Program a Microchip PIC16 in BASIC with the Basil compiler

This tutorial builds an LED blink program for the **Microchip PIC16F18346**
using **Basil**, a BASIC compiler for selected PIC16 and PIC18 microcontrollers.
You will write a complete BASIC program, compile it to a `.hex` file and see
how much flash and RAM it needs. Basil runs on Windows, Linux and macOS.

The example below has been assembled and checked in the basil-sim simulator.
It has not yet been tested on a physical microcontroller.

## What you need

- The [Basil compiler download](https://github.com/garyPenhook/PIC_Basic_Compiler/releases/latest)
  for your operating system. Extract the archive and put its `basil` executable
  on your `PATH`. Rust is only needed if you build Basil from source.
- Microchip MPLAB XC8, which supplies the `pic-as` assembler, and the
  `PIC16F1xxxx_DFP` device pack. Install these separately; they are not bundled
  with Basil. See the [tool setup instructions](../QUICKSTART.md#1-prerequisites).
- For a physical build: a PIC16F18346, an LED with a series resistor, a suitable
  supply and a compatible ICSP programmer, such as a PICkit supported by your
  installed Microchip programming tools.

Run these commands to check the compiler and tool setup:

```sh
basil --version
basil --doctor
```

`--doctor` reports the assembler and device packs it finds. For explicit tool
paths, see the [quick start](../QUICKSTART.md). This tutorial's measurements
use Basil 0.1.260.

## Connect an LED to RC0

Connect **RC0 → 330 ohm resistor → LED anode**, with the LED cathode connected
to **VSS (ground)**. A high output turns the LED on. Choose the device's supply,
decoupling, reset and ICSP connections using the
[Microchip PIC16F18346 product page and datasheet](https://www.microchip.com/en-us/product/PIC16F18346).
Use the pin diagram for your package: RC0 is a port name, not a physical pin
number. On a development board, check its schematic for the onboard LED's pin
and polarity before adapting this example.

## Write the BASIC program

Save this as `blink.bas`, or use the repository's
[complete PIC16 example](../examples/PIC16F18346/onchip/blink.bas):

```basic
Program Blink
Device = 16F18346
Clock = 32
Config FEXTOSC = OFF, RSTOSC = HFINT32, WDTE = OFF, LVP = ON

Dim led As PORTC.0

ANSELC = 0
LATC = 0
Output(led)
While True
    Toggle(led)
    DelayMS(500)
Wend
```

`Device` selects the PIC16F18346. `Clock = 32` tells Basil to calculate delays
for a 32 MHz oscillator, and `RSTOSC = HFINT32` selects that internal oscillator
configuration at reset. The clock declaration must agree with the hardware
configuration; changing `Clock` alone does not change the oscillator.

`Dim led As PORTC.0` names the RC0 pin. `ANSELC = 0` makes port C digital,
`LATC = 0` initializes its output latch, and `Output(led)` makes RC0 an output.
The loop toggles the LED and waits 500 milliseconds: approximately half a second
on, then half a second off. No external oscillator or library module is needed
for this example.

## Compile BASIC into PIC firmware

```sh
basil --check blink.bas
basil --report blink.bas
```

The first command checks syntax and types. The second compiles and invokes the
Microchip assembler to produce `blink.hex`, with `blink.S` assembly and a
`blink.map` map file. Its report includes:

```text
Program: 23 words (46 bytes)
Data RAM:
  0x070    3  __D
  total 3 bytes (overlaid objects share addresses)
```

The three RAM bytes are compiler scratch storage for the delay. The `led`
declaration aliases a hardware pin; it does not allocate a separate variable.

Open `blink.hex` in your Microchip programming tool, select **PIC16F18346**,
and program the device through ICSP. After programming, the expected behavior
is an LED changing state roughly every 500 ms. Programming the chip is separate
from compiling the source.

## Measured flash, RAM and timing

The following results were checked with Basil 0.1.260 and basil-sim on
PIC16F18346, using the default optimized build:

| Measurement | Result |
| --- | ---: |
| Program size, including startup and delay | 23 instruction words / 46 bytes |
| Reported data RAM | 3 bytes |
| Simulator cycles between successive loop entries | 4,000,005 |
| Nominal time between loop entries at 32 MHz | 500.000625 ms |

PIC16 executes one instruction cycle per four oscillator clocks. At 32 MHz,
4,000,000 instruction cycles represent 500 ms; the five extra cycles are loop
and toggle overhead. Physical timing also depends on oscillator accuracy.

For a larger example, the
[decimal display benchmark](../bench/embedded/display.bas) formats ADC and
millivolt readings into a 16-character line. On the same compiler version and
device it uses **774 flash bytes, 50 RAM bytes and 690,230 simulator cycles**
for 64 updates, with checked result `474523`. This measures formatting and
checksum work, not LCD bus transfers or ADC conversion time. The
[benchmark runner](../bench/embedded/README.md) explains how to reproduce it.
These are project-authored examples, not a claim about every PIC application.

## If the LED does not blink

| Symptom | Check |
| --- | --- |
| `pic-as` or a device pack is missing | Run `basil --doctor` and follow the paths in its report. |
| Configuration value is rejected | Use the exact `Device` and `Config` lines above; other PIC families use different oscillator names. |
| Firmware builds but the LED stays dark | Check supply, ICSP programming, LED polarity, series resistor and the RC0 connection. |
| An onboard LED does not respond | Check the board schematic; it may use another port or turn on with a low output. |
| Blink timing is wrong | Check that `Clock` and the actual oscillator configuration agree. |

## Continue with PIC BASIC

- [Language and supported-device manual](MANUAL.md): types, loops, functions,
  interrupts, registers and supported PIC16/PIC18 families.
- [Peripheral libraries](LIBRARY.md): GPIO, serial, ADC, timers, I2C, SPI and displays.
- [More complete examples](../examples/README.md).
- [PIC compiler benchmarks](BENCHMARKS.md) and
  [optimization measurements](EFFICIENCY.md).

To use a different PIC16 or a PIC18, start with its supported-device entry and
an example for that family. Configuration bits, registers and pin assignments
can differ; changing only the `Device` line is not always sufficient.
