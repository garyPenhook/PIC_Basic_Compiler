# PIC BASIC for VS Code

Editor support for the `basil` PIC BASIC compiler (`.bas` files).

* **Device name correction** — with a `Device = 18F27Q10` line, register and bit names take the spelling
  of the device description (`lata = 0` becomes `LATA = 0`, `portb.0` becomes `PORTB.0`) at the same moments as
  keywords. A name the program declares itself is left alone. The description is found in the nearest
  `devices` folder above the file, the workspace, or `picbasic.devicesPath`.
* **Keyword case correction** — `dim x as byte` becomes `Dim x As Byte` as you type a separator
  (space, `(`, `,`, `:`, Enter), on save, and on *Format Document*. Strings, comments, `Asm` blocks,
  preprocessor lines, `Config` settings, `$hex`/`%bin` literals, identifiers and `.member` names are never touched.
  The table is checked against `src/lexer.rs` by `npm test`.
* **Formatting** — re-indents `Sub`/`Function`/`If`/`Select`/loops (4 spaces or your tab setting), trims trailing whitespace.
  Indents the new line after Enter.
* **Highlighting**, snippets, bracket/comment configuration (`'`, `//`, `(* *)`, `{ }`).
* **Diagnostics** — runs `basil --check` on open/save (or while typing with `picbasic.diagnostics = onType`).
  Library `Module` files are skipped because they have no `Device`.
* **Navigation** — outline, go to definition (own file, `Include`d modules, `lib/`), signature help.
* **Hover and completion everywhere** — hover shows documentation for: reserved words; your own and library routines (parameters, return type, doc comment, where defined); `Module.Member` and `Include "name"` (what the library does and its public routines); parameters and locals; registers and bits of the program's `Device` (address, width, bit fields, mask, datasheet) including what a `Dim x As PORTB.0` alias points at; `Config` fields and their allowed values; and numeric literals (decimal, hex, binary). Completion offers the same, plus registers, bits and `Module.` members after a dot, and `Config` fields and values.
* **Build** — *PIC BASIC: Build / Check / Show Resource Report* commands and a `picbasic` task type with the `$basil` problem matcher.

## Project, programming and debugging

Requirements: the Microchip *MPLAB Extension Pack* and the device pack of the target (basil needs it anyway);
a programmer/debugger only for physical hardware (the simulator needs none).

### Quick start

New Project, pick the device and 4000000 Hz, *Select Programmer/Debugger* (Simulator), **Ctrl+F7**, then **F5**.
Hardware: select the tool, **Ctrl+F7** and F5 to debug it, or **F8** to program it.

### Commands

Open the Command Palette (Ctrl+Shift+P) and type *PIC BASIC*. The editor title bar also has buttons for
Build, Build Debug, Program and Select Programmer/Debugger on `.bas` files.

| Command | Key | What it does |
|---|---|---|
| New Project | | Pick a folder, name, device (from the `devices/` descriptions) and oscillator frequency. Creates the `.bas`, `picbasic.json` (project settings), `.vscode/launch.json`, `.vscode/tasks.json`, `dist/` and a `.gitignore`. |
| Pick Target Device | | Changes the `Device` line, `picbasic.json` and `launch.json` together. |
| Select Programmer/Debugger | | Simulator, or a PICkit / ICD / Snap the MPLAB extension reports as connected (a fixed list if none is). Stored in `picbasic.json` and `launch.json`. |
| Build (F7) | F7 | `basil`, then copies `.hex`, `.elf` and `.map` into `dist/`. |
| Build Debug (Ctrl+F7) | Ctrl+F7 | `basil -g`, then the same copy. |
| Program Device (F8) | F8 | Builds, then programs `dist/<name>.hex` through the MPLAB extension with the selected tool. Refuses the simulator. |
| Show Build Output | | Opens the output channel. |

F7, Ctrl+F7 and F8 apply while a `.bas` file is active. A second build is refused while one is running.

### Debugging

1. *Select Programmer/Debugger* (the simulator is the default).
2. **Build Debug (Ctrl+F7)**. This runs `basil -g`, which puts BASIC line numbers, variables and routines
   into `dist/<name>.elf`.
3. **F5** starts the `PIC BASIC: Debug` configuration of `.vscode/launch.json` (`mplab-core-da`, stop on entry).
   F9 sets a breakpoint, F10 steps over, F11 steps into, Shift+F11 steps out, Shift+F5 stops.

Breakpoints and stepping work on the `.bas` lines (library modules included). The debugger sees global variables
and each routine's parameters and locals with their BASIC types (Byte, Word, Integer, String, arrays; structures
as bytes). Interrupt handlers and routines that were not inlined appear as functions; the locals of an inlined routine
are not listed. Code the compiler adds (start-up, helpers) is shown under the nearest statement.
This was checked with the MPLAB X simulator's command-line debugger (call stack with parameters, `print` of
globals and parameters); the VS Code Locals and Watch views use the same ELF but have not been exercised.
Edit `launch.json` to change the tool, `stopOnEntry` or the `dap.log` path. When reporting a problem include the
VS Code, basil, MPLAB Extension Pack and device pack versions, the device, the tool, a minimal project, the
build output and `dap.log`.

### Troubleshooting

| Symptom | Cause and fix |
|---|---|
| The debugger cannot find `dist/<name>.elf` | Run **Build Debug (Ctrl+F7)** first; F7 and the plain Build also write an ELF, but only Ctrl+F7 has the BASIC line and variable information. |
| A breakpoint does not stop | The ELF is older than the source, or was built without `-g`. Rebuild with Ctrl+F7. |
| Stepping shows assembly or a library file | Normal: compiler-added code is shown under the nearest statement, and library routines (`serial.bas`, `intosc.bas`) are real source files you step into. |
| A variable is missing or shows another routine's value | Routines share RAM. Only variables of the routine you are stopped in are valid; an inlined routine's locals are not listed. |
| Locals/Watch empty | Not yet exercised in VS Code. The simulator's `print NAME` and the call-stack parameters work on the same ELF; send `dap.log`. |
| "cannot run basil" / no `.hex` | Set `picbasic.compilerPath`; `pic-as` (MPLAB XC8) and the device pack must be installed. |
| Programming does nothing | The simulator cannot program a chip. Select a PICkit/ICD/Snap, check cabling and target power. |
| Device list empty | Set `picbasic.devicesPath` to the folder holding the device `.toml` files. |

### Project settings (`picbasic.json`)

```json
{ "name": "Blink", "device": "18F27Q10", "clockHz": 4000000, "source": "Blink.bas",
  "debug": { "tool": "Simulator" }, "programming": { "tool": "PICkit 4" } }
```

`debug.serial` / `programming.serial` name a specific connected tool. `source` tells the commands which file to build
when no `.bas` file is open.

## Settings

| Setting | Default |
|---|---|
| `picbasic.compilerPath` | `basil` |
| `picbasic.compilerArgs` | `[]` (e.g. `["-L","/path/lib","--pic-as","/path/pic-as"]`) |
| `picbasic.autoCorrectKeywords` | `true` |
| `picbasic.fixKeywordCaseOnSave` | `true` |
| `picbasic.autoCorrectDeviceNames` | `true` |
| `picbasic.devicesPath` | empty (search as above) |
| `picbasic.formatIndentation` | `true` |
| `picbasic.diagnostics` | `onSave` (`off`, `onSave`, `onType`) |

Set `"[picbasic]": { "editor.formatOnSave": true }` to format on save.

## Install

    cd vscode-extension && npm test && npx @vscode/vsce package
    code --install-extension picbasic-0.2.4.vsix
