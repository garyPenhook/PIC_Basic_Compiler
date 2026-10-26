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

## Planned: project, programming and debugging support

Modelled on the feature set of the Swordfish BASIC VS Code beta. None of this exists yet.

* **New Project wizard** — pick a project name, PIC device and oscillator frequency; generates the `.bas` source,
  a project settings file, `launch.json`, `tasks.json` and a `dist` output directory.
* **Device catalog and target selection** — choose the target device from inside VS Code from every device
  description in `devices/`.
* **Build shortcuts** — F7 normal build, Ctrl+F7 debug build (with debug information), *Show Build Output*.
* **Programming** — F8 programs the device through a programmer chosen with *Select Programmer/Debugger*
  (PICkit, ICD, Snap).
* **Debugging through the Microchip MPLAB extension pack** — simulator (no hardware) and hardware debugging,
  source-level breakpoints and stepping (F5, F9, F10, F11, Shift+F11), procedure parameters and locals in the
  Locals view, globals through the Watch view, and BASIC type information including bit metadata.
* **ELF/DWARF converter** — turn basil's listing/debug map and HEX output into a Microchip-compatible
  `dist/project.elf` for the MPLAB debugger, implemented in TypeScript inside the extension so Python is not needed.

Requirements for these features: the official Microchip *MPLAB Extension Pack* and the matching device packs;
a programmer/debugger only for physical hardware.

Known limitations to expect: a final call such as `DelayMs()` may lose its source cursor when the compiler emits
it as a tail branch into shared runtime code; hardware support depends on the Microchip extension, device packs,
tool firmware, target power and wiring; code completion beyond what is listed above is separate work.

When reporting a problem with these features, include: VS Code version, basil version, MPLAB Extension Pack and
device pack versions, PIC device, selected simulator/programmer/debugger, a minimal project, the exact steps to
reproduce, and the build output, Debug Console output and `dap.log` where available.

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
    code --install-extension picbasic-0.1.0.vsix
