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
//! routines nobody calls (`Program::isrs`); `Save` and `Enable`/`Disable` become `St::Save`/`St::Int`. A Float is a
//! 32-bit pattern; its arithmetic, comparisons and conversions are calls into `lib/floatlib.bas`. Events
//! report `E-BACKEND`.

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
        Ty::Bool | Ty::Bit | Ty::Char | Ty::EventVar(_) | Ty::EventAny(_) => Some((8, false)),
        Ty::Int(w, s) => Some((*w, *s)),
        // A Float is held as its 32-bit pattern; the arithmetic is the FloatLib routines.
        Ty::Float => Some((32, false)),
        _ => None,
    }
}

/// The bits a constant stores as in an object of type `ty` (a Float is its binary32 pattern).
fn cval_for(c: &CVal, ty: &Ty) -> u32 {
    match (ty, c) {
        (Ty::Float, CVal::Float(f)) => (*f as f32).to_bits(),
        (Ty::Float, CVal::Int(i)) => (*i as f32).to_bits(),
        _ => cval_u32(c),
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

/// The shared routine that calls whichever handler an event variable holds: its first parameter is
/// the variable's value, the rest are the event's arguments.
struct EvDisp {
    sig: Vec<Ty>,
    id: FuncId,
    idv: VarId,
    pvs: Vec<VarId>,
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
    event_decls: HashMap<usize, &'a EventDecl>,
    /// Event handlers that are referenced, in order; an event variable holds the 1-based index (0 = none).
    event_order: Vec<usize>,
    /// The routines that call the handler an event variable holds, one per parameter list.
    event_disp: Vec<EvDisp>,
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
    /// Constant tables in program memory: `Const` arrays and array initialisers.
    flash: Vec<FlashObj>,
    /// The flash table of each `Const` array symbol.
    sym_flash: HashMap<usize, usize>,
    /// RAM copies of constant arrays passed to `ByRefConst` parameters (by flash table).
    flash_copies: HashMap<usize, VarId>,
    /// Array parameters whose run-time length (`Bound`) the routine reads.
    len_used: HashSet<VarId>,
    /// Bit and Boolean arrays stored eight elements to a byte (D47).
    packed: HashSet<VarId>,
    /// `(callee parameter, caller parameter)`: an array parameter passed on to another one.
    len_fwd: Vec<(VarId, VarId)>,
    isrs: Vec<(FuncId, Level)>,
    externs: Vec<ExternSig>,
    n_saves: usize,
    /// Nesting depth of `Save` blocks being lowered.
    in_save: u32,
    /// Lowering the body of an interrupt handler.
    in_isr: bool,
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
        event_decls: HashMap::new(),
        event_order: Vec::new(),
        event_disp: Vec::new(),
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
        flash: Vec::new(),
        sym_flash: HashMap::new(),
        flash_copies: HashMap::new(),
        len_used: HashSet::new(),
        packed: HashSet::new(),
        len_fwd: Vec::new(),
        isrs: Vec::new(),
        externs: Vec::new(),
        n_saves: 0,
        in_save: 0,
        in_isr: false,
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
            if let DeclKind::Event(e) = &d.kind
                && let Some(&sym) = a.decl_syms.get(&e.name.span)
            {
                lw.event_decls.insert(sym, e);
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
    lw.finish_event_dispatch();
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
        // Bits the pack's `implemented` mask leaves out stay at their unprogrammed value (1), as Microchip's
        // compiler writes them: on the PIC18-Q41 the mask omits DEBUG (CONFIG7 bit 5) and WRTAPP (CONFIG8
        // bit 7), which are real bits whose 0 means "debug mode" and "application block write-protected"
        // [DS40002214G 8.6 p.53, 8.1 p.43]; clearing them made self-writes to program flash fail.
        config.push((reg.name.clone(), reg.addr, v as u8));
    }

    let main = Func { asm: "__main".into(), name: "main".into(), params: vec![], result: None, body: main_body, span: Span::default() };
    let mut funcs: Vec<Func> = lw.funcs.into_iter().map(|f| f.expect("every queued routine is lowered")).collect();
    let mut main = main;
    strip_unused_lengths(&mut lw.vars, &lw.len_used, &lw.len_fwd, &mut funcs, &mut main);
    Some(Program {
        externs: lw.externs,
        cfiles: a.cfiles.clone(),
        vars: lw.vars,
        funcs,
        flash: lw.flash,
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
        self.err("E-BACKEND", span, format!("{what} is not supported by the back end yet (some array and by-reference forms and a few intrinsics are not implemented yet)"));
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
            let start = Place { base: Base::Abs { addr: 0, name: String::new() }, off: head.off, bit: head.bit, idx: None, dbit: None, ty: head.ty.clone() };
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
        self.vars.push(Var { asm, name: name.to_string(), ty, bytes, kind, owner: self.cur_func, init, by_ref: false, volatile: false });
        self.vars.len() - 1
    }

    /// A table in program memory holding `vals` as little-endian elements of `size` bytes.
    fn new_flash(&mut self, vals: &[u32], size: u32) -> usize {
        let mut bytes = Vec::new();
        for &v in vals {
            for i in 0..size {
                bytes.push((v >> (8 * i)) as u8);
            }
        }
        let asm = self.unique(format!("__CA{}", self.flash.len()));
        self.flash.push(FlashObj { asm, bytes });
        self.flash.len() - 1
    }

    /// The value of a constant-table element at a compile-time position, if `p` names one.
    fn flash_const(&self, p: &Place) -> Option<Ex> {
        let Base::Flash(f) = p.base else { return None };
        let (w, s) = nat(&p.ty)?;
        if p.idx.is_some() || p.bit.is_some() {
            return None;
        }
        let bytes = &self.flash[f].bytes;
        let mut v = 0u32;
        for i in 0..(w as usize / 8) {
            v |= (*bytes.get(p.off as usize + i)? as u32) << (8 * i);
        }
        Some(Ex::konst(v, w, s))
    }

    /// A RAM copy of a constant table, filled at start-up, for a `ByRefConst` argument.
    fn flash_copy(&mut self, f: usize, ty: &Ty, span: Span) -> Place {
        let v = match self.flash_copies.get(&f) {
            Some(&v) => v,
            None => {
                let saved = self.cur_func.take();
                let v = self.new_var(format!("__CACOPY{f}"), "(constant array)", ty.clone(), VarKind::Hidden, None);
                self.cur_func = saved;
                self.flash_copies.insert(f, v);
                let bytes = self.flash[f].bytes.len() as u32;
                let dst = Place { base: Base::Var(v), off: 0, bit: None, idx: None, dbit: None, ty: ty.clone() };
                let src = Place { base: Base::Flash(f), off: 0, bit: None, idx: None, dbit: None, ty: ty.clone() };
                self.startup.push(S { st: St::Copy { dst, src, bytes }, span });
                v
            }
        };
        Place { base: Base::Var(v), off: 0, bit: None, idx: None, dbit: None, ty: ty.clone() }
    }

    fn hidden_var(&mut self, ty: Ty) -> Place {
        self.hidden += 1;
        let asm = format!("{}__H{}", self.cur_asm, self.hidden);
        let v = self.new_var(asm, "(hidden)", ty.clone(), VarKind::Hidden, None);
        Place { base: Base::Var(v), off: 0, bit: None, idx: None, dbit: None, ty }
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
            DeclKind::Const(_) | DeclKind::Event(_) | DeclKind::Structure(_) | DeclKind::EventType(..) | DeclKind::Routine(_) => {}
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
        self.in_isr = true;
        let mut rest = self.block(&i.body.stmts, ui);
        self.in_isr = false;
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
        // A `Static` local is initialised once, before the main program, not at each entry.
        let mut once = Vec::new();
        let inits = if dim.is_static { &mut once } else { inits };
        for it in &dim.items {
            let Some(&sym) = self.a.decl_syms.get(&it.name.span) else { continue };
            match self.a.symbols[sym].kind.clone() {
                SymKind::Var { ty } => {
                    let array = match &ty {
                        Ty::Array(elem, _) => {
                            if nat(elem).is_none() && !matches!(**elem, Ty::Struct(_) | Ty::Str(_)) {
                                self.unsupported_sym(sym, &format!("an array of {elem}"));
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
                    let init = if string || array { None } else { init_e.and_then(|e| self.a.consts.get(&e.id)).map(|c| cval_for(c, &ty)) };
                    let init = init.map(|v| v & mask(nat(&ty).map_or(32, |t| t.0)));
                    let s = &self.a.symbols[sym];
                    let asm = if s.local { format!("{}__{}", self.cur_asm, sanitize(&s.name)) } else { format!("{}_{}", unit_prefix(self.proj, ui), sanitize(&s.name)) };
                    let name = s.name.clone();
                    let local = s.local;
                    // A `Static` local is a global with a local name: its own address, never
                    // overlaid, cleared and initialised once at start-up instead of at each entry.
                    let local = local && !dim.is_static;
                    let kind = if local { VarKind::Local } else { VarKind::Global };
                    let v = self.new_var(asm, &name, ty.clone(), kind, init.filter(|&i| i != 0 || local));
                    if !local {
                        self.vars[v].owner = None;
                    }
                    self.vars[v].volatile = dim.is_volatile;
                    self.sym_var.insert(sym, v);
                    if let Ty::Array(e, n) = &ty
                        && matches!(**e, Ty::Bit | Ty::Bool)
                        && !self.a.unpackable.contains(&sym)
                    {
                        self.packed.insert(v);
                        self.vars[v].bytes = n.div_ceil(8);
                    }
                    if let (Ty::Str(cap), Some(e)) = (&ty, init_e) {
                        let dst = Place { base: Base::Var(v), off: 0, bit: None, idx: None, dbit: None, ty: ty.clone() };
                        self.str_assign(dst, *cap, e, it.name.span, inits);
                    }
                    if let Ty::Struct(sid) = &ty {
                        let list: Vec<&'a Expr> = match (it.list.as_ref().or(dim.trailing_list.as_ref()), init_e) {
                            (Some(l), _) => l.iter().collect(),
                            (None, Some(e)) => vec![e],
                            _ => Vec::new(),
                        };
                        self.struct_init(v, *sid, &list, it.name.span, inits);
                    }
                    if let Ty::Array(elem, _) = &ty {
                        let list: Option<Vec<&'a Expr>> = match (it.list.as_ref().or(dim.trailing_list.as_ref()), init_e) {
                            (Some(l), _) => Some(l.iter().collect()),
                            (None, Some(e)) => Some(vec![e]),
                            _ => None,
                        };
                        if let Some(list) = list {
                            let vals: Vec<u32> = list.iter().map(|e| self.a.consts.get(&e.id).map(|c| cval_for(c, elem)).unwrap_or(0)).collect();
                            self.array_init(v, elem, &vals, it.name.span, inits);
                        }
                    }
                    if local && !array && !record && let Some(i) = init {
                        inits.push(S { st: St::Assign(Place { base: Base::Var(v), off: 0, bit: None, idx: None, dbit: None, ty: ty.clone() }, Ex::konst(i, nat(&ty).unwrap().0, nat(&ty).unwrap().1)), span: it.name.span });
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
        self.startup.append(&mut once);
    }

    /// Gives a freshly declared structure its initial values, field by field. Storage is zero
    /// already, so a zero is not stored.
    fn struct_init(&mut self, v: VarId, sid: usize, list: &[&'a Expr], span: Span, inits: &mut Vec<S>) {
        if list.is_empty() {
            return;
        }
        let Some(lay) = self.layout(sid) else { return };
        let SymKind::Struct { fields, .. } = self.a.symbols[sid].kind.clone() else { return };
        let owned = fields.iter().zip(lay.iter()).filter(|(f, _)| !f.alias);
        for ((_, f), e) in owned.zip(list) {
            let dst = Place { base: Base::Var(v), off: f.off, bit: None, idx: None, dbit: None, ty: f.ty.clone() };
            if let Ty::Str(cap) = f.ty {
                self.str_assign(dst, cap, e, span, inits);
                continue;
            }
            let Some(c) = self.a.consts.get(&e.id) else { continue };
            let (w, sg) = nat(&f.ty).unwrap_or((8, false));
            let x = cval_for(c, &f.ty) & mask(w);
            if x != 0 {
                inits.push(S { st: St::Assign(dst, Ex::konst(x, w, sg)), span });
            }
        }
    }

    /// Gives a freshly declared array its initial values. Storage is zero already (start-up
    /// clears globals, entry clears locals), so a few non-zero values are stored one by one and
    /// a longer table is copied from program memory.
    fn array_init(&mut self, v: VarId, elem: &Ty, vals: &[u32], span: Span, inits: &mut Vec<S>) {
        let size = self.size_of(elem);
        let (w, sg) = nat(elem).unwrap_or((8, false));
        let nonzero = vals.iter().filter(|&&x| x & mask(w) != 0).count() as u32;
        if nonzero == 0 {
            return;
        }
        let ty = self.vars[v].ty.clone();
        if nonzero * size <= 8 {
            for (i, &x) in vals.iter().enumerate() {
                if x & mask(w) != 0 {
                    let dst = Place { base: Base::Var(v), off: i as u32 * size, bit: None, idx: None, dbit: None, ty: elem.clone() };
                    inits.push(S { st: St::Assign(dst, Ex::konst(x, w, sg)), span });
                }
            }
            return;
        }
        let f = self.new_flash(vals, size);
        let bytes = self.flash[f].bytes.len() as u32;
        let dst = Place { base: Base::Var(v), off: 0, bit: None, idx: None, dbit: None, ty: ty.clone() };
        let src = Place { base: Base::Flash(f), off: 0, bit: None, idx: None, dbit: None, ty };
        inits.push(S { st: St::Copy { dst, src, bytes }, span });
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
                ParamMode::ByRef => matches!(info.ty, Ty::Str(_)) || matches!(pointee, Ty::Struct(_)) || (nat(pointee).is_some() && (!matches!(pointee, Ty::Bit) || matches!(info.ty, Ty::Array(..)))),
                ParamMode::ByRefConst => matches!(info.ty, Ty::Str(_)) || (matches!(info.ty, Ty::Array(..)) && nat(pointee).is_some()),
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
            let default = p.default.as_ref().and_then(|e| self.a.consts.get(&e.id)).map(|c| Ex::konst(cval_for(c, &info.ty), w, s));
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

    /// The function id of an event handler; its number is what an event variable holds.
    fn event_func(&mut self, sym: usize) -> Option<(FuncId, u32)> {
        let n = self.event_order.iter().position(|&s| s == sym);
        if let (Some(n), Some(fi)) = (n, self.sym_func.get(&sym)) {
            return Some((fi.id, n as u32 + 1));
        }
        let e = *self.event_decls.get(&sym)?;
        let sig = self.event_sig(sym);
        let id = self.funcs.len();
        self.funcs.push(None);
        let ui = self.a.symbols[sym].unit;
        let asm = self.unique(format!("{}_{}", unit_prefix(self.proj, ui), sanitize(&e.name.name)));
        self.asm_names.insert(format!("{asm}__TMP"));
        let saved = (self.cur_func, std::mem::take(&mut self.cur_asm));
        self.cur_func = Some(id);
        self.cur_asm = asm.clone();
        let mut params = Vec::new();
        for (p, ty) in e.params.iter().zip(&sig) {
            let v = self.new_var(format!("{asm}__{}", sanitize(&p.name.name)), &p.name.name, ty.clone(), VarKind::Param, None);
            if let Some(&psym) = self.a.decl_syms.get(&p.name.span) {
                self.sym_var.insert(psym, v);
            }
            params.push((v, None));
        }
        self.cur_func = saved.0;
        self.cur_asm = saved.1;
        self.sym_func.insert(sym, FuncInfo { id, asm, params, result: None });
        self.event_order.push(sym);
        self.queue.push(sym);
        Some((id, self.event_order.len() as u32))
    }

    /// The parameter types of an event type or handler.
    fn event_sig(&self, sym: usize) -> Vec<Ty> {
        match &self.a.symbols[sym].kind {
            SymKind::EventType { params } | SymKind::Event { params } => params.clone(),
            _ => Vec::new(),
        }
    }

    fn lower_event(&mut self, sym: usize, e: &'a EventDecl) {
        let (id, asm, params) = {
            let fi = &self.sym_func[&sym];
            (fi.id, fi.asm.clone(), fi.params.iter().map(|p| p.0).collect::<Vec<_>>())
        };
        let ui = self.a.symbols[sym].unit;
        let saved = (self.cur_func, std::mem::take(&mut self.cur_asm), std::mem::take(&mut self.labels), self.cur_result.take());
        self.cur_func = Some(id);
        self.cur_asm = asm.clone();
        let mut body = Vec::new();
        for d in &e.body.decls {
            self.decl(d, ui, &mut body);
        }
        let mut rest = self.block(&e.body.stmts, ui);
        body.append(&mut rest);
        let mut entry = self.entry_clears(id, &body, e.name.span);
        entry.append(&mut body);
        let mut body = entry;
        body.push(S { st: St::Return, span: e.name.span });
        self.funcs[id] = Some(Func { asm, name: e.name.name.clone(), params, result: None, body, span: e.name.span });
        self.cur_func = saved.0;
        self.cur_asm = saved.1;
        self.labels = saved.2;
        self.cur_result = saved.3;
    }

    /// The call of the handler held by an event variable, as a call of the shared dispatcher for
    /// its parameter list.
    fn event_call(&mut self, held: Place, args: &'a [Expr]) -> Option<(FuncId, Vec<(Place, Ex)>)> {
        let Ty::EventVar(t) = held.ty else { return None };
        let sig = self.event_sig(t);
        let k = match self.event_disp.iter().position(|d| d.sig == sig) {
            Some(k) => k,
            None => {
                let k = self.event_disp.len();
                let asm = if k == 0 { "__EVDISP".to_string() } else { format!("__EVDISP{k}") };
                let id = self.funcs.len();
                self.funcs.push(None);
                self.asm_names.insert(format!("{asm}__TMP"));
                let saved = self.cur_func.replace(id);
                let idv = self.new_var(format!("{asm}__ID"), "(event)", BYTE, VarKind::Param, None);
                let pvs = sig.iter().enumerate().map(|(j, ty)| self.new_var(format!("{asm}__P{j}"), "(event argument)", ty.clone(), VarKind::Param, None)).collect();
                self.cur_func = saved;
                self.event_disp.push(EvDisp { sig: sig.clone(), id, idv, pvs });
                k
            }
        };
        let (id, idv, pvs) = (self.event_disp[k].id, self.event_disp[k].idv, self.event_disp[k].pvs.clone());
        let var = |v: VarId, ty: Ty| Place { base: Base::Var(v), off: 0, bit: None, idx: None, dbit: None, ty };
        let mut out = vec![(var(idv, BYTE), Ex::new(ExK::Load(held), 8, false))];
        for ((arg, ty), pv) in args.iter().zip(&sig).zip(pvs) {
            let ex = self.value_for(arg, ty)?;
            out.push((var(pv, ty.clone()), ex));
        }
        Some((id, out))
    }

    /// Fills each dispatcher once every referenced handler is known: it calls the one whose number
    /// the variable holds, and does nothing for 0 (no handler assigned).
    fn finish_event_dispatch(&mut self) {
        let sp = Span::default();
        for k in 0..self.event_disp.len() {
            let (sig, id, idv, pvs) = {
                let d = &self.event_disp[k];
                (d.sig.clone(), d.id, d.idv, d.pvs.clone())
            };
            let var = |v: VarId, ty: Ty| Place { base: Base::Var(v), off: 0, bit: None, idx: None, dbit: None, ty };
            let mut arms = Vec::new();
            for (n, sym) in self.event_order.clone().into_iter().enumerate() {
                if self.event_sig(sym) != sig {
                    continue;
                }
                let (fid, hparams) = {
                    let fi = &self.sym_func[&sym];
                    (fi.id, fi.params.iter().map(|p| p.0).collect::<Vec<_>>())
                };
                let cond = Ex::boolean(ExK::Cmp(CmpKind::Eq, Box::new(Ex::new(ExK::Load(var(idv, BYTE)), 8, false)), Box::new(Ex::konst(n as u32 + 1, 8, false))));
                let mut cargs = Vec::new();
                for ((hp, ty), pv) in hparams.into_iter().zip(&sig).zip(&pvs) {
                    let (w, sg) = nat(ty).unwrap_or((8, false));
                    cargs.push((var(hp, ty.clone()), Ex::new(ExK::Load(var(*pv, ty.clone())), w, sg)));
                }
                arms.push((cond, vec![S { st: St::Call(fid, cargs), span: sp }]));
            }
            let mut body = Vec::new();
            if !arms.is_empty() {
                body.push(S { st: St::If(arms, vec![]), span: sp });
            }
            body.push(S { st: St::Return, span: sp });
            let name = if k == 0 { "__EVDISP".to_string() } else { format!("__EVDISP{k}") };
            let mut params = vec![idv];
            params.extend(pvs);
            self.funcs[id] = Some(Func { asm: name, name: "event".into(), params, result: None, body, span: sp });
        }
    }

    /// The event handler a designator names (not calls), if it is one.
    fn handler_of(&self, d: &Designator) -> Option<usize> {
        let sym = match self.a.resolved.get(&d.id)? {
            Res::Sym(id) => *id,
            Res::Module(u) => {
                let Some(Part::Member(n)) = d.parts.first() else { return None };
                *self.unit_syms.get(&(*u, n.key()))?
            }
            _ => return None,
        };
        matches!(self.a.symbols[sym].kind, SymKind::Event { .. }).then_some(sym)
    }

    fn lower_routine(&mut self, sym: usize) {
        if let Some(&e) = self.event_decls.get(&sym) {
            return self.lower_event(sym, e);
        }
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
        if r.ext {
            body.push(S { st: St::Asm(self.extern_thunk(r, &params, result)), span: r.name.span });
        }
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

    /// The body of an `Extern` routine: moves the arguments from the parameter variables to where
    /// XC8 expects them, calls the C function and moves the value back (MPLAB XC8 C Compiler User
    /// Guide DS-50002737L §5.8.5-5.8.6, compiled stack: a first one-byte parameter is passed in W, the
    /// others in `?_func` upwards in order; a one-byte value comes back in W, a longer one in `?_func`).
    fn extern_thunk(&mut self, r: &Routine, params: &[VarId], result: Option<VarId>) -> Vec<String> {
        let c = &r.name.name;
        let sig = |v: VarId| (self.vars[v].bytes as u8, self.vars[v].ty.clone());
        let mut lines = Vec::new();
        let mut at = 0;
        let mut esig = ExternSig { name: c.clone(), params: Vec::new(), ret: None };
        for (i, &p) in params.iter().enumerate() {
            let (n, ty) = sig(p);
            esig.params.push((n, nat(&ty).is_some_and(|x| x.1)));
            let src = self.vars[p].asm.clone();
            if i == 0 && n == 1 {
                lines.push(format!("    movff {src}, WREG"));
                continue;
            }
            for k in 0..u32::from(n) {
                lines.push(format!("    movff {src}+{k}, ?_{c}+{}", at + k));
            }
            at += u32::from(n);
        }
        lines.push(format!("    call _{c}"));
        if let Some(rv) = result {
            let (n, ty) = sig(rv);
            esig.ret = Some((n, nat(&ty).is_some_and(|x| x.1)));
            let dst = self.vars[rv].asm.clone();
            if n == 1 {
                lines.push(format!("    movff WREG, {dst}"));
            } else {
                for k in 0..u32::from(n) {
                    lines.push(format!("    movff ?_{c}+{k}, {dst}+{k}"));
                }
            }
        }
        match self.externs.iter().find(|e| e.name == esig.name) {
            None => self.externs.push(esig),
            Some(e) if e.params != esig.params || e.ret != esig.ret => {
                self.diags.error("E-EXTERN", r.name.span, format!("`{c}` is declared Extern twice with different parameter or result types, but C has one function of that name"));
                self.failed = true;
            }
            Some(_) => {}
        }
        lines
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
            // A routine whose own `Asm` block stores into its `Result` sets it itself.
            if var.kind == VarKind::Result && body.iter().any(|s| matches!(&s.st, St::Asm(ls) if ls.iter().any(|l| l.split(|c: char| !(c.is_ascii_alphanumeric() || c == '_')).any(|t| t == var.asm)))) {
                continue;
            }
            if var.kind == VarKind::Local && !mentions(body, v) {
                continue;
            }
            let place = |off: u32, ty: Ty| Place { base: Base::Var(v), off, bit: None, idx: None, dbit: None, ty };
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
                return Some(Place { base: Base::Ptr(v), off: 0, bit: None, idx: None, dbit: None, ty: self.vars[v].ty.clone() });
            }
            return Some(Place { base: Base::Var(v), off: 0, bit: None, idx: None, dbit: None, ty: self.vars[v].ty.clone() });
        }
        if let Some(p) = self.sym_alias.get(&sym) {
            return Some(p.clone());
        }
        if let SymKind::ConstArray { elem, vals } = self.a.symbols[sym].kind.clone() {
            if nat(&elem).is_none() {
                self.unsupported(span, &format!("a constant array of {elem}"));
                return None;
            }
            let f = match self.sym_flash.get(&sym) {
                Some(&f) => f,
                None => {
                    let size = self.size_of(&elem);
                    let words: Vec<u32> = vals.iter().map(|c| cval_for(c, &elem)).collect();
                    let f = self.new_flash(&words, size);
                    self.sym_flash.insert(sym, f);
                    f
                }
            };
            return Some(Place { base: Base::Flash(f), off: 0, bit: None, idx: None, dbit: None, ty: Ty::Array(Box::new(elem), vals.len() as u32) });
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
            return Some(Place { base: Base::Abs { addr: s.addr, name: s.name.clone() }, off: 0, bit: None, idx: None, dbit: None, ty: BYTE });
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
            return Some(Place { base: Base::Abs { addr: j.addr, name: j.name.clone() }, off: 0, bit: None, idx: None, dbit: None, ty });
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
        p
    }

    fn place_inner(&mut self, d: &'a Designator) -> Option<Place> {
        self.place_inner_parts(d, &d.parts)
    }

    fn place_inner_parts(&mut self, d: &'a Designator, parts: &'a [Part]) -> Option<Place> {
        let mut i = 0;
        let place = match self.a.resolved.get(&d.id).cloned() {
            Some(Res::Sym(id)) => {
                // `Module.Name`: sema resolves it to the symbol itself and leaves the member name in `parts`.
                if let Some(Part::Member(n)) = parts.first()
                    && d.head.key() != self.a.symbols[id].name.to_ascii_lowercase()
                    && n.key() == self.a.symbols[id].name.to_ascii_lowercase()
                {
                    i = 1;
                }
                self.var_place(id, d.head.span)?
            }
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
                Place { base: Base::Var(v), off: 0, bit: None, idx: None, dbit: None, ty: self.vars[v].ty.clone() }
            }
        };
        self.apply_parts(place, parts, i, d.span)
    }

    /// Follows `parts[i..]` (members, bit numbers, indices) from `place`.
    fn apply_parts(&mut self, mut place: Place, parts: &'a [Part], mut i: usize, _span: Span) -> Option<Place> {
        while i < parts.len() {
            match &parts[i] {
                Part::BitIndex(n, _) => {
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
                    let md = self.a.md_index.get(sp).cloned();
                    if place.bit.is_some() || (args.len() != 1 && md.is_none()) {
                        self.unsupported(*sp, "this array access");
                        return None;
                    }
                    if md.is_none()
                        && let Base::Var(v) = place.base
                        && self.packed.contains(&v)
                        && place.off == 0
                        && place.idx.is_none()
                        && matches!(*elem, Ty::Bit | Ty::Bool)
                    {
                        place = self.packed_element(place, &elem, n, &args[0])?;
                        i += 1;
                        continue;
                    }
                    let size = self.size_of(&elem);
                    // One index, or one per dimension of a multi-dimensional array: each steps
                    // over `stride` elements, the product of the dimensions after it.
                    let dims = md.unwrap_or_else(|| vec![n]);
                    for (k, arg) in args.iter().enumerate() {
                        let step = size * dims[k + 1..].iter().product::<u32>();
                        if let Some(CVal::Int(c)) = self.a.consts.get(&arg.id) {
                            if *c < 0 || (dims[k] > 0 && *c >= dims[k] as i128) {
                                self.err("E-BOUNDS", arg.span, format!("index {c} is outside the array (0 to {})", dims[k].saturating_sub(1)));
                                return None;
                            }
                            place.off += *c as u32 * step;
                        } else {
                            let ix = self.expr(arg)?;
                            let ix = conv(ix, 16, false);
                            let off = match step {
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
            CVal::Float(_) | CVal::Int(_) if ty == Ty::Float => cval_for(c, &ty),
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
            ExprKind::Unary(UnOp::AddressOf, x) => self.address_value(x),
            ExprKind::Unary(op, x) => {
                let xv = self.expr(x)?;
                if ty == Ty::Float {
                    return match op {
                        UnOp::Plus => Some(xv),
                        // Flip the sign bit.
                        UnOp::Neg => Some(Ex::new(ExK::Bin(BinKind::Xor, Box::new(xv), Box::new(Ex::konst(0x8000_0000, 32, false))), 32, false)),
                        _ => {
                            self.unsupported(e.span, "this operator on a Float");
                            None
                        }
                    };
                }
                let ex = match op {
                    UnOp::Plus => conv(xv, w, ns),
                    UnOp::Neg => Ex::new(ExK::Neg(Box::new(conv(xv, w, ns))), w, ns),
                    UnOp::Not => match ty {
                        Ty::Bool => Ex::boolean(ExK::NotB(Box::new(xv))),
                        Ty::Bit => Ex::new(ExK::Bin(BinKind::Xor, Box::new(xv), Box::new(Ex::konst(1, 8, false))), 8, false),
                        _ => Ex::new(ExK::Com(Box::new(conv(xv, w, ns))), w, ns),
                    },
                    UnOp::AddressOf => unreachable!(),
                };
                Some(ex)
            }
            ExprKind::Binary(op, l, r) => {
                if matches!(op, BinOp::Eq | BinOp::Ne) && matches!(self.a.types.get(&l.id), Some(Ty::Str(_))) && matches!(self.a.types.get(&r.id), Some(Ty::Str(_))) {
                    return self.str_compare(*op, l, r, e);
                }
                if matches!(self.a.types.get(&l.id), Some(Ty::Float)) || matches!(self.a.types.get(&r.id), Some(Ty::Float)) {
                    return self.float_binary(*op, l, r, e);
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

    // ---- Float ---------------------------------------------------------------------------

    /// A call of the FloatLib routine `name` on 32-bit operands.
    fn flt_call(&mut self, name: &str, args: Vec<Ex>, span: Span) -> Option<Ex> {
        if self.in_isr {
            // The FloatLib routines keep their working storage in static frames, which a handler
            // would overwrite while the main program is inside the same routine.
            self.err("E-ISR-CALL", span, "Float arithmetic, comparison or conversion inside an interrupt handler would share the Float routines' frames with the main program; do it in a routine and call that inside Save(…) … Restore (LANGUAGE.md §8)");
            return None;
        }
        let unit = self.proj.units.iter().position(|u| u.path.file_stem().is_some_and(|f| f == "floatlib"));
        let sym = unit.and_then(|u| self.unit_syms.get(&(u, name.to_ascii_lowercase())).copied());
        let Some(sym) = sym else {
            self.err("E-BACKEND", span, "Float needs the FloatLib module (lib/floatlib.bas), which was not found in the library folders");
            return None;
        };
        let id = self.func_of(sym, span)?;
        let params = self.sym_func[&sym].params.clone();
        let result = self.sym_func[&sym].result;
        let (w, s) = result.and_then(|r| nat(&self.vars[r].ty)).unwrap_or((8, false));
        let mut out = Vec::new();
        for ((pv, _), a) in params.iter().zip(args) {
            let (pw, ps) = nat(&self.vars[*pv].ty).unwrap_or((32, false));
            out.push((Place { base: Base::Var(*pv), off: 0, bit: None, idx: None, dbit: None, ty: self.vars[*pv].ty.clone() }, conv(a, pw, ps)));
        }
        Some(Ex::new(ExK::Call(id, out), w, s))
    }

    /// The Float (as bits) with the value of the integer `ex`.
    fn to_float(&mut self, ex: Ex, span: Span) -> Option<Ex> {
        if let ExK::Const(v) = ex.k {
            let val = if ex.signed { sign_extend(v, ex.w) } else { v as i64 };
            return Some(Ex::konst((val as f32).to_bits(), 32, false));
        }
        if !ex.signed && ex.w == 32 {
            self.flt_call("FFromULong", vec![ex], span)
        } else {
            self.flt_call("FFromLong", vec![conv(ex, 32, true)], span)
        }
    }

    /// The value of `e` as stored in an object of type `target`: an integer is converted when the
    /// target is a Float, otherwise it is cut or extended to the target's width.
    fn value_for(&mut self, e: &'a Expr, target: &Ty) -> Option<Ex> {
        let v = self.expr(e)?;
        let (w, sg) = nat(target)?;
        if *target == Ty::Float && !matches!(self.a.types.get(&e.id), Some(Ty::Float)) {
            return self.to_float(v, e.span);
        }
        Some(conv(v, w, sg))
    }

    /// An operation with a Float operand: arithmetic gives a Float, a comparison a Boolean.
    fn float_binary(&mut self, op: BinOp, l: &'a Expr, r: &'a Expr, e: &Expr) -> Option<Ex> {
        let name = match op {
            BinOp::Add => "FAdd",
            BinOp::Sub => "FSub",
            BinOp::Mul => "FMul",
            BinOp::Div => "FDiv",
            BinOp::Eq => "FEq",
            BinOp::Ne => "FNe",
            BinOp::Lt => "FLt",
            BinOp::Le => "FLe",
            BinOp::Gt => "FGt",
            BinOp::Ge => "FGe",
            _ => {
                self.unsupported(e.span, "this operator on a Float");
                return None;
            }
        };
        let lv = self.value_for(l, &Ty::Float)?;
        let rv = self.value_for(r, &Ty::Float)?;
        if op.is_relational() {
            // `Cmp` answers -1, 0, 1 (a < b, a = b, a > b) or 2 (not ordered); testing its answer
            // here saves the copy of both operands that the FEq..FGe wrappers would make.
            let c = self.flt_call("Cmp", vec![lv, rv], e.span)?;
            let k = |v: u32| Box::new(Ex::konst(v, 8, true));
            let ex = match op {
                BinOp::Eq => ExK::Cmp(CmpKind::Eq, Box::new(c), k(0)),
                BinOp::Ne => ExK::Cmp(CmpKind::Ne, Box::new(c), k(0)),
                BinOp::Lt => ExK::Cmp(CmpKind::Eq, Box::new(c), k(0xFF)),
                BinOp::Le => ExK::Cmp(CmpKind::Le, Box::new(c), k(0)),
                BinOp::Gt => ExK::Cmp(CmpKind::Eq, Box::new(c), k(1)),
                // Only 0 and 1 are "equal or greater": below 2 when read unsigned.
                _ => ExK::Cmp(CmpKind::Lt, Box::new(Ex::new(ExK::Conv(Box::new(c)), 8, false)), Box::new(Ex::konst(2, 8, false))),
            };
            return Some(Ex::boolean(ex));
        }
        self.flt_call(name, vec![lv, rv], e.span)
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
        let sym = self.a.call_targets.get(&d.id).copied().unwrap_or(sym);
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
        let mut lens = Vec::new();
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
                    if pl.is_bit() {
                        self.unsupported(dd.span, "a bit passed ByRef");
                        return None;
                    }
                    match pl.base {
                        // A constant table is read through a RAM copy made at start-up.
                        Base::Flash(f) if pl.off == 0 && pl.idx.is_none() => self.flash_copy(f, &pl.ty.clone(), dd.span),
                        Base::Flash(_) => {
                            self.unsupported(dd.span, "part of a constant array passed by reference");
                            return None;
                        }
                        _ => pl,
                    }
                };
                if matches!(self.vars[*pv].ty, Ty::Array(..)) {
                    // The callee may ask for the array's length with `Bound`; it travels beside the address.
                    let len = match (&pl.ty, &pl.base) {
                        (Ty::Array(_, n), _) if *n > 0 => Ex::konst(*n, 16, false),
                        (Ty::Array(_, 0), Base::Ptr(src)) if pl.off == 0 && pl.idx.is_none() => {
                            self.len_fwd.push((*pv, *src));
                            Ex::new(ExK::Load(Place { base: Base::Var(*src), off: 2, bit: None, idx: None, dbit: None, ty: WORD }), 16, false)
                        }
                        _ => {
                            self.unsupported(span, "this array argument");
                            return None;
                        }
                    };
                    lens.push((Place { base: Base::Var(*pv), off: 2, bit: None, idx: None, dbit: None, ty: WORD }, len));
                }
                Ex::new(ExK::Addr(pl), 16, false)
            } else {
                let (w, s) = nat(&pty).unwrap();
                match args.get(i) {
                    Some(a) => {
                        let _ = (w, s);
                        self.value_for(a, &pty)?
                    }
                    None => def.clone()?,
                }
            };
            out.push((Place { base: Base::Var(*pv), off: 0, bit: None, idx: None, dbit: None, ty: pty }, ex));
        }
        out.append(&mut lens);
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
        if let Some(sym) = self.handler_of(d) {
            let (_, n) = self.event_func(sym)?;
            return Some(Ex::konst(n, 8, false));
        }
        let place = self.place_idx_of(d)?;
        if let Some(k) = self.flash_const(&place) {
            return Some(k);
        }
        let Some((w, s)) = nat(&place.ty) else {
            self.unsupported(d.span, &format!("a value of type {}", place.ty));
            return None;
        };
        if place.is_bit() && place.indirect() {
            return self.bit_read(&place, d.span);
        }
        Some(Ex::new(ExK::Load(place), w, s))
    }

    /// Element `ix` of a packed bit array: bit `ix % 8` of byte `ix / 8`. A constant index is
    /// folded into the place; otherwise the byte comes from `idx` and the bit from `dbit`.
    fn packed_element(&mut self, mut place: Place, elem: &Ty, n: u32, ix: &'a Expr) -> Option<Place> {
        if let Some(CVal::Int(c)) = self.a.consts.get(&ix.id) {
            if *c < 0 || (n > 0 && *c >= n as i128) {
                self.err("E-BOUNDS", ix.span, format!("index {c} is outside the array (0 to {})", n.saturating_sub(1)));
                return None;
            }
            place.off = *c as u32 / 8;
            place.bit = Some((*c % 8) as u8);
        } else {
            let e = self.expr(ix)?;
            let e16 = conv(e, 16, false);
            let byte = Ex::new(ExK::Bin(BinKind::Shr, Box::new(e16.clone()), Box::new(Ex::konst(3, 8, false))), 16, false);
            let e8 = conv(e16, 8, false);
            let bit = Ex::new(ExK::Bin(BinKind::And, Box::new(e8), Box::new(Ex::konst(7, 8, false))), 8, false);
            place.idx = Some(Box::new(byte));
            place.dbit = Some(Box::new(bit));
        }
        place.ty = elem.clone();
        Some(place)
    }

    /// The value (0 or 1) of a bit of a byte that is reached through FSR0 or TBLPTR: an element of
    /// an array picked at run time, a field of one, a `ByRef` parameter or a constant table.
    fn bit_read(&mut self, p: &Place, span: Span) -> Option<Ex> {
        if p.idx.as_ref().is_some_and(|i| i.has_call()) {
            self.unsupported(span, "a call inside the index of a bit");
            return None;
        }
        let byte = Place { bit: None, dbit: None, ty: BYTE, ..p.clone() };
        let load = Ex::new(ExK::Load(byte), 8, false);
        if let Some(n) = &p.dbit {
            let shifted = Ex::new(ExK::Bin(BinKind::Shr, Box::new(load), n.clone()), 8, false);
            return Some(Ex::new(ExK::Bin(BinKind::And, Box::new(shifted), Box::new(Ex::konst(1, 8, false))), 8, false));
        }
        let b = p.bit?;
        let masked = Ex::new(ExK::Bin(BinKind::And, Box::new(load), Box::new(Ex::konst(1 << b, 8, false))), 8, false);
        Some(if b == 0 { masked } else { Ex::new(ExK::Bin(BinKind::Shr, Box::new(masked), Box::new(Ex::konst(b as u32, 8, false))), 8, false) })
    }

    /// Stores 0 or 1 (`v`, 8 bits) into a bit read by `bit_read`, as a read-modify-write of its
    /// byte. `toggle` flips the bit instead.
    fn bit_write(&mut self, p: &Place, v: Option<Ex>, span: Span) -> Option<St> {
        if p.idx.as_ref().is_some_and(|i| i.has_call()) {
            self.unsupported(span, "a call inside the index of a bit");
            return None;
        }
        let byte = Place { bit: None, dbit: None, ty: BYTE, ..p.clone() };
        let load = Ex::new(ExK::Load(byte.clone()), 8, false);
        let bin = |k: BinKind, l: Ex, r: Ex| Ex::new(ExK::Bin(k, Box::new(l), Box::new(r)), 8, false);
        if let Some(n) = &p.dbit {
            let mask = bin(BinKind::Shl, Ex::konst(1, 8, false), (**n).clone());
            let cleared = |load: Ex, mask: Ex| bin(BinKind::And, load, Ex::new(ExK::Com(Box::new(mask)), 8, false));
            let new = match v {
                None => bin(BinKind::Xor, load, mask),
                Some(v) => match v.as_const() {
                    Some(0) => cleared(load, mask),
                    Some(_) => bin(BinKind::Or, load, mask),
                    None => {
                        let shifted = bin(BinKind::Shl, v, (**n).clone());
                        bin(BinKind::Or, cleared(load, mask), shifted)
                    }
                },
            };
            return Some(St::Assign(byte, new));
        }
        let b = p.bit?;
        let mask = 1u32 << b;
        let new = match v {
            // Toggle.
            None => bin(BinKind::Xor, load, Ex::konst(mask, 8, false)),
            Some(v) => match v.as_const() {
                Some(0) => bin(BinKind::And, load, Ex::konst(!mask, 8, false)),
                Some(_) => bin(BinKind::Or, load, Ex::konst(mask, 8, false)),
                None => {
                    let shifted = if b == 0 { v } else { bin(BinKind::Shl, v, Ex::konst(b as u32, 8, false)) };
                    bin(BinKind::Or, bin(BinKind::And, load, Ex::konst(!mask, 8, false)), shifted)
                }
            },
        };
        Some(St::Assign(byte, new))
    }

    /// `bit_write` as it is emitted. The write is a read-modify-write of a byte that other bits
    /// may share (neighbouring elements of a packed bit array, other fields of a structure), so
    /// when the program has an interrupt handler it runs with the global interrupt enable off:
    /// a handler that changed another bit of the byte between the read and the write would have
    /// its change overwritten. The enable is put back only if it was set on entry, so a write
    /// made in a handler or in code that disabled interrupts leaves them as they were. A value
    /// that is not trivially cheap is worked out first so the window stays short.
    fn bit_store(&mut self, p: &Place, v: Option<Ex>, span: Span, out: &mut Vec<S>) {
        let has_isr = self.a.symbols.iter().any(|s| matches!(s.kind, SymKind::Interrupt { .. }));
        // The global enable is bit 7 of `INTCON` (Q10) or of `INTCON0` (vectored interrupt controller).
        let intcon = if has_isr { self.reg_place("INTCON", span).or_else(|| self.reg_place("INTCON0", span)) } else { None };
        let Some(intcon) = intcon else {
            if let Some(st) = self.bit_write(p, v, span) {
                Self::push(out, st, span);
            }
            return;
        };
        let v = match v {
            Some(x) if !matches!(x.k, ExK::Const(_) | ExK::Load(_)) || x.has_call() => {
                let t = self.hidden_var(BYTE);
                Self::push(out, St::Assign(t.clone(), x), span);
                Some(Ex::new(ExK::Load(t), 8, false))
            }
            other => other,
        };
        let Some(write) = self.bit_write(p, v, span) else { return };
        let saved = self.hidden_var(BYTE);
        Self::push(out, St::Assign(saved.clone(), Ex::new(ExK::Load(intcon), 8, false)), span);
        Self::push(out, St::Int { level: Level::High, on: false }, span);
        Self::push(out, write, span);
        let was_on = Ex::new(ExK::Bin(BinKind::And, Box::new(Ex::new(ExK::Load(saved), 8, false)), Box::new(Ex::konst(0x80, 8, false))), 8, false);
        let cond = Ex::boolean(ExK::Cmp(CmpKind::Ne, Box::new(was_on), Box::new(Ex::konst(0, 8, false))));
        let on = vec![S { st: St::Int { level: Level::High, on: true }, span }];
        Self::push(out, St::If(vec![(cond, on)], Vec::new()), span);
    }

    /// `AddressOf(x)` / `@x`: the data address of a variable, register, array or element (a
    /// `Word`), or the program-memory address of a routine or constant table (a `LongWord`).
    fn address_value(&mut self, arg: &'a Expr) -> Option<Ex> {
        let ExprKind::Designator(d) = &arg.kind else {
            self.unsupported(arg.span, "the address of this");
            return None;
        };
        if let Some((sym, _, _)) = self.callee_of(d) {
            let f = self.func_of(sym, arg.span)?;
            return Some(Ex::new(ExK::FuncAddr(f), 32, false));
        }
        let p = self.place_idx_of(d)?;
        if p.is_bit() {
            self.unsupported(arg.span, "the address of a bit");
            return None;
        }
        if let Base::Flash(t) = p.base {
            if p.idx.is_some() {
                self.unsupported(arg.span, "the address of a constant table element chosen at run time");
                return None;
            }
            return Some(Ex::new(ExK::FlashAddr(t, p.off), 32, false));
        }
        if p.idx.as_ref().is_some_and(|i| i.has_call()) {
            self.unsupported(arg.span, "a call inside the index of AddressOf");
            return None;
        }
        Some(Ex::new(ExK::Addr(p), 16, false))
    }

    fn intrinsic_value(&mut self, name: &str, d: &'a Designator, e: &'a Expr) -> Option<Ex> {
        let args: &[Expr] = match d.parts.first() {
            Some(Part::Args(a, _)) => a,
            _ => &[],
        };
        let ty = self.a.types.get(&e.id).cloned().unwrap_or(BYTE);
        match name {
            "float" => self.value_for(&args[0], &Ty::Float),
            "addressof" => self.address_value(&args[0]),
            "byte" | "word" | "integer" | "longword" | "longint" | "shortint" | "char" => {
                let (w, s) = nat(&ty)?;
                let x = self.expr(&args[0])?;
                if matches!(self.a.types.get(&args[0].id), Some(Ty::Float)) {
                    // Truncates toward zero, then cuts to the target like any integer conversion.
                    let l = self.flt_call("FToLong", vec![x], e.span)?;
                    return Some(conv(l, w, s));
                }
                Some(conv(x, w, s))
            }
            "boolean" | "bit" => {
                let x = self.expr(&args[0])?;
                let argty = self.a.types.get(&args[0].id).cloned().unwrap_or(BYTE);
                if argty == Ty::Float && name == "boolean" {
                    return self.flt_call("FNe", vec![x, Ex::konst(0, 32, false)], e.span).map(|c| Ex::boolean(c.k));
                }
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
            "bound" => {
                // Only an array parameter gets here (sema folds the others): its length travels
                // with the address, in the two bytes after it.
                let Some(Expr { kind: ExprKind::Designator(dd), .. }) = args.first() else {
                    self.unsupported(e.span, "`Bound` of this");
                    return None;
                };
                let p = self.place_idx_of(dd)?;
                let Base::Ptr(v) = p.base else {
                    self.unsupported(e.span, "`Bound` of this");
                    return None;
                };
                if p.off != 0 || p.idx.is_some() || !matches!(p.ty, Ty::Array(_, 0)) {
                    self.unsupported(e.span, "`Bound` of this");
                    return None;
                }
                self.len_used.insert(v);
                let len = Ex::new(ExK::Load(Place { base: Base::Var(v), off: 2, bit: None, idx: None, dbit: None, ty: WORD }), 16, false);
                Some(Ex::new(ExK::Bin(BinKind::Sub, Box::new(len), Box::new(Ex::konst(1, 16, false))), 16, false))
            }
            // Clear the sign bit.
            "abs" if matches!(self.a.types.get(&args[0].id), Some(Ty::Float)) => {
                let x = self.expr(&args[0])?;
                Some(Ex::new(ExK::Bin(BinKind::And, Box::new(x), Box::new(Ex::konst(0x7FFF_FFFF, 32, false))), 32, false))
            }
            // |x| = x + ((-2x) & mask), mask = all ones when x < 0. Unsigned values are their own magnitude.
            "abs" => {
                let (w, s) = nat(&ty)?;
                let x = conv(self.expr(&args[0])?, w, s);
                if !s {
                    return Some(x);
                }
                if x.has_call() {
                    self.unsupported(e.span, "a call inside the argument of Abs");
                    return None;
                }
                let neg = Ex::boolean(ExK::Cmp(CmpKind::Lt, Box::new(x.clone()), Box::new(Ex::konst(0, w, s))));
                let mask = Ex::new(ExK::Neg(Box::new(conv(neg, w, s))), w, s);
                let twice = Ex::new(ExK::Bin(BinKind::Add, Box::new(x.clone()), Box::new(x.clone())), w, s);
                let minus_twice = Ex::new(ExK::Neg(Box::new(twice)), w, s);
                let pick = Ex::new(ExK::Bin(BinKind::And, Box::new(minus_twice), Box::new(mask)), w, s);
                Some(Ex::new(ExK::Bin(BinKind::Add, Box::new(x), Box::new(pick)), w, s))
            }
            // Min = b + ((a - b) & mask) with mask all ones when a < b; Max the same with a > b.
            "min" | "max" => {
                let (w, s) = nat(&ty)?;
                let a = conv(self.expr(&args[0])?, w, s);
                let b = conv(self.expr(&args[1])?, w, s);
                if a.has_call() || b.has_call() {
                    self.unsupported(e.span, &format!("a call inside the arguments of {}", if name == "min" { "Min" } else { "Max" }));
                    return None;
                }
                let kind = if name == "min" { CmpKind::Lt } else { CmpKind::Gt };
                let pick_a = Ex::boolean(ExK::Cmp(kind, Box::new(a.clone()), Box::new(b.clone())));
                let mask = Ex::new(ExK::Neg(Box::new(conv(pick_a, w, false))), w, s);
                let diff = Ex::new(ExK::Bin(BinKind::Sub, Box::new(a), Box::new(b.clone())), w, s);
                let pick = Ex::new(ExK::Bin(BinKind::And, Box::new(diff), Box::new(mask)), w, s);
                Some(Ex::new(ExK::Bin(BinKind::Add, Box::new(b), Box::new(pick)), w, s))
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
                if p.idx.as_ref().is_some_and(|i| i.has_call() || i.uses_fsr()) || p.bit.is_some() {
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
        if bytes == 0 {
            self.unsupported(span, &format!("{what} of a {} of unknown size", p.ty));
            return None;
        }
        if p.is_bit() || p.idx.as_ref().is_some_and(|i| i.has_call()) {
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
        if dst.idx.as_ref().is_some_and(|i| i.has_call() || i.uses_fsr()) {
            self.unsupported(span, "assigning to a String whose array index reads an array or calls a routine");
            return;
        }
        let mut parts = Vec::new();
        if self.str_parts(value, &mut parts).is_none() {
            return;
        }
        // `s = s + x` appends in place. The target anywhere else on the right would be
        // overwritten before it is read.
        let same = |p: &StrSrc| matches!(p, StrSrc::Ram(q) if q.base == dst.base && q.off == dst.off && q.idx == dst.idx);
        // Elements picked at run time can be the same string whatever their indices say.
        let may_alias = |p: &StrSrc| matches!(p, StrSrc::Ram(q) if q.base == dst.base && (q.idx.is_some() || dst.idx.is_some()));
        let keep = parts.first().is_some_and(same);
        if parts.iter().skip(1).any(|p| same(p) || may_alias(p)) {
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
                    let dst = Place { base: Base::Var(v), off: 0, bit: None, idx: None, dbit: None, ty: ty.clone() };
                    self.startup.push(S { st: St::StrSet { dst, cap: len, parts: vec![StrSrc::Lit(bytes)], keep: false }, span });
                }
                v
            }
        };
        Place { base: Base::Var(v), off: 0, bit: None, idx: None, dbit: None, ty }
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
                if nat(&p.ty).is_none() {
                    self.unsupported(target.span, &format!("assigning a {}", p.ty));
                    return;
                }
                let Some(v) = self.value_for(value, &p.ty) else { return };
                if p.is_bit() && p.indirect() {
                    self.bit_store(&p, Some(v), span, out);
                    return;
                }
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
        if let Some(Part::Args(args, _)) = d.parts.last()
            && !matches!(self.a.resolved.get(&d.id), Some(Res::Intrinsic(_)))
        {
            let n = d.parts.len() - 1;
            if let Some(held) = self.place_inner_parts(d, &d.parts[..n])
                && matches!(held.ty, Ty::EventVar(_))
            {
                if let Some((id, a)) = self.event_call(held, args) {
                    let call = S { st: St::Call(id, a), span };
                    if self.in_isr && self.in_save == 0 {
                        // The shared dispatcher and the handlers use storage the interrupted code may be
                        // using, so the call saves the working registers and every frame it can reach.
                        let sid = self.n_saves;
                        self.n_saves += 1;
                        Self::push(out, St::Save { id: sid, items: vec![SaveIt::Regs], body: vec![call] }, span);
                    } else {
                        out.push(call);
                    }
                }
                return;
            }
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
                    if matches!(name.as_str(), "inc" | "dec" | "clear" | "high" | "low" | "toggle") {
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
                if p.ty == Ty::Float {
                    self.unsupported(span, "Inc/Dec of a Float");
                    return;
                }
                let amount_ex = match args.get(1) {
                    Some(a) => {
                        let Some((w, sg)) = nat(&p.ty) else { return };
                        match self.expr(a) {
                            Some(x) => Some(conv(x, w, sg)),
                            None => return,
                        }
                    }
                    None => None,
                };
                if let Some(amt) = amount_ex {
                    if p.is_bit() {
                        self.unsupported(span, "Inc/Dec of a bit with an amount");
                        return;
                    }
                    if p.idx.as_ref().is_some_and(|i| i.has_call()) || amt.has_call() {
                        self.unsupported(span, "a call inside the index or amount of Inc/Dec");
                        return;
                    }
                    if let (Some(c), false) = (amt.as_const(), p.indirect()) {
                        let delta = if name == "inc" { c } else { 0u32.wrapping_sub(c) };
                        Self::push(out, St::Add(p, delta), span);
                        return;
                    }
                    let Some((w, sg)) = nat(&p.ty) else { return };
                    let load = Ex::new(ExK::Load(p.clone()), w, sg);
                    let kind = if name == "inc" { BinKind::Add } else { BinKind::Sub };
                    let sum = Ex::new(ExK::Bin(kind, Box::new(load), Box::new(amt)), w, sg);
                    Self::push(out, St::Assign(p, sum), span);
                    return;
                }
                let delta = if name == "inc" { 1u32 } else { u32::MAX };
                if p.is_bit() && p.indirect() {
                    self.unsupported(span, "Inc/Dec of a bit reached through a pointer or index");
                    return;
                }
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
                if p.is_bit() && p.indirect() {
                    self.bit_store(&p, Some(Ex::konst(0, 8, false)), span, out);
                    return;
                }
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
                if p.is_bit() && p.indirect() {
                    let v = match name.as_str() {
                        "high" => Some(Ex::konst(1, 8, false)),
                        "low" => Some(Ex::konst(0, 8, false)),
                        _ => None,
                    };
                    self.bit_store(&p, v, span, out);
                    return;
                }
                if p.bit.is_some() {
                    let st = match name.as_str() {
                        "high" => St::SetBit(p, true),
                        "low" => St::SetBit(p, false),
                        _ => St::ToggleBit(p),
                    };
                    Self::push(out, st, span);
                } else {
                    if p.idx.as_ref().is_some_and(|i| i.has_call()) {
                        self.unsupported(span, "a call inside the index of High/Low/Toggle");
                        return;
                    }
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
        if vp.ty == Ty::Float {
            self.unsupported(var.span, "a Float loop variable");
            return;
        }
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

/// Drops the hidden length argument of every array parameter whose routine never asks for
/// `Bound`, and gives the parameters that do keep it room for it (address, then length).
fn strip_unused_lengths(vars: &mut [Var], used: &HashSet<VarId>, fwd: &[(VarId, VarId)], funcs: &mut [Func], main: &mut Func) {
    // A length that is passed on to a routine that reads it is itself read.
    let mut used = used.clone();
    loop {
        let before = used.len();
        for &(callee, caller) in fwd {
            if used.contains(&callee) {
                used.insert(caller);
            }
        }
        if used.len() == before {
            break;
        }
    }
    for &v in &used {
        vars[v].bytes = 4;
    }
    let is_len = |p: &Place| matches!(p.base, Base::Var(v) if p.off == 2 && vars[v].by_ref && matches!(vars[v].ty, Ty::Array(..)) && !used.contains(&v));
    for f in funcs.iter_mut().chain(std::iter::once(main)) {
        strip_block(&mut f.body, &is_len);
    }
}

type LenTest<'a> = &'a dyn Fn(&Place) -> bool;

fn strip_block(b: &mut [S], is_len: LenTest) {
    for s in b {
        match &mut s.st {
            St::Assign(p, e) => {
                strip_place(p, is_len);
                strip_ex(e, is_len);
            }
            St::Add(p, _) | St::SetBit(p, _) | St::ToggleBit(p) | St::Clear(p) | St::ClearMem(p, _) | St::Direction { place: p, .. } => strip_place(p, is_len),
            St::Copy { dst, src, .. } => {
                strip_place(dst, is_len);
                strip_place(src, is_len);
            }
            St::StrSet { dst, parts, .. } => {
                strip_place(dst, is_len);
                for p in parts {
                    match p {
                        StrSrc::Ram(p) => strip_place(p, is_len),
                        StrSrc::Char(e) => strip_ex(e, is_len),
                        StrSrc::Lit(_) => {}
                    }
                }
            }
            St::Call(_, args) => strip_args(args, is_len),
            St::If(arms, other) => {
                for (c, body) in arms {
                    strip_ex(c, is_len);
                    strip_block(body, is_len);
                }
                strip_block(other, is_len);
            }
            St::While(c, body) | St::Repeat(body, c) => {
                strip_ex(c, is_len);
                strip_block(body, is_len);
            }
            St::For { var, from, limit, body, .. } => {
                strip_place(var, is_len);
                strip_ex(from, is_len);
                strip_ex(limit, is_len);
                strip_block(body, is_len);
            }
            St::Count { counter, body, step, .. } => {
                strip_place(counter, is_len);
                if let Some((p, _)) = step {
                    strip_place(p, is_len);
                }
                strip_block(body, is_len);
            }
            St::DelayUs(e) | St::DelayMs(e) => strip_ex(e, is_len),
            St::Save { body, .. } => strip_block(body, is_len),
            St::Break | St::Continue | St::Return | St::Goto(_) | St::Label(_) | St::Asm(_) | St::Halt | St::Int { .. } => {}
            St::FlashSeek(_, _, e) => {
                if let Some(e) = e {
                    strip_ex(e, is_len);
                }
            }
        }
    }
}

fn strip_args(args: &mut Vec<(Place, Ex)>, is_len: LenTest) {
    args.retain(|(p, _)| !is_len(p));
    for (p, e) in args.iter_mut() {
        strip_place(p, is_len);
        strip_ex(e, is_len);
    }
}

fn strip_place(p: &mut Place, is_len: LenTest) {
    if let Some(i) = &mut p.idx {
        strip_ex(i, is_len);
    }
    if let Some(i) = &mut p.dbit {
        strip_ex(i, is_len);
    }
}

fn strip_ex(e: &mut Ex, is_len: LenTest) {
    match &mut e.k {
        ExK::Const(_) | ExK::FuncAddr(_) | ExK::FlashAddr(..) => {}
        ExK::Load(p) | ExK::Addr(p) => strip_place(p, is_len),
        ExK::Neg(x) | ExK::Com(x) | ExK::Conv(x) | ExK::NotB(x) => strip_ex(x, is_len),
        ExK::Bin(_, a, b) | ExK::Cmp(_, a, b) | ExK::AndAlso(a, b) | ExK::OrElse(a, b) => {
            strip_ex(a, is_len);
            strip_ex(b, is_len);
        }
        ExK::Call(_, args) => strip_args(args, is_len),
        ExK::StrEq(a, b) => {
            for s in [a, b] {
                match s {
                    StrSrc::Ram(p) => strip_place(p, is_len),
                    StrSrc::Char(e) => strip_ex(e, is_len),
                    StrSrc::Lit(_) => {}
                }
            }
        }
    }
}
