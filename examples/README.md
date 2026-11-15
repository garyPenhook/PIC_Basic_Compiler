# Examples

Complete programs that show a library module, a sensor or a display at work. Each one builds as it is:

```sh
basil examples/timer/timer_interrupt_blink.bas
```

`cargo test examples_build` compiles every program in this folder, so an example that stops building is caught.

## Layout

One folder per module or device, one program per idea:

```
examples/
  timer/        timer_interrupt_blink.bas
  <module>/     <what_it_shows>.bas
```

## How an example is written

* **A header comment** at the top says what the program does, the device it is written for, what to connect
  (pin, part, pull-ups, supply) and what you should see. Anything the program cannot check itself, such as a
  waveform or a display, is stated as what to look for.
* **A full program**: `Program`, `Device`, `Clock`, `Config` and every `Include`, so it builds and runs without
  editing. The examples use the PIC18F27Q10 unless they are about another part; the header says how to move
  it to another device when that needs more than changing `Device`.
* **Short and on one topic.** The manual has an entry per routine; an example shows how the routines fit
  together in a real program.
* **Hardware status.** Say whether the program has been run on a real chip, only in the simulator
  (`basil-sim`), or only built. Nothing has been run on hardware yet unless the header says so.

## Index

| Folder | Program | Shows |
|---|---|---|
| `timer` | `timer_interrupt_blink.bas` | Timer0 overflow interrupt toggling an LED, with the flag cleared in the handler |
