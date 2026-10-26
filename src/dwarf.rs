//! Typed variables and routine scopes for the debugger (`-g`).
//!
//! pic-as writes the line table but no variable information. This appends one more DWARF 3
//! compilation unit to the ELF it produced: base types, a `DW_TAG_subprogram` per routine holding
//! its parameters and locals, and the globals, each at its fixed data-memory address.

use crate::types::Ty;

pub struct DVar {
    pub name: String,
    pub ty: Ty,
    pub bytes: u32,
    pub addr: u32,
    /// Index into `DebugInfo::funcs`; `None` for a global.
    pub scope: Option<usize>,
    pub param: bool,
}

pub struct DFunc {
    pub name: String,
    /// Byte addresses `[low, high)`.
    pub low: u32,
    pub high: u32,
}

#[derive(Default)]
pub struct DebugInfo {
    pub vars: Vec<DVar>,
    pub funcs: Vec<DFunc>,
    /// Program size in bytes.
    pub end: u32,
}

fn uleb(out: &mut Vec<u8>, mut v: u64) {
    loop {
        let b = (v & 0x7f) as u8;
        v >>= 7;
        if v == 0 {
            out.push(b);
            return;
        }
        out.push(b | 0x80);
    }
}

fn cstr(out: &mut Vec<u8>, s: &str) {
    out.extend(s.bytes().filter(|&b| b != 0));
    out.push(0);
}

// Abbreviation codes of the table written below.
const A_CU: u64 = 1;
const A_BASE: u64 = 2;
const A_VAR: u64 = 3;
const A_FUNC: u64 = 4;
const A_ARRAY: u64 = 5;
const A_RANGE: u64 = 6;
const A_PARAM: u64 = 7;

fn abbrevs() -> Vec<u8> {
    let mut o = Vec::new();
    // (code, tag, children, [(attribute, form)])
    let table: &[(u64, u64, u8, &[(u64, u64)])] = &[
        (A_CU, 0x11, 1, &[(0x03, 0x08), (0x25, 0x08), (0x13, 0x05), (0x11, 0x01), (0x12, 0x01)]),
        (A_BASE, 0x24, 0, &[(0x03, 0x08), (0x0b, 0x0b), (0x3e, 0x0b)]),
        (A_VAR, 0x34, 0, &[(0x03, 0x08), (0x49, 0x13), (0x3f, 0x0c), (0x02, 0x0a)]),
        (A_FUNC, 0x2e, 1, &[(0x03, 0x08), (0x3f, 0x0c), (0x11, 0x01), (0x12, 0x01)]),
        (A_ARRAY, 0x01, 1, &[(0x49, 0x13)]),
        (A_RANGE, 0x21, 0, &[(0x2f, 0x05)]),
        (A_PARAM, 0x05, 0, &[(0x03, 0x08), (0x49, 0x13), (0x02, 0x0a)]),
    ];
    for (code, tag, children, attrs) in table {
        uleb(&mut o, *code);
        uleb(&mut o, *tag);
        o.push(*children);
        for (a, f) in *attrs {
            uleb(&mut o, *a);
            uleb(&mut o, *f);
        }
        o.extend([0, 0]);
    }
    o.push(0);
    o
}

/// Emits the type DIEs into `buf` and returns each one's offset from the start of the unit.
struct Types {
    buf: Vec<u8>,
    base: usize,
    seen: Vec<(String, usize)>,
}

impl Types {
    fn base_type(&mut self, name: &str, size: u8, enc: u8) -> usize {
        if let Some((_, o)) = self.seen.iter().find(|(k, _)| k == name) {
            return *o;
        }
        let off = self.base + self.buf.len();
        uleb(&mut self.buf, A_BASE);
        cstr(&mut self.buf, name);
        self.buf.push(size);
        self.buf.push(enc);
        self.seen.push((name.to_string(), off));
        off
    }

    fn array(&mut self, elem: usize, count: u32, key: String) -> usize {
        if let Some((_, o)) = self.seen.iter().find(|(k, _)| *k == key) {
            return *o;
        }
        let off = self.base + self.buf.len();
        uleb(&mut self.buf, A_ARRAY);
        self.buf.extend((elem as u32).to_le_bytes());
        uleb(&mut self.buf, A_RANGE);
        self.buf.extend((count.saturating_sub(1).min(0xffff) as u16).to_le_bytes());
        self.buf.push(0);
        self.seen.push((key, off));
        off
    }

    fn of(&mut self, ty: &Ty, bytes: u32) -> usize {
        const ENC_BOOL: u8 = 2;
        const ENC_FLOAT: u8 = 4;
        const ENC_SIGNED: u8 = 5;
        const ENC_UCHAR: u8 = 8;
        const ENC_UNSIGNED: u8 = 7;
        match ty {
            Ty::Bool | Ty::Bit => self.base_type("Boolean", 1, ENC_BOOL),
            Ty::Int(w, signed) => {
                let name = match (w, signed) {
                    (8, false) => "Byte",
                    (8, true) => "ShortInt",
                    (16, false) => "Word",
                    (16, true) => "Integer",
                    (24, false) => "UInt24",
                    (24, true) => "Int24",
                    (_, false) => "LongWord",
                    (_, true) => "LongInt",
                };
                self.base_type(name, (*w / 8).max(1), if *signed { ENC_SIGNED } else { ENC_UNSIGNED })
            }
            Ty::Float => self.base_type("Float", 4, ENC_FLOAT),
            Ty::Char => self.base_type("Char", 1, ENC_UCHAR),
            Ty::Str(n) => {
                let c = self.base_type("Char", 1, ENC_UCHAR);
                self.array(c, n + 1, format!("String({n})"))
            }
            Ty::Array(e, n) if *n > 0 && bytes % n == 0 && !matches!(**e, Ty::Array(..) | Ty::Struct(_)) => {
                let el = self.of(e, bytes / n);
                self.array(el, *n, format!("{e}[{n}]"))
            }
            // Structures and nested arrays: shown as their bytes.
            _ => {
                let b = self.base_type("Byte", 1, ENC_UNSIGNED);
                self.array(b, bytes.max(1), format!("bytes[{bytes}]"))
            }
        }
    }
}

/// The compilation unit (with its header) for `info`, given the abbreviation table's offset.
fn unit(info: &DebugInfo, source: &str, abbrev_off: u32) -> Vec<u8> {
    let mut head = Vec::new(); // the unit DIE, children follow
    uleb(&mut head, A_CU);
    cstr(&mut head, source);
    cstr(&mut head, "basil");
    head.extend(0x8001u16.to_le_bytes());
    head.extend(0u32.to_le_bytes());
    head.extend(info.end.to_le_bytes());
    let mut types = Types { buf: Vec::new(), base: 11 + head.len(), seen: Vec::new() };
    let tys: Vec<usize> = info.vars.iter().map(|v| types.of(&v.ty, v.bytes)).collect();
    let mut body = Vec::new();
    let var = |body: &mut Vec<u8>, v: &DVar, ty: usize, global: bool| {
        uleb(body, if v.param { A_PARAM } else { A_VAR });
        cstr(body, &v.name);
        body.extend((ty as u32).to_le_bytes());
        if !v.param {
            body.push(global as u8);
        }
        // DW_OP_addr <address>
        body.push(5);
        body.push(0x03);
        body.extend(v.addr.to_le_bytes());
    };
    for (i, v) in info.vars.iter().enumerate().filter(|(_, v)| v.scope.is_none()) {
        var(&mut body, v, tys[i], true);
    }
    for (f, func) in info.funcs.iter().enumerate() {
        uleb(&mut body, A_FUNC);
        cstr(&mut body, &func.name);
        body.push(1);
        body.extend(func.low.to_le_bytes());
        body.extend(func.high.to_le_bytes());
        for (i, v) in info.vars.iter().enumerate().filter(|(_, v)| v.scope == Some(f)) {
            var(&mut body, v, tys[i], false);
        }
        body.push(0);
    }
    body.push(0);
    let mut out = Vec::new();
    let len = 7 + head.len() + types.buf.len() + body.len();
    out.extend((len as u32).to_le_bytes());
    out.extend(3u16.to_le_bytes());
    out.extend(abbrev_off.to_le_bytes());
    out.push(4);
    out.extend(head);
    out.extend(types.buf);
    out.extend(body);
    out
}

fn u16_at(b: &[u8], o: usize) -> Option<usize> {
    Some(u16::from_le_bytes(b.get(o..o + 2)?.try_into().ok()?) as usize)
}

fn u32_at(b: &[u8], o: usize) -> Option<usize> {
    Some(u32::from_le_bytes(b.get(o..o + 4)?.try_into().ok()?) as usize)
}

/// Appends the debug unit to the ELF32 file `elf`. The new section contents are written after the
/// existing file and the section headers point at them, so nothing already in the file moves.
pub fn augment(elf: &mut Vec<u8>, info: &DebugInfo, source: &str) -> Result<(), String> {
    let bad = || "unexpected ELF layout".to_string();
    if elf.get(..4) != Some(b"\x7fELF") || elf.get(4) != Some(&1) {
        return Err(bad());
    }
    let shoff = u32_at(elf, 0x20).ok_or_else(bad)?;
    let shentsize = u16_at(elf, 0x2e).ok_or_else(bad)?;
    let shnum = u16_at(elf, 0x30).ok_or_else(bad)?;
    let shstr = u16_at(elf, 0x32).ok_or_else(bad)?;
    let hdr = |i: usize| shoff + i * shentsize;
    let names_off = u32_at(elf, hdr(shstr) + 0x10).ok_or_else(bad)?;
    let find = |elf: &[u8], want: &str| -> Option<usize> {
        (0..shnum).find(|&i| {
            let n = names_off + u32_at(elf, hdr(i)).unwrap_or(0);
            elf.get(n..).is_some_and(|s| s.starts_with(want.as_bytes()) && s.get(want.len()) == Some(&0))
        })
    };
    let (Some(info_s), Some(abbrev_s)) = (find(elf, ".debug_info"), find(elf, ".debug_abbrev")) else {
        return Err("no .debug_info or .debug_abbrev section".into());
    };
    let section = |elf: &[u8], i: usize| -> Option<Vec<u8>> {
        let (o, n) = (u32_at(elf, hdr(i) + 0x10)?, u32_at(elf, hdr(i) + 0x14)?);
        Some(elf.get(o..o + n)?.to_vec())
    };
    let old_info = section(elf, info_s).ok_or_else(bad)?;
    let mut abbrev = section(elf, abbrev_s).ok_or_else(bad)?;
    let abbrev_off = abbrev.len() as u32;
    abbrev.extend(abbrevs());
    let unit_off = old_info.len() as u32;
    let mut new_info = old_info;
    new_info.extend(unit(info, source, abbrev_off));
    let replace = |elf: &mut Vec<u8>, i: usize, data: &[u8]| {
        let at = elf.len() as u32;
        elf.extend(data);
        elf[hdr(i) + 0x10..hdr(i) + 0x14].copy_from_slice(&at.to_le_bytes());
        elf[hdr(i) + 0x14..hdr(i) + 0x18].copy_from_slice(&(data.len() as u32).to_le_bytes());
    };
    replace(elf, info_s, &new_info);
    replace(elf, abbrev_s, &abbrev);
    // Address ranges: one more set for the new unit, so the debugger finds it from a program counter.
    if let Some(ar) = find(elf, ".debug_aranges")
        && let Some(mut a) = section(elf, ar)
    {
        let mut set = Vec::new();
        set.extend(2u16.to_le_bytes());
        set.extend(unit_off.to_le_bytes());
        set.extend([4, 0, 0, 0]);
        set.extend(0u32.to_le_bytes());
        set.extend(0u32.to_le_bytes());
        set.extend(info.end.to_le_bytes());
        set.extend([0u8; 8]);
        let mut full = (set.len() as u32).to_le_bytes().to_vec();
        full.extend(set);
        a.extend(full);
        replace(elf, ar, &a);
    }
    Ok(())
}
