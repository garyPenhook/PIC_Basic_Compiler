# pic-config

![pic-config](../../docs/images/pic-config.png)

Qt 6 / C++ helper that turns drop-down choices into a `Config` line (basil) or `#pragma config`
lines (XC8) to paste into a source file.

## Build and run

    cmake -S . -B build -G Ninja -DCMAKE_PREFIX_PATH=$HOME/Qt/6.12.0/gcc_64
    cmake --build build
    ./build/pic-config

## Adding a PIC

Drop the part's Microchip `<device>.cfgdata` into `data/devices/` and re-run cmake. It is found at
`xc8/pic/dat/cfgdata/` in the device pack (for example `/opt/microchip/mplabx/*/packs/Microchip/*_DFP/*/`).
The device name is read from the file's header comment. No code changes are needed. At run time,
"Add device file…" loads a `.cfgdata` without rebuilding.

`18f27q10.cfgdata` carries two local fixes, listed at the top of the file and checked against
DS40002043F p.34-35 (WDTCPS_14 ratio, WRT4 description).

## Adding an output format

Extend `OutputFormat` and `formatConfig()` in `src/OutputFormatter.*`.

## Layout

- `src/DeviceDef.*` — `.cfgdata` parser and the device model (words, settings, values, defaults)
- `src/OutputFormatter.*` — model + selection to text
- `src/MainWindow.*` — UI; one drop-down per setting, built from the model
