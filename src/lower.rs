//! Lowers the checked tree to the IR (`ir.rs`).
//!
//! Everything the semantic pass recorded (types, constants, evaluation widths, name
//! resolutions) is consumed here; the code generator never looks at the AST. M4 covers scalar
//! programs: Boolean, Bit, Char and the 8/16/32-bit integers, device registers and register
//! bits, routines with by-value parameters, and the structured statements. One-dimensional
//! arrays of integers and Char (no initialisers yet) are indexed through `Place::idx`. Strings
//! are Null-terminated RAM objects handled by `St::StrSet` and `ExK::StrEq`; literals live in
//! program memory. Structures are laid out field after field (`layout`); a field is a byte
//! offset into the variable, so member access is the same `Place` arithmetic as arrays, and
//! whole structures are cleared and copied with `St::ClearMem`/`St::Copy`. Interrupt handlers are
//! routines nobody calls (`Program::isrs`); `Save` and `Enable`/`Disable` become `St::Save`/`St::Int`. Floats and
//! events report `E-BACKEND`.

use crate::ast::*;
use crate::diag::{Diagnostics, Span};
use crate::ir::*;
use crate::project::Project;
use crate::sema::{Analysis, Res, SymKind};
use crate::types::*;
use std::collections::{HashMap, HashSet};
use std::rc::Rc;

/// Width and signedness of a scalar type, or None for types the back end cannot hold yet.
fn nat(t: &Ty) -> Option<(u8, bool)> {
    match t {
        Ty::Bool | Ty::Bit | Ty::Char => Some((8, false)),
        Ty::Int(w, s) => Some((*w, *s)),
        _ => None,
    }
}

/// The integer a constant stores as; a one-character string is a Char.
fn cval_u32(c: &CVal) -> u32 {
    match c {
        CVal::Int(i) => *i as u32,
        CVal::Bool(b) => *b as u32,
        CVal::Str(s) if s.len() == 1 => s.as_bytes()[0] as u32,
        _ => 0,
    }
}

fn sign_extend(v: u32, w: u8) -> i64 {
    if w >= 32 {
        v as i32 as i64
    } else if v & (1 << (w - 1)) != 0 {
        (v | !mask(w)) as i32 as i64
    } else {
        v as i64
    }
}

/// Converts `ex` to `w`/`signed`, extending by the operand's own signedness.
pub fn conv(ex: Ex, w: u8, signed: bool) -> Ex {
    if ex.w == w && ex.signed == signed {
        return ex;
    }
    if let ExK::Const(v) = ex.k {
        let val = if ex.signed { sign_extend(v, ex.w) } else { v as i64 };
        return Ex::konst(val as u32, w, signed);
    }
    if ex.w == w && matches!(ex.k, ExK::Load(_)) {
        return Ex { signed, ..ex };
    }
    Ex::new(ExK::Conv(Box::new(ex)), w, signed)
}

/// Where one field of a structure sits: `off` bytes from its start, or bit `bit` of that byte.
struct FieldLay {
    name: String,
    off: u32,
    bit: Option<u8>,
    ty: Ty,
}

struct FuncInfo {
    id: FuncId,
    asm: String,
    params: Vec<(VarId, Option<Ex>)>,
    result: Option<VarId>,
}

pub struct Lowerer<'a> {
    proj: &'a Project,
    a: &'a Analysis,
    diags: &'a mut Diagnostics,
    vars: Vec<Var>,
    funcs: Vec<Option<Func>>,
    label_names: Vec<String>,
    sym_var: HashMap<usize, VarId>,
    sym_alias: HashMap<usize, Place>,
    sym_func: HashMap<usize, FuncInfo>,
    /// Symbols the back end cannot represent yet, with a description for the message.
    unsupported: HashMap<usize, String>,
    unit_syms: HashMap<(usize, String), usize>,
    routines: HashMap<usize, &'a Routine>,
    struct_decls: HashMap<usize, &'a StructDecl>,
    layouts: HashMap<usize, Rc<Vec<FieldLay>>>,
    queue: Vec<usize>,
    asm_names: HashSet<String>,
    cur_func: Option<FuncId>,
    cur_asm: String,
    cur_result: Option<(VarId, String)>,
    labels: HashMap<String, LabelId>,
    hidden: u32,
    /// Static buffers holding string literals passed to `ByRefConst` parameters.
    lits: HashMap<Vec<u8>, VarId>,
    /// Statements that run before the program body (they fill those buffers).
    startup: Vec<S>,
    isrs: Vec<(FuncId, Level)>,
    n_saves: usize,
    /// Nesting depth of `Save` blocks being lowered.
    in_save: u32,
    failed: bool,
}

pub fn lower(proj: &Project, a: &Analysis, diags: &mut Diagnostics) -> Option<Program> {
    let device = a.device.as_ref()?;
    let mut lw = Lowerer {
        proj,
        a,
        diags,
        vars: Vec::new(),
        funcs: Vec::new(),
        label_names: Vec::new(),
        sym_var: HashMap::new(),
        sym_alias: HashMap::new(),
        sym_func: HashMap::new(),
        unsupported: HashMap::new(),
        unit_syms: HashMap::new(),
        routines: HashMap::new(),
        struct_decls: HashMap::new(),
        layouts: HashMap::new(),
        queue: Vec::new(),
        asm_names: HashSet::new(),
        cur_func: None,
        cur_asm: String::new(),
        cur_result: None,
        labels: HashMap::new(),
        hidden: 0,
        lits: HashMap::new(),
        startup: Vec::new(),
        isrs: Vec::new(),
        n_saves: 0,
        in_save: 0,
        failed: false,
    };
    for (id, s) in a.symbols.iter().enumerate() {
        if !s.local && s.unit != usize::MAX {
            lw.unit_syms.entry((s.unit, s.name.to_ascii_lowercase())).or_insert(id);
        }
    }
    for lu in &proj.units {
        for d in &lu.unit.decls {
            if let DeclKind::Routine(r) = &d.kind
                && let Some(&sym) = a.decl_syms.get(&r.name.span)
            {
                lw.routines.insert(sym, r);
            }
            if let DeclKind::Structure(sd) = &d.kind
                && let Some(&sym) = a.decl_syms.get(&sd.name.span)
            {
                lw.struct_decls.insert(sym, sd);
            }
        }
    }

    let mut main_body = Vec::new();
    for (ui, lu) in proj.units.iter().enumerate() {
        lw.labels.clear();
        lw.cur_func = None;
        lw.cur_asm = unit_prefix(proj, ui);
        for d in &lu.unit.decls {
            lw.decl(d, ui, &mut main_body);
        }
        let mut body = lw.block(&lu.unit.stmts, ui);
        main_body.append(&mut body);
    }
    while let Some(sym) = lw.queue.pop() {
        lw.lower_routine(sym);
    }
    if lw.failed {
        return None;
    }
    let main_body = {
        let mut b = std::mem::take(&mut lw.startup);
        b.append(&mut main_body);
        b
    };

    // Configuration words: the device's defaults overlaid with the program's settings.
    let mut config = Vec::new();
    for reg in &device.config {
        if reg.implemented == 0 {
            continue;
        }
        let mut v = reg.default;
        for cs in a.config.iter().filter(|c| c.register.eq_ignore_ascii_case(&reg.name)) {
            if let Some(f) = reg.fields.iter().find(|f| f.name.eq_ignore_ascii_case(&cs.field)) {
                let m = ((1u32 << f.width) - 1) << f.pos;
                v = (v & !m) | ((cs.value << f.pos) & m);
            }
        }
        config.push((reg.name.clone(), reg.addr, (v & reg.implemented) as u8));
    }

    let main = Func { asm: "__main".into(), name: "main".into(), params: vec![], result: None, body: main_body, span: Span::default() };
    let funcs = lw.funcs.into_iter().map(|f| f.expect("every queued routine is lowered")).collect();
    Some(Program {
        vars: lw.vars,
        funcs,
        main,
        label_names: lw.label_names,
        device: device.device.name.clone(),
        clock_mhz: a.clock_mhz.unwrap_or(0.0),
        config,
        isrs: lw.isrs,
        n_saves: lw.n_saves,
        isr_shadow: a.options.isr_shadow,
    })
}

/// The vector a handler with this priority (`ipLow` = 1, `ipHigh` = 2) serves.
fn level_of(priority: &Option<i64>) -> Level {
    match priority {
        None => Level::Single,
        Some(2) => Level::High,
        Some(_) => Level::Low,
    }
}

fn unit_prefix(proj: &Project, ui: usize) -> String {
    let n = proj.units[ui].unit.name.as_ref().map(|n| n.name.clone()).unwrap_or_else(|| "MAIN".into());
    sanitize(&n)
}

fn sanitize(s: &str) -> String {
    s.chars().map(|c| if c.is_ascii_alphanumeric() { c.to_ascii_uppercase() } else { '_' }).collect()
}

impl<'a> Lowerer<'a> {
    fn err(&mut self, code: &'static str, span: Span, msg: impl Into<String>) {
        self.failed = true;
        self.diags.error(code, span, msg);
    }

    fn unsupported(&mut self, span: Span, what: &str) {
        self.err("E-BACKEND", span, format!("{what} is not supported by the back end yet (structures, floats, and some array and by-reference forms are not implemented yet)"));
    }

    fn unique(&mut self, base: String) -> String {
        let mut n = base.clone();
        let mut i = 2;
        while !self.asm_names.insert(n.clone()) {
            n = format!("{base}_{i}");
            i += 1;
        }
        n
    }

    /// Size in bytes of a type, structures included.
    fn size_of(&self, ty: &Ty) -> u32 {
        let a = self.a;
        ty.size_bytes(&|s| match &a.symbols[s].kind {
            SymKind::Struct { size, .. } => *size,
            _ => 0,
        })
    }

    /// The fields of a structure with their offsets. Fields follow one another; an alias field
    /// (a union member such as `Flag As Val.0`) is placed by following its designator from the
    /// field it names.
    fn layout(&mut self, sid: usize) -> Option<Rc<Vec<FieldLay>>> {
        if let Some(l) = self.layouts.get(&sid) {
            return Some(l.clone());
        }
        let SymKind::Struct { fields, .. } = &self.a.symbols[sid].kind else { return None };
        let sd = *self.struct_decls.get(&sid)?;
        let mut lay: Vec<FieldLay> = Vec::new();
        let mut off = 0;
        for f in fields {
            let key = f.name.to_ascii_lowercase();
            if !f.alias {
                lay.push(FieldLay { name: key, off, bit: None, ty: f.ty.clone() });
                off += self.size_of(&f.ty);
                continue;
            }
            let ast = sd.fields.iter().find(|x| x.name.key() == key)?;
            let AsClause::Designator(d) = &ast.as_clause else { return None };
            let head = lay.iter().find(|x| x.name == d.head.key())?;
            // Followed on a stand-in place; only the offset, bit and type it ends on are used.
            let start = Place { base: Base::Abs { addr: 0, name: String::new() }, off: head.off, bit: head.bit, idx: None, ty: head.ty.clone() };
            let end = self.apply_parts(start, &d.parts, 0, d.span)?;
            lay.push(FieldLay { name: key, off: end.off, bit: end.bit, ty: end.ty });
        }
        let lay = Rc::new(lay);
        self.layouts.insert(sid, lay.clone());
        Some(lay)
    }

    fn new_var(&mut self, asm: String, name: &str, ty: Ty, kind: VarKind, init: Option<u32>) -> VarId {
        let bytes = self.size_of(&ty);
        let asm = self.unique(asm);
        self.vars.push(Var { asm, name: name.to_string(), ty, bytes, kind, owner: self.cur_func, init, by_ref: false });
        self.vars.len() - 1
    }

    fn hidden_var(&mut self, ty: Ty) -> Place {
        self.hidden += 1;
        let asm = format!("{}__H{}", self.cur_asm, self.hidden);
        let v = self.new_var(asm, "(hidden)", ty.clone(), VarKind::Hidden, None);
        Place { base: Base::Var(v), off: 0, bit: None, idx: None, ty }
    }

    // ---- declarations --------------------------------------------------------------------

    /// Declares the variables and aliases of one declaration. Local declarations append their
    /// initialisers to `inits`.
    fn decl(&mut self, d: &'a Decl, ui: usize, inits: &mut Vec<S>) {
        match &d.kind {
            DeclKind::Dim(dim) => self.dim(dim, ui, inits),
            DeclKind::Symbol(name, e) => {
                let Some(&sym) = self.a.decl_syms.get(&name.span) else { return };
                if matches!(self.a.symbols[sym].kind, SymKind::Alias { .. })
                    && let ExprKind::Designator(dd) = &e.kind
                    && let Some(p) = self.place_of(dd)
                {
                    self.sym_alias.insert(sym, p);
                }
            }
            DeclKind::Interrupt(i) => self.lower_interrupt(i, ui),
            DeclKind::Event(e) => self.unsupported(e.name.span, "an Event"),
            DeclKind::Const(_) | DeclKind::Structure(_) | DeclKind::EventType(_) | DeclKind::Routine(_) => {}
        }
    }

    /// An interrupt handler is a routine nobody calls: its own frame (never overlaid, see
    /// `codegen::independent`), no parameters and no result.
    fn lower_interrupt(&mut self, i: &'a InterruptDecl, ui: usize) {
        let Some(&sym) = self.a.decl_syms.get(&i.name.span) else { return };
        let SymKind::Interrupt { priority } = &self.a.symbols[sym].kind else { return };
        let level = level_of(priority);
        let id = self.funcs.len();
        self.funcs.push(None);
        let asm = self.unique(format!("{}_{}", unit_prefix(self.proj, ui), sanitize(&i.name.name)));
        self.asm_names.insert(format!("{asm}__TMP"));
        let saved = (self.cur_func, std::mem::take(&mut self.cur_asm), std::mem::take(&mut self.labels), self.cur_result.take());
        self.cur_func = Some(id);
        self.cur_asm = asm.clone();
        let mut body = Vec::new();
        for d in &i.body.decls {
            self.decl(d, ui, &mut body);
        }
        let mut rest = self.block(&i.body.stmts, ui);
        body.append(&mut rest);
        let mut entry = self.entry_clears(id, &body, i.name.span);
        entry.append(&mut body);
        self.funcs[id] = Some(Func { asm, name: i.name.name.clone(), params: vec![], result: None, body: entry, span: i.name.span });
        self.isrs.push((id, level));
        self.cur_func = saved.0;
        self.cur_asm = saved.1;
        self.labels = saved.2;
        self.cur_result = saved.3;
    }

    fn dim(&mut self, dim: &'a DimDecl, ui: usize, inits: &mut Vec<S>) {
        for it in &dim.items {
            let Some(&sym) = self.a.decl_syms.get(&it.name.span) else { continue };
            match self.a.symbols[sym].kind.clone() {
                SymKind::Var { ty } => {
                    let array = match &ty {
                        Ty::Array(elem, _) => {
                            if matches!(**elem, Ty::Bit | Ty::Bool) || (nat(elem).is_none() && !matches!(**elem, Ty::Struct(_))) {
                                self.unsupported_sym(sym, &format!("an array of {elem}"));
                                continue;
                            }
                            if it.init.is_some() || dim.trailing_init.is_some() {
                                self.unsupported_sym(sym, "an array with an initialiser");
                                continue;
                            }
                            true
                        }
                        _ => false,
                    };
                    let string = matches!(ty, Ty::Str(_));
                    let record = matches!(ty, Ty::Struct(_));
                    if !array && !string && !record && nat(&ty).is_none() {
                        self.unsupported_sym(sym, &format!("a variable of type {ty}"));
                        continue;
                    }
                    let init_e = it.init.as_ref().or(dim.trailing_init.as_ref());
                    let init = if string { None } else { init_e.and_then(|e| self.a.consts.get(&e.id)).map(cval_u32) };
                    let init = init.map(|v| v & mask(nat(&ty).map_or(32, |t| t.0)));
                    let s = &self.a.symbols[sym];
                    let asm = if s.local { format!("{}__{}", self.cur_asm, sanitize(&s.name)) } else { format!("{}_{}", unit_prefix(self.proj, ui), sanitize(&s.name)) };
                    let name = s.name.clone();
                    let local = s.local;
                    let kind = if local { VarKind::Local } else { VarKind::Global };
                    let v = self.new_var(asm, &name, ty.clone(), kind, init.filter(|&i| i != 0 || local));
                    self.sym_var.insert(sym, v);
                    if let (Ty::Str(cap), Some(e)) = (&ty, init_e) {
                        let dst = Place { base: Base::Var(v), off: 0, bit: None, idx: None, ty: ty.clone() };
                        self.str_assign(dst, *cap, e, it.name.span, inits);
                    }
                    if local && !array && !record && let Some(i) = init {
                        inits.push(S { st: St::Assign(Place { base: Base::Var(v), off: 0, bit: None, idx: None, ty: ty.clone() }, Ex::konst(i, nat(&ty).unwrap().0, nat(&ty).unwrap().1)), span: it.name.span });
                    }
                }
                SymKind::Alias { .. } => {
                    if let Some(AsClause::Designator(dd)) = &dim.as_clause
                        && let Some(p) = self.place_of(dd)
                    {
                        self.sym_alias.insert(sym, p);
                    }
                }
                _ => {}
            }
        }
    }

    fn unsupported_sym(&mut self, sym: usize, what: &str) {
        self.unsupported.insert(sym, what.to_string());
    }

    // ---- routines ------------------------------------------------------------------------

    /// The function id of a routine, creating its frame variables on first use.
    fn func_of(&mut self, sym: usize, span: Span) -> Option<FuncId> {
        if let Some(fi) = self.sym_func.get(&sym) {
            return Some(fi.id);
        }
        let r = *self.routines.get(&sym)?;
        if r.reentrant {
            self.unsupported(r.name.span, &format!("the Reentrant routine `{}`", r.name.name));
        }
        let (params_info, ret) = match &self.a.symbols[sym].kind {
            SymKind::Routine { params, ret, .. } => (params.clone(), ret.clone()),
            _ => return None,
        };
        let id = self.funcs.len();
        self.funcs.push(None);
        let ui = self.a.symbols[sym].unit;
        let asm = self.unique(format!("{}_{}", unit_prefix(self.proj, ui), sanitize(&r.name.name)));
        // The code generator names the routine's temporary area this; a local must not take it.
        self.asm_names.insert(format!("{asm}__TMP"));
        let saved = (self.cur_func, std::mem::take(&mut self.cur_asm));
        self.cur_func = Some(id);
        self.cur_asm = asm.clone();
        let mut params = Vec::new();
        let mut ok = true;
        for (p, info) in r.params.iter().zip(&params_info) {
            let pointee = match &info.ty {
                Ty::Array(e, _) => &**e,
                t => t,
            };
            let supported = match info.mode {
                ParamMode::ByVal => nat(&info.ty).is_some(),
                ParamMode::ByRef => matches!(info.ty, Ty::Str(_)) || matches!(pointee, Ty::Struct(_)) || (nat(pointee).is_some() && !matches!(pointee, Ty::Bit) && !(matches!(info.ty, Ty::Array(..)) && *pointee == Ty::Bool)),
                ParamMode::ByRefConst => matches!(info.ty, Ty::Str(_)),
            };
            if !supported {
                self.unsupported(p.name.span, &format!("parameter `{}` ({})", p.name.name, if info.mode == ParamMode::ByVal { "non-scalar" } else { "this by-reference form" }));
                ok = false;
                continue;
            }
            let v = self.new_var(format!("{asm}__{}", sanitize(&p.name.name)), &p.name.name, info.ty.clone(), VarKind::Param, None);
            if info.mode != ParamMode::ByVal {
                self.vars[v].by_ref = true;
                self.vars[v].bytes = 2;
            }
            if let Some(&psym) = self.a.decl_syms.get(&p.name.span) {
                self.sym_var.insert(psym, v);
            }
            let (w, s) = nat(&info.ty).unwrap_or((16, false));
            let default = p.default.as_ref().and_then(|e| self.a.consts.get(&e.id)).map(|c| Ex::konst(cval_u32(c), w, s));
            params.push((v, default));
        }
        let result = match &ret {
            Some(t) if nat(t).is_some() => Some(self.new_var(format!("{asm}__RESULT"), "Result", t.clone(), VarKind::Result, None)),
            Some(t) => {
                self.unsupported(span, &format!("a function returning {t}"));
                ok = false;
                None
            }
            None => None,
        };
        self.cur_func = saved.0;
        self.cur_asm = saved.1;
        let _ = ok;
        self.sym_func.insert(sym, FuncInfo { id, asm, params, result });
        self.queue.push(sym);
        Some(id)
    }

    fn lower_routine(&mut self, sym: usize) {
        let r = self.routines[&sym];
        let (id, asm, result, params) = {
            let fi = &self.sym_func[&sym];
            (fi.id, fi.asm.clone(), fi.result, fi.params.iter().map(|p| p.0).collect::<Vec<_>>())
        };
        let ui = self.a.symbols[sym].unit;
        let saved = (self.cur_func, std::mem::take(&mut self.cur_asm), std::mem::take(&mut self.labels), self.cur_result.take());
        self.cur_func = Some(id);
        self.cur_asm = asm.clone();
        self.cur_result = result.map(|v| (v, r.name.key()));
        let mut body = Vec::new();
        for d in &r.body.decls {
            self.decl(d, ui, &mut body);
        }
        let mut rest = self.block(&r.body.stmts, ui);
        body.append(&mut rest);
        let mut entry = self.entry_clears(id, &body, r.name.span);
        entry.append(&mut body);
        let mut body = entry;
        body.push(S { st: St::Return, span: r.name.span });
        self.funcs[id] = Some(Func { asm, name: r.name.name.clone(), params, result, body, span: r.name.span });
        self.cur_func = saved.0;
        self.cur_asm = saved.1;
        self.labels = saved.2;
        self.cur_result = saved.3;
    }

    /// Statements that zero the routine's locals and `Result` on entry. Frames are overlaid, so
    /// storage holds whatever another routine left there; a variable is zero at every entry
    /// unless the body provably writes it first (LANGUAGE.md §4).
    fn entry_clears(&self, id: FuncId, body: &[S], span: Span) -> Vec<S> {
        let mut out = Vec::new();
        for (v, var) in self.vars.iter().enumerate() {
            if var.owner != Some(id) || !matches!(var.kind, VarKind::Local | VarKind::Result) {
                continue;
            }
            let ty = var.ty.clone();
            let scalar = nat(&ty).is_some();
            if (scalar || matches!(ty, Ty::Str(_))) && written_first(body, v) {
                continue;
            }
            if var.kind == VarKind::Local && !mentions(body, v) {
                continue;
            }
            let place = |off: u32, ty: Ty| Place { base: Base::Var(v), off, bit: None, idx: None, ty };
            if scalar {
                out.push(S { st: St::Clear(place(0, ty)), span });
            } else if matches!(ty, Ty::Str(_)) {
                // The text is empty once its first byte is Null.
                out.push(S { st: St::Assign(place(0, Ty::Char), Ex::konst(0, 8, false)), span });
            } else {
                let mut off = 0;
                while off < var.bytes {
                    let n = (var.bytes - off).min(255);
                    out.push(S { st: St::ClearMem(place(off, ty.clone()), n), span });
                    off += n;
                }
            }
        }
        out
    }

    // ---- places --------------------------------------------------------------------------

    fn var_place(&mut self, sym: usize, span: Span) -> Option<Place> {
        if let Some(&v) = self.sym_var.get(&sym) {
            if self.vars[v].by_ref {
                return Some(Place { base: Base::Ptr(v), off: 0, bit: None, idx: None, ty: self.vars[v].ty.clone() });
            }
            return Some(Place { base: Base::Var(v), off: 0, bit: None, idx: None, ty: self.vars[v].ty.clone() });
        }
        if let Some(p) = self.sym_alias.get(&sym) {
            return Some(p.clone());
        }
        let name = self.a.symbols[sym].name.clone();
        match self.unsupported.get(&sym).cloned() {
            Some(what) => self.unsupported(span, &format!("`{name}` ({what})")),
            None => self.unsupported(span, &format!("`{name}`")),
        }
        None
    }

    fn reg_place(&mut self, name: &str, span: Span) -> Option<Place> {
        let dev = self.a.device.as_ref()?;
        if let Some(s) = dev.find_sfr(name) {
            if s.width > 8 {
                self.unsupported(span, &format!("the {}-bit register `{}`", s.width, s.name));
                return None;
            }
            return Some(Place { base: Base::Abs { addr: s.addr, name: s.name.clone() }, off: 0, bit: None, idx: None, ty: BYTE });
        }
        if let Some(j) = dev.joined.iter().find(|j| j.name.eq_ignore_ascii_case(name)) {
            let ty = match j.bytes {
                1 => BYTE,
                2 => WORD,
                4 => LONGWORD,
                n => {
                    self.unsupported(span, &format!("the {n}-byte register `{}`", j.name));
                    return None;
                }
            };
            return Some(Place { base: Base::Abs { addr: j.addr, name: j.name.clone() }, off: 0, bit: None, idx: None, ty });
        }
        None
    }

    /// The place a designator names, or None after reporting why not. Elements picked by a
    /// run-time index are only accepted by `place_idx_of`.
    pub fn place_of(&mut self, d: &'a Designator) -> Option<Place> {
        let p = self.place_idx_of(d)?;
        if p.indirect() {
            self.unsupported(d.span, "an array element or ByRef parameter here");
            return None;
        }
        Some(p)
    }

    pub fn place_idx_of(&mut self, d: &'a Designator) -> Option<Place> {
        let before = self.diags.error_count();
        let p = self.place_inner(d);
        if p.is_none() && self.diags.error_count() == before {
            self.unsupported(d.span, &format!("`{}` here", d.head.name));
        }
        if let Some(pl) = &p
            && pl.bit.is_some()
            && pl.indirect()
        {
            self.unsupported(d.span, "a bit of an array element or ByRef parameter");
            return None;
        }
        p
    }

    fn place_inner(&mut self, d: &'a Designator) -> Option<Place> {
        let mut i = 0;
        let place = match self.a.resolved.get(&d.id).cloned() {
            Some(Res::Sym(id)) => self.var_place(id, d.head.span)?,
            Some(Res::Register(name)) => self.reg_place(&name, d.head.span)?,
            Some(Res::Module(u)) => {
                let Some(Part::Member(n)) = d.parts.first() else { return None };
                let id = *self.unit_syms.get(&(u, n.key()))?;
                i = 1;
                self.var_place(id, n.span)?
            }
            Some(Res::Intrinsic(_)) => {
                self.unsupported(d.span, "this use of an intrinsic");
                return None;
            }
            None => {
                // `Result`, or the function's own name used as its result.
                let (v, key) = self.cur_result.clone()?;
                if d.head.key() != "result" && d.head.key() != key {
                    self.unsupported(d.span, &format!("`{}`", d.head.name));
                    return None;
                }
                Place { base: Base::Var(v), off: 0, bit: None, idx: None, ty: self.vars[v].ty.clone() }
            }
        };
        self.apply_parts(place, &d.parts, i, d.span)
    }

    /// Follows `parts[i..]` (members, bit numbers, indices) from `place`.
    fn apply_parts(&mut self, mut place: Place, parts: &'a [Part], mut i: usize, span: Span) -> Option<Place> {
        while i < parts.len() {
            match &parts[i] {
                Part::BitIndex(n, _) => {
                    if place.idx.is_some() {
                        self.unsupported(span, "a bit of an array element");
                        return None;
                    }
                    place.off += (*n / 8) as u32;
                    place.bit = Some((*n % 8) as u8);
                    place.ty = Ty::Bit;
                }
                Part::Member(n) => {
                    let key = n.key();
                    if let Ty::Struct(sid) = place.ty {
                        let Some(lay) = self.layout(sid) else {
                            self.unsupported(n.span, &format!("the structure layout needed for `{}`", n.name));
                            return None;
                        };
                        let Some(f) = lay.iter().find(|f| f.name == key) else {
                            self.unsupported(n.span, &format!("the member `{}`", n.name));
                            return None;
                        };
                        place.off += f.off;
                        place.ty = f.ty.clone();
                        if f.bit.is_some() {
                            place.bit = f.bit;
                        }
                        i += 1;
                        continue;
                    }
                    // A named bit field of a device register.
                    if let Base::Abs { name, .. } = &place.base
                        && place.off == 0
                        && place.bit.is_none()
                        && let Some(s) = self.a.device.as_ref().and_then(|dv| dv.find_sfr(name))
                        && let Some(f) = s.fields.iter().chain(s.legacy.iter()).find(|f| f.name.eq_ignore_ascii_case(&key))
                    {
                        if f.width != 1 {
                            self.unsupported(n.span, &format!("the multi-bit field `{}`", n.name));
                            return None;
                        }
                        place.bit = Some(f.pos);
                        place.ty = Ty::Bit;
                        i += 1;
                        continue;
                    }
                    if let Some(num) = key.strip_prefix("byte").and_then(|s| s.parse::<u32>().ok()) {
                        place.off += num;
                        place.ty = BYTE;
                    } else if let Some(num) = key.strip_prefix("word").and_then(|s| s.parse::<u32>().ok()) {
                        place.off += num * 2;
                        place.ty = WORD;
                    } else {
                        match key.as_str() {
                            "bytes" | "words" | "bits" | "booleans" => {
                                let Some(Part::Args(args, _)) = parts.get(i + 1) else { return None };
                                let Some(CVal::Int(c)) = args.first().and_then(|e| self.a.consts.get(&e.id)) else { return None };
                                let c = *c as u32;
                                i += 1;
                                match key.as_str() {
                                    "bytes" => {
                                        place.off += c;
                                        place.ty = BYTE;
                                    }
                                    "words" => {
                                        place.off += c * 2;
                                        place.ty = WORD;
                                    }
                                    _ => {
                                        place.off += c / 8;
                                        place.bit = Some((c % 8) as u8);
                                        place.ty = if key == "bits" { Ty::Bit } else { Ty::Bool };
                                    }
                                }
                            }
                            "asbyte" => place.ty = BYTE,
                            "asshortint" => place.ty = SHORTINT,
                            "asword" => place.ty = WORD,
                            "asinteger" => place.ty = INTEGER,
                            "aslongword" => place.ty = LONGWORD,
                            "aslongint" => place.ty = LONGINT,
                            _ => {
                                self.unsupported(n.span, &format!("the member `{}`", n.name));
                                return None;
                            }
                        }
                    }
                }
                Part::Args(args, sp) => {
                    // A string is indexed like an array of Char with room for the Null.
                    let (elem, n) = match place.ty.clone() {
                        Ty::Array(elem, n) => (elem, n),
                        Ty::Str(n) => (Box::new(Ty::Char), n + 1),
                        _ => {
                            self.unsupported(*sp, "indexing this");
                            return None;
                        }
                    };
                    if place.bit.is_some() || args.len() != 1 {
                        self.unsupported(*sp, "this array access");
                        return None;
                    }
                    let size = self.size_of(&elem);
                    if let Some(CVal::Int(c)) = self.a.consts.get(&args[0].id) {
                        if *c < 0 || (n > 0 && *c >= n as i128) {
                            self.err("E-BOUNDS", args[0].span, format!("index {c} is outside the array (0 to {})", n.saturating_sub(1)));
                            return None;
                        }
                        place.off += *c as u32 * size;
                    } else {
                        let ix = self.expr(&args[0])?;
                        let ix = conv(ix, 16, false);
                        let off = match size {
                            1 => ix,
                            s if s.is_power_of_two() => Ex::new(ExK::Bin(BinKind::Shl, Box::new(ix), Box::new(Ex::konst(s.trailing_zeros(), 8, false))), 16, false),
                            s => Ex::new(ExK::Bin(BinKind::Mul, Box::new(ix), Box::new(Ex::konst(s, 16, false))), 16, false),
                        };
                        // A second run-time index (a field array of an array element) adds up.
                        place.idx = Some(Box::new(match place.idx.take() {
                            Some(prev) => Ex::new(ExK::Bin(BinKind::Add, prev, Box::new(off)), 16, false),
                            None => off,
                        }));
                    }
                    place.ty = *elem;
                }
            }
            i += 1;
        }
        Some(place)
    }

    // ---- expressions ---------------------------------------------------------------------

    fn const_ex(&mut self, e: &Expr, c: &CVal) -> Option<Ex> {
        let ty = self.a.types.get(&e.id).cloned().unwrap_or(BYTE);
        let (w, s) = match nat(&ty) {
            Some(x) => x,
            None => match c {
                // A one-character string constant is a Char.
                CVal::Str(st) if st.len() == 1 => (8, false),
                _ => {
                    self.unsupported(e.span, &format!("a constant of type {ty}"));
                    return None;
                }
            },
        };
        let v = match c {
            CVal::Int(i) => *i as u32,
            CVal::Bool(b) => *b as u32,
            CVal::Str(st) if st.len() == 1 => st.as_bytes()[0] as u32,
            _ => {
                self.unsupported(e.span, "this constant");
                return None;
            }
        };
        Some(Ex::konst(v, w, s))
    }

    /// Applies the evaluation width the semantic pass chose for the node.
    fn widen(&self, e: &Expr, ex: Ex) -> Ex {
        match self.a.widths.get(&e.id) {
            Some(&w) if w != ex.w && w >= ex.w => {
                let sg = ex.signed;
                conv(ex, w, sg)
            }
            _ => ex,
        }
    }

    pub fn expr(&mut self, e: &'a Expr) -> Option<Ex> {
        if let Some(c) = self.a.consts.get(&e.id) {
            let ex = self.const_ex(e, c)?;
            return Some(self.widen(e, ex));
        }
        let ty = self.a.types.get(&e.id).cloned().unwrap_or(BYTE);
        let Some((nw, ns)) = nat(&ty) else {
            self.unsupported(e.span, &format!("an expression of type {ty}"));
            return None;
        };
        let w = self.a.widths.get(&e.id).copied().unwrap_or(nw).max(nw);
        match &e.kind {
            ExprKind::Designator(d) => {
                let ex = self.designator_value(d, e)?;
                Some(self.widen(e, ex))
            }
            ExprKind::Unary(op, x) => {
                let xv = self.expr(x)?;
                let ex = match op {
                    UnOp::Plus => conv(xv, w, ns),
                    UnOp::Neg => Ex::new(ExK::Neg(Box::new(conv(xv, w, ns))), w, ns),
                    UnOp::Not => match ty {
                        Ty::Bool => Ex::boolean(ExK::NotB(Box::new(xv))),
                        Ty::Bit => Ex::new(ExK::Bin(BinKind::Xor, Box::new(xv), Box::new(Ex::konst(1, 8, false))), 8, false),
                        _ => Ex::new(ExK::Com(Box::new(conv(xv, w, ns))), w, ns),
                    },
                    UnOp::AddressOf => {
                        self.unsupported(e.span, "`@` (address of)");
                        return None;
                    }
                };
                Some(ex)
            }
            ExprKind::Binary(op, l, r) => {
                if matches!(op, BinOp::Eq | BinOp::Ne) && matches!(self.a.types.get(&l.id), Some(Ty::Str(_))) && matches!(self.a.types.get(&r.id), Some(Ty::Str(_))) {
                    return self.str_compare(*op, l, r, e);
                }
                let lv = self.expr(l)?;
                let rv = self.expr(r)?;
                self.binary(*op, lv, rv, &ty, w, ns, e)
            }
            _ => {
                self.unsupported(e.span, "this expression");
                None
            }
        }
    }

    #[allow(clippy::too_many_arguments)]
    fn binary(&mut self, op: BinOp, lv: Ex, rv: Ex, ty: &Ty, w: u8, ns: bool, e: &Expr) -> Option<Ex> {
        if op.is_relational() {
            let kind = match op {
                BinOp::Eq => CmpKind::Eq,
                BinOp::Ne => CmpKind::Ne,
                BinOp::Lt => CmpKind::Lt,
                BinOp::Gt => CmpKind::Gt,
                BinOp::Le => CmpKind::Le,
                _ => CmpKind::Ge,
            };
            let cw = lv.w.max(rv.w);
            let sg = lv.signed || rv.signed;
            return Some(Ex::boolean(ExK::Cmp(kind, Box::new(conv(lv, cw, sg)), Box::new(conv(rv, cw, sg)))));
        }
        if *ty == Ty::Bool {
            return Some(match op {
                BinOp::And => Ex::boolean(ExK::AndAlso(Box::new(lv), Box::new(rv))),
                BinOp::Or => Ex::boolean(ExK::OrElse(Box::new(lv), Box::new(rv))),
                _ => Ex::boolean(ExK::Bin(BinKind::Xor, Box::new(lv), Box::new(rv))),
            });
        }
        let kind = match op {
            BinOp::Add => BinKind::Add,
            BinOp::Sub => BinKind::Sub,
            BinOp::Mul => BinKind::Mul,
            BinOp::Div => BinKind::Div,
            BinOp::Mod => BinKind::Mod,
            BinOp::And => BinKind::And,
            BinOp::Or => BinKind::Or,
            BinOp::Xor => BinKind::Xor,
            BinOp::Shl => BinKind::Shl,
            BinOp::Shr => BinKind::Shr,
            _ => {
                self.unsupported(e.span, "this operator");
                return None;
            }
        };
        let l = conv(lv, w, ns);
        let r = if matches!(kind, BinKind::Shl | BinKind::Shr) { conv(rv, 8, false) } else { conv(rv, w, ns) };
        // Unsigned division and remainder by a power of two are a shift and a mask.
        if !ns && let Some(c) = r.as_const() {
            if kind == BinKind::Div && c.is_power_of_two() {
                return Some(Ex::new(ExK::Bin(BinKind::Shr, Box::new(l), Box::new(Ex::konst(c.trailing_zeros(), 8, false))), w, ns));
            }
            if kind == BinKind::Mod && c.is_power_of_two() {
                return Some(Ex::new(ExK::Bin(BinKind::And, Box::new(l), Box::new(Ex::konst(c - 1, w, ns))), w, ns));
            }
        }
        Some(Ex::new(ExK::Bin(kind, Box::new(l), Box::new(r)), w, ns))
    }

    /// The routine a designator calls, with its argument list, when it is a call.
    fn callee_of(&self, d: &'a Designator) -> Option<(usize, &'a [Expr], Span)> {
        let (sym, next) = match self.a.resolved.get(&d.id)? {
            // `Module.Routine(...)` is resolved to the routine itself; the member name stays in `parts`.
            Res::Sym(id) if matches!(self.a.symbols[*id].kind, SymKind::Routine { .. }) => (*id, usize::from(matches!(d.parts.first(), Some(Part::Member(_))))),
            Res::Module(u) => {
                let Some(Part::Member(n)) = d.parts.first() else { return None };
                let id = *self.unit_syms.get(&(*u, n.key()))?;
                if !matches!(self.a.symbols[id].kind, SymKind::Routine { .. }) {
                    return None;
                }
                (id, 1)
            }
            _ => return None,
        };
        match d.parts.get(next) {
            Some(Part::Args(args, sp)) => Some((sym, args.as_slice(), *sp)),
            None => Some((sym, &[], d.span)),
            _ => None,
        }
    }

    fn call(&mut self, sym: usize, args: &'a [Expr], span: Span) -> Option<(FuncId, Vec<(Place, Ex)>)> {
        let id = self.func_of(sym, span)?;
        let params: Vec<(VarId, Option<Ex>)> = self.sym_func[&sym].params.clone();
        let nparams = match &self.a.symbols[sym].kind {
            SymKind::Routine { params, .. } => params.len(),
            _ => 0,
        };
        if params.len() != nparams {
            // A parameter the back end rejected has already been reported.
            return None;
        }
        let mut out = Vec::new();
        for (i, (pv, def)) in params.iter().enumerate() {
            let mut pty = self.vars[*pv].ty.clone();
            let ex = if self.vars[*pv].by_ref {
                pty = WORD;
                let literal = match args.get(i).and_then(|a| self.a.consts.get(&a.id)) {
                    Some(CVal::Str(t)) if matches!(self.vars[*pv].ty, Ty::Str(_)) => Some(t.bytes().take_while(|&b| b != 0).collect::<Vec<u8>>()),
                    _ => None,
                };
                let pl = if let Some(bytes) = literal {
                    if bytes.len() > 255 {
                        self.unsupported(span, "a string literal longer than 255 characters");
                        return None;
                    }
                    self.lit_place(bytes, span)
                } else {
                    let Some(Expr { kind: ExprKind::Designator(dd), .. }) = args.get(i) else {
                        self.unsupported(span, "this ByRef argument");
                        return None;
                    };
                    let pl = self.place_idx_of(dd)?;
                    if pl.bit.is_some() {
                        self.unsupported(dd.span, "a bit passed ByRef");
                        return None;
                    }
                    pl
                };
                Ex::new(ExK::Addr(pl), 16, false)
            } else {
                let (w, s) = nat(&pty).unwrap();
                match args.get(i) {
                    Some(a) => conv(self.expr(a)?, w, s),
                    None => def.clone()?,
                }
            };
            out.push((Place { base: Base::Var(*pv), off: 0, bit: None, idx: None, ty: pty }, ex));
        }
        Some((id, out))
    }

    fn designator_value(&mut self, d: &'a Designator, e: &'a Expr) -> Option<Ex> {
        if let Some((sym, args, sp)) = self.callee_of(d) {
            let (id, args) = self.call(sym, args, sp)?;
            let fi = &self.sym_func[&sym];
            let Some(rv) = fi.result else {
                self.err("E-BACKEND", e.span, "a subroutine has no value");
                return None;
            };
            let (w, s) = nat(&self.vars[rv].ty).unwrap();
            let boolean = self.vars[rv].ty == Ty::Bool;
            let _ = boolean;
            return Some(Ex::new(ExK::Call(id, args), w, s));
        }
        if let Some(Res::Intrinsic(name)) = self.a.resolved.get(&d.id).cloned() {
            return self.intrinsic_value(&name, d, e);
        }
        let place = self.place_idx_of(d)?;
        let Some((w, s)) = nat(&place.ty) else {
            self.unsupported(d.span, &format!("a value of type {}", place.ty));
            return None;
        };
        Some(Ex::new(ExK::Load(place), w, s))
    }

    fn intrinsic_value(&mut self, name: &str, d: &'a Designator, e: &'a Expr) -> Option<Ex> {
        let args: &[Expr] = match d.parts.first() {
            Some(Part::Args(a, _)) => a,
            _ => &[],
        };
        let ty = self.a.types.get(&e.id).cloned().unwrap_or(BYTE);
        match name {
            "byte" | "word" | "integer" | "longword" | "longint" | "shortint" | "char" => {
                let (w, s) = nat(&ty)?;
                let x = self.expr(&args[0])?;
                Some(conv(x, w, s))
            }
            "boolean" | "bit" => {
                let x = self.expr(&args[0])?;
                let argty = self.a.types.get(&args[0].id).cloned().unwrap_or(BYTE);
                if matches!(argty, Ty::Bool | Ty::Bit) {
                    return Some(Ex { signed: false, ..x });
                }
                if name == "bit" {
                    self.unsupported(e.span, "converting a number to Bit");
                    return None;
                }
                let zero = Ex::konst(0, x.w, x.signed);
                Some(Ex::boolean(ExK::Cmp(CmpKind::Ne, Box::new(x), Box::new(zero))))
            }
            n => {
                self.unsupported(e.span, &format!("the intrinsic `{n}`"));
                None
            }
        }
    }

    // ---- strings -------------------------------------------------------------------------

    /// The pieces a String expression is made of: literals, String variables and Chars joined by `+`.
    fn str_parts(&mut self, e: &'a Expr, out: &mut Vec<StrSrc>) -> Option<()> {
        let ty = self.a.types.get(&e.id).cloned();
        if let Some(c) = self.a.consts.get(&e.id) {
            let bytes: Vec<u8> = match c {
                CVal::Str(t) => t.bytes().take_while(|&b| b != 0).collect(),
                CVal::Int(i) if ty == Some(Ty::Char) => vec![*i as u8].into_iter().filter(|&b| b != 0).collect(),
                _ => {
                    self.unsupported(e.span, "this string constant");
                    return None;
                }
            };
            if !bytes.is_empty() {
                out.push(StrSrc::Lit(bytes));
            }
            return Some(());
        }
        match (&e.kind, ty) {
            (ExprKind::Binary(BinOp::Add, l, r), Some(Ty::Str(_))) => {
                self.str_parts(l, out)?;
                self.str_parts(r, out)
            }
            (ExprKind::Designator(d), Some(Ty::Str(_))) => {
                let p = self.place_idx_of(d)?;
                if p.idx.is_some() || p.bit.is_some() {
                    self.unsupported(d.span, "this string");
                    return None;
                }
                out.push(StrSrc::Ram(p));
                Some(())
            }
            (_, Some(Ty::Char)) => {
                let x = self.expr(e)?;
                out.push(StrSrc::Char(Box::new(conv(x, 8, false))));
                Some(())
            }
            _ => {
                self.unsupported(e.span, "this string expression");
                None
            }
        }
    }

    /// Size of a whole structure or array that is cleared or copied, if the back end can do it.
    fn block_bytes(&mut self, p: &Place, span: Span, what: &str) -> Option<u32> {
        let bytes = self.size_of(&p.ty);
        if bytes == 0 || bytes > 255 {
            self.unsupported(span, &format!("{what} of a {bytes}-byte {} (1 to 255 bytes are handled)", p.ty));
            return None;
        }
        if p.bit.is_some() || p.idx.as_ref().is_some_and(|i| i.has_call()) {
            self.unsupported(span, &format!("{what} of this place"));
            return None;
        }
        Some(bytes)
    }

    /// `a = b` for two structures (or two arrays) of one type: a block copy.
    fn copy_assign(&mut self, dst: Place, value: &'a Expr, span: Span, out: &mut Vec<S>) {
        let ExprKind::Designator(d) = &value.kind else {
            self.unsupported(span, "this structure or array value");
            return;
        };
        let Some(src) = self.place_idx_of(d) else { return };
        let Some(bytes) = self.block_bytes(&dst, span, "assigning") else { return };
        if self.size_of(&dst.ty) != self.size_of(&src.ty) {
            self.unsupported(span, "assigning between arrays of different sizes");
            return;
        }
        if self.block_bytes(&src, span, "assigning").is_none() {
            return;
        }
        Self::push(out, St::Copy { dst, src, bytes }, span);
    }

    fn str_assign(&mut self, dst: Place, cap: u32, value: &'a Expr, span: Span, out: &mut Vec<S>) {
        if dst.idx.is_some() {
            self.unsupported(span, "assigning to a String field of an array element picked at run time");
            return;
        }
        let mut parts = Vec::new();
        if self.str_parts(value, &mut parts).is_none() {
            return;
        }
        // `s = s + x` appends in place. The target anywhere else on the right would be
        // overwritten before it is read.
        let same = |p: &StrSrc| matches!(p, StrSrc::Ram(q) if q.base == dst.base && q.off == dst.off);
        let keep = parts.first().is_some_and(same);
        if parts.iter().skip(1).any(same) {
            self.unsupported(span, "a String that is also read after its first operand on the right of its own assignment");
            return;
        }
        Self::push(out, St::StrSet { dst, cap, parts, keep }, span);
    }

    fn str_compare(&mut self, op: BinOp, l: &'a Expr, r: &'a Expr, e: &Expr) -> Option<Ex> {
        let (mut lp, mut rp) = (Vec::new(), Vec::new());
        self.str_parts(l, &mut lp)?;
        self.str_parts(r, &mut rp)?;
        // An empty literal compares as the Null string; a single part is needed on each side.
        let one = |v: Vec<StrSrc>| match v.len() {
            0 => Some(StrSrc::Lit(Vec::new())),
            1 => v.into_iter().next(),
            _ => None,
        };
        let (Some(a), Some(b)) = (one(lp), one(rp)) else {
            self.unsupported(e.span, "comparing a concatenation");
            return None;
        };
        let (a, b) = match (a, b) {
            (a @ StrSrc::Ram(_), b @ (StrSrc::Ram(_) | StrSrc::Lit(_))) => (a, b),
            (a @ StrSrc::Lit(_), b @ StrSrc::Ram(_)) => (b, a),
            _ => {
                self.unsupported(e.span, "this string comparison");
                return None;
            }
        };
        let eq = Ex::boolean(ExK::StrEq(a, b));
        Some(if op == BinOp::Ne { Ex::boolean(ExK::NotB(Box::new(eq))) } else { eq })
    }

    /// A static RAM copy of a string literal, filled at start-up, for a `ByRefConst` argument.
    fn lit_place(&mut self, bytes: Vec<u8>, span: Span) -> Place {
        let len = bytes.len() as u32;
        let ty = Ty::Str(len);
        let v = match self.lits.get(&bytes) {
            Some(&v) => v,
            None => {
                let saved = self.cur_func.take();
                let v = self.new_var(format!("__STRLIT{}", self.lits.len()), "(string literal)", ty.clone(), VarKind::Hidden, None);
                self.cur_func = saved;
                self.lits.insert(bytes.clone(), v);
                if !bytes.is_empty() {
                    let dst = Place { base: Base::Var(v), off: 0, bit: None, idx: None, ty: ty.clone() };
                    self.startup.push(S { st: St::StrSet { dst, cap: len, parts: vec![StrSrc::Lit(bytes)], keep: false }, span });
                }
                v
            }
        };
        Place { base: Base::Var(v), off: 0, bit: None, idx: None, ty }
    }

    // ---- statements ----------------------------------------------------------------------

    fn label_id(&mut self, name: &Ident) -> LabelId {
        let key = name.key();
        if let Some(&l) = self.labels.get(&key) {
            return l;
        }
        let id = self.label_names.len();
        self.label_names.push(format!("L_{}_{}", id, sanitize(&name.name)));
        self.labels.insert(key, id);
        id
    }

    pub fn block(&mut self, ss: &'a [Stmt], ui: usize) -> Vec<S> {
        let mut out = Vec::new();
        for s in ss {
            self.stmt(s, ui, &mut out);
        }
        out
    }

    fn push(out: &mut Vec<S>, st: St, span: Span) {
        out.push(S { st, span });
    }

    fn stmt(&mut self, s: &'a Stmt, ui: usize, out: &mut Vec<S>) {
        let span = s.span;
        match &s.kind {
            StmtKind::Assign { target, value } => {
                let Some(p) = self.place_idx_of(target) else { return };
                if let Ty::Str(cap) = p.ty {
                    self.str_assign(p, cap, value, span, out);
                    return;
                }
                if matches!(p.ty, Ty::Struct(_) | Ty::Array(..)) {
                    self.copy_assign(p, value, span, out);
                    return;
                }
                let Some(v) = self.expr(value) else { return };
                let Some((w, sg)) = nat(&p.ty) else {
                    self.unsupported(target.span, &format!("assigning a {}", p.ty));
                    return;
                };
                let v = conv(v, w, sg);
                Self::push(out, St::Assign(p, v), span);
            }
            StmtKind::Call(d) => self.call_stmt(d, span, out),
            StmtKind::If { arms, otherwise } => {
                let mut a = Vec::new();
                for (c, b) in arms {
                    let Some(cv) = self.expr(c) else { return };
                    a.push((cv, self.block(b, ui)));
                }
                let o = otherwise.as_ref().map(|b| self.block(b, ui)).unwrap_or_default();
                Self::push(out, St::If(a, o), span);
            }
            StmtKind::IfGoto { cond, label } => {
                let Some(cv) = self.expr(cond) else { return };
                let l = self.label_id(label);
                Self::push(out, St::If(vec![(cv, vec![S { st: St::Goto(l), span }])], vec![]), span);
            }
            StmtKind::Select { subject, cases, otherwise } => self.select(subject, cases, otherwise.as_deref(), ui, span, out),
            StmtKind::While { cond, body } => {
                let Some(cv) = self.expr(cond) else { return };
                let b = self.block(body, ui);
                Self::push(out, St::While(cv, b), span);
            }
            StmtKind::Repeat { body, until } => {
                let b = self.block(body, ui);
                let Some(cv) = self.expr(until) else { return };
                Self::push(out, St::Repeat(b, cv), span);
            }
            StmtKind::For { var, from, to, step, body } => self.for_stmt(var, from, to, step.as_ref(), body, ui, span, out),
            StmtKind::Break => Self::push(out, St::Break, span),
            StmtKind::Continue => Self::push(out, St::Continue, span),
            StmtKind::Exit => Self::push(out, St::Return, span),
            StmtKind::GoTo(l) if self.in_save > 0 => self.unsupported(l.span, "Goto inside Save"),
            StmtKind::Label(l) if self.in_save > 0 => self.unsupported(l.span, "a label inside Save"),
            StmtKind::GoTo(l) => {
                let id = self.label_id(l);
                Self::push(out, St::Goto(id), span);
            }
            StmtKind::Label(l) => {
                let id = self.label_id(l);
                Self::push(out, St::Label(id), span);
            }
            StmtKind::Save { items, body } => {
                let mut its = Vec::new();
                for it in items {
                    match it {
                        SaveItem::Int(..) => its.push(SaveIt::Regs),
                        SaveItem::Designator(d) => {
                            if let Some((sym, _, sp)) = self.callee_of(d) {
                                if let Some(f) = self.func_of(sym, sp) {
                                    its.push(SaveIt::Func(f));
                                }
                            } else if let Some(p) = self.place_of(d) {
                                match p.base {
                                    Base::Var(v) if !p.indirect() => its.push(SaveIt::Var(v)),
                                    _ => self.unsupported(d.span, "this item in Save (only variables, routines and 0)"),
                                }
                            }
                        }
                    }
                }
                let id = self.n_saves;
                self.n_saves += 1;
                self.in_save += 1;
                let b = self.block(body, ui);
                self.in_save -= 1;
                Self::push(out, St::Save { id, items: its, body: b }, span);
            }
            StmtKind::Asm { lines, .. } => Self::push(out, St::Asm(lines.clone()), span),
            StmtKind::Enable(n) | StmtKind::Disable(n) => {
                let on = matches!(s.kind, StmtKind::Enable(_));
                match self.a.enables.get(&n.span).map(|&sym| &self.a.symbols[sym].kind) {
                    Some(SymKind::Interrupt { priority }) => Self::push(out, St::Int { level: level_of(priority), on }, span),
                    _ => self.err("E-ENABLE", n.span, format!("`{}` does not name an Interrupt", n.name)),
                }
            }
        }
    }

    fn call_stmt(&mut self, d: &'a Designator, span: Span, out: &mut Vec<S>) {
        if let Some((sym, args, sp)) = self.callee_of(d) {
            if let Some((id, a)) = self.call(sym, args, sp) {
                Self::push(out, St::Call(id, a), span);
            }
            return;
        }
        let Some(Res::Intrinsic(name)) = self.a.resolved.get(&d.id).cloned() else {
            self.unsupported(span, "this statement");
            return;
        };
        let args: &'a [Expr] = match d.parts.first() {
            Some(Part::Args(a, _)) => a,
            _ => &[],
        };
        // The first argument as a place, for the intrinsics that act on one.
        let arg_place = |this: &mut Self| -> Option<Place> {
            match args.first().map(|a| &a.kind) {
                Some(ExprKind::Designator(dd)) => {
                    if matches!(name.as_str(), "inc" | "dec" | "clear") {
                        this.place_idx_of(dd)
                    } else {
                        this.place_of(dd)
                    }
                }
                _ => None,
            }
        };
        match name.as_str() {
            "inc" | "dec" => {
                let Some(p) = arg_place(self) else { return };
                let delta = if name == "inc" { 1u32 } else { u32::MAX };
                if p.indirect() {
                    // The index is evaluated twice, so it must not contain a call.
                    let Some((w, sg)) = nat(&p.ty) else { return };
                    if p.idx.as_ref().is_some_and(|i| i.has_call()) {
                        self.unsupported(span, "a call inside the index of Inc/Dec");
                        return;
                    }
                    let load = Ex::new(ExK::Load(p.clone()), w, sg);
                    let sum = Ex::new(ExK::Bin(BinKind::Add, Box::new(load), Box::new(Ex::konst(delta, w, sg))), w, sg);
                    Self::push(out, St::Assign(p, sum), span);
                } else {
                    Self::push(out, St::Add(p, delta), span);
                }
            }
            "clear" => {
                let Some(p) = arg_place(self) else { return };
                match nat(&p.ty) {
                    None if matches!(p.ty, Ty::Str(_)) => {
                        // The text is empty once its first byte is Null.
                        let first = Place { ty: Ty::Char, ..p };
                        Self::push(out, St::Assign(first, Ex::konst(0, 8, false)), span);
                    }
                    Some((w, sg)) if p.indirect() => Self::push(out, St::Assign(p, Ex::konst(0, w, sg)), span),
                    Some(_) => Self::push(out, St::Clear(p), span),
                    None if matches!(p.ty, Ty::Struct(_) | Ty::Array(..)) => {
                        let Some(bytes) = self.block_bytes(&p, span, "Clear") else { return };
                        Self::push(out, St::ClearMem(p, bytes), span);
                    }
                    None => self.unsupported(span, &format!("Clear of a {}", p.ty)),
                }
            }
            "high" | "low" | "toggle" => {
                let Some(p) = arg_place(self) else { return };
                if p.bit.is_some() {
                    let st = match name.as_str() {
                        "high" => St::SetBit(p, true),
                        "low" => St::SetBit(p, false),
                        _ => St::ToggleBit(p),
                    };
                    Self::push(out, st, span);
                } else {
                    // A Boolean or Bit variable holds 0 or 1 in a byte.
                    let v = match name.as_str() {
                        "high" => Ex::konst(1, 8, false),
                        "low" => Ex::konst(0, 8, false),
                        _ => Ex::new(ExK::Bin(BinKind::Xor, Box::new(Ex::new(ExK::Load(p.clone()), 8, false)), Box::new(Ex::konst(1, 8, false))), 8, false),
                    };
                    Self::push(out, St::Assign(p, v), span);
                }
            }
            "input" | "output" => {
                let Some(p) = arg_place(self) else { return };
                Self::push(out, St::Direction { place: p, output: name == "output" }, span);
            }
            "delayms" | "delayus" => {
                let Some(x) = self.expr(&args[0]) else { return };
                Self::push(out, if name == "delayms" { St::DelayMs(x) } else { St::DelayUs(x) }, span);
            }
            "terminate" => Self::push(out, St::Halt, span),
            n => self.unsupported(span, &format!("the intrinsic `{n}`")),
        }
    }

    #[allow(clippy::too_many_arguments)]
    fn for_stmt(&mut self, var: &'a Designator, from: &'a Expr, to: &'a Expr, step: Option<&'a Expr>, body: &'a [Stmt], ui: usize, span: Span, out: &mut Vec<S>) {
        let Some(vp) = self.place_of(var) else { return };
        let (w, sg) = nat(&vp.ty).unwrap();
        let step_v = match step {
            None => 1i64,
            Some(se) => match self.a.consts.get(&se.id) {
                Some(CVal::Int(i)) => *i as i64,
                _ => {
                    self.unsupported(se.span, "a For step that is not a constant");
                    return;
                }
            },
        };
        let (Some(f), Some(t)) = (self.expr(from), self.expr(to)) else { return };
        let (f, t) = (conv(f, w, sg), conv(t, w, sg));
        let limit = if t.as_const().is_some() {
            t
        } else {
            let h = self.hidden_var(vp.ty.clone());
            Self::push(out, St::Assign(h.clone(), t), span);
            Ex::new(ExK::Load(h), w, sg)
        };
        let b = self.block(body, ui);
        if let (Some(fv), Some(lv), Base::Var(vid), None, None) = (f.as_const(), limit.as_const(), &vp.base, &vp.idx, vp.bit) {
            let v = |x: u32| if sg { sign_extend(x, w) } else { x as i64 };
            let (fv, lv) = (v(fv), v(lv));
            let span_len = if step_v > 0 { lv - fv } else { fv - lv };
            let s = step_v.abs();
            let global = self.vars[*vid].kind == VarKind::Global;
            if step_v != 0 && span_len >= 0 && span_len / s < 255 {
                // The loop runs span_len / s + 1 times and ends with the last value it took.
                let n = span_len / s + 1;
                let last = fv + (n - 1) * step_v;
                let pure = !blocks_count_loop(&b, *vid, global, true);
                if pure || !blocks_count_loop(&b, *vid, global, false) {
                    let counter = self.hidden_var(crate::types::BYTE);
                    if pure {
                        Self::push(out, St::Count { counter, count: n as u8, body: b, step: None }, span);
                        Self::push(out, St::Assign(vp, Ex::konst(last as u32, w, sg)), span);
                    } else {
                        Self::push(out, St::Assign(vp.clone(), f), span);
                        Self::push(out, St::Count { counter, count: n as u8, body: b, step: Some((vp, step_v as u32)) }, span);
                    }
                    return;
                }
            }
        }
        Self::push(out, St::For { var: vp, from: f, limit, step: step_v, body: b }, span);
    }

    fn select(&mut self, subject: &'a Expr, cases: &'a [Case], otherwise: Option<&'a [Stmt]>, ui: usize, span: Span, out: &mut Vec<S>) {
        let Some(sv) = self.expr(subject) else { return };
        let (w, sg) = (sv.w, sv.signed);
        let sty = if sg { Ty::Int(w, true) } else { Ty::Int(w, false) };
        let h = self.hidden_var(sty);
        Self::push(out, St::Assign(h.clone(), sv), span);
        let load = |h: &Place| Ex::new(ExK::Load(h.clone()), w, sg);
        let cmp = |k: CmpKind, a: Ex, b: Ex| Ex::boolean(ExK::Cmp(k, Box::new(a), Box::new(b)));
        let mut arms = Vec::new();
        for c in cases {
            let mut cond: Option<Ex> = None;
            for cc in &c.conds {
                let one = match cc {
                    CaseCond::Value(e) => {
                        let Some(v) = self.expr(e) else { return };
                        cmp(CmpKind::Eq, load(&h), conv(v, w, sg))
                    }
                    CaseCond::Range(lo, hi) => {
                        let (Some(l), Some(u)) = (self.expr(lo), self.expr(hi)) else { return };
                        let a = cmp(CmpKind::Ge, load(&h), conv(l, w, sg));
                        let b = cmp(CmpKind::Le, load(&h), conv(u, w, sg));
                        Ex::boolean(ExK::AndAlso(Box::new(a), Box::new(b)))
                    }
                    CaseCond::Rel(op, e) => {
                        let Some(v) = self.expr(e) else { return };
                        let k = match op {
                            BinOp::Lt => CmpKind::Lt,
                            BinOp::Gt => CmpKind::Gt,
                            BinOp::Le => CmpKind::Le,
                            BinOp::Ge => CmpKind::Ge,
                            BinOp::Ne => CmpKind::Ne,
                            _ => CmpKind::Eq,
                        };
                        cmp(k, load(&h), conv(v, w, sg))
                    }
                };
                cond = Some(match cond {
                    None => one,
                    Some(prev) => Ex::boolean(ExK::OrElse(Box::new(prev), Box::new(one))),
                });
            }
            let Some(cond) = cond else { continue };
            arms.push((cond, self.block(&c.body, ui)));
        }
        let o = otherwise.map(|b| self.block(b, ui)).unwrap_or_default();
        Self::push(out, St::If(arms, o), span);
    }
}
