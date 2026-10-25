//! Semantic analysis: name resolution, types, constant evaluation and the language's static
//! rules (LANGUAGE.md). The tree is not modified; results are attached to node ids in `Analysis`.

use crate::ast::*;
use crate::diag::{Diagnostics, Span};
use crate::project::Project;
use crate::types::*;
use devdesc::Device;
use std::collections::{HashMap, HashSet};
use std::path::PathBuf;

// ---- public results ------------------------------------------------------------------------

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Optimize {
    Size,
    Speed,
    Balanced,
}

#[derive(Clone, Debug)]
pub struct Options {
    pub strict: bool,
    pub bounds_check: bool,
    pub optimize: Optimize,
    pub isr_shadow: bool,
    /// Warning codes switched off with `#option Warn.<id> = false`.
    pub warn_off: HashSet<String>,
}

impl Default for Options {
    fn default() -> Self {
        Options { strict: false, bounds_check: false, optimize: Optimize::Balanced, isr_shadow: true, warn_off: HashSet::new() }
    }
}

#[derive(Clone, Debug)]
pub struct FieldInfo {
    pub name: String,
    pub ty: Ty,
    /// A union member that shares another field's storage.
    pub alias: bool,
}

#[derive(Clone, Debug)]
pub struct ParamInfo {
    pub name: String,
    pub ty: Ty,
    pub mode: ParamMode,
    pub is_array: bool,
    pub has_default: bool,
}

#[derive(Clone, Debug)]
pub enum SymKind {
    Const { ty: Ty, val: CVal, typed: bool },
    ConstArray { elem: Ty, vals: Vec<CVal> },
    Var { ty: Ty },
    Param { ty: Ty, mode: ParamMode },
    Alias { ty: Ty },
    Struct { fields: Vec<FieldInfo>, size: u32 },
    EventType,
    Routine { params: Vec<ParamInfo>, ret: Option<Ty>, reentrant: bool, inlining: Inlining },
    Interrupt { priority: Option<i64> },
    Event,
}

#[derive(Clone, Debug)]
pub struct Symbol {
    pub name: String,
    pub span: Span,
    pub vis: Vis,
    /// Index of the unit that declared it; `usize::MAX` for predefined names.
    pub unit: usize,
    /// True for symbols declared inside a routine.
    pub local: bool,
    /// The routine, interrupt or event that declares a local symbol or parameter.
    pub owner: Option<SymId>,
    pub kind: SymKind,
}

/// What a designator's head name resolved to.
#[derive(Clone, Debug, PartialEq)]
pub enum Res {
    Sym(SymId),
    Register(String),
    Intrinsic(String),
    Module(usize),
}

#[derive(Clone, Debug)]
pub struct CallEdge {
    pub caller: Option<SymId>,
    pub callee: SymId,
    pub span: Span,
}

#[derive(Clone, Debug)]
pub struct ConfigSetting {
    pub register: String,
    pub field: String,
    pub value: u32,
}

#[derive(Default)]
pub struct Analysis {
    pub symbols: Vec<Symbol>,
    pub device: Option<Device>,
    pub clock_mhz: Option<f64>,
    /// Where `Clock` is given (for diagnostics about it).
    pub clock_span: Option<Span>,
    pub options: Options,
    pub config: Vec<ConfigSetting>,
    /// Type of every checked expression.
    pub types: HashMap<NodeId, Ty>,
    /// Value of every expression that folded to a constant.
    pub consts: HashMap<NodeId, CVal>,
    /// Evaluation width in bits chosen for integer arithmetic nodes (D16).
    pub widths: HashMap<NodeId, u8>,
    /// Resolution of each designator's head.
    pub resolved: HashMap<NodeId, Res>,
    pub calls: Vec<CallEdge>,
    /// Bytes of global variables.
    pub global_ram: u32,
    /// The symbol declared at the position of a declared name; the back end uses it to walk the
    /// tree and find the symbol each declaration created.
    pub decl_syms: HashMap<Span, SymId>,
    /// The `Interrupt` each `Enable`/`Disable` names, keyed by the span of the name.
    pub enables: HashMap<Span, SymId>,
    /// `Bit`/`Boolean` arrays that are used as a whole somewhere (passed, copied, cleared,
    /// initialised, given a bit or byte view). They keep one byte per element; every other
    /// `Dim`med bit array is packed eight to a byte (D47).
    pub unpackable: HashSet<SymId>,
    /// Global `Bit`/`Boolean` arrays with their element counts, for the RAM check.
    pub global_bit_arrays: Vec<(SymId, u32)>,
}

/// Parsed device descriptions by path. The 18F27Q10 file is large, and tests and tools analyse
/// many programs against it.
fn load_device_cached(path: &std::path::Path) -> Result<Device, devdesc::Error> {
    use std::sync::{Mutex, OnceLock};
    static CACHE: OnceLock<Mutex<HashMap<PathBuf, Device>>> = OnceLock::new();
    let cache = CACHE.get_or_init(|| Mutex::new(HashMap::new()));
    if let Some(d) = cache.lock().unwrap().get(path) {
        return Ok(d.clone());
    }
    let d = Device::load(path)?;
    cache.lock().unwrap().insert(path.to_path_buf(), d.clone());
    Ok(d)
}

pub struct SemaConfig {
    pub devices_dirs: Vec<PathBuf>,
}

// ---- internals -----------------------------------------------------------------------------

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum Place {
    None,
    Var,
    ReadOnly,
}

#[derive(Clone, Debug)]
struct EI {
    ty: Ty,
    val: Option<CVal>,
    /// An untyped literal or inferred constant: it adapts to the type it meets.
    lit: bool,
    place: Place,
    call: bool,
    in_array: bool,
}

impl EI {
    fn new(ty: Ty) -> EI {
        EI { ty, val: None, lit: false, place: Place::None, call: false, in_array: false }
    }
    fn place(ty: Ty, place: Place) -> EI {
        EI { place, ..EI::new(ty) }
    }
    fn lit(ty: Ty, val: CVal) -> EI {
        EI { val: Some(val), lit: true, ..EI::new(ty) }
    }
    fn int_lit(v: i128) -> EI {
        EI::lit(narrowest(v), CVal::Int(v))
    }
}

#[derive(Clone)]
struct RegInfo {
    name: String,
    ty: Ty,
    /// Bit fields: name, position, width.
    fields: Vec<(String, u8, u8)>,
}

enum Cur {
    Val(EI),
    Module(usize),
    Routine(SymId),
    Intrinsic(String),
    Reg(RegInfo),
    Handler,
}

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
enum Kind {
    Main,
    Sub,
    Function,
    Interrupt,
    Event,
}

struct Ctx {
    routine: Option<SymId>,
    kind: Kind,
    ret: Option<Ty>,
    fn_key: Option<String>,
    loops: u32,
    saves: u32,
    labels: HashSet<String>,
    result_assigned: bool,
}

impl Ctx {
    fn main() -> Ctx {
        Ctx { routine: None, kind: Kind::Main, ret: None, fn_key: None, loops: 0, saves: 0, labels: HashSet::new(), result_assigned: false }
    }
}

const CONVERSIONS: &[&str] = &["byte", "word", "integer", "longword", "longint", "shortint", "float", "boolean", "bit", "char"];
const PREDEFINED_INTRINSICS: &[&str] = &["abs", "min", "max"];

pub struct Sema<'p, 'd> {
    proj: &'p Project,
    diags: &'d mut Diagnostics,
    cfg: &'p SemaConfig,
    a: Analysis,
    unit: usize,
    unit_scopes: Vec<HashMap<String, SymId>>,
    scopes: Vec<HashMap<String, SymId>>,
    predef: HashMap<String, SymId>,
    ctx: Ctx,
    for_vars: Vec<SymId>,
    enabled: HashMap<Option<i64>, SymId>,
    interrupts: Vec<SymId>,
    reentrant_ok: HashSet<SymId>,
    /// True while the operand of `Bound` is checked: it only needs the array's type.
    in_bound: bool,
}

pub fn analyze(proj: &Project, cfg: &SemaConfig, diags: &mut Diagnostics) -> Analysis {
    if proj.units.is_empty() {
        // The main file could not be read; the loader has already reported why.
        return Analysis::default();
    }
    let mut s = Sema {
        proj,
        diags,
        cfg,
        a: Analysis::default(),
        unit: 0,
        unit_scopes: vec![HashMap::new(); proj.units.len()],
        scopes: Vec::new(),
        predef: HashMap::new(),
        ctx: Ctx::main(),
        for_vars: Vec::new(),
        enabled: HashMap::new(),
        interrupts: Vec::new(),
        reentrant_ok: HashSet::new(),
        in_bound: false,
    };
    s.run();
    s.a
}

impl<'p, 'd> Sema<'p, 'd> {
    // ---- plumbing ------------------------------------------------------------------------

    fn err<T>(&mut self, code: &'static str, span: Span, msg: impl Into<String>) -> Option<T> {
        self.diags.error(code, span, msg);
        None
    }

    fn add_symbol(&mut self, name: &str, span: Span, vis: Vis, kind: SymKind) -> SymId {
        let local = !self.scopes.is_empty();
        let owner = if local { self.ctx.routine } else { None };
        self.a.symbols.push(Symbol { name: name.to_string(), span, vis, unit: self.unit, local, owner, kind });
        let id = self.a.symbols.len() - 1;
        if span != Span::default() {
            self.a.decl_syms.insert(span, id);
        }
        id
    }

    /// Declares `name` in the innermost scope; reports a clash with a name in the same scope.
    fn declare(&mut self, name: &Ident, vis: Vis, kind: SymKind) -> Option<SymId> {
        let key = name.key();
        let existing = match self.scopes.last() {
            Some(s) => s.get(&key).copied(),
            None => self.unit_scopes[self.unit].get(&key).copied(),
        };
        if let Some(prev) = existing {
            let at = self.a.symbols[prev].span;
            return self.err("E-REDECL", name.span, format!("`{}` is already declared (line {})", name.name, at.line));
        }
        if self.a.device.is_some() && self.find_register(&key).is_some() {
            self.diags.warn("W-REGNAME", name.span, format!("`{}` is also a device register; from here on the name means this declaration, not the register", name.name));
        }
        let id = self.add_symbol(&name.name, name.span, vis, kind);
        match self.scopes.last_mut() {
            Some(s) => s.insert(key, id),
            None => self.unit_scopes[self.unit].insert(key, id),
        };
        Some(id)
    }

    fn lookup(&mut self, key: &str, span: Span) -> Option<Option<SymId>> {
        for s in self.scopes.iter().rev() {
            if let Some(&id) = s.get(key) {
                return Some(Some(id));
            }
        }
        if let Some(&id) = self.unit_scopes[self.unit].get(key) {
            return Some(Some(id));
        }
        let mut found: Vec<(usize, SymId)> = Vec::new();
        for &inc in &self.proj.units[self.unit].includes {
            if let Some(&id) = self.unit_scopes[inc].get(key)
                && self.a.symbols[id].vis == Vis::Public
            {
                found.push((inc, id));
            }
        }
        match found.len() {
            0 => {}
            1 => return Some(Some(found[0].1)),
            _ => {
                let names: Vec<String> = found.iter().filter_map(|(u, _)| self.proj.units[*u].unit.name.as_ref().map(|n| n.name.clone())).collect();
                self.diags.error("E-AMBIG", span, format!("`{key}` is declared in several included modules ({}); qualify it, e.g. `{}.{key}`", names.join(", "), names.first().cloned().unwrap_or_default()));
                return None;
            }
        }
        if let Some(&id) = self.predef.get(key) {
            return Some(Some(id));
        }
        Some(None)
    }

    fn module_by_name(&self, key: &str) -> Option<usize> {
        self.proj.units[self.unit].includes.iter().copied().find(|&u| self.proj.units[u].unit.name.as_ref().is_some_and(|n| n.key() == key))
    }

    fn struct_size(&self, id: SymId) -> u32 {
        match &self.a.symbols[id].kind {
            SymKind::Struct { size, .. } => *size,
            _ => 0,
        }
    }

    fn size_of(&self, ty: &Ty) -> u32 {
        ty.size_bytes(&|s| self.struct_size(s))
    }

    // ---- driver --------------------------------------------------------------------------

    fn run(&mut self) {
        let proj = self.proj;
        self.read_options();
        self.find_device();
        self.predefine();
        // Clock and Config of every unit first, so that `_Clock` is visible to library modules
        // that are analysed before the main program.
        for i in 0..proj.units.len() {
            self.unit = i;
            self.headers(i);
        }
        for i in 0..proj.units.len() {
            self.unit = i;
            let u = &proj.units[i].unit;
            for d in &u.decls {
                self.decl(d);
            }
            self.ctx = Ctx::main();
            self.check_labels(&u.stmts);
            for s in &u.stmts {
                self.stmt(s);
            }
            self.ctx = Ctx::main();
        }
        self.check_recursion();
        self.check_ram();
        self.check_clock_setup();
        let off = self.a.options.warn_off.clone();
        self.diags.items.retain(|d| !(d.severity == crate::diag::Severity::Warning && off.contains(d.code)));
    }

    /// `Clock` only tells the compiler the speed to expect. When it differs from the speed the
    /// `RSTOSC` setting starts the part at (Table 5-1: `HFINTOSC_64MHZ` 64 MHz, `HFINTOSC_1MHZ`
    /// 1 MHz) and nothing in the program sets the oscillator, every delay and baud rate is wrong.
    fn check_clock_setup(&mut self) {
        let (Some(clock), Some(span)) = (self.a.clock_mhz, self.a.clock_span) else { return };
        let Some(rst) = self.a.config.iter().find(|c| c.field == "RSTOSC") else { return };
        let reset_mhz = match rst.value {
            0 => 64.0,
            6 => 1.0,
            _ => return,
        };
        if (clock - reset_mhz).abs() < 1e-9 {
            return;
        }
        let proj = self.proj;
        let by_module = proj.units.iter().any(|u| u.path.file_stem().is_some_and(|n| n.eq_ignore_ascii_case("intosc")));
        if by_module || proj.sources.texts().any(writes_oscillator) {
            return;
        }
        self.diags.warn(
            "W-CLOCK",
            span,
            format!("Clock is {clock} MHz but RSTOSC starts the part at {reset_mhz} MHz and nothing sets the oscillator: Include \"intosc\", write OSCFRQ, or change RSTOSC (docs/CLOCK.md)"),
        );
    }

    fn read_options(&mut self) {
        let proj = self.proj;
        let mut o = Options::default();
        for d in &proj.options {
            let bool_of = |v: &str| match v {
                "true" | "on" | "yes" | "1" => Some(true),
                "false" | "off" | "no" | "0" => Some(false),
                _ => None,
            };
            let ok = match d.name.as_str() {
                "strict" => bool_of(&d.value).map(|b| o.strict = b).is_some(),
                "boundscheck" => bool_of(&d.value).map(|b| o.bounds_check = b).is_some(),
                "isr_shadow" => bool_of(&d.value).map(|b| o.isr_shadow = b).is_some(),
                "optimize" => {
                    let v = match d.value.as_str() {
                        "size" => Some(Optimize::Size),
                        "speed" => Some(Optimize::Speed),
                        "balanced" => Some(Optimize::Balanced),
                        _ => None,
                    };
                    v.map(|v| o.optimize = v).is_some()
                }
                n if n.starts_with("warn.") && n.len() > 5 => match bool_of(&d.value) {
                    Some(on) => {
                        let code = format!("W-{}", n[5..].to_ascii_uppercase());
                        if on {
                            o.warn_off.remove(&code);
                        } else {
                            o.warn_off.insert(code);
                        }
                        true
                    }
                    None => false,
                },
                n => {
                    self.diags.error("E-OPTION", d.span, format!("unknown option `{n}` (known: Strict, BoundsCheck, ISR_SHADOW, Optimize, Warn.<id>)"));
                    continue;
                }
            };
            if !ok {
                self.diags.error("E-OPTION", d.span, format!("bad value `{}` for option `{}`", d.value, d.name));
            }
        }
        self.a.options = o;
    }

    fn find_device(&mut self) {
        let proj = self.proj;
        let mut chosen: Option<(String, Span)> = None;
        for lu in &proj.units {
            for h in &lu.unit.headers {
                if let HeaderKind::Device(name) = &h.kind {
                    match &chosen {
                        None => chosen = Some((name.clone(), h.span)),
                        Some((first, _)) if first != name => {
                            self.diags.error("E-DEVICE", h.span, format!("this unit says Device = {name} but another unit says {first}"));
                        }
                        _ => {}
                    }
                }
            }
        }
        let main = proj.units.last().expect("a project has at least one unit");
        let Some((name, span)) = chosen else {
            if main.unit.kind == UnitKind::Program {
                let sp = Span { file: main.unit.file, line: 1, col: 1 };
                self.diags.error("E-NODEVICE", sp, "no `Device = …` line; the compiler does not assume a part (LANGUAGE.md §1)");
            }
            return;
        };
        let bare = name.strip_prefix("PIC").unwrap_or(&name).to_string();
        let mut tried = Vec::new();
        for dir in &self.cfg.devices_dirs {
            let p = dir.join(format!("{bare}.toml"));
            tried.push(p.display().to_string());
            if p.is_file() {
                match load_device_cached(&p) {
                    Ok(d) => {
                        if !d.device.name.eq_ignore_ascii_case(&name) {
                            self.diags.error("E-DEVICE", span, format!("{} describes {}, not {name}", p.display(), d.device.name));
                        } else {
                            self.a.device = Some(d);
                        }
                    }
                    Err(e) => self.diags.error("E-DEVICE", span, format!("cannot load {}: {e}", p.display())),
                }
                return;
            }
        }
        self.diags.error("E-DEVICE", span, format!("no device description for {name} (looked for {})", if tried.is_empty() { "no device folders".to_string() } else { tried.join(", ") }));
    }

    fn predefine(&mut self) {
        let add = |this: &mut Self, name: &str, ty: Ty, val: CVal| {
            let id = this.add_symbol(name, Span::default(), Vis::Public, SymKind::Const { ty, val, typed: false });
            this.a.symbols[id].unit = usize::MAX;
            this.predef.insert(name.to_ascii_lowercase(), id);
        };
        add(self, "ipLow", BYTE, CVal::Int(1));
        add(self, "ipHigh", BYTE, CVal::Int(2));
        if let Some(d) = &self.a.device {
            let n = d.device.name.clone();
            add(self, "_Device", Ty::Str(n.len() as u32), CVal::Str(n));
        }
    }

    fn headers(&mut self, unit: usize) {
        let proj = self.proj;
        let mut seen_config: HashSet<String> = HashSet::new();
        for h in &proj.units[unit].unit.headers {
            match &h.kind {
                HeaderKind::Device(_) => {}
                HeaderKind::Clock(e) => {
                    let Some(v) = self.const_value(e) else { continue };
                    let Some(mhz) = v.as_f64() else {
                        self.diags.error("E-CLOCK", e.span, "Clock must be a number of MHz");
                        continue;
                    };
                    if mhz <= 0.0 {
                        self.diags.error("E-CLOCK", e.span, "Clock must be greater than zero");
                    } else if let Some(prev) = self.a.clock_mhz
                        && (prev - mhz).abs() > f64::EPSILON
                    {
                        self.diags.error("E-CLOCK", e.span, format!("Clock is {mhz} here but {prev} elsewhere"));
                    } else {
                        self.a.clock_mhz = Some(mhz);
                        self.a.clock_span = Some(e.span);
                        let id = self.add_symbol("_Clock", Span::default(), Vis::Public, SymKind::Const { ty: Ty::Float, val: CVal::Float(mhz), typed: false });
                        self.a.symbols[id].unit = usize::MAX;
                        self.predef.insert("_clock".into(), id);
                    }
                }
                HeaderKind::Config(items) => {
                    for it in items {
                        self.config_item(it, &mut seen_config);
                    }
                }
            }
        }
    }

    fn config_item(&mut self, it: &ConfigItem, seen: &mut HashSet<String>) {
        let Some(dev) = self.a.device.clone() else { return };
        let key = it.name.key();
        if !seen.insert(key.clone()) {
            self.diags.error("E-CONFIG", it.name.span, format!("configuration setting `{}` is given twice", it.name.name));
            return;
        }
        let found = dev.config.iter().find_map(|r| r.fields.iter().find(|f| f.name.eq_ignore_ascii_case(&key)).map(|f| (r, f)));
        let Some((reg, field)) = found else {
            self.diags.error("E-CONFIG", it.name.span, format!("`{}` is not a configuration setting of {}", it.name.name, dev.device.name));
            return;
        };
        let value = match &it.value {
            ConfigValue::Name(n) => match field.settings.iter().find(|s| s.name.eq_ignore_ascii_case(&n.name)) {
                Some(s) => s.value,
                None => {
                    let list: Vec<&str> = field.settings.iter().map(|s| s.name.as_str()).take(12).collect();
                    self.diags.error("E-CONFIG", n.span, format!("`{}` is not a value of {} (values: {}{})", n.name, field.name, list.join(", "), if field.settings.len() > 12 { ", …" } else { "" }));
                    return;
                }
            },
            ConfigValue::Int(v, sp) => {
                if *v >= 1u64 << field.width {
                    self.diags.error("E-CONFIG", *sp, format!("{v} does not fit the {}-bit setting {}", field.width, field.name));
                    return;
                }
                *v as u32
            }
        };
        self.a.config.push(ConfigSetting { register: reg.name.clone(), field: field.name.clone(), value });
    }

    // ---- declarations --------------------------------------------------------------------

    fn decl(&mut self, d: &'p Decl) {
        let vis = d.vis.unwrap_or(Vis::Private);
        match &d.kind {
            DeclKind::Const(items) => {
                for it in items {
                    self.const_item(it, vis);
                }
            }
            DeclKind::Dim(dim) => self.dim_decl(dim, vis),
            DeclKind::Structure(sd) => self.struct_decl(sd, vis),
            DeclKind::EventType(n) => {
                self.declare(n, vis, SymKind::EventType);
            }
            DeclKind::Symbol(n, e) => self.symbol_decl(n, e, vis),
            DeclKind::Routine(r) => self.routine_decl(r, vis, d.span),
            DeclKind::Interrupt(i) => self.interrupt_decl(i, vis),
            DeclKind::Event(e) => {
                let Some(id) = self.declare(&e.name, vis, SymKind::Event) else { return };
                self.body(&e.body, Kind::Event, Some(id), None, None, &[]);
            }
        }
    }

    fn const_item(&mut self, it: &'p ConstItem, vis: Vis) {
        let declared = it.ty.as_ref().and_then(|t| self.resolve_type(t));
        if it.ty.is_some() && declared.is_none() {
            return;
        }
        match &it.init {
            ConstInit::Scalar(e) => {
                if it.size.is_some() {
                    self.diags.error("E-CONST", it.name.span, "a constant with a size needs a list of values: `Const T(3) As Byte = (1, 2, 3)`");
                    return;
                }
                let Some(ei) = self.check_expr(e) else { return };
                let Some(val) = ei.val.clone() else {
                    self.diags.error("E-CONST-EXPR", e.span, format!("the value of constant `{}` must be known at compile time", it.name.name));
                    return;
                };
                match declared {
                    Some(t) => {
                        if !matches!(t, Ty::Int(..) | Ty::Float | Ty::Bool | Ty::Bit | Ty::Char | Ty::Str(_)) {
                            self.diags.error("E-CONST", it.name.span, format!("a {t} cannot be a constant"));
                            return;
                        }
                        if self.assign_ok(&t, &ei, e.span, "constant") {
                            let val = coerce_const(&t, val);
                            self.declare(&it.name, vis, SymKind::Const { ty: t, val, typed: true });
                        }
                    }
                    None => {
                        self.declare(&it.name, vis, SymKind::Const { ty: ei.ty.clone(), val, typed: false });
                    }
                }
            }
            ConstInit::List(items) => {
                let Some(elem) = declared else {
                    self.diags.error("E-CONST", it.name.span, "a constant array needs an element type: `Const T(3) As Byte = (…)`");
                    return;
                };
                let n = match &it.size {
                    Some(sz) => match self.const_int(sz) {
                        Some(n) if n >= 1 && n <= 65535 => n as u32,
                        Some(_) => {
                            self.diags.error("E-CONST", sz.span, "array size must be 1 to 65535");
                            return;
                        }
                        None => return,
                    },
                    None => items.len() as u32,
                };
                if n as usize != items.len() {
                    self.diags.error("E-CONST-ARRAY", it.name.span, format!("`{}` declares {n} elements but the list has {}", it.name.name, items.len()));
                    return;
                }
                let mut vals = Vec::new();
                let mut ok = true;
                for e in items {
                    let Some(ei) = self.check_expr(e) else {
                        ok = false;
                        continue;
                    };
                    let Some(v) = ei.val.clone() else {
                        self.diags.error("E-CONST-EXPR", e.span, "constant array elements must be known at compile time");
                        ok = false;
                        continue;
                    };
                    if self.assign_ok(&elem, &ei, e.span, "element") {
                        vals.push(coerce_const(&elem, v));
                    } else {
                        ok = false;
                    }
                }
                if ok {
                    self.declare(&it.name, vis, SymKind::ConstArray { elem, vals });
                }
            }
        }
    }

    fn resolve_type(&mut self, t: &'p TypeSpec) -> Option<Ty> {
        Some(match t {
            TypeSpec::Boolean => Ty::Bool,
            TypeSpec::Bit => Ty::Bit,
            TypeSpec::Byte => BYTE,
            TypeSpec::ShortInt => SHORTINT,
            TypeSpec::Word => WORD,
            TypeSpec::Integer => INTEGER,
            TypeSpec::LongWord => LONGWORD,
            TypeSpec::LongInt => LONGINT,
            TypeSpec::Float => Ty::Float,
            TypeSpec::Char => Ty::Char,
            TypeSpec::String(None) => Ty::Str(DEFAULT_STRING_SIZE),
            TypeSpec::String(Some(e)) => {
                let n = self.const_int(e)?;
                if !(1..=255).contains(&n) {
                    return self.err("E-CONST-RANGE", e.span, "string size must be 1 to 255");
                }
                Ty::Str(n as u32)
            }
            TypeSpec::Named(id) => return self.named_type(id),
        })
    }

    fn named_type(&mut self, id: &Ident) -> Option<Ty> {
        match self.lookup(&id.key(), id.span)? {
            Some(s) => match &self.a.symbols[s].kind {
                SymKind::Struct { .. } => Some(Ty::Struct(s)),
                SymKind::EventType => Some(Ty::EventVar(s)),
                _ => self.err("E-TYPE", id.span, format!("`{}` is not a type", id.name)),
            },
            None => self.err("E-UNDECLARED", id.span, format!("unknown type `{}`", id.name)),
        }
    }

    /// If an `As` designator is just the name of a structure or event type, that type.
    fn designator_as_type(&mut self, d: &Designator) -> Option<Option<Ty>> {
        if !d.parts.is_empty() {
            return Some(None);
        }
        match self.lookup(&d.head.key(), d.head.span)? {
            Some(s) => match &self.a.symbols[s].kind {
                SymKind::Struct { .. } => Some(Some(Ty::Struct(s))),
                SymKind::EventType => Some(Some(Ty::EventVar(s))),
                _ => Some(None),
            },
            None => Some(None),
        }
    }

    fn dim_decl(&mut self, dim: &'p DimDecl, vis: Vis) {
        let Some(ac) = &dim.as_clause else {
            self.diags.error("E-DIM", dim.items[0].name.span, "a variable needs a type: `Dim x As Byte`");
            return;
        };
        let ty = match ac {
            AsClause::Type(t) => match self.resolve_type(t) {
                Some(t) => Some(t),
                None => return,
            },
            AsClause::Designator(d) => match self.designator_as_type(d) {
                Some(t) => t,
                None => return,
            },
        };
        let Some(base) = ty else {
            let AsClause::Designator(d) = ac else { unreachable!() };
            self.alias_decl(dim, d, vis);
            return;
        };
        if dim.trailing_list.is_some() && (dim.items.len() != 1 || dim.items[0].init.is_some() || dim.items[0].list.is_some() || dim.items[0].size.is_none()) {
            self.diags.error("E-DIM", dim.items[0].name.span, "a list of initial values after `As` needs a single array: `Dim a(3) As Byte = (1, 2, 3)`");
            return;
        }
        if dim.trailing_init.is_some() && (dim.items.len() != 1 || dim.items[0].init.is_some() || dim.items[0].list.is_some()) {
            self.diags.error("E-DIM", dim.items[0].name.span, "an initial value after `As` needs a single variable");
            return;
        }
        for it in &dim.items {
            let mut vty = base.clone();
            if let Some(sz) = &it.size {
                let Some(n) = self.const_int(sz) else { continue };
                if !(1..=65535).contains(&n) {
                    self.diags.error("E-CONST-RANGE", sz.span, "array size must be 1 to 65535");
                    continue;
                }
                if matches!(vty, Ty::EventVar(_)) {
                    self.diags.error("E-DIM", it.name.span, "arrays of events are not supported");
                    continue;
                }
                vty = Ty::Array(Box::new(vty), n as u32);
            }
            let init = it.init.as_ref().or(dim.trailing_init.as_ref());
            let list = it.list.as_ref().or(dim.trailing_list.as_ref());
            if let Some(items) = list {
                match &vty {
                    Ty::Array(elem, n) => self.array_init(&it.name, elem, *n, items),
                    _ => self.diags.error("E-DIM", it.name.span, "a list of initial values is for an array"),
                }
            } else if let Some(e) = init {
                if let Ty::Array(elem, n) = &vty {
                    // A one-element array may be initialised with a plain value.
                    if *n == 1 {
                        self.array_init(&it.name, elem, 1, std::slice::from_ref(e));
                    } else {
                        self.diags.error("E-DIM", e.span, format!("an array is initialised with a list: `Dim {}({n}) As {elem} = (…)`", it.name.name));
                    }
                } else if matches!(vty, Ty::Struct(_) | Ty::EventVar(_)) {
                    self.diags.error("E-DIM", e.span, format!("a {vty} cannot have an initial value here"));
                } else if let Some(ei) = self.check_expr(e) {
                    if ei.val.is_none() {
                        self.diags.error("E-CONST-EXPR", e.span, "an initial value must be known at compile time");
                    } else {
                        self.assign_ok(&vty, &ei, e.span, "initial value");
                    }
                }
            }
            let bytes = self.size_of(&vty);
            let is_global = self.scopes.is_empty();
            let bit_array = match &vty {
                Ty::Array(e, n) if matches!(**e, Ty::Bit | Ty::Bool) => Some(*n),
                _ => None,
            };
            let initialised = list.is_some() || init.is_some();
            if let Some(id) = self.declare(&it.name, vis, SymKind::Var { ty: vty }) {
                if bit_array.is_some() && initialised {
                    self.a.unpackable.insert(id);
                }
                if is_global {
                    self.a.global_ram += bytes;
                    if let Some(n) = bit_array {
                        self.a.global_bit_arrays.push((id, n));
                    }
                }
            }
        }
    }

    /// Checks the values of an array initialiser: as many as the array has elements, each known
    /// at compile time and assignable to the element type.
    fn array_init(&mut self, name: &Ident, elem: &Ty, n: u32, items: &'p [Expr]) {
        if !matches!(elem, Ty::Int(..) | Ty::Char | Ty::Bool | Ty::Bit) {
            self.diags.error("E-DIM", name.span, format!("an array of {elem} cannot have initial values"));
            return;
        }
        if items.len() != n as usize {
            self.diags.error("E-DIM-ARRAY", name.span, format!("`{}` declares {n} elements but the list has {}", name.name, items.len()));
            return;
        }
        for e in items {
            let Some(ei) = self.check_expr(e) else { continue };
            if ei.val.is_none() {
                self.diags.error("E-CONST-EXPR", e.span, "an initial value must be known at compile time");
            } else {
                self.assign_ok(elem, &ei, e.span, "initial value");
            }
        }
    }

    fn alias_decl(&mut self, dim: &'p DimDecl, d: &'p Designator, vis: Vis) {
        let it = &dim.items[0];
        if dim.items.len() != 1 || it.size.is_some() || it.init.is_some() || it.list.is_some() || dim.trailing_init.is_some() || dim.trailing_list.is_some() {
            self.diags.error("E-ALIAS", it.name.span, "an alias names one existing object and has no size or initial value");
            return;
        }
        let Some(ei) = self.eval_designator(d, true).map(|(e, _)| e) else { return };
        if ei.place != Place::Var {
            self.diags.error("E-ALIAS", d.span, "an alias must refer to a variable, a register or a part of one");
            return;
        }
        self.declare(&it.name, vis, SymKind::Alias { ty: ei.ty });
    }

    fn symbol_decl(&mut self, name: &Ident, e: &'p Expr, vis: Vis) {
        if let ExprKind::Designator(d) = &e.kind
            && let Some((ei, _)) = self.eval_designator(d, true)
        {
            if ei.place == Place::Var {
                self.declare(name, vis, SymKind::Alias { ty: ei.ty });
                return;
            }
            if let Some(v) = ei.val.clone() {
                self.declare(name, vis, SymKind::Const { ty: ei.ty, val: v, typed: false });
                return;
            }
            self.diags.error("E-SYMBOL", e.span, "Symbol needs a constant or an existing variable or register");
            return;
        }
        if matches!(e.kind, ExprKind::Designator(_)) {
            return;
        }
        let Some(ei) = self.check_expr(e) else { return };
        match ei.val.clone() {
            Some(v) => {
                self.declare(name, vis, SymKind::Const { ty: ei.ty, val: v, typed: false });
            }
            None => {
                self.diags.error("E-SYMBOL", e.span, "Symbol needs a constant or an existing variable or register");
            }
        }
    }

    fn struct_decl(&mut self, sd: &'p StructDecl, vis: Vis) {
        // Fields are visible to later alias fields through a temporary scope.
        self.scopes.push(HashMap::new());
        let mut fields: Vec<FieldInfo> = Vec::new();
        let mut size = 0u32;
        for f in &sd.fields {
            let key = f.name.key();
            if fields.iter().any(|x| x.name.eq_ignore_ascii_case(&key)) {
                self.diags.error("E-REDECL", f.name.span, format!("field `{}` is declared twice", f.name.name));
                continue;
            }
            let (ty, alias) = match &f.as_clause {
                AsClause::Type(t) => match self.resolve_type(t) {
                    Some(t) => (t, false),
                    None => continue,
                },
                AsClause::Designator(d) => match self.designator_as_type(d) {
                    None => continue,
                    Some(Some(t)) => (t, false),
                    Some(None) => {
                        if f.size.is_some() {
                            self.diags.error("E-ALIAS", f.name.span, "an alias field has no size");
                            continue;
                        }
                        match self.eval_designator(d, true) {
                            Some((ei, _)) if ei.place == Place::Var => (ei.ty, true),
                            Some(_) => {
                                self.diags.error("E-ALIAS", d.span, "an alias field must refer to another field of the structure");
                                continue;
                            }
                            None => continue,
                        }
                    }
                },
            };
            let mut ty = ty;
            if let Some(sz) = &f.size {
                let Some(n) = self.const_int(sz) else { continue };
                if !(1..=65535).contains(&n) {
                    self.diags.error("E-CONST-RANGE", sz.span, "array size must be 1 to 65535");
                    continue;
                }
                ty = Ty::Array(Box::new(ty), n as u32);
            }
            if !alias {
                size += self.size_of(&ty);
            }
            let sid = self.add_symbol(&f.name.name, f.name.span, Vis::Private, SymKind::Var { ty: ty.clone() });
            self.scopes.last_mut().unwrap().insert(key, sid);
            fields.push(FieldInfo { name: f.name.name.clone(), ty, alias });
        }
        self.scopes.pop();
        if fields.is_empty() && sd.fields.is_empty() {
            self.diags.error("E-STRUCT", sd.name.span, format!("structure `{}` has no fields", sd.name.name));
        }
        self.declare(&sd.name, vis, SymKind::Struct { fields, size });
    }

    fn routine_decl(&mut self, r: &'p Routine, vis: Vis, _span: Span) {
        let mut params = Vec::new();
        let mut seen_default = false;
        let mut ok = true;
        for p in &r.params {
            let Some(base) = self.resolve_type(&p.ty) else {
                ok = false;
                continue;
            };
            let aggregate = matches!(base, Ty::Struct(_) | Ty::Str(_));
            let mode = if (p.is_array || aggregate) && !p.mode_explicit { ParamMode::ByRef } else { p.mode };
            if (p.is_array || aggregate) && mode == ParamMode::ByVal {
                self.diags.error("E-PARAM", p.name.span, format!("`{}`: arrays, strings and structures are passed ByRef or ByRefConst", p.name.name));
                ok = false;
            }
            if mode == ParamMode::ByRefConst && !(p.is_array || matches!(base, Ty::Str(_))) {
                self.diags.error("E-PARAM", p.name.span, format!("`{}`: ByRefConst is for constant arrays and strings", p.name.name));
                ok = false;
            }
            if let Some(def) = &p.default {
                seen_default = true;
                if mode != ParamMode::ByVal {
                    self.diags.error("E-PARAM", p.name.span, "only ByVal parameters can have a default value");
                    ok = false;
                } else if let Some(ei) = self.check_expr(def) {
                    if ei.val.is_none() {
                        self.diags.error("E-CONST-EXPR", def.span, "a default value must be known at compile time");
                    } else {
                        self.assign_ok(&base, &ei, def.span, "default value");
                    }
                }
            } else if seen_default {
                self.diags.error("E-PARAM", p.name.span, "parameters after one with a default value must have defaults too");
                ok = false;
            }
            let ty = if p.is_array { Ty::Array(Box::new(base), 0) } else { base };
            params.push(ParamInfo { name: p.name.name.clone(), ty, mode, is_array: p.is_array, has_default: p.default.is_some() });
        }
        let ret = match &r.ret {
            Some(t) => match self.resolve_type(t) {
                Some(t) => Some(t),
                None => {
                    ok = false;
                    None
                }
            },
            None => None,
        };
        if !ok {
            return;
        }
        let kind = SymKind::Routine { params: params.clone(), ret: ret.clone(), reentrant: r.reentrant, inlining: r.inlining };
        let Some(id) = self.declare(&r.name, vis, kind) else { return };
        if r.reentrant {
            self.reentrant_ok.insert(id);
        }
        self.body(&r.body, if r.is_function { Kind::Function } else { Kind::Sub }, Some(id), ret, Some(r.name.key()), &params_with_ast(&r.params, &params));
    }

    fn interrupt_decl(&mut self, i: &'p InterruptDecl, vis: Vis) {
        let prio = match &i.priority {
            None => None,
            Some(e) => match self.const_int(e) {
                Some(v @ (1 | 2)) => Some(v as i64),
                Some(_) => {
                    self.diags.error("E-ISR-PRIO", e.span, "priority must be ipLow (1) or ipHigh (2)");
                    return;
                }
                None => return,
            },
        };
        for &o in &self.interrupts.clone() {
            if let SymKind::Interrupt { priority } = &self.a.symbols[o].kind
                && priority.is_some() != prio.is_some()
            {
                self.diags.error("E-ISR-PRIO", i.name.span, "when there are several interrupt handlers, every one needs a priority");
                return;
            }
        }
        let Some(id) = self.declare(&i.name, vis, SymKind::Interrupt { priority: prio }) else { return };
        self.interrupts.push(id);
        self.body(&i.body, Kind::Interrupt, Some(id), None, None, &[]);
    }

    /// Checks a routine body in its own scope. `params` supplies the AST parameter for each
    /// `ParamInfo` so that names and spans are reported correctly.
    fn body(&mut self, b: &'p Body, kind: Kind, routine: Option<SymId>, ret: Option<Ty>, fn_key: Option<String>, params: &[(Ident, ParamInfo)]) {
        let saved_ctx = std::mem::replace(
            &mut self.ctx,
            Ctx { routine, kind, ret: ret.clone(), fn_key, loops: 0, saves: 0, labels: HashSet::new(), result_assigned: false },
        );
        let saved_for = std::mem::take(&mut self.for_vars);
        self.scopes.push(HashMap::new());
        for (id, p) in params {
            self.declare(id, Vis::Private, SymKind::Param { ty: p.ty.clone(), mode: p.mode });
        }
        for d in &b.decls {
            self.decl(d);
        }
        self.check_labels(&b.stmts);
        for s in &b.stmts {
            self.stmt(s);
        }
        if kind == Kind::Function && !self.ctx.result_assigned
            && let Some(r) = routine
        {
            let sp = self.a.symbols[r].span;
            let nm = self.a.symbols[r].name.clone();
            self.diags.warn("W-NORESULT", sp, format!("function `{nm}` never assigns its result"));
        }
        self.scopes.pop();
        self.ctx = saved_ctx;
        self.for_vars = saved_for;
    }

    fn check_labels(&mut self, stmts: &'p [Stmt]) {
        let mut seen: HashMap<String, Span> = HashMap::new();
        fn walk(ss: &[Stmt], out: &mut Vec<(String, Span)>) {
            for s in ss {
                match &s.kind {
                    StmtKind::Label(l) => out.push((l.key(), l.span)),
                    StmtKind::If { arms, otherwise } => {
                        for (_, b) in arms {
                            walk(b, out);
                        }
                        if let Some(b) = otherwise {
                            walk(b, out);
                        }
                    }
                    StmtKind::Select { cases, otherwise, .. } => {
                        for c in cases {
                            walk(&c.body, out);
                        }
                        if let Some(b) = otherwise {
                            walk(b, out);
                        }
                    }
                    StmtKind::While { body, .. } | StmtKind::Repeat { body, .. } | StmtKind::For { body, .. } | StmtKind::Save { body, .. } => walk(body, out),
                    _ => {}
                }
            }
        }
        let mut all = Vec::new();
        walk(stmts, &mut all);
        for (k, sp) in all {
            if let Some(prev) = seen.insert(k.clone(), sp) {
                self.diags.error("E-LABEL", sp, format!("label `{k}` is already defined on line {}", prev.line));
            }
            self.ctx.labels.insert(k);
        }
    }

    // ---- statements ----------------------------------------------------------------------

    fn block(&mut self, ss: &'p [Stmt]) {
        for s in ss {
            self.stmt(s);
        }
    }

    fn check_cond(&mut self, e: &'p Expr) {
        if let Some(ei) = self.check_expr(e)
            && ei.ty != Ty::Bool
        {
            self.diags.error("E-COND", e.span, format!("a condition must be Boolean, found {}", ei.ty));
        }
    }

    fn stmt(&mut self, s: &'p Stmt) {
        match &s.kind {
            StmtKind::Assign { target, value } => self.assign(target, value, s.span),
            StmtKind::Call(d) => {
                let Some((ei, _)) = self.eval_designator(d, false) else { return };
                if !ei.call {
                    self.diags.error("E-STMT", d.span, "this is not a statement; a call is needed here (use `name(args)`)");
                }
            }
            StmtKind::If { arms, otherwise } => {
                for (c, b) in arms {
                    self.check_cond(c);
                    self.block(b);
                }
                if let Some(b) = otherwise {
                    self.block(b);
                }
            }
            StmtKind::IfGoto { cond, label } => {
                self.check_cond(cond);
                self.check_goto(label);
            }
            StmtKind::Select { subject, cases, otherwise } => self.select(subject, cases, otherwise.as_deref(), s.span),
            StmtKind::While { cond, body } => {
                self.check_cond(cond);
                self.ctx.loops += 1;
                self.block(body);
                self.ctx.loops -= 1;
            }
            StmtKind::Repeat { body, until } => {
                self.ctx.loops += 1;
                self.block(body);
                self.ctx.loops -= 1;
                self.check_cond(until);
            }
            StmtKind::For { var, from, to, step, body } => self.for_stmt(var, from, to, step.as_ref(), body),
            StmtKind::Break => {
                if self.ctx.loops == 0 {
                    self.diags.error("E-LOOP", s.span, "`Break` is only valid inside a loop");
                }
            }
            StmtKind::Continue => {
                if self.ctx.loops == 0 {
                    self.diags.error("E-LOOP", s.span, "`Continue` is only valid inside a loop");
                }
            }
            StmtKind::Exit => {
                if self.ctx.kind == Kind::Main {
                    self.diags.error("E-EXIT", s.span, "`Exit` is only valid inside a Sub, Function, Interrupt or Event");
                }
            }
            StmtKind::GoTo(l) => self.check_goto(l),
            StmtKind::Label(_) => {}
            StmtKind::Save { items, body } => {
                for it in items {
                    match it {
                        SaveItem::Int(v, sp) => {
                            if *v != 0 {
                                self.diags.error("E-SAVE", *sp, "the only number allowed in Save is 0 (the compiler's working registers)");
                            }
                        }
                        SaveItem::Designator(d) => {
                            if let Some((ei, is_routine)) = self.eval_designator(d, true)
                                && ei.place != Place::Var
                                && !is_routine
                            {
                                self.diags.error("E-SAVE", d.span, "Save takes variables, routines or 0");
                            }
                        }
                    }
                }
                self.ctx.saves += 1;
                self.block(body);
                self.ctx.saves -= 1;
            }
            StmtKind::Asm { preserves, .. } => {
                for p in preserves {
                    let k = p.key();
                    let known = k == "w" || self.a.device.as_ref().is_some_and(|d| d.find_sfr(&k).is_some());
                    if !known {
                        self.diags.error("E-ASM", p.span, format!("`{}` is not a register that Asm can preserve", p.name));
                    }
                }
            }
            StmtKind::Enable(n) => self.enable(n, true),
            StmtKind::Disable(n) => self.enable(n, false),
        }
    }

    fn check_goto(&mut self, l: &Ident) {
        if !self.ctx.labels.contains(&l.key()) {
            self.diags.error("E-LABEL", l.span, format!("no label `{}` in this routine", l.name));
        }
    }

    fn enable(&mut self, n: &Ident, enabling: bool) {
        let Some(found) = self.lookup(&n.key(), n.span) else { return };
        let Some(id) = found else {
            self.diags.error("E-UNDECLARED", n.span, format!("`{}` is not declared", n.name));
            return;
        };
        let SymKind::Interrupt { priority } = self.a.symbols[id].kind.clone() else {
            self.diags.error("E-ENABLE", n.span, format!("`{}` is not an Interrupt", n.name));
            return;
        };
        self.a.enables.insert(n.span, id);
        if !enabling {
            if self.enabled.get(&priority) == Some(&id) {
                self.enabled.remove(&priority);
            }
        } else {
            match self.enabled.get(&priority) {
                Some(&other) if other != id => {
                    let on = self.a.symbols[other].name.clone();
                    self.diags.error("E-ISR-PRIO", n.span, format!("`{on}` is already enabled at this priority"));
                }
                _ => {
                    self.enabled.insert(priority, id);
                }
            }
        }
    }

    fn assign(&mut self, target: &'p Designator, value: &'p Expr, span: Span) {
        // `FunctionName = value` inside the function assigns its result.
        if target.head.key() == "result" && self.ctx.ret.is_some() {
            // `Result = x`, `Result.Byte0 = x` and `Result(i) = x` all assign the result.
            self.ctx.result_assigned = true;
        }
        let fn_target = target.parts.is_empty() && self.ctx.kind == Kind::Function && self.ctx.fn_key.as_deref() == Some(&target.head.key());
        let tgt = if fn_target || (target.parts.is_empty() && target.head.key() == "result") {
            match self.ctx.ret.clone() {
                Some(t) => {
                    self.ctx.result_assigned = true;
                    EI::place(t, Place::Var)
                }
                None => {
                    self.diags.error("E-RESULT", target.span, "`Result` is only available inside a Function");
                    return;
                }
            }
        } else {
            let Some((ei, _)) = self.eval_designator(target, false) else {
                // Still check the right-hand side for its own errors.
                self.check_expr(value);
                return;
            };
            ei
        };
        let val = self.check_expr(value);
        match tgt.place {
            Place::Var => {}
            Place::ReadOnly => {
                self.diags.error("E-READONLY", target.span, format!("`{}` is read-only", target.head.name));
                return;
            }
            Place::None => {
                self.diags.error("E-ASSIGN", target.span, "the left side of `=` must be a variable, register or bit");
                return;
            }
        }
        self.note_modified(target);
        if let Some(v) = val
            && self.assign_ok(&tgt.ty, &v, value.span, "assignment")
        {
            self.annotate_assignment(&tgt.ty, &v, value);
        }
        let _ = span;
    }

    fn note_modified(&mut self, d: &Designator) {
        if let Some(Res::Sym(s)) = self.a.resolved.get(&d.id)
            && self.for_vars.contains(s)
        {
            let n = self.a.symbols[*s].name.clone();
            self.diags.error("E-LOOPVAR", d.span, format!("`{n}` is a For loop variable and cannot be changed inside the loop"));
        }
    }

    fn for_stmt(&mut self, var: &'p Designator, from: &'p Expr, to: &'p Expr, step: Option<&'p Expr>, body: &'p [Stmt]) {
        let vt = self.eval_designator(var, false).map(|(e, _)| e);
        let mut sym = None;
        if let Some(v) = &vt {
            if !v.ty.is_int() || v.place != Place::Var {
                self.diags.error("E-FOR", var.span, format!("the For variable must be an integer variable, found {}", if v.place == Place::Var { v.ty.to_string() } else { "a read-only value".into() }));
            } else if let Some(Res::Sym(s)) = self.a.resolved.get(&var.id)
                && var.parts.is_empty()
            {
                sym = Some(*s);
            }
            if self.for_vars.iter().any(|s| Some(*s) == sym) {
                self.diags.error("E-LOOPVAR", var.span, "this variable is already the counter of an enclosing For loop");
            }
            if let Some(Res::Sym(s)) = self.a.resolved.get(&var.id)
                && self.for_vars.contains(s)
                && sym.is_none()
            {
                self.diags.error("E-LOOPVAR", var.span, "a For loop variable cannot be reused inside its own loop");
            }
        }
        for e in [from, to] {
            if let Some(ei) = self.check_expr(e)
                && let Some(v) = &vt
                && v.ty.is_int()
                && self.assign_ok(&v.ty, &ei, e.span, "For bound")
            {
                self.annotate_assignment(&v.ty, &ei, e);
            }
        }
        if let Some(st) = step
            && let Some(ei) = self.check_expr(st)
        {
            match (&ei.val, &vt) {
                (Some(CVal::Int(0)), _) => {
                    self.diags.error("E-FOR", st.span, "Step cannot be zero");
                }
                (Some(CVal::Int(c)), Some(v)) if v.ty.is_int() => {
                    let (_, hi) = v.ty.int_range().unwrap();
                    if c.abs() > hi {
                        self.diags.error("E-CONST-RANGE", st.span, format!("Step {c} is larger than the range of {}", v.ty));
                    }
                }
                (None, Some(v)) if v.ty.is_int() => {
                    self.assign_ok(&v.ty, &ei, st.span, "Step");
                }
                (_, Some(v)) if v.ty.is_int() && !ei.ty.is_numeric_int() => {
                    self.diags.error("E-TYPE", st.span, format!("Step must be an integer, found {}", ei.ty));
                }
                _ => {}
            }
        }
        if let Some(s) = sym {
            self.for_vars.push(s);
        }
        self.ctx.loops += 1;
        self.block(body);
        self.ctx.loops -= 1;
        if sym.is_some() {
            self.for_vars.pop();
        }
    }

    fn select(&mut self, subject: &'p Expr, cases: &'p [Case], otherwise: Option<&'p [Stmt]>, span: Span) {
        let sub = self.check_expr(subject);
        let sty = sub.as_ref().map(|s| s.ty.clone());
        let range = match &sty {
            Some(Ty::Char) => Some((0i128, 255i128)),
            Some(t) if t.is_int() => t.int_range(),
            Some(t) => {
                self.diags.error("E-TYPE", subject.span, format!("Select needs an integer or Char, found {t}"));
                None
            }
            None => None,
        };
        let mut seen: Vec<(i128, i128)> = Vec::new();
        let mut ok = range.is_some();
        for c in cases {
            for cond in &c.conds {
                let mut ivs: Vec<(i128, i128, Span)> = Vec::new();
                let (min, max) = range.unwrap_or((0, 0));
                let value_of = |this: &mut Self, e: &'p Expr| -> Option<i128> {
                    let ei = this.check_expr(e)?;
                    let t = sty.clone()?;
                    let Some(v) = ei.val.clone() else {
                        this.diags.error("E-CONST-EXPR", e.span, "Case values must be known at compile time");
                        return None;
                    };
                    if !this.assign_ok(&t, &ei, e.span, "Case value") {
                        return None;
                    }
                    match v {
                        CVal::Int(i) => Some(i),
                        CVal::Str(s) => Some(s.bytes().next().map(|b| b as i128).unwrap_or(0)),
                        _ => None,
                    }
                };
                match cond {
                    CaseCond::Value(e) => {
                        if let Some(v) = value_of(self, e) {
                            ivs.push((v, v, e.span));
                        } else {
                            ok = false;
                        }
                    }
                    CaseCond::Range(a, b) => {
                        let (x, y) = (value_of(self, a), value_of(self, b));
                        match (x, y) {
                            (Some(x), Some(y)) if x <= y => ivs.push((x, y, a.span)),
                            (Some(_), Some(_)) => {
                                self.diags.error("E-CASE-RANGE", a.span, "the range is empty: the first value is larger than the second");
                                ok = false;
                            }
                            _ => ok = false,
                        }
                    }
                    CaseCond::Rel(op, e) => match value_of(self, e) {
                        Some(v) => match op {
                            BinOp::Eq => ivs.push((v, v, e.span)),
                            BinOp::Ne => {
                                ivs.push((min, v - 1, e.span));
                                ivs.push((v + 1, max, e.span));
                            }
                            BinOp::Lt => ivs.push((min, v - 1, e.span)),
                            BinOp::Le => ivs.push((min, v, e.span)),
                            BinOp::Gt => ivs.push((v + 1, max, e.span)),
                            _ => ivs.push((v, max, e.span)),
                        },
                        None => ok = false,
                    },
                }
                for (lo, hi, sp) in ivs {
                    if lo > hi {
                        continue;
                    }
                    if seen.iter().any(|(a, b)| lo <= *b && *a <= hi) {
                        self.diags.error("E-CASE-OVERLAP", sp, "this Case overlaps an earlier one, so part of it can never run");
                        ok = false;
                    }
                    seen.push((lo, hi));
                }
            }
            self.block(&c.body);
        }
        if let Some(b) = otherwise {
            if ok && let Some((min, max)) = range {
                let mut iv = seen.clone();
                iv.sort();
                let mut next = min;
                for (lo, hi) in iv {
                    if lo > next {
                        break;
                    }
                    next = next.max(hi + 1);
                }
                if next > max {
                    self.diags.warn("W-CASE-ELSE", span, "the Cases cover every value, so `Else` can never run");
                }
            }
            self.block(b);
        }
    }

    // ---- types: compatibility ------------------------------------------------------------

    fn narrowing(&mut self, span: Span, msg: String) {
        if self.a.options.strict {
            self.diags.error("E-NARROW", span, format!("{msg} (error under #option Strict)"));
        } else {
            self.diags.warn("W-NARROW", span, msg);
        }
    }

    /// Checks that `v` can be stored in `target`. Reports the problem and returns false if not.
    fn assign_ok(&mut self, target: &Ty, v: &EI, span: Span, what: &str) -> bool {
        let vt = &v.ty;
        match (target, vt) {
            (Ty::Int(..), Ty::Int(..) | Ty::Bit) | (Ty::Bit, Ty::Int(..) | Ty::Bit) => {
                let (lo, hi) = target.int_range().unwrap();
                if let Some(CVal::Int(c)) = &v.val {
                    if *c < lo || *c > hi {
                        self.diags.error("E-CONST-RANGE", span, format!("{what}: {c} does not fit {target} ({lo} to {hi})"));
                        return false;
                    }
                    return true;
                }
                let (vlo, vhi) = vt.int_range().unwrap();
                if vlo < lo || vhi > hi {
                    self.narrowing(span, format!("{what}: {vt} may not fit in {target}; the value can be truncated"));
                }
                true
            }
            (Ty::Float, Ty::Int(..) | Ty::Bit | Ty::Float) => true,
            (Ty::Int(..) | Ty::Bit, Ty::Float) => {
                self.diags.error("E-TYPE", span, format!("{what}: a Float cannot be stored in {target} without an explicit conversion, e.g. {}(x)", target));
                false
            }
            (Ty::Bool, Ty::Bool) => true,
            (Ty::Char, Ty::Char) => true,
            (Ty::Char, Ty::Str(_)) if v.lit => match &v.val {
                Some(CVal::Str(s)) if s.len() <= 1 => true,
                _ => {
                    self.diags.error("E-CONST-RANGE", span, format!("{what}: a Char holds one character"));
                    false
                }
            },
            (Ty::Str(n), Ty::Str(m)) => {
                if m > n {
                    if v.lit {
                        self.diags.error("E-CONST-RANGE", span, format!("{what}: the text is {m} characters but the String holds {n}"));
                        return false;
                    }
                    self.narrowing(span, format!("{what}: String({m}) may not fit in String({n}); the text can be cut off"));
                }
                true
            }
            (Ty::Str(_), Ty::Char) => true,
            (Ty::Struct(a), Ty::Struct(b)) if a == b => true,
            (Ty::EventVar(_), Ty::EventAny) => true,
            (Ty::EventVar(a), Ty::EventVar(b)) if a == b => true,
            (Ty::Array(a, n), Ty::Array(b, m)) if a == b && n == m => true,
            _ => {
                let hint = match (target, vt) {
                    (Ty::Bool, Ty::Bit | Ty::Int(..)) => " (use a comparison, or Boolean(x))",
                    (Ty::Bit | Ty::Int(..), Ty::Bool) => " (use Bit(x))",
                    (Ty::Int(..), Ty::Char) => " (use Byte(c))",
                    (Ty::Char, Ty::Int(..)) => " (write a character code as #65)",
                    _ => "",
                };
                self.diags.error("E-TYPE", span, format!("{what}: cannot use {vt} where {target} is expected{hint}"));
                false
            }
        }
    }

    /// Records the D16 evaluation width for an expression stored into `target`.
    fn annotate_assignment(&mut self, target: &Ty, v: &EI, e: &'p Expr) {
        if v.val.is_some() {
            return;
        }
        if let (Some(tw), Some(vw)) = (target.width(), v.ty.width())
            && target.is_numeric_int()
            && v.ty.is_numeric_int()
        {
            self.set_width(e, tw.max(vw));
        }
    }

    /// Pushes an evaluation width down through arithmetic and bitwise nodes. Comparisons and
    /// calls start their own widths.
    fn set_width(&mut self, e: &Expr, w: u8) {
        match &e.kind {
            ExprKind::Binary(op, l, r) if !op.is_relational() => {
                self.a.widths.insert(e.id, w);
                self.set_width(l, w);
                if !matches!(op, BinOp::Shl | BinOp::Shr) {
                    self.set_width(r, w);
                }
            }
            ExprKind::Unary(UnOp::Neg | UnOp::Not | UnOp::Plus, x) => {
                if self.a.types.get(&e.id).is_some_and(|t| t.is_numeric_int()) {
                    self.a.widths.insert(e.id, w);
                    self.set_width(x, w);
                }
            }
            _ => {
                if self.a.types.get(&e.id).is_some_and(|t| t.is_numeric_int()) {
                    self.a.widths.insert(e.id, w);
                }
            }
        }
    }

    /// The common type of two numeric operands (LANGUAGE.md §5.3 rule 2).
    fn common(&mut self, a: &EI, b: &EI, span: Span) -> Option<Ty> {
        if !a.ty.is_numeric() || !b.ty.is_numeric() {
            return None;
        }
        if a.ty == Ty::Float || b.ty == Ty::Float {
            return Some(Ty::Float);
        }
        let norm = |t: &Ty| if *t == Ty::Bit { BYTE } else { t.clone() };
        let (ta, tb) = (norm(&a.ty), norm(&b.ty));
        let (Ty::Int(wa, sa), Ty::Int(wb, sb)) = (&ta, &tb) else { return None };
        if sa == sb {
            return Some(Ty::Int(*wa.max(wb), *sa));
        }
        // One signed, one unsigned.
        let ((sw, _), (uw, uei)) = if *sa { ((*wa, a), (*wb, b)) } else { ((*wb, b), (*wa, a)) };
        if let (true, Some(CVal::Int(c))) = (uei.lit, &uei.val) {
            // A literal adapts: it only needs to fit the signed type it meets.
            let need = signed_width_for(*c).unwrap_or(64);
            return Some(Ty::Int(sw.max(need), true));
        }
        if uw < sw {
            return Some(Ty::Int(sw, true));
        }
        self.diags.error("E-SIGN", span, format!("cannot mix {} and {} in one operation; convert one explicitly (e.g. {}(x))", a.ty, b.ty, if *sa { b.ty.clone() } else { a.ty.clone() }));
        None
    }

    // ---- expressions ---------------------------------------------------------------------

    /// Evaluates a constant expression and reports `E-CONST-EXPR` if it is not constant.
    fn const_value(&mut self, e: &'p Expr) -> Option<CVal> {
        let ei = self.check_expr(e)?;
        match ei.val {
            Some(v) => Some(v),
            None => self.err("E-CONST-EXPR", e.span, "this must be a constant expression"),
        }
    }

    fn const_int(&mut self, e: &'p Expr) -> Option<i128> {
        match self.const_value(e)? {
            CVal::Int(i) => Some(i),
            _ => self.err("E-TYPE", e.span, "this must be a whole number"),
        }
    }

    fn record(&mut self, e: &Expr, ei: &EI) {
        self.a.types.insert(e.id, ei.ty.clone());
        if let Some(v) = &ei.val {
            self.a.consts.insert(e.id, v.clone());
        }
    }

    /// Type-checks an expression, reporting errors. `None` means an error was already reported.
    fn check_expr(&mut self, e: &'p Expr) -> Option<EI> {
        let ei = self.check_expr_inner(e)?;
        if ei.ty == Ty::Void {
            return self.err("E-CALL", e.span, "a subroutine has no value and cannot be used in an expression");
        }
        self.record(e, &ei);
        Some(ei)
    }

    fn check_expr_inner(&mut self, e: &'p Expr) -> Option<EI> {
        match &e.kind {
            ExprKind::Int(v) => {
                if *v > u32::MAX as u64 {
                    return self.err("E-CONST-RANGE", e.span, format!("{v} is larger than the biggest integer type (LongWord, 4294967295)"));
                }
                Some(EI::int_lit(*v as i128))
            }
            ExprKind::Float(v) => Some(EI::lit(Ty::Float, CVal::Float(*v))),
            ExprKind::Str(s) => {
                if s.len() > 255 {
                    return self.err("E-CONST-RANGE", e.span, "a string literal is at most 255 characters");
                }
                Some(EI::lit(Ty::Str(s.len() as u32), CVal::Str(s.clone())))
            }
            ExprKind::Char(c) => Some(EI::lit(Ty::Char, CVal::Int(*c as i128))),
            ExprKind::Bool(b) => Some(EI::lit(Ty::Bool, CVal::Bool(*b))),
            ExprKind::Null => Some(EI::lit(Ty::Str(0), CVal::Str(String::new()))),
            ExprKind::Designator(d) => self.eval_designator(d, false).map(|(e, _)| e),
            ExprKind::Unary(op, x) => self.check_unary(*op, x, e),
            ExprKind::Binary(op, l, r) => self.check_binary(*op, l, r, e),
        }
    }

    fn check_unary(&mut self, op: UnOp, x: &'p Expr, e: &'p Expr) -> Option<EI> {
        if op == UnOp::AddressOf {
            let ExprKind::Designator(d) = &x.kind else {
                return self.err("E-ADDR", x.span, "`@` needs a variable, array or routine");
            };
            let (ei, is_routine) = self.eval_designator(d, true)?;
            return self.address_of(&ei, is_routine, x.span);
        }
        let v = self.check_expr(x)?;
        match op {
            UnOp::Plus => {
                if !v.ty.is_numeric() {
                    return self.err("E-TYPE", e.span, format!("unary + needs a number, found {}", v.ty));
                }
                Some(EI { place: Place::None, call: false, ..v })
            }
            UnOp::Neg => match (&v.ty, &v.val) {
                (_, Some(CVal::Int(c))) if v.ty.is_numeric_int() => {
                    let r = -*c;
                    if v.lit {
                        Some(EI::int_lit(r))
                    } else {
                        match signed_of(&v.ty) {
                            Some(t) => Some(EI { val: Some(CVal::Int(r)), ..EI::new(t) }),
                            None => self.err("E-TYPE", e.span, format!("cannot negate a {}; convert it to LongInt first", v.ty)),
                        }
                    }
                }
                (Ty::Float, Some(CVal::Float(f))) => Some(EI { val: Some(CVal::Float(-f)), lit: v.lit, ..EI::new(Ty::Float) }),
                (Ty::Float, None) => Some(EI::new(Ty::Float)),
                (t, None) if t.is_numeric_int() => match signed_of(t) {
                    Some(s) => Some(EI::new(s)),
                    None => self.err("E-TYPE", e.span, format!("cannot negate a {t}; convert it to LongInt first")),
                },
                (t, _) => self.err("E-TYPE", e.span, format!("unary - needs a number, found {t}")),
            },
            UnOp::Not => match (&v.ty, &v.val) {
                (Ty::Bool, Some(CVal::Bool(b))) => Some(EI::lit(Ty::Bool, CVal::Bool(!b))).map(|r| EI { lit: v.lit, ..r }),
                (Ty::Bool, None) => Some(EI::new(Ty::Bool)),
                (Ty::Bit, Some(CVal::Int(c))) => Some(EI { val: Some(CVal::Int(1 - c)), ..EI::new(Ty::Bit) }),
                (Ty::Bit, None) => Some(EI::new(Ty::Bit)),
                (Ty::Int(w, s), val) => {
                    let width_ty = Ty::Int(*w, *s);
                    match val {
                        Some(CVal::Int(c)) => {
                            let mask = (1i128 << w) - 1;
                            let r = !c & mask;
                            let r = if *s && r >= 1i128 << (w - 1) { r - (1i128 << w) } else { r };
                            Some(EI { val: Some(CVal::Int(r)), lit: false, ..EI::new(width_ty) })
                        }
                        _ => Some(EI::new(width_ty)),
                    }
                }
                (t, _) => self.err("E-TYPE", e.span, format!("`Not` needs a Boolean or an integer, found {t}")),
            },
            UnOp::AddressOf => unreachable!(),
        }
    }

    fn address_of(&mut self, ei: &EI, is_routine: bool, span: Span) -> Option<EI> {
        if is_routine {
            return Some(EI::new(LONGWORD));
        }
        match ei.place {
            Place::Var => Some(EI::new(WORD)),
            Place::ReadOnly if matches!(ei.ty, Ty::Array(..)) => Some(EI::new(LONGWORD)),
            _ => self.err("E-ADDR", span, "only variables, arrays, constant arrays and routines have an address"),
        }
    }

    fn check_binary(&mut self, op: BinOp, l: &'p Expr, r: &'p Expr, e: &'p Expr) -> Option<EI> {
        let a = self.check_expr(l);
        let b = self.check_expr(r);
        let (a, b) = (a?, b?);
        let span = e.span;
        if op.is_logical_or_bitwise() {
            return self.logical(op, &a, &b, span);
        }
        if op.is_relational() {
            return self.relational(op, &a, &b, l, r, span);
        }
        if matches!(op, BinOp::Shl | BinOp::Shr) {
            if !a.ty.is_numeric_int() {
                return self.err("E-TYPE", span, format!("shifts need an integer on the left, found {}", a.ty));
            }
            let count_ok = match (&b.val, &b.ty) {
                (Some(CVal::Int(c)), _) => *c >= 0,
                (None, Ty::Int(8, false)) => true,
                _ => false,
            };
            if !count_ok {
                return self.err("E-TYPE", r.span, "a shift count must be a non-negative constant or a Byte");
            }
            if let (Some(CVal::Int(x)), Some(CVal::Int(n))) = (&a.val, &b.val) {
                let n = (*n).min(127) as u32;
                let v = if op == BinOp::Shl { x.checked_shl(n).unwrap_or(0) } else { x >> n.min(126) };
                return Some(if a.lit { EI::int_lit(v) } else { EI { val: Some(CVal::Int(v)), ..EI::new(a.ty.clone()) } });
            }
            return Some(EI::new(if a.ty == Ty::Bit { BYTE } else { a.ty.clone() }));
        }
        // + - * / Mod
        if op == BinOp::Add && matches!(a.ty, Ty::Str(_) | Ty::Char) && matches!(b.ty, Ty::Str(_) | Ty::Char) {
            let len = |t: &Ty| match t {
                Ty::Str(n) => *n,
                _ => 1,
            };
            let n = (len(&a.ty) + len(&b.ty)).min(255);
            let txt = |x: &EI| match &x.val {
                Some(CVal::Str(s)) => Some(s.clone()),
                Some(CVal::Int(c)) if x.ty == Ty::Char => Some((*c as u8 as char).to_string()),
                _ => None,
            };
            return Some(match (txt(&a), txt(&b)) {
                (Some(x), Some(y)) => EI::lit(Ty::Str((x.len() + y.len()) as u32), CVal::Str(x + &y)),
                _ => EI::new(Ty::Str(n)),
            });
        }
        let name = match op {
            BinOp::Add => "+",
            BinOp::Sub => "-",
            BinOp::Mul => "*",
            BinOp::Div => "/",
            _ => "Mod",
        };
        if !a.ty.is_numeric() || !b.ty.is_numeric() {
            let bad = if a.ty.is_numeric() { &b.ty } else { &a.ty };
            return self.err("E-TYPE", span, format!("`{name}` needs numbers, found {bad}"));
        }
        if op == BinOp::Mod && (a.ty == Ty::Float || b.ty == Ty::Float) {
            return self.err("E-TYPE", span, "`Mod` needs integers");
        }
        let ct = self.common(&a, &b, span)?;
        if matches!(op, BinOp::Div | BinOp::Mod) {
            let zero = matches!(&b.val, Some(CVal::Int(0))) || matches!(&b.val, Some(CVal::Float(f)) if *f == 0.0);
            if zero {
                return self.err("E-DIV0", r.span, "division by zero");
            }
        }
        // Fold when both are constants.
        if let (Some(x), Some(y)) = (&a.val, &b.val) {
            let lit = a.lit && b.lit;
            if ct == Ty::Float {
                let (x, y) = (x.as_f64()?, y.as_f64()?);
                let v = match op {
                    BinOp::Add => x + y,
                    BinOp::Sub => x - y,
                    BinOp::Mul => x * y,
                    _ => x / y,
                };
                return Some(EI { val: Some(CVal::Float(v)), lit, ..EI::new(Ty::Float) });
            }
            let (x, y) = (x.as_int()?, y.as_int()?);
            let v = match op {
                BinOp::Add => x.checked_add(y),
                BinOp::Sub => x.checked_sub(y),
                BinOp::Mul => x.checked_mul(y),
                BinOp::Div => x.checked_div(y),
                _ => x.checked_rem(y),
            };
            let Some(v) = v else {
                return self.err("E-CONST-RANGE", span, "constant overflow");
            };
            return Some(if lit { EI::int_lit(v) } else { EI { val: Some(CVal::Int(v)), ..EI::new(ct) } });
        }
        Some(EI::new(ct))
    }

    fn logical(&mut self, op: BinOp, a: &EI, b: &EI, span: Span) -> Option<EI> {
        let name = match op {
            BinOp::And => "And",
            BinOp::Or => "Or",
            _ => "Xor",
        };
        match (&a.ty, &b.ty) {
            (Ty::Bool, Ty::Bool) => {
                let val = match (&a.val, &b.val) {
                    (Some(CVal::Bool(x)), Some(CVal::Bool(y))) => Some(CVal::Bool(match op {
                        BinOp::And => *x && *y,
                        BinOp::Or => *x || *y,
                        _ => x ^ y,
                    })),
                    _ => None,
                };
                Some(EI { val, lit: a.lit && b.lit, ..EI::new(Ty::Bool) })
            }
            (Ty::Bool, t) | (t, Ty::Bool) => {
                let _ = t;
                self.err("E-MIX", span, format!("`{name}` cannot mix a Boolean with a number ({} and {}); `{name}` is logical on Booleans and bitwise on integers", a.ty, b.ty))
            }
            (x, y) if x.is_numeric_int() && y.is_numeric_int() => {
                let ct = self.common(a, b, span)?;
                if let (Some(CVal::Int(x)), Some(CVal::Int(y))) = (&a.val, &b.val) {
                    let v = match op {
                        BinOp::And => x & y,
                        BinOp::Or => x | y,
                        _ => x ^ y,
                    };
                    return Some(if a.lit && b.lit { EI::int_lit(v) } else { EI { val: Some(CVal::Int(v)), ..EI::new(ct) } });
                }
                Some(EI::new(ct))
            }
            _ => self.err("E-TYPE", span, format!("`{name}` needs two Booleans or two integers, found {} and {}", a.ty, b.ty)),
        }
    }

    fn relational(&mut self, op: BinOp, a: &EI, b: &EI, l: &'p Expr, r: &'p Expr, span: Span) -> Option<EI> {
        let eq = matches!(op, BinOp::Eq | BinOp::Ne);
        let cmp = |x: f64, y: f64| match op {
            BinOp::Eq => x == y,
            BinOp::Ne => x != y,
            BinOp::Lt => x < y,
            BinOp::Gt => x > y,
            BinOp::Le => x <= y,
            _ => x >= y,
        };
        let one_char = |x: &EI| matches!(&x.val, Some(CVal::Str(s)) if s.len() == 1) && x.lit;
        let result = |v: Option<bool>, lit: bool| EI { val: v.map(CVal::Bool), lit, ..EI::new(Ty::Bool) };
        if a.ty.is_numeric() && b.ty.is_numeric() {
            let ct = self.common(a, b, span)?;
            if let Some(w) = ct.width() {
                self.set_width(l, w);
                self.set_width(r, w);
            }
            let v = match (&a.val, &b.val) {
                (Some(x), Some(y)) => Some(cmp(x.as_f64()?, y.as_f64()?)),
                _ => None,
            };
            // Whole numbers compare exactly (f64 is not exact above 2^53).
            let v = match (&a.val, &b.val) {
                (Some(CVal::Int(x)), Some(CVal::Int(y))) => Some(match op {
                    BinOp::Eq => x == y,
                    BinOp::Ne => x != y,
                    BinOp::Lt => x < y,
                    BinOp::Gt => x > y,
                    BinOp::Le => x <= y,
                    _ => x >= y,
                }),
                _ => v,
            };
            return Some(result(v, a.lit && b.lit));
        }
        match (&a.ty, &b.ty) {
            (Ty::Bool, Ty::Bool) if eq => {
                let v = match (&a.val, &b.val) {
                    (Some(CVal::Bool(x)), Some(CVal::Bool(y))) => Some((x == y) == (op == BinOp::Eq)),
                    _ => None,
                };
                Some(result(v, a.lit && b.lit))
            }
            (Ty::Char, Ty::Char) => {
                let v = match (&a.val, &b.val) {
                    (Some(CVal::Int(x)), Some(CVal::Int(y))) => Some(cmp(*x as f64, *y as f64)),
                    _ => None,
                };
                Some(result(v, a.lit && b.lit))
            }
            (Ty::Char, Ty::Str(_)) | (Ty::Str(_), Ty::Char) if eq => {
                let (s, c) = if matches!(a.ty, Ty::Str(_)) { (a, b) } else { (b, a) };
                if one_char(s) || c.val.is_some() && one_char(s) {
                    Some(result(None, false))
                } else {
                    self.err("E-TYPE", span, "a Char can only be compared with a one-character string")
                }
            }
            (Ty::Str(_), Ty::Str(_)) | (Ty::Str(_), Ty::Char) | (Ty::Char, Ty::Str(_)) => {
                if !eq {
                    return self.err("E-TYPE", span, "only `=` and `<>` apply to strings");
                }
                let v = match (&a.val, &b.val) {
                    (Some(CVal::Str(x)), Some(CVal::Str(y))) => Some((x == y) == (op == BinOp::Eq)),
                    _ => None,
                };
                Some(result(v, a.lit && b.lit))
            }
            (Ty::Bool, Ty::Bool) => self.err("E-TYPE", span, "Booleans can only be compared with `=` and `<>`"),
            (x, y) if (matches!(x, Ty::Bool) && y.is_numeric()) || (matches!(y, Ty::Bool) && x.is_numeric()) => {
                self.err("E-MIX", span, format!("cannot compare a Boolean with a number ({x} and {y})"))
            }
            (x, y) => self.err("E-TYPE", span, format!("cannot compare {x} with {y}")),
        }
    }

    // ---- designators ---------------------------------------------------------------------

    fn reg_value_ty(bits: u8) -> Ty {
        match bits {
            0..=8 => BYTE,
            9..=16 => WORD,
            _ => LONGWORD,
        }
    }

    fn find_register(&self, name: &str) -> Option<RegInfo> {
        let dev = self.a.device.as_ref()?;
        if let Some(s) = dev.find_sfr(name) {
            let mut fields: Vec<(String, u8, u8)> = s.fields.iter().chain(s.legacy.iter()).map(|f| (f.name.clone(), f.pos, f.width)).collect();
            fields.dedup();
            return Some(RegInfo { name: s.name.clone(), ty: Self::reg_value_ty(s.width), fields });
        }
        let j = dev.joined.iter().find(|j| j.name.eq_ignore_ascii_case(name))?;
        Some(RegInfo { name: j.name.clone(), ty: Self::reg_value_ty(j.bytes * 8), fields: vec![] })
    }

    fn cur_from_symbol(&mut self, id: SymId, d: &Designator, addr_mode: bool, module: bool) -> Option<Cur> {
        self.a.resolved.insert(d.id, Res::Sym(id));
        let sym = self.a.symbols[id].clone();
        if !self.in_bound && matches!(&sym.kind, SymKind::Var { ty: Ty::Array(e, _) } if matches!(**e, Ty::Bit | Ty::Bool)) {
            // Only `a(i)` (or `Module.a(i)`) leaves the layout free to be packed.
            let lead = usize::from(module);
            let indexed = d.parts.len() == lead + 1 && matches!(d.parts.last(), Some(Part::Args(..)));
            if !indexed {
                self.a.unpackable.insert(id);
            }
        }
        Some(match sym.kind {
            SymKind::Const { ty, val, typed } => Cur::Val(EI { ty, val: Some(val), lit: !typed, place: Place::ReadOnly, call: false, in_array: false }),
            SymKind::ConstArray { elem, vals } => Cur::Val(EI::place(Ty::Array(Box::new(elem), vals.len() as u32), Place::ReadOnly)),
            SymKind::Var { ty } | SymKind::Alias { ty } => Cur::Val(EI::place(ty, Place::Var)),
            SymKind::Param { ty, mode } => Cur::Val(EI::place(ty, if mode == ParamMode::ByRefConst { Place::ReadOnly } else { Place::Var })),
            SymKind::Routine { .. } => Cur::Routine(id),
            SymKind::Event => Cur::Handler,
            SymKind::Interrupt { .. } => return self.err("E-NOTVALUE", d.head.span, format!("`{}` is an Interrupt; it can only be used with Enable and Disable", sym.name)),
            SymKind::Struct { .. } | SymKind::EventType => return self.err("E-NOTVALUE", d.head.span, format!("`{}` is a type, not a value", sym.name)),
        })
        .inspect(|_| {
            let _ = addr_mode;
        })
    }

    fn resolve_head(&mut self, d: &Designator, addr_mode: bool) -> Option<Cur> {
        let key = d.head.key();
        if key == "result" {
            return match self.ctx.ret.clone() {
                Some(t) => Some(Cur::Val(EI::place(t, Place::Var))),
                None => self.err("E-RESULT", d.head.span, "`Result` is only available inside a Function"),
            };
        }
        if let Some(found) = self.lookup(&key, d.head.span)? {
            return self.cur_from_symbol(found, d, addr_mode, false);
        }
        if let Some(m) = self.module_by_name(&key) {
            self.a.resolved.insert(d.id, Res::Module(m));
            return Some(Cur::Module(m));
        }
        if let Some(r) = self.find_register(&key) {
            self.a.resolved.insert(d.id, Res::Register(r.name.clone()));
            return Some(Cur::Reg(r));
        }
        let is_kw_intrinsic = crate::lexer::CALLABLE_KEYWORDS.contains(&key.as_str());
        if is_kw_intrinsic || PREDEFINED_INTRINSICS.contains(&key.as_str()) {
            self.a.resolved.insert(d.id, Res::Intrinsic(key.clone()));
            return Some(Cur::Intrinsic(key));
        }
        let msg = if self.a.device.is_none() { format!("`{}` is not declared", d.head.name) } else { format!("`{}` is not declared and is not a register of {}", d.head.name, self.a.device.as_ref().unwrap().device.name) };
        self.err("E-UNDECLARED", d.head.span, msg)
    }

    /// Evaluates a designator. The flag in the result is true when it names a routine without
    /// calling it (address mode). `addr_mode` stops a bare routine name from being called.
    fn eval_designator(&mut self, d: &'p Designator, addr_mode: bool) -> Option<(EI, bool)> {
        let mut cur = self.resolve_head(d, addr_mode)?;
        let mut i = 0;
        while i < d.parts.len() {
            let part = &d.parts[i];
            cur = match (cur, part) {
                (Cur::Module(u), Part::Member(n)) => {
                    let Some(&id) = self.unit_scopes[u].get(&n.key()) else {
                        let m = self.proj.units[u].unit.name.as_ref().map(|x| x.name.clone()).unwrap_or_default();
                        return self.err("E-UNDECLARED", n.span, format!("module `{m}` has no declaration `{}`", n.name));
                    };
                    if self.a.symbols[id].vis != Vis::Public {
                        return self.err("E-PRIVATE", n.span, format!("`{}` is Private to its module", n.name));
                    }
                    self.cur_from_symbol(id, d, addr_mode, true)?
                }
                (Cur::Module(_), _) => return self.err("E-SYNTAX", d.span, "a module name must be followed by `.name`"),
                (Cur::Reg(r), Part::Member(n)) => {
                    let key = n.key();
                    match r.fields.iter().find(|f| f.0.eq_ignore_ascii_case(&key)) {
                        Some((_, _, w)) => Cur::Val(EI::place(if *w == 1 { Ty::Bit } else { Self::reg_value_ty(*w) }, Place::Var)),
                        None => self.modifier(EI::place(r.ty.clone(), Place::Var), n, d, &mut i)?,
                    }
                }
                (Cur::Reg(r), _) => {
                    cur = Cur::Val(EI::place(r.ty.clone(), Place::Var));
                    continue;
                }
                (Cur::Val(v), Part::Member(n)) => match &v.ty {
                    Ty::Struct(sid) => {
                        let SymKind::Struct { fields, .. } = &self.a.symbols[*sid].kind else { unreachable!() };
                        match fields.iter().find(|f| f.name.eq_ignore_ascii_case(&n.name)) {
                            Some(f) => {
                                let ty = f.ty.clone();
                                Cur::Val(EI { ty, place: v.place, ..EI::new(Ty::Void) })
                            }
                            None => return self.err("E-NOMEMBER", n.span, format!("the structure has no field `{}`", n.name)),
                        }
                    }
                    _ => self.modifier(v, n, d, &mut i)?,
                },
                (Cur::Val(v), Part::BitIndex(n, sp)) => {
                    let bits = match v.ty {
                        Ty::Int(w, _) => w as u64,
                        _ => return self.err("E-TYPE", *sp, format!("a bit number can only follow an integer or register, not {}", v.ty)),
                    };
                    if *n >= bits {
                        return self.err("E-BOUNDS", *sp, format!("bit {n} does not exist in a {}-bit {}", bits, v.ty));
                    }
                    Cur::Val(EI { ty: Ty::Bit, place: v.place, in_array: false, ..EI::new(Ty::Bit) })
                }
                (Cur::Val(v), Part::Args(args, sp)) => match v.ty.clone() {
                    Ty::Array(elem, n) => {
                        if args.len() != 1 {
                            return self.err("E-ARGS", *sp, "an array index is a single number");
                        }
                        let ix = self.check_expr(&args[0])?;
                        if !ix.ty.is_int() {
                            return self.err("E-TYPE", args[0].span, format!("an array index must be an integer, found {}", ix.ty));
                        }
                        match &ix.val {
                            Some(CVal::Int(c)) if *c < 0 || (n > 0 && *c >= n as i128) => {
                                return self.err("E-BOUNDS", args[0].span, format!("index {c} is outside the array (0 to {})", n.saturating_sub(1)));
                            }
                            _ => {}
                        }
                        Cur::Val(EI { ty: *elem, place: v.place, in_array: true, ..EI::new(Ty::Void) })
                    }
                    Ty::Str(n) => {
                        if args.len() != 1 {
                            return self.err("E-ARGS", *sp, "a string index is a single number");
                        }
                        let ix = self.check_expr(&args[0])?;
                        if !ix.ty.is_int() {
                            return self.err("E-TYPE", args[0].span, format!("a string index must be an integer, found {}", ix.ty));
                        }
                        if let Some(CVal::Int(c)) = &ix.val
                            && (*c < 0 || *c > n as i128)
                        {
                            return self.err("E-BOUNDS", args[0].span, format!("index {c} is outside the string (0 to {n})"));
                        }
                        Cur::Val(EI { ty: Ty::Char, place: v.place, in_array: true, ..EI::new(Ty::Void) })
                    }
                    Ty::EventVar(_) => {
                        if !args.is_empty() {
                            return self.err("E-ARGS", *sp, "an event takes no arguments");
                        }
                        if self.ctx.kind == Kind::Interrupt && self.ctx.saves == 0 {
                            self.diags.error("E-ISR-CALL", *sp, "an interrupt handler cannot call an event directly; the call goes through a shared dispatcher. Wrap the call in Save(…) … Restore (LANGUAGE.md §8)");
                        }
                        Cur::Val(EI { call: true, ..EI::new(Ty::Void) })
                    }
                    t => return self.err("E-TYPE", *sp, format!("a {t} cannot be indexed or called")),
                },
                (Cur::Routine(id), Part::Args(args, sp)) => Cur::Val(self.check_call(id, args, *sp)?),
                (Cur::Routine(_), _) => return self.err("E-CALL", d.span, "a routine can only be followed by its arguments"),
                (Cur::Intrinsic(name), Part::Args(args, sp)) => Cur::Val(self.check_intrinsic(&name, args, *sp, d)?),
                (Cur::Intrinsic(name), _) => return self.err("E-CALL", d.span, format!("`{name}` needs its arguments in parentheses")),
                (Cur::Handler, Part::Args(..)) => return self.err("E-CALL", d.span, "an event handler is called through a variable of an event type, not by name"),
                (Cur::Handler, _) => return self.err("E-SYNTAX", d.span, "unexpected name or index after an event handler"),
            };
            i += 1;
        }
        // The designator ended; turn what remains into a value.
        match cur {
            Cur::Val(v) => Some((v, false)),
            Cur::Routine(id) if addr_mode => {
                let _ = id;
                Some((EI::new(LONGWORD), true))
            }
            Cur::Routine(id) => Some((self.check_call(id, &[], d.span)?, false)),
            Cur::Reg(r) => Some((EI::place(r.ty, Place::Var), false)),
            Cur::Handler => Some((EI::new(Ty::EventAny), false)),
            Cur::Intrinsic(name) => {
                if name == "terminate" {
                    Some((self.check_intrinsic(&name, &[], d.span, d)?, false))
                } else {
                    self.err("E-CALL", d.span, format!("`{}` needs its arguments in parentheses", d.head.name))
                }
            }
            Cur::Module(_) => self.err("E-NOTVALUE", d.span, format!("`{}` is a module, not a value", d.head.name)),
        }
    }

    /// Modifiers (LANGUAGE.md §3.4): `.ByteN`, `.WordN`, `.Bytes(n)`, `.Words(n)`, `.Bits(n)`,
    /// `.Booleans(n)` and the promotions `.AsWord` … `.AsLongInt`.
    fn modifier(&mut self, v: EI, n: &'p Ident, d: &'p Designator, i: &mut usize) -> Option<Cur> {
        let key = n.key();
        let bits = match v.ty {
            Ty::Int(w, _) => w as u32,
            Ty::Float => 32,
            _ => 0,
        };
        let place = v.place;
        let mk = |ty: Ty| Some(Cur::Val(EI { ty, place, ..EI::new(Ty::Void) }));
        if bits == 0 && !key.starts_with("as") {
            return self.err("E-NOMEMBER", n.span, format!("a {} has no member `{}`", v.ty, n.name));
        }
        if let Some(num) = key.strip_prefix("byte").and_then(|s| s.parse::<u32>().ok()) {
            if num >= bits / 8 {
                return self.err("E-BOUNDS", n.span, format!("a {} has no `{}`", v.ty, n.name));
            }
            return mk(BYTE);
        }
        if let Some(num) = key.strip_prefix("word").and_then(|s| s.parse::<u32>().ok()) {
            if num >= bits / 16 {
                return self.err("E-BOUNDS", n.span, format!("a {} has no `{}`", v.ty, n.name));
            }
            return mk(WORD);
        }
        match key.as_str() {
            "bytes" | "words" | "bits" | "booleans" => {
                let Some(Part::Args(args, sp)) = d.parts.get(*i + 1) else {
                    return self.err("E-SYNTAX", n.span, format!("`{}` needs an index: `.{}(n)`", n.name, n.name));
                };
                if args.len() != 1 {
                    return self.err("E-ARGS", *sp, "one index is needed");
                }
                *i += 1;
                let c = self.const_int(&args[0])?;
                let (limit, ty) = match key.as_str() {
                    "bytes" => (bits / 8, BYTE),
                    "words" => (bits / 16, WORD),
                    "bits" => (bits, Ty::Bit),
                    _ => (bits, Ty::Bool),
                };
                if c < 0 || c >= limit as i128 {
                    return self.err("E-BOUNDS", args[0].span, format!("index {c} is outside 0 to {} for a {}", limit.saturating_sub(1), v.ty));
                }
                mk(ty)
            }
            "asbyte" | "asshortint" | "asword" | "asinteger" | "aslongword" | "aslongint" => {
                let target = match key.as_str() {
                    "asbyte" => BYTE,
                    "asshortint" => SHORTINT,
                    "asword" => WORD,
                    "asinteger" => INTEGER,
                    "aslongword" => LONGWORD,
                    _ => LONGINT,
                };
                if v.place != Place::Var {
                    return self.err("E-ALIAS", n.span, "a promotion applies to a variable or register");
                }
                let have = self.size_of(&v.ty) * 8;
                let want = target.width().unwrap() as u32;
                if want > have && !v.in_array {
                    return self.err("E-ALIAS", n.span, format!("`.{}` needs {} bytes of storage but a {} has {}; promotion over larger storage is for array elements", n.name, want / 8, v.ty, have / 8));
                }
                mk(target)
            }
            _ => self.err("E-NOMEMBER", n.span, format!("a {} has no member or modifier `{}`", v.ty, n.name)),
        }
    }

    fn check_call(&mut self, id: SymId, args: &'p [Expr], span: Span) -> Option<EI> {
        let SymKind::Routine { params, ret, .. } = self.a.symbols[id].kind.clone() else { unreachable!() };
        let name = self.a.symbols[id].name.clone();
        let required = params.iter().filter(|p| !p.has_default).count();
        if args.len() < required || args.len() > params.len() {
            let want = if required == params.len() { format!("{required}") } else { format!("{required} to {}", params.len()) };
            return self.err("E-ARGS", span, format!("`{name}` takes {want} argument(s), {} given", args.len()));
        }
        if self.ctx.kind == Kind::Interrupt && self.ctx.saves == 0 {
            self.diags.error("E-ISR-CALL", span, format!("an interrupt handler cannot call `{name}` directly; its frame may overlay main-line storage. Wrap the call in Save(…) … Restore (LANGUAGE.md §8)"));
        }
        let mut ok = true;
        for (a, p) in args.iter().zip(&params) {
            match p.mode {
                ParamMode::ByVal => {
                    if let Some(ei) = self.check_expr(a) {
                        if self.assign_ok(&p.ty, &ei, a.span, &format!("argument `{}`", p.name)) {
                            self.annotate_assignment(&p.ty, &ei, a);
                        } else {
                            ok = false;
                        }
                    } else {
                        ok = false;
                    }
                }
                ParamMode::ByRef | ParamMode::ByRefConst => {
                    let Some(ei) = self.check_expr(a) else {
                        ok = false;
                        continue;
                    };
                    let const_ok = p.mode == ParamMode::ByRefConst;
                    let is_lit_str = const_ok && ei.lit && matches!(ei.ty, Ty::Str(_));
                    if !is_lit_str {
                        let place_ok = if const_ok { ei.place != Place::None } else { ei.place == Place::Var };
                        if !place_ok {
                            self.diags.error("E-PARAM", a.span, format!("argument `{}` is passed {}; give a {}", p.name, if const_ok { "ByRefConst" } else { "ByRef" }, if const_ok { "constant array or string" } else { "variable" }));
                            ok = false;
                            continue;
                        }
                        if let ExprKind::Designator(dd) = &a.kind
                            && !const_ok
                        {
                            self.note_modified(dd);
                        }
                    }
                    let same = match (&p.ty, &ei.ty) {
                        (Ty::Array(pe, _), Ty::Array(ae, _)) => pe == ae,
                        // A ByRef string must have the callee's capacity: a longer write would
                        // run past a smaller buffer. ByRefConst only reads, so any size is fine.
                        (Ty::Str(pn), Ty::Str(an)) => const_ok || pn == an,
                        (x, y) => x == y,
                    };
                    if !same {
                        self.diags.error("E-TYPE", a.span, format!("argument `{}` expects {}, found {}", p.name, p.ty, ei.ty));
                        ok = false;
                    }
                }
            }
        }
        if !ok {
            return None;
        }
        self.a.calls.push(CallEdge { caller: self.ctx.routine, callee: id, span });
        Some(EI { call: true, ..EI::new(ret.unwrap_or(Ty::Void)) })
    }

    fn lvalue_arg(&mut self, e: &'p Expr, what: &str) -> Option<EI> {
        let ei = self.check_expr(e)?;
        if ei.place != Place::Var {
            return self.err("E-ARGS", e.span, format!("{what} needs a variable, register or bit"));
        }
        if let ExprKind::Designator(d) = &e.kind {
            self.note_modified(d);
        }
        Some(ei)
    }

    fn check_intrinsic(&mut self, name: &str, args: &'p [Expr], span: Span, d: &'p Designator) -> Option<EI> {
        let want = |this: &mut Self, n: usize| -> bool {
            if args.len() == n {
                true
            } else {
                this.diags.error("E-ARGS", span, format!("`{}` takes {n} argument(s), {} given", d.head.name, args.len()));
                false
            }
        };
        let call = |ty: Ty| Some(EI { call: true, ..EI::new(ty) });
        match name {
            "inc" | "dec" => {
                // `Inc(x)` / `Dec(x)`, or `Inc(x, amount)` / `Dec(x, amount)` with an integer amount.
                if args.len() != 1 && args.len() != 2 {
                    self.diags.error("E-ARGS", span, format!("`{}` takes 1 or 2 arguments, {} given", d.head.name, args.len()));
                    return None;
                }
                let v = self.lvalue_arg(&args[0], d.head.name.as_str())?;
                if !v.ty.is_int() {
                    return self.err("E-TYPE", args[0].span, format!("`{}` needs an integer variable, found {}", d.head.name, v.ty));
                }
                if let Some(amount) = args.get(1) {
                    let a = self.check_expr(amount)?;
                    if !a.ty.is_numeric_int() {
                        return self.err("E-TYPE", amount.span, format!("the amount of `{}` must be an integer, found {}", d.head.name, a.ty));
                    }
                }
                call(Ty::Void)
            }
            "clear" => {
                if !want(self, 1) {
                    return None;
                }
                self.lvalue_arg(&args[0], "Clear")?;
                call(Ty::Void)
            }
            "toggle" | "high" | "low" | "input" | "output" => {
                if !want(self, 1) {
                    return None;
                }
                let v = self.lvalue_arg(&args[0], d.head.name.as_str())?;
                let ok = matches!(v.ty, Ty::Bit | Ty::Bool) || (matches!(name, "input" | "output") && v.ty == BYTE);
                if !ok {
                    return self.err("E-TYPE", args[0].span, format!("`{}` needs a Bit or Boolean{}, found {}", d.head.name, if matches!(name, "input" | "output") { " (or a Byte port)" } else { "" }, v.ty));
                }
                call(Ty::Void)
            }
            "delayms" | "delayus" => {
                if !want(self, 1) {
                    return None;
                }
                let v = self.check_expr(&args[0])?;
                if !v.ty.is_int() {
                    return self.err("E-TYPE", args[0].span, format!("`{}` needs a whole number, found {}", d.head.name, v.ty));
                }
                if let Some(CVal::Int(c)) = &v.val
                    && *c < 0
                {
                    return self.err("E-CONST-RANGE", args[0].span, "a delay cannot be negative");
                }
                call(Ty::Void)
            }
            "terminate" => {
                if !want(self, 0) {
                    return None;
                }
                call(Ty::Void)
            }
            "bound" => {
                if !want(self, 1) {
                    return None;
                }
                self.in_bound = true;
                let v = self.check_expr(&args[0]);
                self.in_bound = false;
                let v = v?;
                match v.ty {
                    Ty::Array(_, 0) => Some(EI::new(WORD)),
                    Ty::Array(_, n) => Some(EI::int_lit(n as i128 - 1)),
                    ref t => self.err("E-TYPE", args[0].span, format!("`Bound` needs an array, found {t}")),
                }
            }
            "addressof" => {
                if !want(self, 1) {
                    return None;
                }
                let ExprKind::Designator(dd) = &args[0].kind else {
                    return self.err("E-ADDR", args[0].span, "`AddressOf` needs a variable, array or routine");
                };
                let (ei, is_routine) = self.eval_designator(dd, true)?;
                self.address_of(&ei, is_routine, args[0].span)
            }
            "bitof" => self.err("E-UNSUPPORTED", span, "`BitOf` is not specified in language version 0.1; use `x.n` or `x.Bits(n)`"),
            "string" => self.err("E-UNSUPPORTED", span, "conversion to String is not supported yet"),
            n if CONVERSIONS.contains(&n) => {
                if !want(self, 1) {
                    return None;
                }
                let v = self.check_expr(&args[0])?;
                let target = match n {
                    "byte" => BYTE,
                    "word" => WORD,
                    "integer" => INTEGER,
                    "longword" => LONGWORD,
                    "longint" => LONGINT,
                    "shortint" => SHORTINT,
                    "float" => Ty::Float,
                    "boolean" => Ty::Bool,
                    "bit" => Ty::Bit,
                    _ => Ty::Char,
                };
                let src_ok = match (&target, &v.ty) {
                    (Ty::Bool, t) => matches!(t, Ty::Bit | Ty::Bool) || t.is_int(),
                    (Ty::Bit, t) => matches!(t, Ty::Bool) || t.is_numeric_int(),
                    (Ty::Char, t) => matches!(t, Ty::Char) || (t.is_int() && v.val.is_some()) || *t == BYTE,
                    (_, t) => t.is_numeric() || matches!(t, Ty::Char),
                };
                if !src_ok {
                    return self.err("E-TYPE", args[0].span, format!("cannot convert {} to {}", v.ty, target));
                }
                if let Some(val) = &v.val {
                    let as_i = match val {
                        CVal::Int(i) => Some(*i),
                        CVal::Float(f) if target.is_numeric_int() => Some(f.trunc() as i128),
                        CVal::Bool(b) => Some(*b as i128),
                        _ => None,
                    };
                    if let (Some(i), Some((lo, hi))) = (as_i, target.int_range()) {
                        if i < lo || i > hi {
                            return self.err("E-CONST-RANGE", args[0].span, format!("{i} does not fit {target}"));
                        }
                        let cv = if target == Ty::Bool { CVal::Bool(i != 0) } else { CVal::Int(i) };
                        return Some(EI { val: Some(cv), ..EI::new(target) });
                    }
                    if target == Ty::Bool
                        && let Some(i) = as_i
                    {
                        return Some(EI { val: Some(CVal::Bool(i != 0)), ..EI::new(Ty::Bool) });
                    }
                    if target == Ty::Float
                        && let Some(f) = val.as_f64()
                    {
                        return Some(EI { val: Some(CVal::Float(f)), ..EI::new(Ty::Float) });
                    }
                }
                Some(EI::new(target))
            }
            "abs" => {
                if !want(self, 1) {
                    return None;
                }
                let v = self.check_expr(&args[0])?;
                if !v.ty.is_numeric() {
                    return self.err("E-TYPE", args[0].span, format!("`Abs` needs a number, found {}", v.ty));
                }
                Some(match &v.val {
                    Some(CVal::Int(c)) => EI { val: Some(CVal::Int(c.abs())), ..if v.lit { EI::int_lit(c.abs()) } else { EI::new(v.ty.clone()) } },
                    Some(CVal::Float(f)) => EI { val: Some(CVal::Float(f.abs())), ..EI::new(Ty::Float) },
                    _ => EI::new(v.ty.clone()),
                })
            }
            "min" | "max" => {
                if !want(self, 2) {
                    return None;
                }
                let a = self.check_expr(&args[0]);
                let b = self.check_expr(&args[1]);
                let (a, b) = (a?, b?);
                if !a.ty.is_numeric_int() || !b.ty.is_numeric_int() {
                    return self.err("E-TYPE", span, "`Min` and `Max` take integers");
                }
                let ct = self.common(&a, &b, span)?;
                if let (Some(CVal::Int(x)), Some(CVal::Int(y))) = (&a.val, &b.val) {
                    let v = if name == "min" { *x.min(y) } else { *x.max(y) };
                    return Some(if a.lit && b.lit { EI::int_lit(v) } else { EI { val: Some(CVal::Int(v)), ..EI::new(ct) } });
                }
                Some(EI::new(ct))
            }
            _ => self.err("E-UNSUPPORTED", span, format!("intrinsic `{name}` is not implemented")),
        }
    }

    // ---- whole-program checks ------------------------------------------------------------

    fn check_recursion(&mut self) {
        let n = self.a.symbols.len();
        let mut edges: Vec<Vec<(SymId, Span)>> = vec![Vec::new(); n];
        for c in &self.a.calls {
            if let Some(from) = c.caller {
                edges[from].push((c.callee, c.span));
            }
        }
        // 0 = unvisited, 1 = on the path, 2 = done
        let mut state = vec![0u8; n];
        let mut reported: HashSet<SymId> = HashSet::new();
        fn dfs(v: SymId, edges: &[Vec<(SymId, Span)>], state: &mut [u8], path: &mut Vec<SymId>, found: &mut Vec<(Vec<SymId>, Span)>) {
            state[v] = 1;
            path.push(v);
            for &(w, sp) in &edges[v] {
                if state[w] == 1 {
                    let start = path.iter().position(|x| *x == w).unwrap();
                    found.push((path[start..].to_vec(), sp));
                } else if state[w] == 0 {
                    dfs(w, edges, state, path, found);
                }
            }
            path.pop();
            state[v] = 2;
        }
        let mut found = Vec::new();
        for v in 0..n {
            if state[v] == 0 {
                dfs(v, &edges, &mut state, &mut Vec::new(), &mut found);
            }
        }
        for (cycle, sp) in found {
            if cycle.iter().any(|c| self.reentrant_ok.contains(c)) || !reported.insert(cycle[0]) {
                continue;
            }
            let names: Vec<String> = cycle.iter().map(|c| self.a.symbols[*c].name.clone()).collect();
            let what = if names.len() == 1 { format!("`{}` calls itself", names[0]) } else { format!("calls form a cycle: {}", names.join(" → ")) };
            self.diags.error("E-RECURSION", sp, format!("{what}; recursion needs the Reentrant attribute (D13)"));
        }
    }

    fn check_ram(&mut self) {
        let Some(dev) = &self.a.device else { return };
        let usable = dev.memory.data.usable_gpr;
        // Packed bit arrays take n/8 bytes, not n.
        let saved: u32 = self.a.global_bit_arrays.iter().filter(|(id, _)| !self.a.unpackable.contains(id)).map(|(_, n)| n - n.div_ceil(8)).sum();
        let ram = self.a.global_ram - saved;
        if ram > usable {
            let sp = Span { file: self.proj.units.last().map(|u| u.unit.file).unwrap_or(0), line: 1, col: 1 };
            let msg = format!("global variables need {} bytes but {} has only {} bytes of usable RAM", ram, dev.device.name, usable);
            self.diags.error("E-RAM", sp, msg);
        }
    }
}

fn signed_of(t: &Ty) -> Option<Ty> {
    match t {
        Ty::Int(w, true) => Some(Ty::Int(*w, true)),
        Ty::Int(8, false) | Ty::Bit => Some(INTEGER),
        Ty::Int(16, false) => Some(LONGINT),
        _ => None,
    }
}

/// A constant stored into a typed place: a one-character string becomes its code for Char.
fn coerce_const(t: &Ty, v: CVal) -> CVal {
    match (t, &v) {
        (Ty::Char, CVal::Str(s)) => CVal::Int(s.bytes().next().unwrap_or(0) as i128),
        (Ty::Float, CVal::Int(i)) => CVal::Float(*i as f64),
        _ => v,
    }
}

fn params_with_ast(ast: &[Param], infos: &[ParamInfo]) -> Vec<(Ident, ParamInfo)> {
    ast.iter().zip(infos).map(|(a, i)| (a.name.clone(), i.clone())).collect()
}

/// True when the text has a statement that assigns to `OSCFRQ` or `OSCCON1` (a line starting with
/// the register name and then `=` or `.`). Comments are ignored; reads in conditions do not count.
fn writes_oscillator(text: &str) -> bool {
    text.lines().any(|l| {
        let code = l.split('\'').next().unwrap_or("").trim_start().to_ascii_lowercase();
        ["oscfrq", "osccon1"].iter().any(|r| {
            code.strip_prefix(r).is_some_and(|rest| matches!(rest.trim_start().chars().next(), Some('=') | Some('.')))
        })
    })
}
