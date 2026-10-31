//! devgen — generate a device description from a Microchip device pack and cross-check it against
//! the data sheet.
//!
//! ```text
//! devgen gen   <pack>/edc/<PART>.PIC  <out.toml>
//! devgen check <device.toml>          <expect.toml>
//! ```
//!
//! `gen` reads Microchip's machine-readable device description (the pack's `.PIC` file), builds a
//! [`devdesc::Device`], validates it, and writes TOML. Hand-entered values (vectors) come from a
//! small per-family table below, each with its data sheet source.
//!
//! `check` compares a generated description with an `expect` file holding numbers read by hand
//! from the data sheet (Table 1 of the device data sheet), so a pack/data-sheet disagreement is
//! caught instead of silently trusted.

use devdesc::*;
use serde::Deserialize;
use std::collections::BTreeMap;
use std::path::Path;
use std::process::ExitCode;

type Res<T> = Result<T, String>;

fn main() -> ExitCode {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let result = match args.iter().map(String::as_str).collect::<Vec<_>>().as_slice() {
        ["gen", pic, out] => generate(Path::new(pic), Path::new(out)),
        ["check", dev, expect] => check(Path::new(dev), Path::new(expect)),
        _ => Err("usage: devgen gen <pack>/edc/<PART>.PIC <out.toml>\n       devgen check <device.toml> <expect.toml>".into()),
    };
    match result {
        Ok(()) => ExitCode::SUCCESS,
        Err(e) => {
            eprintln!("devgen: {e}");
            ExitCode::FAILURE
        }
    }
}

// ---------------------------------------------------------------------------------------------
// XML helpers

/// Attribute by local name (the pack prefixes every attribute with `edc:`).
fn attr<'a>(n: roxmltree::Node<'a, 'a>, local: &str) -> Option<&'a str> {
    n.attributes().find(|a| a.name() == local).map(|a| a.value())
}

fn req<'a>(n: roxmltree::Node<'a, 'a>, local: &str) -> Res<&'a str> {
    attr(n, local).ok_or_else(|| format!("<{}> has no '{}' attribute", n.tag_name().name(), local))
}

fn num(s: &str) -> Res<u32> {
    let t = s.trim();
    let r = match t.strip_prefix("0x").or_else(|| t.strip_prefix("0X")) {
        Some(h) => u32::from_str_radix(h, 16),
        None => t.parse(),
    };
    r.map_err(|e| format!("bad number {t:?}: {e}"))
}

fn req_num(n: roxmltree::Node, local: &str) -> Res<u32> {
    num(req(n, local)?)
}

fn children<'a>(n: roxmltree::Node<'a, 'a>, name: &'static str) -> impl Iterator<Item = roxmltree::Node<'a, 'a>> {
    n.children().filter(move |c| c.is_element() && c.tag_name().name() == name)
}

fn descendants<'a>(n: roxmltree::Node<'a, 'a>, name: &'static str) -> impl Iterator<Item = roxmltree::Node<'a, 'a>> {
    n.descendants().filter(move |c| c.is_element() && c.tag_name().name() == name)
}

// ---------------------------------------------------------------------------------------------
// Per-family hand-entered facts

struct FamilyFacts {
    family: &'static str,
    vectors: (u32, u32, u32),
    vectors_source: &'static str,
}

/// Values the pack does not carry. Each family entry must be verified against a data sheet before
/// a device of that family is added (docs/DEVICE-FORMAT.md, "Adding a device").
fn family_facts(arch: &str) -> Res<FamilyFacts> {
    match arch {
        "18xxxx" => Ok(FamilyFacts {
            family: "pic18",
            vectors: (0x00, 0x08, 0x18),
            vectors_source: "PIC18F27/47Q10 data sheet DS40002043F p.108 and p.193 (fixed vectors: reset 0000h, high 0008h, low 0018h); PIC18F0x/1xQ41 data sheet DS40002214G p.57 and p.114 (reset 000000h; with MVECEN = 0 the IVTBASE default 000008h is the high vector and the low vector is eight words on, 000018h)",
        }),
        // Enhanced mid-range: one interrupt vector, so high and low are both 0004h.
        "16Exxx" => Ok(FamilyFacts {
            family: "pic16e",
            vectors: (0x00, 0x04, 0x04),
            vectors_source: "PIC16F17126/46 data sheet DS40002343F p.36 and Fig. 9-1 p.37; PIC16F13145 family data sheet DS40002519D p.34; PIC16F18313/18323 data sheet DS40001799F Fig. 4-1 p.22, PIC16F18324/44 DS40001800E p.26, PIC16F18325/45 DS40001795K p.28, PIC16F18326/46 DS40001839E p.28; PIC16F15213/14/23/24/43/44 data sheet DS40002195E Fig. 9-1 p.33 (Reset vector 0000h, interrupt vector 0004h)",
        }),
        other => Err(format!("architecture '{other}' has no family table in devgen yet; add and verify one before generating")),
    }
}

// ---------------------------------------------------------------------------------------------
// Generation

fn pack_info(pic: &Path) -> Res<(String, String)> {
    // .../<PackName>/<version>/edc/<PART>.PIC
    let edc = pic.parent().ok_or("no parent directory")?;
    let version = edc.parent().and_then(|p| p.file_name()).ok_or("cannot find pack version in path")?;
    let pack = edc.parent().and_then(|p| p.parent()).and_then(|p| p.file_name()).ok_or("cannot find pack name in path")?;
    Ok((pack.to_string_lossy().into(), version.to_string_lossy().into()))
}

fn generate(pic: &Path, out: &Path) -> Res<()> {
    let text = std::fs::read_to_string(pic).map_err(|e| format!("{}: {e}", pic.display()))?;
    let doc = roxmltree::Document::parse(&text).map_err(|e| format!("XML error: {e}"))?;
    let root = doc.root_element();
    let arch = req(root, "arch")?;
    let facts = family_facts(arch)?;
    let (pack, pack_version) = pack_info(pic)?;

    let device = Device {
        device: Info {
            name: req(root, "name")?.to_string(),
            family: facts.family.to_string(),
            arch: arch.to_string(),
            pack,
            pack_version,
            source: format!("edc/{}", pic.file_name().unwrap_or_default().to_string_lossy()),
            datasheet: attr(root, "dsid").unwrap_or("").to_string(),
        },
        vectors: Vectors {
            reset: facts.vectors.0,
            interrupt_high: facts.vectors.1,
            interrupt_low: facts.vectors.2,
            source: facts.vectors_source.to_string(),
        },
        memory: memory(root, facts.family)?,
        config: config_registers(root)?,
        sfr: sfrs(root)?,
        joined: Vec::new(),
    };
    let device = Device { joined: joined(root, &device.sfr)?, ..device };

    let problems = device.validate();
    if !problems.is_empty() {
        return Err(format!("generated description is inconsistent:\n  {}", problems.join("\n  ")));
    }
    let header = format!(
        "# GENERATED by devgen from {} {} ({}). Do not edit by hand; regenerate instead.\n\
         # Addresses are decimal. Ranges are [start, end). See docs/DEVICE-FORMAT.md.\n\n",
        device.device.pack, device.device.pack_version, device.device.source
    );
    let body = device.to_toml().map_err(|e| e.to_string())?;
    std::fs::write(out, header + &body).map_err(|e| format!("{}: {e}", out.display()))?;
    eprintln!(
        "devgen: wrote {} ({} SFRs, {} joined, {} config registers)",
        out.display(),
        device.sfr.len(),
        device.joined.len(),
        device.config.len()
    );
    Ok(())
}

/// The Access Bank exists only on PIC18; other families get an empty range.
fn no_access_bank(found: Option<Range>, family: &str, what: &str) -> Res<Range> {
    match (found, family) {
        (Some(r), _) => Ok(r),
        (None, "pic16e") => Ok(Range { start: 0, end: 0 }),
        (None, _) => Err(format!("pack has no access {what} region")),
    }
}

/// A memory region made of one or more pack sectors. Sectors must be contiguous: a device with
/// split or gapped flash would otherwise get a silently wrong size, so it is refused instead.
fn region(root: roxmltree::Node, tag: &'static str, what: &str) -> Res<Region> {
    let mut parts: Vec<(u32, u32)> = Vec::new();
    for n in descendants(root, tag) {
        parts.push((req_num(n, "beginaddr")?, req_num(n, "endaddr")?));
    }
    if parts.is_empty() {
        return Err(format!("pack has no {what} ({tag})"));
    }
    parts.sort();
    for w in parts.windows(2) {
        if w[0].1 != w[1].0 {
            return Err(format!("{what}: sectors are not contiguous ({:#x}-{:#x} then {:#x}-{:#x}); extend devgen before using this device", w[0].0, w[0].1, w[1].0, w[1].1));
        }
    }
    let (start, end) = (parts[0].0, parts[parts.len() - 1].1);
    if end <= start {
        return Err(format!("{what}: empty region"));
    }
    Ok(Region { start, size: end - start })
}

fn memory(root: roxmltree::Node, family: &str) -> Res<Memory> {
    let program = region(root, "CodeSector", "program memory")?;
    // The PIC16F13145 family has no data EEPROM (DS40002519D Table 1, p.1): the region is empty.
    let eeprom = match region(root, "EEDataSector", "data EEPROM") {
        Err(_) if family == "pic16e" && descendants(root, "EEDataSector").next().is_none() => Region { start: 0, size: 0 },
        r => r?,
    };
    let user_id = region(root, "UserIDSector", "user IDs")?;
    let config = region(root, "ConfigFuseSector", "configuration words")?;
    let did = descendants(root, "DeviceIDSector").next().ok_or("pack has no device ID")?;
    let (db, de) = (req_num(did, "beginaddr")?, req_num(did, "endaddr")?);
    let device_id = DeviceId { start: db, size: de - db, value: attr(did, "value").map(num).transpose()?.unwrap_or(0) };

    let mut gpr = Vec::new();
    let mut access_ram = None;
    for n in root.descendants().filter(|n| n.is_element()) {
        let tag = n.tag_name().name();
        if tag != "GPRDataSector" && tag != "SystemGPRDataSector" {
            continue;
        }
        let (b, e) = (req_num(n, "beginaddr")?, req_num(n, "endaddr")?);
        // A shadow is another view of common RAM (enhanced mid-range), not extra storage.
        if attr(n, "shadowidref").is_some() {
            continue;
        }
        if attr(n, "regionid") == Some("accessram") {
            access_ram = Some(Range { start: b, end: e }); // overlaps bank 0; not a separate RAM
            continue;
        }
        let bank = attr(n, "bank").map(num).transpose()?.unwrap_or(b >> 8) as u8;
        gpr.push(GprRange { bank, start: b, end: e, system: tag == "SystemGPRDataSector" });
    }
    gpr.sort_by_key(|g| g.start);
    let total_gpr: u32 = gpr.iter().map(|g| g.end - g.start).sum();
    let usable_gpr: u32 = gpr.iter().filter(|g| !g.system).map(|g| g.end - g.start).sum();

    let mut sfr = Vec::new();
    let mut access_sfr = None;
    for n in descendants(root, "SFRDataSector") {
        let r = Range { start: req_num(n, "beginaddr")?, end: req_num(n, "endaddr")? };
        if attr(n, "regionid") == Some("accesssfr") {
            access_sfr = Some(r.clone());
        }
        sfr.push(r);
    }
    sfr.sort_by_key(|r| r.start);

    let hw_stack = descendants(root, "MemTraits").next().and_then(|n| attr(n, "hwstackdepth")).map(num).transpose()?.unwrap_or(0);

    Ok(Memory {
        hw_stack,
        program,
        eeprom,
        user_id,
        config,
        device_id,
        data: Data {
            total_gpr,
            usable_gpr,
            gpr,
            sfr,
            access_ram: no_access_bank(access_ram, family, "RAM")?,
            access_sfr: no_access_bank(access_sfr, family, "SFR")?,
        },
    })
}

/// Walk a `*Mode` element's children, assigning bit positions: each field takes `nzwidth` bits,
/// each `AdjustPoint` skips `offset` bits. Calls `on_field(node, pos, width)` for each field.
fn walk_fields<'a>(
    mode: roxmltree::Node<'a, 'a>,
    field_tag: &str,
    mut on_field: impl FnMut(roxmltree::Node<'a, 'a>, u8, u8) -> Res<()>,
) -> Res<()> {
    let mut pos: u32 = 0;
    for c in mode.children().filter(|c| c.is_element()) {
        let tag = c.tag_name().name();
        if tag == field_tag {
            let w = req_num(c, "nzwidth")?;
            if pos + w > 255 {
                return Err("field position overflow".into());
            }
            on_field(c, pos as u8, w as u8)?;
            pos += w;
        } else if tag == "AdjustPoint" {
            pos += req_num(c, "offset")?;
        }
    }
    Ok(())
}

fn config_registers(root: roxmltree::Node) -> Res<Vec<ConfigRegister>> {
    let mut out = Vec::new();
    for reg in descendants(root, "DCRDef") {
        let name = req(reg, "cname")?.to_string();
        let mut fields = Vec::new();
        if let Some(mode) = descendants(reg, "DCRMode").next() {
            walk_fields(mode, "DCRFieldDef", |f, pos, width| {
                let mut settings = Vec::new();
                for s in children(f, "DCRFieldSemantic") {
                    // when="(field & 0x7) == 0x4"
                    let when = req(s, "when")?;
                    let v = when.rsplit("==").next().ok_or("bad 'when'")?;
                    settings.push(Setting { name: req(s, "cname")?.to_string(), value: num(v)? });
                }
                fields.push(ConfigField { name: req(f, "cname")?.to_string(), pos, width, settings });
                Ok(())
            })?;
        }
        out.push(ConfigRegister {
            name,
            addr: req_num(reg, "_addr")?,
            default: attr(reg, "default").map(num).transpose()?.unwrap_or(0xFF),
            implemented: attr(reg, "impl").map(num).transpose()?.unwrap_or(0xFF),
            fields,
        });
    }
    out.sort_by_key(|r| r.addr);
    Ok(out)
}

fn sfrs(root: roxmltree::Node) -> Res<Vec<Sfr>> {
    let mut by_name: BTreeMap<String, Sfr> = BTreeMap::new();
    for reg in descendants(root, "SFRDef") {
        // Simulator-internal registers (TMR0_Internal, ...) carry an `nmmrid` and no address: they
        // are not memory-mapped, so they are not part of the device description.
        if attr(reg, "_addr").is_none() {
            continue;
        }
        let name = req(reg, "cname")?.to_string();
        let width = req_num(reg, "nzwidth")? as u8;
        let mut fields = Vec::new();
        let mut legacy = Vec::new();
        for mode in descendants(reg, "SFRMode") {
            let id = attr(mode, "id").unwrap_or("");
            let target = if id.starts_with("DS") && fields.is_empty() {
                &mut fields
            } else if id.starts_with("LT") && legacy.is_empty() {
                &mut legacy
            } else {
                continue; // further alternate views are not needed yet
            };
            walk_fields(mode, "SFRFieldDef", |f, pos, w| {
                target.push(Field { name: req(f, "cname")?.to_string(), pos, width: w });
                Ok(())
            })?;
        }
        // Drop a legacy view identical to the primary one.
        if legacy == fields {
            legacy.clear();
        }
        let aliases = descendants(reg, "LegacyAlias").filter_map(|a| attr(a, "cname")).map(String::from).collect();
        let sfr = Sfr { name: name.clone(), addr: req_num(reg, "_addr")?, width, aliases, fields, legacy };
        if let Some(prev) = by_name.get(&name) {
            if prev.addr != sfr.addr {
                return Err(format!("SFR {name} is defined at two addresses ({:#x}, {:#x})", prev.addr, sfr.addr));
            }
            continue; // same register seen again through another module
        }
        by_name.insert(name, sfr);
    }
    let mut v: Vec<Sfr> = by_name.into_values().collect();
    v.sort_by(|a, b| a.addr.cmp(&b.addr).then(a.name.cmp(&b.name)));
    Ok(v)
}

/// Joined (multi-byte) registers. The pack's declared width is not reliable (a 22-bit address
/// register is declared 16-bit), and some entries list no members, so a joined register is defined
/// by its byte members: direct `SFRDef` children when present, otherwise the registers named
/// `<name>L`, `<name>H`, `<name>U` at consecutive addresses starting at the joined address.
fn joined(root: roxmltree::Node, sfrs: &[Sfr]) -> Res<Vec<Joined>> {
    let mut v = Vec::new();
    for j in descendants(root, "JoinedSFRDef") {
        let name = req(j, "cname")?.to_string();
        let addr = req_num(j, "_addr")?;
        let mut members: Vec<String> = children(j, "SFRDef").map(|s| req(s, "cname").map(String::from)).collect::<Res<_>>()?;
        if members.is_empty() {
            for (i, suffix) in ["L", "H", "U"].iter().enumerate() {
                let want = format!("{name}{suffix}");
                match sfrs.iter().find(|s| s.name == want && s.addr == addr + i as u32) {
                    Some(s) => members.push(s.name.clone()),
                    None => break,
                }
            }
        }
        // The pack declares DAC1DAT (and the like) as 16 bits wide although it has one byte member
        // (DS40002214G p.765: DAC1DATL is 8 bits). A single byte is an ordinary SFR, not a join.
        if members.len() == 1 && children(j, "SFRDef").count() == 1 {
            continue;
        }
        if members.len() < 2 {
            return Err(format!("cannot resolve the byte members of joined register {name} at {addr:#x}"));
        }
        v.push(Joined { name, addr, bytes: members.len() as u8, members });
    }
    v.sort_by(|a, b| a.addr.cmp(&b.addr).then(a.name.cmp(&b.name)));
    v.dedup_by(|a, b| a.name == b.name);
    Ok(v)
}

// ---------------------------------------------------------------------------------------------
// Cross-check against the data sheet

#[derive(Deserialize)]
struct Expect {
    source: ExpectSource,
    memory: ExpectMemory,
    /// Values the pack gives that differ from the data sheet, each with the reason it is accepted.
    #[serde(default)]
    accepted: BTreeMap<String, Accepted>,
    vectors: ExpectVectors,
    /// SFR-name pattern (`#` = one digit) -> expected count, with the data sheet feature it checks.
    counts: BTreeMap<String, u32>,
}

#[derive(Deserialize)]
struct ExpectSource {
    datasheet: String,
    reference: String,
}

#[derive(Deserialize)]
struct Accepted {
    pack: u32,
    reason: String,
}

#[derive(Deserialize)]
struct ExpectMemory {
    program_bytes: u32,
    /// The data sheet's SRAM figure.
    sram_bytes: u32,
    /// RAM the pack lists on top of `sram_bytes` that the data sheet reserves (the NVM buffer bank).
    #[serde(default)]
    system_ram_bytes: u32,
    /// Levels of the hardware return stack, when the data sheet gives them.
    #[serde(default)]
    hw_stack_levels: Option<u32>,
    eeprom_bytes: u32,
    config_bytes: u32,
    user_id_bytes: u32,
}

#[derive(Deserialize)]
struct ExpectVectors {
    reset: u32,
    interrupt_high: u32,
    interrupt_low: u32,
}

fn check(dev: &Path, expect: &Path) -> Res<()> {
    let d = Device::load(dev).map_err(|e| format!("{}: {e}", dev.display()))?;
    let text = std::fs::read_to_string(expect).map_err(|e| format!("{}: {e}", expect.display()))?;
    let e: Expect = toml::from_str(&text).map_err(|e2| format!("{}: {e2}", expect.display()))?;

    let mut bad = d.validate();
    let mut compared = 0usize;
    let accepted = &e.accepted;
    let mut cmp = |what: &str, got: u32, want: u32| {
        compared += 1;
        let key = what.split(" (").next().unwrap_or(what);
        match accepted.get(key) {
            Some(a) if got == a.pack && got != want => println!("note: {key}: pack says {got}, data sheet says {want}; accepted ({})", a.reason),
            _ if got != want => bad.push(format!("{what}: description says {got}, data sheet says {want}")),
            _ => {}
        }
    };
    cmp("program memory bytes", d.memory.program.size, e.memory.program_bytes);
    if e.memory.system_ram_bytes > 0 {
        // The data sheet's figure leaves the system RAM out, so it is what the compiler may allocate.
        cmp("SRAM bytes (usable GPR)", d.memory.data.usable_gpr, e.memory.sram_bytes);
    }
    cmp("SRAM bytes (total GPR)", d.memory.data.total_gpr, e.memory.sram_bytes + e.memory.system_ram_bytes);
    if let Some(levels) = e.memory.hw_stack_levels {
        cmp("hardware stack levels", d.memory.hw_stack, levels);
    }
    cmp("data EEPROM bytes", d.memory.eeprom.size, e.memory.eeprom_bytes);
    cmp("configuration bytes", d.memory.config.size, e.memory.config_bytes);
    cmp("user ID bytes", d.memory.user_id.size, e.memory.user_id_bytes);
    cmp("reset vector", d.vectors.reset, e.vectors.reset);
    cmp("high interrupt vector", d.vectors.interrupt_high, e.vectors.interrupt_high);
    cmp("low interrupt vector", d.vectors.interrupt_low, e.vectors.interrupt_low);
    for (pat, want) in &e.counts {
        cmp(&format!("count of SFRs matching {pat}"), d.count_sfr(pat) as u32, *want);
    }
    if bad.is_empty() {
        println!("OK: {} agrees with {} ({}): {} values compared", d.device.name, e.source.datasheet, e.source.reference, compared);
        Ok(())
    } else {
        Err(format!("{} problem(s):\n  {}", bad.len(), bad.join("\n  ")))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn numbers_parse_hex_and_decimal() {
        assert_eq!(num("0xF8D").unwrap(), 0xF8D);
        assert_eq!(num(" 8 ").unwrap(), 8);
        assert!(num("zz").is_err());
    }

    #[test]
    fn field_positions_honour_adjust_points() {
        let xml = r#"<m xmlns:edc="x">
            <edc:SFRFieldDef edc:cname="A" edc:nzwidth="3"/>
            <edc:AdjustPoint edc:offset="1"/>
            <edc:SFRFieldDef edc:cname="B" edc:nzwidth="0x2"/>
        </m>"#;
        let doc = roxmltree::Document::parse(xml).unwrap();
        let mut got = Vec::new();
        walk_fields(doc.root_element(), "SFRFieldDef", |f, pos, w| {
            got.push((req(f, "cname")?.to_string(), pos, w));
            Ok(())
        })
        .unwrap();
        assert_eq!(got, vec![("A".to_string(), 0, 3), ("B".to_string(), 4, 2)]);
    }

    #[test]
    fn unknown_architecture_is_refused() {
        assert!(family_facts("33xxxx").is_err());
        assert_eq!(family_facts("18xxxx").unwrap().family, "pic18");
        assert_eq!(family_facts("16Exxx").unwrap().vectors, (0, 4, 4));
    }
}
