//! Back-end driver: builds the code generator's target description from the device file, runs
//! pic-as, and prints the size report.

use crate::codegen::{Generated, Target};
use crate::ir::Program;
use devdesc::Device;
use std::path::{Path, PathBuf};
use std::process::Command;

pub fn target_of(dev: &Device) -> Target {
    let mut ram: Vec<(u32, u32)> = Vec::new();
    for g in dev.memory.data.gpr.iter().filter(|g| !g.system) {
        let start = g.start.max(dev.memory.data.access_ram.end);
        if start >= g.end {
            continue;
        }
        match ram.last_mut() {
            Some(l) if l.1 == start => l.1 = g.end,
            _ => ram.push((start, g.end)),
        }
    }
    let sfr = dev.sfr.iter().map(|s| (s.name.clone(), s.addr)).collect();
    Target { ram, access: (dev.memory.data.access_ram.start, dev.memory.data.access_ram.end), access_sfr: dev.memory.data.access_sfr.start, sfr }
}

/// The newest installed pic-as, or the one named by `BASICC_PICAS`.
pub fn find_pic_as() -> Option<PathBuf> {
    if let Ok(p) = std::env::var("BASICC_PICAS") {
        return Some(PathBuf::from(p));
    }
    let root = Path::new("/opt/microchip/xc8");
    let mut found: Vec<PathBuf> = std::fs::read_dir(root).ok()?.filter_map(|e| e.ok()).map(|e| e.path().join("pic-as/bin/pic-as")).filter(|p| p.is_file()).collect();
    found.sort();
    found.pop()
}

/// The device pack's `xc8` folder (`-mdfp`).
pub fn find_dfp(dev: &Device) -> Option<PathBuf> {
    let home = std::env::var("HOME").ok()?;
    let p = Path::new(&home).join(".mchp_packs/Microchip").join(&dev.device.pack).join(&dev.device.pack_version).join("xc8");
    p.is_dir().then_some(p)
}

pub struct AsmRun {
    pub ok: bool,
    pub output: String,
}

pub fn run_pic_as(pic_as: &Path, dev: &Device, asm: &Path, hex: &Path, map: &Path) -> Result<AsmRun, String> {
    let dfp = find_dfp(dev).ok_or_else(|| format!("device pack {} {} not found under ~/.mchp_packs", dev.device.pack, dev.device.pack_version))?;
    let cpu = dev.device.name.strip_prefix("PIC").unwrap_or(&dev.device.name).to_string();
    let out = Command::new(pic_as)
        .arg(format!("-mcpu={cpu}"))
        .arg(format!("-mdfp={}", dfp.display()))
        .arg(format!("-Wl,-Map={}", map.display()))
        .arg("-o")
        .arg(hex)
        .arg(asm)
        .output()
        .map_err(|e| format!("cannot run {}: {e}", pic_as.display()))?;
    let mut text = String::from_utf8_lossy(&out.stdout).into_owned();
    text.push_str(&String::from_utf8_lossy(&out.stderr));
    Ok(AsmRun { ok: out.status.success(), output: text })
}

pub fn report(p: &Program, g: &Generated) -> String {
    let mut s = String::new();
    s.push_str(&format!("Program: {} words ({} bytes)\n", g.out.words, g.out.words * 2));
    for (n, w) in &g.out.func_words {
        s.push_str(&format!("  {:6} words  {n}\n", w));
    }
    let nv = p.vars.len();
    let mut total = 0;
    s.push_str("Data RAM:\n");
    let mut rows: Vec<(u32, String, u32)> = Vec::new();
    for (i, o) in g.objs.iter().enumerate() {
        if let Some(a) = g.layout.addr.get(i).copied().flatten() {
            let name = if i < nv { format!("{} ({})", o.name, p.vars[i].name) } else { o.name.clone() };
            rows.push((a, name, o.bytes));
            total += o.bytes;
        }
    }
    rows.sort();
    for (a, n, b) in rows {
        s.push_str(&format!("  0x{a:03X}  {b:3}  {n}\n"));
    }
    s.push_str(&format!("  total {total} bytes\n"));
    s
}
