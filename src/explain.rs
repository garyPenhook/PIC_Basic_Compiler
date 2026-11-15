//! `basil --explain CODE`: the meaning of a diagnostic code, from `docs/DIAGNOSTICS.md`, and for
//! the codes met most often a longer explanation with a program that raises it and the fix.
//! The test `explain_examples` compiles every example, so they stay true.

/// The code table, built into the compiler.
const TABLE: &str = include_str!("../docs/DIAGNOSTICS.md");

/// One long explanation. `wrong` and `right` are program text placed after
/// `Program T` / `Device = 18F27Q10` and before the final `End`.
pub struct Entry {
    pub code: &'static str,
    pub text: &'static str,
    pub wrong: &'static str,
    pub right: &'static str,
}

pub const ENTRIES: &[Entry] = &[
    Entry {
        code: "E-UNDECLARED",
        text: "A name is used that nothing declares where it is used: not a variable, constant or routine\n\
               in scope, not a register of the device, and not a built-in. The usual causes are a typing\n\
               slip (the message offers the closest names), a local variable of another routine, or a\n\
               library routine whose module is not included (the message names the module).",
        wrong: "Dim counter As Byte\ncountr = 5",
        right: "Dim counter As Byte\ncounter = 5",
    },
    Entry {
        code: "E-SYNTAX",
        text: "The text does not match the grammar. Blocks are closed by their own words (`Next`, `Wend`,\n\
               `End If`, `End Select`, `Loop`, `Until`, `End Sub`); an `If` condition ends with `Then`, and\n\
               the statements go on the lines below. Calls put their arguments in parentheses.",
        wrong: "Dim i As Byte\nIf i = 3\n    i = 1\nEnd If",
        right: "Dim i As Byte\nIf i = 3 Then\n    i = 1\nEnd If",
    },
    Entry {
        code: "E-TYPE",
        text: "A value of the wrong type for the operation or the target. A Float is not stored in an\n\
               integer without an explicit conversion (`Byte(f)`), a number is not a Boolean (compare it),\n\
               and a String is not a number (`Val(s)` reads one).",
        wrong: "Dim f As Float\nDim i As Byte\ni = f",
        right: "Dim f As Float\nDim i As Byte\ni = Byte(f)",
    },
    Entry {
        code: "E-COND",
        text: "An `If`, `While`, `Until` or `ElseIf` condition must be Boolean. A number or a bit is not\n\
               true or false by itself: compare it.",
        wrong: "Dim i As Byte\nIf i Then\n    i = 0\nEnd If",
        right: "Dim i As Byte\nIf i <> 0 Then\n    i = 0\nEnd If",
    },
    Entry {
        code: "E-MIX",
        text: "A Boolean and a number are combined. `And`, `Or` and `Xor` are logical on Booleans and\n\
               bitwise on integers, never both at once; a Boolean is compared with `True` or `False`, not\n\
               with 0 or 1.",
        wrong: "Dim b As Boolean\nDim i As Byte\nIf b = 1 Then\n    i = 1\nEnd If",
        right: "Dim b As Boolean\nDim i As Byte\nIf b = True Then\n    i = 1\nEnd If",
    },
    Entry {
        code: "E-SIGN",
        text: "A signed and an unsigned operand meet in one operation (Integer and Word, Integer and\n\
               LongWord) and neither type holds every value of the other, so the compiler does not pick\n\
               one: convert an operand explicitly.",
        wrong: "Dim n As Integer\nDim w As Word\nDim l As LongInt\nl = n + w",
        right: "Dim n As Integer\nDim w As Word\nDim l As LongInt\nl = LongInt(n) + LongInt(w)",
    },
    Entry {
        code: "E-CONST-RANGE",
        text: "A constant does not fit the type it is stored in or compared with. The message gives the\n\
               type's range; use a wider type or a smaller value.",
        wrong: "Dim i As Byte\ni = 300",
        right: "Dim w As Word\nw = 300",
    },
    Entry {
        code: "W-NARROW",
        text: "A value of a wider type is stored in a narrower one, so its upper part can be lost. Convert\n\
               explicitly (`Byte(w)`) or take the part you mean (`w.Byte0`) to say it is intended. Under\n\
               `#option Strict = true` this is the error E-NARROW. `#option Warn.Narrow = false` turns the\n\
               warning off.",
        wrong: "Dim w As Word\nDim i As Byte\ni = w",
        right: "Dim w As Word\nDim i As Byte\ni = Byte(w)",
    },
    Entry {
        code: "W-NOTCMP",
        text: "`Not` binds tighter than a comparison, so `Not x = 5` complements `x` and then compares it.\n\
               Write `Not (x = 5)` to negate the comparison, or `(Not x) = 5` to keep the meaning.",
        wrong: "Dim x As Byte\nDim b As Boolean\nb = Not x = 5",
        right: "Dim x As Byte\nDim b As Boolean\nb = Not (x = 5)",
    },
    Entry {
        code: "E-ARGS",
        text: "A call gives a different number of arguments than the routine has parameters (parameters\n\
               with a default may be left out). The message names what is missing and shows where the\n\
               routine is declared.",
        wrong: "Sub Foo(a As Byte, b As Byte)\nEnd Sub\nFoo(1)",
        right: "Sub Foo(a As Byte, b As Byte)\nEnd Sub\nFoo(1, 2)",
    },
    Entry {
        code: "E-ORDER",
        text: "A file is laid out in order: `Device`, `Clock` and `Config` first, then `Include`s, then\n\
               declarations (`Dim`, `Const`, routines), then the statements of the main program. Inside a\n\
               routine its `Dim`s come before its statements.",
        wrong: "Dim i As Byte\ni = 1\nDim j As Byte",
        right: "Dim i As Byte\nDim j As Byte\ni = 1",
    },
    Entry {
        code: "E-LOOPVAR",
        text: "The variable of a `For` loop is changed inside the loop. The loop counts it itself (and may\n\
               keep it in a register or count down); use another variable for the work.",
        wrong: "Dim i As Byte\nFor i = 0 To 5\n    i = 2\nNext",
        right: "Dim i As Byte\nDim j As Byte\nFor i = 0 To 5\n    j = i\nNext",
    },
    Entry {
        code: "E-LOOP",
        text: "`Break` or `Continue` outside a loop. `Break` leaves the innermost loop and `Continue` starts\n\
               its next pass; `Exit` leaves the current routine.",
        wrong: "Dim i As Byte\nBreak",
        right: "Dim i As Byte\nWhile True\n    Break\nWend",
    },
    Entry {
        code: "E-RECURSION",
        text: "A routine can call itself, directly or through others. Routines keep their variables in\n\
               fixed RAM, so a recursive one must be declared `Reentrant`, which gives it a stack frame.",
        wrong: "Sub A()\n    A()\nEnd Sub\nA()",
        right: "Reentrant Sub A()\n    A()\nEnd Sub\nA()",
    },
    Entry {
        code: "E-ISR-CALL",
        text: "An interrupt handler calls a routine directly. The routine's variables may share RAM with\n\
               main-line code that the interrupt has stopped, so the call goes inside `Save(…) … Restore`,\n\
               which keeps that storage (LANGUAGE.md §8).",
        wrong: "Sub Foo()\nEnd Sub\nInterrupt Tick()\n    Foo()\nEnd Interrupt\nEnable(Tick)",
        right: "Sub Foo()\nEnd Sub\nInterrupt Tick()\n    Save(0)\n        Foo()\n    Restore\nEnd Interrupt\nEnable(Tick)",
    },
    Entry {
        code: "E-CONFIG",
        text: "A `Config` setting or value the device does not have, or a setting given twice. The names\n\
               are the device pack's (as in the data sheet's configuration word tables); the message lists\n\
               the values a setting takes and offers the closest name.",
        wrong: "Config RSTSOC = HFINTOSC_64MHZ",
        right: "Config RSTOSC = HFINTOSC_64MHZ",
    },
    Entry {
        code: "E-CLOCK",
        text: "`Clock` is the speed the program is built for, in MHz (`Clock = 64`), given once.",
        wrong: "Clock = 64000000",
        right: "Clock = 64",
    },
    Entry {
        code: "E-NOMEMBER",
        text: "A name after a dot that the value does not have: a register bit or field the device does\n\
               not define, a structure field, or a modifier that does not fit the type (a Word has\n\
               `Byte0` and `Byte1`, not `Byte2`).",
        wrong: "INTCON.GIEE = 1",
        right: "INTCON.GIE = 1",
    },
    Entry {
        code: "E-INCLUDE",
        text: "An `Include` names a module that is not found next to the file or in the library folders, or\n\
               includes form a cycle. Library modules are included by their file name without `.bas`.",
        wrong: "Clock = 64\nInclude \"seriall\"",
        right: "Clock = 64\nInclude \"serial\"",
    },
];

/// The section heading and the meaning of `code` in the code table, if it is there. A row may
/// list several codes (`E-LOOP, E-EXIT, E-LABEL`, `E-NARROW / W-NARROW`).
pub fn table_row(code: &str) -> Option<(String, String)> {
    let mut section = String::new();
    for line in TABLE.lines() {
        if let Some(h) = line.strip_prefix("## ") {
            section = h.trim().to_string();
            continue;
        }
        let Some(rest) = line.strip_prefix('|') else { continue };
        let mut cells = rest.splitn(2, '|');
        let (Some(codes), Some(meaning)) = (cells.next(), cells.next()) else { continue };
        if codes.split([',', '/']).any(|c| c.trim().trim_matches('`').eq_ignore_ascii_case(code)) {
            return Some((section, meaning.trim().trim_end_matches('|').trim().to_string()));
        }
    }
    None
}

/// The whole explanation printed by `basil --explain CODE`, or `None` for an unknown code.
pub fn explain(code: &str) -> Option<String> {
    let code = code.trim().to_ascii_uppercase();
    let row = table_row(&code);
    let entry = ENTRIES.iter().find(|e| e.code == code);
    if row.is_none() && entry.is_none() {
        return None;
    }
    let mut out = String::new();
    match &row {
        Some((section, meaning)) => out.push_str(&format!("{code} ({section}): {}\n", meaning.replace('`', ""))),
        None => out.push_str(&format!("{code}\n")),
    }
    if let Some(e) = entry {
        out.push_str(&format!("\n{}\n", e.text.replace('`', "")));
        let indent = |t: &str| t.lines().map(|l| format!("    {l}\n")).collect::<String>();
        out.push_str(&format!("\nFor example:\n\n{}\nraises {code}. Written like this it compiles:\n\n{}", indent(e.wrong), indent(e.right)));
    }
    Some(out)
}

/// Every code the table names, for "did you mean" on a mistyped `--explain` argument.
pub fn all_codes() -> Vec<String> {
    let mut v = Vec::new();
    for line in TABLE.lines() {
        let Some(rest) = line.strip_prefix('|') else { continue };
        let Some(codes) = rest.split('|').next() else { continue };
        for c in codes.split([',', '/']) {
            let c = c.trim().trim_matches('`');
            if (c.starts_with("E-") || c.starts_with("W-")) && !v.iter().any(|x: &String| x == c) {
                v.push(c.to_string());
            }
        }
    }
    v
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rows_are_found() {
        assert!(table_row("E-TYPE").is_some());
        assert!(table_row("e-label").is_some());
        assert!(table_row("W-NARROW").is_some());
        assert!(table_row("E-NOPE").is_none());
        for e in ENTRIES {
            assert!(table_row(e.code).is_some(), "{} is not in docs/DIAGNOSTICS.md", e.code);
        }
        assert!(all_codes().len() > 50);
    }
}
