# Examples

Complete programs that show library modules, sensors and displays at work. Each one builds as it is:

```sh
basil examples/PIC18F27Q10/onchip/timer_interrupt_blink.bas
```

`cargo test examples_build` compiles every program in this folder, so an example that stops building is caught.

## Layout

By processor, then by the sensor or external part the program uses:

```
examples/
  PIC18F27Q10/                  the Device the program is written for
    onchip/                     on-chip peripherals only (timers, ADC, PWM ...), at most an LED or a button
      timer_interrupt_blink.bas
    <sensor or part>/           e.g. aht30, ds18b20, hd44780, ssd1309, mcp7940n
      <what_it_shows>.bas
  <another processor>/
    ...
```

* The **processor folder** is named after the `Device` value with its `PIC` prefix (`PIC18F27Q10`, `PIC16F18346`).
* The **sensor folder** is named after the part (lower case, as on the chip), not the library module, so
  two programs for the same sensor sit together whichever module drives it. A program that uses several
  external parts goes in the folder of the main one, and its header lists the others.
* The same idea on another processor is its own program in that processor's folder.
* A program that has been run in basil-sim keeps its board next to it (`<program>.stim.toml`: the simulated
  sensors and displays), with the command line in the file's first lines. The editor command *PIC BASIC: Debug in Simulator* picks that file up
  automatically, so an example can be stepped through with its board attached.

## How an example is written

* **A header comment** at the top says what the program does, the device it is written for, what to connect
  (pin, part, pull-ups, supply) and what you should see. Anything the program cannot check itself, such as a
  waveform or a display, is stated as what to look for.
* **A full program**: `Program`, `Device`, `Clock`, `Config` and every `Include`, so it builds and runs without
  editing.
* **Short and on one topic.** The manual has an entry per routine; an example shows how the routines fit
  together in a real program.
* **Hardware status.** Say whether the program has been run on a real chip, only in the simulator
  (`basil-sim`), or only built. Nothing has been run on hardware yet unless the header says so.

## Index

For a first PIC16 program, see [Program a Microchip PIC16 in BASIC](../docs/PIC16-BASIC-TUTORIAL.md).

| Processor | Sensor / part | Program | Modules | Shows |
|---|---|---|---|---|
| PIC16F18346 | onchip (LED) | [`onchip/blink.bas`](PIC16F18346/onchip/blink.bas) | none | RC0 LED blink with a 500 ms delay and internal 32 MHz oscillator; beginner tutorial |
| PIC18F25K22 | aht30, ssd1309 | `aht30/aht30_oled_display.bas` (+ `.stim.toml` for basil-sim) | `intosc`, `i2c`, `aht30`, `oled`, `format` | Temperature and humidity once a second on a 128 x 64 OLED, both on the MSSP1 I2C bus; a sensor error shown as its status code |
| PIC18F27Q10 | onchip (LED) | `onchip/timer_interrupt_blink.bas` | `intosc`, `timer` | Timer0 overflow interrupt toggling an LED, with the flag cleared in the handler |
