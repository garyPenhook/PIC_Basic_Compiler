//! Loads a program and the modules it includes, in dependency order.
//!
//! `Include "name"` searches the including file's folder, then each library folder given to the
//! loader (LANGUAGE.md §9). A module is loaded once however often it is included.

use crate::ast::{Unit, UnitKind};
use crate::diag::{Diagnostics, SourceMap, Span};
use crate::lexer::{Tok, lex};
use crate::parser::parse_unit;
use crate::pp::{OptionDirective, Predef, preprocess, scan_header};
use std::collections::{HashMap, HashSet};
use std::path::{Path, PathBuf};

pub struct LoadedUnit {
    pub unit: Unit,
    pub path: PathBuf,
    /// Indices (into `Project::units`) of the modules this unit includes directly, in order.
    pub includes: Vec<usize>,
}

#[derive(Default)]
pub struct Project {
    /// Dependencies first; the main program is last.
    pub units: Vec<LoadedUnit>,
    pub options: Vec<OptionDirective>,
    pub sources: SourceMap,
    next_id: u32,
}

pub struct LoadConfig {
    pub lib_dirs: Vec<PathBuf>,
    pub defines: Vec<String>,
    /// Folders searched for `<part>.toml`, so `#if _has(REG)` can see the device's registers.
    pub devices_dirs: Vec<PathBuf>,
}

pub fn load(main: &Path, cfg: &LoadConfig, diags: &mut Diagnostics) -> Project {
    let mut proj = Project::default();
    let mut ld = Loader {
        cfg,
        by_path: HashMap::new(),
        loading: HashSet::new(),
        // `#if` in any file sees the main program's `Clock` and `Device`.
        predef: std::fs::read_to_string(main).map(|t| scan_header(&t)).unwrap_or_default(),
    };
    ld.predef.registers = ld.predef.device.as_deref().and_then(|d| device_registers(d, &cfg.devices_dirs));
    ld.load_file(&mut proj, diags, main, Span::default());
    proj
}

/// Lower-case names of the registers (and aliases) of `device`, from the first matching description.
fn device_registers(device: &str, dirs: &[PathBuf]) -> Option<HashSet<String>> {
    let bare = device.strip_prefix("pic").unwrap_or(device);
    // The header scan lower-cases the name, the files are upper-case.
    let want = format!("{bare}.toml");
    let path = dirs.iter().find_map(|d| {
        std::fs::read_dir(d).ok()?.flatten().map(|e| e.path()).find(|p| p.file_name().and_then(|n| n.to_str()).is_some_and(|n| n.eq_ignore_ascii_case(&want)))
    })?;
    let d = crate::sema::load_device_cached(&path).ok()?;
    let mut set = HashSet::new();
    for s in &d.sfr {
        set.insert(s.name.to_ascii_lowercase());
        set.extend(s.aliases.iter().map(|a| a.to_ascii_lowercase()));
        set.extend(s.fields.iter().chain(&s.legacy).map(|f| format!("{}.{}", s.name, f.name).to_ascii_lowercase()));
    }
    set.extend(d.joined.iter().map(|j| j.name.to_ascii_lowercase()));
    Some(set)
}

/// Parses source text that is already in memory (tests and tools). No includes are followed.
pub fn load_text(name: &str, text: &str, diags: &mut Diagnostics) -> Project {
    let mut proj = Project::default();
    let mut defined = HashSet::new();
    let file = proj.sources.add(name.to_string(), text.to_string());
    let pp = preprocess(file, text, &mut defined, &scan_header(text), diags);
    proj.options.extend(pp.options);
    let toks = lex(file, &pp.text, diags);
    let unit = parse_unit(file, toks, diags, &mut proj.next_id);
    proj.units.push(LoadedUnit { unit, path: PathBuf::from(name), includes: vec![] });
    proj
}

struct Loader<'c> {
    cfg: &'c LoadConfig,
    by_path: HashMap<PathBuf, usize>,
    loading: HashSet<PathBuf>,
    predef: Predef,
}

impl Loader<'_> {
    fn load_file(&mut self, proj: &mut Project, diags: &mut Diagnostics, path: &Path, at: Span) -> Option<usize> {
        let canon = path.canonicalize().unwrap_or_else(|_| path.to_path_buf());
        if let Some(&i) = self.by_path.get(&canon) {
            return Some(i);
        }
        if self.loading.contains(&canon) {
            diags.error("E-INCLUDE", at, format!("`{}` includes itself, directly or indirectly", path.display()));
            return None;
        }
        let text = match std::fs::read_to_string(path) {
            Ok(t) => t,
            Err(e) => {
                diags.error("E-INCLUDE", at, format!("cannot read `{}`: {e}", path.display()));
                return None;
            }
        };
        self.loading.insert(canon.clone());
        let file = proj.sources.add(path.display().to_string(), text.clone());
        // `#define` names are scoped to the file: only the command-line names are shared, so the
        // result does not depend on include order.
        let mut defined: HashSet<String> = self.cfg.defines.iter().map(|d| d.to_ascii_lowercase()).collect();
        let pp = preprocess(file, &text, &mut defined, &self.predef, diags);
        proj.options.extend(pp.options);
        let toks = lex(file, &pp.text, diags);
        // A program that mentions Float gets the Float arithmetic module without asking for it.
        let uses_float = toks.iter().any(|t| t.tok == Tok::Kw("float")) && path.file_stem().is_none_or(|f| f != "floatlib");
        let unit = parse_unit(file, toks, diags, &mut proj.next_id);

        let mut includes = Vec::new();
        let dir = path.parent().map(Path::to_path_buf).unwrap_or_default();
        if uses_float {
            let lib = std::iter::once(&dir).chain(self.cfg.lib_dirs.iter()).map(|d| d.join("floatlib.bas")).find(|c| c.is_file());
            if let Some(i) = lib.and_then(|p| self.load_file(proj, diags, &p, Span::default())) {
                includes.push(i);
            }
        }
        for inc in &unit.includes {
            let mut found = None;
            let fname = format!("{}.bas", inc.name);
            for d in std::iter::once(&dir).chain(self.cfg.lib_dirs.iter()) {
                let cand = d.join(&fname);
                if cand.is_file() {
                    found = Some(cand);
                    break;
                }
            }
            match found {
                None => diags.error("E-INCLUDE", inc.span, format!("module `{}` not found (looked for {fname} next to the including file and in the library folders)", inc.name)),
                Some(p) => {
                    if let Some(i) = self.load_file(proj, diags, &p, inc.span) {
                        let m = &proj.units[i].unit;
                        if m.kind != UnitKind::Module {
                            diags.error("E-INCLUDE", inc.span, format!("`{}` is a program, not a module", inc.name));
                        } else if m.name.as_ref().is_some_and(|n| !n.name.eq_ignore_ascii_case(&inc.name)) {
                            diags.error("E-INCLUDE", inc.span, format!("file `{fname}` declares module `{}`; the names must match", m.name.as_ref().unwrap().name));
                        }
                        if !includes.contains(&i) {
                            includes.push(i);
                        }
                    }
                }
            }
        }
        self.loading.remove(&canon);
        proj.units.push(LoadedUnit { unit, path: path.to_path_buf(), includes: includes.iter().map(|&i| i).collect() });
        let idx = proj.units.len() - 1;
        // Included indices were assigned before this unit was pushed, so they stay valid.
        self.by_path.insert(canon, idx);
        Some(idx)
    }
}
