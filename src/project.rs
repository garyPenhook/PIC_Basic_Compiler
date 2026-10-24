//! Loads a program and the modules it includes, in dependency order.
//!
//! `Include "name"` searches the including file's folder, then each library folder given to the
//! loader (LANGUAGE.md §9). A module is loaded once however often it is included.

use crate::ast::{Unit, UnitKind};
use crate::diag::{Diagnostics, SourceMap, Span};
use crate::lexer::lex;
use crate::parser::parse_unit;
use crate::pp::{OptionDirective, preprocess};
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
}

pub fn load(main: &Path, cfg: &LoadConfig, diags: &mut Diagnostics) -> Project {
    let mut proj = Project::default();
    let mut ld = Loader {
        cfg,
        defined: cfg.defines.iter().map(|d| d.to_ascii_lowercase()).collect(),
        by_path: HashMap::new(),
        loading: HashSet::new(),
    };
    ld.load_file(&mut proj, diags, main, Span::default());
    proj
}

/// Parses source text that is already in memory (tests and tools). No includes are followed.
pub fn load_text(name: &str, text: &str, diags: &mut Diagnostics) -> Project {
    let mut proj = Project::default();
    let mut defined = HashSet::new();
    let file = proj.sources.add(name.to_string(), text.to_string());
    let pp = preprocess(file, text, &mut defined, diags);
    proj.options.extend(pp.options);
    let toks = lex(file, &pp.text, diags);
    let unit = parse_unit(file, toks, diags, &mut proj.next_id);
    proj.units.push(LoadedUnit { unit, path: PathBuf::from(name), includes: vec![] });
    proj
}

struct Loader<'c> {
    cfg: &'c LoadConfig,
    defined: HashSet<String>,
    by_path: HashMap<PathBuf, usize>,
    loading: HashSet<PathBuf>,
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
        let pp = preprocess(file, &text, &mut self.defined, diags);
        proj.options.extend(pp.options);
        let toks = lex(file, &pp.text, diags);
        let unit = parse_unit(file, toks, diags, &mut proj.next_id);

        let mut includes = Vec::new();
        let dir = path.parent().map(Path::to_path_buf).unwrap_or_default();
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
