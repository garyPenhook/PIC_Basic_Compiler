# Common 8-bit PIC application benchmarks

Small application workloads for PIC16F18346 and PIC18F27Q10, separate from the
algorithm/DSP stress programs in `bench/large`. Each workload has matching BASIC
and portable fixed-width C sources. All four optimized BASIC images use less
than 400 PIC16 instruction words and no more than 50 reported RAM bytes in the
initial baseline.

| Workload | Application work | Run length | Checked sink |
| --- | --- | --- | ---: |
| `sensor` | Read a 10-bit ADC trace, average eight samples, scale to 0–5000 mV, apply heater/alarm hysteresis and pack output bits | 64 control updates | 167716 |
| `buttons` | Debounce a bouncing input, detect press edges, toggle an LED, reload 10 ms and 100 ms countdown timers | 1000 logical 1 ms ticks | 2652 |
| `frames` | Parse a UART-style sync/command/value/XOR frame, update four registers, consume accepted payloads, reject bad checksums and unknown commands | 32 passes over a 32-byte stream | 22784 |
| `display` | Convert ADC and millivolt readings to fixed-width decimal ASCII, construct a 16-column LCD status line, consume its characters | 64 display refreshes | 474523 |

The inputs include ADC endpoints and threshold crossings, press/release bounce,
noise before synchronization, malformed and truncated frames, and zero-padded
numbers. Byte/Word arithmetic does the application work; the ADC-to-millivolt
conversion widens to 32 bits to avoid overflowing `reading * 5000`. The shared
32-bit volatile sink is an observable checksum, updated at matching points in
both languages. `sensor` and `frames` use constant input tables rather than
calling peripheral libraries.

These measure firmware computation on deterministic inputs. They do not measure
ADC conversion time, UART baud rate, ISR latency, physical switch behavior or LCD
bus transfers. A logical 1 ms tick in `buttons` is one loop iteration, with no
real-time delay. The input handling and checksum work are included in timing.

## Run

Build the compiler with `cargo build --release`. The default runner requires a
host C compiler (`cc`), pic-as/device packs for BASIC assembly, and basil-sim
(default: the sibling `picsim/target/release/basil-sim`).

From the repository root:

```sh
# Optimized BASIC, both cores; every result checked against host C.
python3 bench/embedded/run.py

# Full correctness and comparison matrix: BASIC, BASIC -O0, XC8 -Os and -O2.
python3 bench/embedded/run.py --o0 --xc8

# One workload on one core.
python3 bench/embedded/run.py --device 16F18346 display
```

`--basil`, `--sim`, `--cc` and `--xc8-cc` override executable locations.
`--device` may be repeated; the supported parts are `16F18346` and `18F27Q10`.
The runner uses a temporary directory and removes build products on exit.
With `--xc8`, it finds installed Microchip PIC16F1xxxx/PIC18F-Q packs under
`~/.mchp_packs/Microchip` and selects the newest installed version.

The runner first builds and executes each C reference on the host and checks
its result against the BASIC file's `expect` declaration. It then compiles,
simulates and verifies every requested target build, failing on compiler or
simulator errors, nontermination, or a different sink. The individual BASIC
files also work with `scripts/exec-test.py --no-keep-vars`.

Flash is reported in **bytes** on both cores (PIC16 words are multiplied by two).
RAM is the compiler's reported whole-image RAM use. Cycles run from reset to the
end marker, including startup and all workload iterations. The C end marker is
an inline assembly label, so it needs no marker function or marker-call
subtraction. Builds use the default BASIC optimization/storage policy, rather
than `--keep-vars`. BASIC `-O0` is a correctness and optimization comparison,
not a claim that every optimization reduces execution time.

## Initial results

[BASELINE.md](BASELINE.md) records all 32 verified runs with Basil 0.1.259 and
XC8 v4.00 on 2026-11-17. Compare each workload and core separately. Do not mix
these numbers into the existing DSP or large-program aggregate: the workloads,
input lengths and timing boundaries differ. These are authored application
models, not an independent sample of production firmware or hardware timings.
