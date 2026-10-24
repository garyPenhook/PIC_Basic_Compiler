# Basic_Compiler

A personal BASIC compiler for PIC microcontrollers, with code efficiency as a top priority.
First target: **PIC18F27Q10**. Other microcontrollers will be added slowly, one at a time, later.

* Language: a structured, typed core (modules, subroutines/functions, structures, interrupts)
  with a friendly command library on top.
* Back end: generates assembly for Microchip's `pic-as`, which assembles and links the `.hex`.
* Plan and status: `PLAN.md`, `docs/PROGRESS.md`. Decisions: `docs/DECISIONS.md`.
* Language: `docs/LANGUAGE.md`, `docs/GRAMMAR.md`. Calling convention: `docs/ABI.md`.

Status: planning / foundations (milestone M0). Nothing compiles yet.

Personal-use project. Vendor manuals under `reference/` are not part of the repository and must
not be redistributed.
