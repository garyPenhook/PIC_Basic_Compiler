//! Guards for reset-page elimination and generated CALL/GOTO page-bit flow.
use super::*;

pub(super) fn reset_page(items: &[Item], assembled: &Assembled, p: &Program, tgt: &Target, objs: &[Obj], layout: &Layout) -> bool {
    // Assembly may manually enter an ISR without hardware first saving the shadow latch.
    // Until entry contexts are analyzed, only wholly typed interrupt programs qualify.
    if !p.isrs.is_empty() && items.iter().any(|it| matches!(it, Item::Raw(_))) { return false; }
    if !crate::asm::code_in_first_page16(items, 0, assembled) || !crate::opt::preserves_page_zero(p, tgt) { return false; }
    neutral(items, p, tgt, objs, layout)
}

pub(super) fn trackable(items: &[Item], p: &Program, tgt: &Target, objs: &[Obj], layout: &Layout) -> bool {
    crate::opt::preserves_page_zero(p, tgt) && neutral(items, p, tgt, objs, layout)
        && items.iter().enumerate().all(|(i, it)| match it {
            Item::Ins(t) | Item::Raw(t) => {
                let op = t.split_whitespace().next().unwrap_or("").to_ascii_lowercase();
                let skip_safe = !matches!(op.as_str(), "btfsc" | "btfss" | "decfsz" | "incfsz")
                    || next_is_single_instruction(&items[i + 1..]);
                skip_safe && !matches!(op.as_str(), "brw" | "callw" | "movlp" | "goto" | "call" | "fcall" | "ljmp")
                    && (!matches!(it, Item::Raw(_)) || !matches!(op.as_str(), "bra" | "reset"))
            }
            _ => true,
        })
}

fn next_is_single_instruction(items: &[Item]) -> bool {
    for it in items {
        match it {
            Item::Label(_) | Item::Comment(_) | Item::Fence | Item::Keep(_) | Item::Fit(_) => {}
            Item::Ins(s) | Item::Raw(s) => match crate::asm::words_of16(s) {
                0 => {},
                1 => return true,
                _ => return false,
            },
            _ => return false,
        }
    }
    false
}

fn neutral(items: &[Item], p: &Program, tgt: &Target, objs: &[Obj], layout: &Layout) -> bool {
    if !p.isrs.is_empty() && items.iter().any(|it| matches!(it, Item::Raw(_))) { return false; }
    let mut symbols = tgt.sfr.clone();
    for (i, o) in objs.iter().enumerate() {
        let Some(a) = layout.addr[i] else { continue };
        symbols.insert(o.name.clone(), a);
        if o.force_access && o.name.starts_with("__") {
            for off in 0..o.bytes { symbols.insert(format!("{}{off}", o.name), a + off); }
        }
    }
    let common = tgt.pic16.as_ref().expect("PIC16 paging needs the memory description").common;
    items.iter().all(|it| match it {
        Item::Raw(text) => neutral_raw(text, &symbols, common),
        _ => true,
    })
}

/// Only known one-word instructions with no latch effects are accepted. For assembly file
/// operands, limit the proof to common RAM plus STATUS/WREG, so an unknown BSR cannot turn an
/// otherwise ordinary operand into PCLATH or its shadow. Typed accesses have a separate IR proof.
fn neutral_raw(text: &str, symbols: &HashMap<String, u32>, common: (u32, u32)) -> bool {
    if text.contains(['\n', '\r']) { return false; }
    let text = text.split(';').next().unwrap_or("").trim();
    if text.is_empty() || (text.ends_with(':') && !text.contains(char::is_whitespace)) { return true; }
    let mut words = text.split_whitespace();
    let op = words.next().unwrap_or("").to_ascii_lowercase();
    match op.as_str() {
        "nop" | "clrwdt" | "sleep" | "reset" | "clrw" | "return"
        | "movlw" | "addlw" | "andlw" | "iorlw" | "xorlw" | "sublw" | "retlw" | "movlb"
        | "bra" | "goto" | "call" => true,
        "movf" | "movwf" | "clrf" | "addwf" | "addwfc" | "subwf" | "subwfb" | "andwf" | "iorwf" | "xorwf"
        | "comf" | "incf" | "decf" | "incfsz" | "decfsz" | "rlf" | "rrf" | "lslf" | "lsrf" | "asrf"
        | "swapf" | "btfsc" | "btfss" | "bsf" | "bcf" => {
            let Some((_, rest)) = text.split_once(char::is_whitespace) else { return false };
            let operand: String = rest.split(',').next().unwrap_or("").chars().filter(|c| !c.is_whitespace()).collect();
            let (base, off) = operand.split_once('+').unwrap_or((&operand, "0"));
            let number = |s: &str| s.strip_prefix("0x").or_else(|| s.strip_prefix("0X")).map_or_else(|| s.parse::<u32>().ok(), |s| u32::from_str_radix(s, 16).ok());
            let Some(addr) = symbols.get(base).copied().or_else(|| number(base)).and_then(|a| number(off).and_then(|off| a.checked_add(off))) else { return false };
            let off = addr & 0x7f;
            matches!(off, 3 | 9) || (common.0..common.1).contains(&off)
        }
        // Includes explicit page selections, CALLW, indirect moves, pseudo-ops, macros and directives.
        _ => false,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    fn symbols() -> HashMap<String, u32> {
        [("__A0", 0x70), ("STATUS", 3), ("WREG", 9), ("PCLATH", 10), ("PCL", 2), ("PCLATH_SHAD", 0x1fe7), ("INDF0", 0), ("LOCAL", 0x20)]
            .map(|(s, a)| (s.into(), a)).into_iter().collect()
    }
    #[test]
    fn verified_assembly_can_use_common_ram_and_core_arithmetic() {
        let syms = symbols();
        for text in ["movf __A0, w", "addwf __A0+1,f", "movwf __A0 + 1", "movwf 0xF0", "btfsc STATUS, 0", "movf WREG,w", "retlw 7", "movlb 3", "return", "bra NEXT", "LABEL:", "; comment"] {
            assert!(neutral_raw(text, &syms, (0x70, 0x80)), "{text}");
        }
    }
    #[test]
    fn latch_access_pointer_moves_macros_and_unknown_banks_keep_paging() {
        let syms = symbols();
        for text in ["movwf PCLATH", "movf PCLATH,w", "movwf 0x08A", "movwf WREG + 1", "bcf PCLATH_SHAD,0", "movwf 0x67", "movwf PCL", "movf INDF0,w", "moviw 0[FSR0]", "movwi FSR0++", "brw", "callw", "retfie", "movlp 0", "pagesel FUNC", "fcall FUNC", "BANKSEL LOCAL", "CUSTOM_MACRO", "movwf LOCAL", "movwf ALIAS", "org 2048", "dw 0", "movlw 0\nmovwf PCLATH"] {
            assert!(!neutral_raw(text, &syms, (0x70, 0x80)), "{text}");
        }
    }
}
