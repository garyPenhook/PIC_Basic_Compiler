//! The width-annotated intermediate representation (PLAN §7A.1 rule 3, D19).
//!
//! The IR is a resolved, structured tree: names are replaced by storage places, every integer
//! expression carries the bit width it is evaluated at and its signedness, aliases and
//! modifiers are flattened to a byte offset and bit number, and `For`/`Select` are reduced to
//! simpler forms. Control flow stays structured; the code generator chooses the branches.

use crate::diag::Span;
use crate::types::Ty;

pub type VarId = usize;
pub type FuncId = usize;
pub type LabelId = usize;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum VarKind {
    Global,
    Local,
    Param,
    Result,
    /// Compiler-made storage that lives for the whole routine (loop limits, `Select` subjects).
    Hidden,
}

/// A statically allocated object (an array is one object of `bytes` = elements × size). A routine's variables are only live while the routine runs, and
/// the frames of routines that are never live together share addresses (`owner` names the routine).
#[derive(Clone, Debug)]
pub struct Var {
    /// Symbol written to the assembly file.
    pub asm: String,
    /// Name as written in the source, for reports.
    pub name: String,
    pub ty: Ty,
    pub bytes: u32,
    pub kind: VarKind,
    pub owner: Option<FuncId>,
    /// Value stored once at start-up (globals) or on every entry (locals).
    pub init: Option<u32>,
    /// A `ByRef` parameter: the object holds the 16-bit address of the argument, and `ty` is
    /// the type it points to (an array of unknown length for an array parameter).
    pub by_ref: bool,
    /// `Volatile`: other code (a handler, the hardware) may change it at any time, so no pass may
    /// keep its value, merge two accesses or drop one.
    pub volatile: bool,
}

#[derive(Clone, Debug, PartialEq)]
pub enum Base {
    Var(VarId),
    /// The object a `ByRef` parameter points to (the variable holds its address).
    Ptr(VarId),
    /// A device register or other fixed data address. The name is the symbol pic-as knows.
    Abs { addr: u32, name: String },
    /// A constant table in program memory (`Program::flash[i]`), read-only.
    Flash(usize),
    /// A byte of `Program::flash[i]` read through TBLPTR as it stands, advancing it (`TBLRD*+`).
    /// Only loads of one byte; `St::FlashSeek` sets the pointer.
    FlashNext(usize),
}

/// Constant data placed in program memory, labelled `asm`.
#[derive(Clone, Debug)]
pub struct FlashObj {
    pub asm: String,
    pub bytes: Vec<u8>,
}

/// A scalar storage place: `bytes` bytes starting `off` bytes into `base`, or a single bit of
/// the byte at `off`.
#[derive(Clone, Debug, PartialEq)]
pub struct Place {
    pub base: Base,
    pub off: u32,
    pub bit: Option<u8>,
    /// Array element selected at run time: the unsigned 16-bit byte offset from `base + off`.
    pub idx: Option<Box<Ex>>,
    /// Bit of the selected byte chosen at run time (0 to 7), for an element of a packed bit
    /// array; `bit` is then None.
    pub dbit: Option<Box<Ex>>,
    pub ty: Ty,
}

impl Place {
    /// Reached through FSR0 (a run-time array index or a `ByRef` parameter) or, for a constant
    /// table, through TBLPTR: there is no direct memory operand.
    pub fn indirect(&self) -> bool {
        self.idx.is_some() || matches!(self.base, Base::Ptr(_) | Base::Flash(_) | Base::FlashNext(_))
    }
    /// A single bit of a byte, fixed or chosen at run time.
    pub fn is_bit(&self) -> bool {
        self.bit.is_some() || self.dbit.is_some()
    }
    /// Width in bits of the value the place holds (a bit place reads as 0/1 in 8 bits).
    pub fn width(&self) -> u8 {
        match &self.ty {
            Ty::Int(w, _) => *w,
            Ty::Float => 32,
            _ => 8,
        }
    }
    pub fn signed(&self) -> bool {
        matches!(self.ty, Ty::Int(_, true))
    }
    pub fn bytes(&self) -> u32 {
        self.width() as u32 / 8
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum BinKind {
    Add,
    Sub,
    Mul,
    Div,
    Mod,
    And,
    Or,
    Xor,
    Shl,
    Shr,
    /// `Min` / `Max` of any width and signedness (`-O0` and the PIC16 back end expand them by `lower::minmax_expand`).
    Min,
    Max,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum CmpKind {
    Eq,
    Ne,
    Lt,
    Gt,
    Le,
    Ge,
}

impl CmpKind {
    pub fn negate(self) -> CmpKind {
        match self {
            CmpKind::Eq => CmpKind::Ne,
            CmpKind::Ne => CmpKind::Eq,
            CmpKind::Lt => CmpKind::Ge,
            CmpKind::Ge => CmpKind::Lt,
            CmpKind::Gt => CmpKind::Le,
            CmpKind::Le => CmpKind::Gt,
        }
    }
    /// The relation with its operands exchanged: `a < b` is `b > a`.
    pub fn swap(self) -> CmpKind {
        match self {
            CmpKind::Lt => CmpKind::Gt,
            CmpKind::Gt => CmpKind::Lt,
            CmpKind::Le => CmpKind::Ge,
            CmpKind::Ge => CmpKind::Le,
            k => k,
        }
    }
}

/// An expression. `w` is the width in bits the value has (8, 16, 24 or 32) and `signed` how its
/// extension and ordering are read. Boolean values are 0/1 in 8 bits.
#[derive(Clone, Debug, PartialEq)]
pub struct Ex {
    pub k: ExK,
    pub w: u8,
    pub signed: bool,
}

#[derive(Clone, Debug, PartialEq)]
pub enum ExK {
    /// Value truncated to `w` bits (negative numbers are stored two's complement).
    Const(u32),
    Load(Place),
    Neg(Box<Ex>),
    /// Magnitude of a signed value (`-O0` and the PIC16 back end expand it by `lower::abs_expand`).
    Abs(Box<Ex>),
    /// Bitwise complement.
    Com(Box<Ex>),
    Bin(BinKind, Box<Ex>, Box<Ex>),
    /// Converts to `w`/`signed`, extending by the operand's own signedness.
    Conv(Box<Ex>),
    Cmp(CmpKind, Box<Ex>, Box<Ex>),
    /// Short-circuit logic on Boolean operands.
    AndAlso(Box<Ex>, Box<Ex>),
    OrElse(Box<Ex>, Box<Ex>),
    NotB(Box<Ex>),
    Call(FuncId, Vec<(Place, Ex)>),
    /// The 16-bit data address of a place (the argument of a `ByRef` parameter).
    Addr(Place),
    /// The 24-bit program-memory address of a routine, as a 32-bit value (`AddressOf(Routine)`).
    FuncAddr(FuncId),
    /// The 24-bit program-memory address of a constant table plus a byte offset, as a 32-bit value.
    FlashAddr(usize, u32),
    /// `a = b` on strings: 1 when equal. `a` is a RAM string, `b` a RAM string or a literal.
    StrEq(StrSrc, StrSrc),
}

/// One piece of a string value.
#[derive(Clone, Debug, PartialEq)]
pub enum StrSrc {
    /// A `String` variable or `ByRef` string parameter (`Place::ty` is `Str`).
    Ram(Place),
    /// A literal held in program flash (without the terminating Null).
    Lit(Vec<u8>),
    /// A single Char value, appended to the text.
    Char(Box<Ex>),
    /// A concatenation, built into the hidden String `tmp` (its size is the room) when the value
    /// is needed. Only a string comparison takes one.
    Cat { tmp: Place, parts: Vec<StrSrc> },
}

impl Ex {
    pub fn new(k: ExK, w: u8, signed: bool) -> Ex {
        Ex { k, w, signed }
    }
    pub fn konst(v: u32, w: u8, signed: bool) -> Ex {
        Ex { k: ExK::Const(v & mask(w)), w, signed }
    }
    pub fn boolean(k: ExK) -> Ex {
        Ex { k, w: 8, signed: false }
    }
    /// `x` when the expression is `x Xor $80000000`: a Float with its sign bit flipped.
    pub fn sign_flipped(&self) -> Option<&Ex> {
        let ExK::Bin(BinKind::Xor, a, b) = &self.k else { return None };
        if self.w != 32 {
            return None;
        }
        match (a.as_const(), b.as_const()) {
            (None, Some(0x8000_0000)) => Some(a),
            (Some(0x8000_0000), None) => Some(b),
            _ => None,
        }
    }
    pub fn has_call(&self) -> bool {
        match &self.k {
            ExK::Call(..) => true,
            ExK::Const(_) | ExK::FuncAddr(_) | ExK::FlashAddr(..) => false,
            ExK::Load(p) | ExK::Addr(p) => p.idx.as_ref().is_some_and(|i| i.has_call()),
            ExK::Neg(x) | ExK::Com(x) | ExK::Conv(x) | ExK::NotB(x) | ExK::Abs(x) => x.has_call(),
            ExK::Bin(_, a, b) | ExK::Cmp(_, a, b) | ExK::AndAlso(a, b) | ExK::OrElse(a, b) => a.has_call() || b.has_call(),
            ExK::StrEq(a, b) => a.has_call() || b.has_call(),
        }
    }
    /// True when evaluating the expression reads memory through an FSR (an array element or a
    /// `ByRef` parameter), which would disturb a string pointer set up beforehand.
    pub fn uses_fsr(&self) -> bool {
        match &self.k {
            ExK::Const(_) | ExK::FuncAddr(_) | ExK::FlashAddr(..) | ExK::Call(..) => false,
            ExK::Load(p) | ExK::Addr(p) => p.indirect() || p.idx.as_ref().is_some_and(|i| i.uses_fsr()),
            ExK::Neg(x) | ExK::Com(x) | ExK::Conv(x) | ExK::NotB(x) | ExK::Abs(x) => x.uses_fsr(),
            ExK::Bin(_, a, b) | ExK::Cmp(_, a, b) | ExK::AndAlso(a, b) | ExK::OrElse(a, b) => a.uses_fsr() || b.uses_fsr(),
            ExK::StrEq(..) => true,
        }
    }
    pub fn as_const(&self) -> Option<u32> {
        match self.k {
            ExK::Const(v) => Some(v),
            _ => None,
        }
    }
}

impl StrSrc {
    pub fn has_call(&self) -> bool {
        match self {
            StrSrc::Ram(p) => p.idx.as_ref().is_some_and(|i| i.has_call()),
            StrSrc::Lit(_) => false,
            StrSrc::Char(e) => e.has_call(),
            StrSrc::Cat { tmp, parts } => tmp.idx.as_ref().is_some_and(|i| i.has_call()) || parts.iter().any(|p| p.has_call()),
        }
    }
}

pub fn mask(w: u8) -> u32 {
    if w >= 32 { u32::MAX } else { (1u32 << w) - 1 }
}

#[derive(Clone, Debug)]
pub enum St {
    Assign(Place, Ex),
    /// `Inc`/`Dec`: add a constant (two's complement) to a place.
    Add(Place, u32),
    SetBit(Place, bool),
    ToggleBit(Place),
    Clear(Place),
    /// Zero `n` bytes (1 to 255) of a structure or array.
    ClearMem(Place, u32),
    /// Copy `bytes` bytes (1 to 255) from `src` to `dst`, two places of one structure or array type.
    Copy { dst: Place, src: Place, bytes: u32 },
    /// `dst = parts[0] + parts[1] + …`, cut off after `cap` characters and Null-terminated. When
    /// `keep` is set `parts[0]` is `dst` itself and is not copied. Only `parts[0]` may be `dst`.
    StrSet { dst: Place, cap: u32, parts: Vec<StrSrc>, keep: bool },
    /// `Input`/`Output` on a port bit or a whole port: sets the matching TRIS bits.
    Direction { place: Place, output: bool },
    Call(FuncId, Vec<(Place, Ex)>),
    /// Points TBLPTR at byte `n` of `Program::flash[i]`, for the `Base::FlashNext` loads that follow.
    /// With an expression (16 bits, unsigned) its value is added to the offset at run time.
    FlashSeek(usize, u32, Option<Ex>),
    If(Vec<(Ex, Vec<S>)>, Vec<S>),
    While(Ex, Vec<S>),
    Repeat(Vec<S>, Ex),
    /// `For`: `var` runs from `from` to the value held in `limit` (a constant, or a hidden
    /// variable evaluated once) in steps of the constant `step`.
    For { var: Place, from: Ex, limit: Ex, step: i64, body: Vec<S> },
    /// A loop that runs `count` (1 to 255) times, counted down in the hidden Byte `counter` with
    /// `DECFSZ`. With `step` the loop variable is kept up to date (added to between passes); the
    /// body never writes it. Without, the body does not mention the variable at all.
    Count { counter: Place, count: u8, body: Vec<S>, step: Option<(Place, u32)> },
    Break,
    Continue,
    Return,
    Goto(LabelId),
    /// `GoSub`: call the code at the label (of this routine) with the hardware return stack; it ends in `SubRet`.
    GoSub(LabelId),
    /// `Return`: leave the code a `GoSub` entered.
    SubRet,
    Label(LabelId),
    /// Raw pic-as lines (`Asm … End Asm`).
    Asm(Vec<String>),
    DelayUs(Ex),
    DelayMs(Ex),
    /// `Terminate`: stop forever.
    Halt,
    /// `Enable`/`Disable` of the interrupt handler that serves `level`.
    Int { level: Level, on: bool },
    /// `Save … Restore`: `items` are copied to a private save area before `body` and back after
    /// it, including on `Return`, `Break` and `Continue`. `id` names the area.
    Save { id: usize, items: Vec<SaveIt>, body: Vec<S> },
}

/// Which vector a handler serves. `Single` is the compatibility mode (IPEN = 0): one handler
/// at the high vector for every source.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Level {
    Single,
    Low,
    High,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum SaveIt {
    /// The compiler's working registers.
    Regs,
    Var(VarId),
    /// The frame of a routine and of everything it calls.
    Func(FuncId),
}

#[derive(Clone, Debug)]
pub struct S {
    pub st: St,
    pub span: Span,
}

#[derive(Clone, Debug)]
pub struct Func {
    /// Assembly label.
    pub asm: String,
    pub name: String,
    pub params: Vec<VarId>,
    pub result: Option<VarId>,
    pub body: Vec<S>,
    pub span: Span,
    /// A register-call routine (the FloatLib arithmetic): the caller loads the first argument into `__A` and the
    /// second into `__B` instead of storing them in the parameters, and the value comes back in `__A` (WREG when
    /// it is a byte). The parameters and `Result` are never stored.
    pub reg: bool,
    /// An `Extern` routine: its body calls into C, which may use any register XC8 does.
    pub ext: bool,
}

/// A routine implemented in C (`Extern`), as the C stub that keeps it in the link declares it.
#[derive(Clone, Debug)]
pub struct ExternSig {
    /// The C name, spelled as in the `Extern` declaration.
    pub name: String,
    /// Each parameter, in order.
    pub params: Vec<CArg>,
    pub ret: Option<CArg>,
}

/// How a value crosses to C.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum CArg {
    /// Integer, Char or Boolean of this many bytes; signed or not.
    Int(u8, bool),
    /// A Float: four bytes, IEEE 754 single precision, which is XC8's `float`.
    Float,
    /// A `ByRef` argument: the 16-bit data address of the object. The text is the C type it points to
    /// (`unsigned int`, `char`, `const unsigned char`, `struct Pt`), which the C definition must spell the same.
    Ptr(String),
}

impl CArg {
    /// Bytes the value takes in `basil_io`.
    pub fn bytes(&self) -> u8 {
        match self {
            CArg::Int(n, _) => *n,
            CArg::Float => 4,
            CArg::Ptr(_) => 2,
        }
    }

    /// The C type, as the stub declares it.
    pub fn c_type(&self) -> String {
        match self {
            CArg::Float => "float".into(),
            CArg::Ptr(to) => format!("{to} *"),
            CArg::Int(bytes, signed) => match (bytes, signed) {
                (1, false) => "unsigned char",
                (1, true) => "signed char",
                (2, false) => "unsigned int",
                (2, true) => "int",
                (3, false) => "__uint24",
                (3, true) => "__int24",
                (_, false) => "unsigned long",
                (_, true) => "long",
            }
            .into(),
        }
    }
}

/// A Basic routine C may call (`Export`). `thunk` is the routine C's wrapper calls (`_basil_x_<name>`): it moves
/// the arguments from `basil_io` into the parameters of `func`, calls it and moves the result back.
#[derive(Clone, Debug)]
pub struct ExportSig {
    pub name: String,
    pub func: FuncId,
    pub thunk: FuncId,
    /// The thunk's name in C (its assembly label without the leading underscore).
    pub entry: String,
    pub params: Vec<CArg>,
    pub ret: Option<CArg>,
}

impl Program {
    /// The program is linked with C by `xc8-cc`.
    pub fn c_link(&self) -> bool {
        !self.externs.is_empty() || !self.exports.is_empty()
    }
}

#[derive(Clone, Debug)]
pub struct Program {
    /// Routines C may call, and the `Extern` routines through which C runs (each may call any of them).
    pub exports: Vec<ExportSig>,
    pub ext_funcs: Vec<FuncId>,
    /// C routines the program calls and the `CFile` sources that provide them.
    pub externs: Vec<ExternSig>,
    pub cfiles: Vec<String>,
    pub vars: Vec<Var>,
    pub funcs: Vec<Func>,
    /// Constant tables kept in program memory.
    pub flash: Vec<FlashObj>,
    /// Module initialisation followed by the program body; runs once after reset.
    pub main: Func,
    pub label_names: Vec<String>,
    pub device: String,
    pub clock_mhz: f64,
    /// `CONFIGnX` register name and the byte written to it.
    pub config: Vec<(String, u32, u16)>,
    /// Interrupt handlers (each is also an entry of `funcs`).
    pub isrs: Vec<(FuncId, Level)>,
    /// Number of `Save` blocks (`St::Save::id` is below this).
    pub n_saves: usize,
    /// `#option ISR_SHADOW`: a handler may use the hardware shadow registers.
    pub isr_shadow: bool,
    /// `#option FetchNop` (default on): see `codegen16`, erratum 1.3.1 of the PIC16F13145 family.
    pub fetch_nop: bool,
    /// `Option Optimize = Speed`: code that is faster but larger than the size-balanced form is allowed.
    pub speed: bool,
}

impl Place {
    /// True when the place is, or may overlap, the object `v` (directly or through a pointer).
    fn is_var(&self, v: VarId) -> bool {
        matches!(self.base, Base::Var(i) | Base::Ptr(i) if i == v)
    }
    fn touches(&self, v: VarId, reads: bool) -> bool {
        self.is_var(v) || self.idx.as_ref().is_some_and(|i| i.touches(v, reads))
    }
}

impl Ex {
    /// True when the expression changes or exposes variable `v`: its address is taken, or, when
    /// `reads` is set, it is loaded as well.
    pub fn touches(&self, v: VarId, reads: bool) -> bool {
        match &self.k {
            ExK::Const(_) | ExK::FuncAddr(_) | ExK::FlashAddr(..) => false,
            ExK::Load(p) => (reads && p.is_var(v)) || p.idx.as_ref().is_some_and(|i| i.touches(v, reads)),
            ExK::Addr(p) => p.touches(v, reads),
            ExK::Neg(x) | ExK::Com(x) | ExK::Conv(x) | ExK::NotB(x) | ExK::Abs(x) => x.touches(v, reads),
            ExK::Bin(_, a, b) | ExK::Cmp(_, a, b) | ExK::AndAlso(a, b) | ExK::OrElse(a, b) => a.touches(v, reads) || b.touches(v, reads),
            ExK::Call(_, args) => args.iter().any(|(p, e)| p.touches(v, reads) || e.touches(v, reads)),
            ExK::StrEq(a, b) => a.touches(v, reads) || b.touches(v, reads),
        }
    }
}

impl StrSrc {
    fn touches(&self, v: VarId, reads: bool) -> bool {
        match self {
            StrSrc::Ram(p) => (reads && p.is_var(v)) || p.idx.as_ref().is_some_and(|i| i.touches(v, reads)),
            StrSrc::Lit(_) => false,
            StrSrc::Char(e) => e.touches(v, reads),
            StrSrc::Cat { tmp, parts } => tmp.is_var(v) || parts.iter().any(|p| p.touches(v, reads)),
        }
    }
}

/// Whether a statement list stops `var` from being the control of a counted loop.
///
/// With `reads` set the body may not mention `var` at all and may not leave the loop (the
/// variable is then set once, after the loop). Without it the body may read `var` and leave the
/// loop, but may not write it or take its address. In both cases a call is refused when `calls`
/// says the callee could reach `var` (a global), and raw assembly is always refused.
pub fn blocks_count_loop(body: &[S], var: VarId, calls: bool, reads: bool) -> bool {
    let ex = |e: &Ex| e.touches(var, reads) || (calls && e.has_call());
    let sub = |b: &[S]| blocks_count_loop(b, var, calls, reads);
    body.iter().any(|s| match &s.st {
        St::Assign(p, e) => p.touches(var, true) || ex(e),
        St::Add(p, _) | St::SetBit(p, _) | St::ToggleBit(p) | St::Clear(p) | St::ClearMem(p, _) | St::Direction { place: p, .. } => p.touches(var, true),
        St::Copy { dst, src, .. } => dst.touches(var, true) || src.touches(var, reads),
        St::StrSet { dst, parts, .. } => dst.touches(var, true) || parts.iter().any(|p| p.touches(var, reads) || (calls && p.has_call())),
        St::Call(_, args) => calls || args.iter().any(|(p, e)| p.touches(var, true) || ex(e)),
        St::If(arms, other) => arms.iter().any(|(c, b)| ex(c) || sub(b)) || sub(other),
        St::While(c, b) | St::Repeat(b, c) => ex(c) || sub(b),
        St::For { var: p, from, limit, body, .. } => p.touches(var, true) || ex(from) || ex(limit) || sub(body),
        St::Count { counter, body, step, .. } => counter.touches(var, true) || step.as_ref().is_some_and(|(p, _)| p.touches(var, true)) || sub(body),
        St::Asm(_) => true,
        St::Save { items, body, .. } => items.iter().any(|i| *i == SaveIt::Var(var)) || sub(body),
        // A jump out leaves `var` unset when it is only assigned after the loop.
        St::Break | St::Return | St::Goto(_) | St::GoSub(_) | St::SubRet | St::Label(_) | St::Halt => reads,
        St::Continue | St::Int { .. } => false,
        St::FlashSeek(_, _, e) => e.as_ref().is_some_and(ex),
        St::DelayUs(e) | St::DelayMs(e) => ex(e),
    })
}

/// The statement lists nested directly inside `st`.
fn sub_blocks(st: &St) -> Vec<&[S]> {
    match st {
        St::If(arms, other) => arms.iter().map(|(_, b)| b.as_slice()).chain(std::iter::once(other.as_slice())).collect(),
        St::While(_, b) | St::Repeat(b, _) | St::For { body: b, .. } | St::Count { body: b, .. } | St::Save { body: b, .. } => vec![b.as_slice()],
        _ => Vec::new(),
    }
}

/// Whether any statement of `body` (at any depth) reads, writes or takes the address of `var`.
/// Raw assembly counts as a mention; a call does not (a routine's own variables are not visible
/// to its callees).
pub fn mentions(body: &[S], var: VarId) -> bool {
    let ex = |e: &Ex| e.touches(var, true);
    body.iter().any(|s| match &s.st {
        St::Assign(p, e) => p.touches(var, true) || ex(e),
        St::Add(p, _) | St::SetBit(p, _) | St::ToggleBit(p) | St::Clear(p) | St::ClearMem(p, _) | St::Direction { place: p, .. } => p.touches(var, true),
        St::Copy { dst, src, .. } => dst.touches(var, true) || src.touches(var, true),
        St::StrSet { dst, parts, .. } => dst.touches(var, true) || parts.iter().any(|p| p.touches(var, true)),
        St::Call(_, args) => args.iter().any(|(p, e)| p.touches(var, true) || ex(e)),
        St::If(arms, other) => arms.iter().any(|(c, b)| ex(c) || mentions(b, var)) || mentions(other, var),
        St::While(c, b) | St::Repeat(b, c) => ex(c) || mentions(b, var),
        St::For { var: p, from, limit, body, .. } => p.touches(var, true) || ex(from) || ex(limit) || mentions(body, var),
        St::Count { counter, body, step, .. } => counter.touches(var, true) || step.as_ref().is_some_and(|(p, _)| p.touches(var, true)) || mentions(body, var),
        St::Asm(_) => true,
        St::Save { items, body, .. } => items.iter().any(|i| *i == SaveIt::Var(var)) || mentions(body, var),
        St::DelayUs(e) | St::DelayMs(e) => ex(e),
        St::Break | St::Continue | St::Return | St::Goto(_) | St::GoSub(_) | St::SubRet | St::Label(_) | St::Halt | St::Int { .. } => false,
        St::FlashSeek(_, _, e) => e.as_ref().is_some_and(ex),
    })
}

fn has_return(s: &S) -> bool {
    matches!(s.st, St::Return) || sub_blocks(&s.st).into_iter().any(|b| b.iter().any(has_return))
}

fn has_break(s: &S) -> bool {
    matches!(s.st, St::Break) || sub_blocks(&s.st).into_iter().any(|b| b.iter().any(has_break))
}

pub fn has_jump_target(body: &[S]) -> bool {
    body.iter().any(|s| matches!(s.st, St::Label(_) | St::Goto(_) | St::GoSub(_) | St::SubRet) || sub_blocks(&s.st).into_iter().any(has_jump_target))
}

/// Whether the scalar `var` is certainly assigned before anything reads it: the first top-level
/// statement that mentions it is a plain assignment of the whole variable from an expression that
/// does not mention it, and the body has no `Goto`/label that could jump over that assignment.
///
/// A `Return` before that assignment leaves the variable unwritten, which matters only when something
/// reads it after the routine is left (`after_exit`: the `Result`); a local nobody can see again is
/// never read on that path.
pub fn written_first(body: &[S], var: VarId, after_exit: bool) -> bool {
    if has_jump_target(body) {
        return false;
    }
    let Some(at) = body.iter().position(|s| mentions(std::slice::from_ref(s), var)) else { return false };
    // A `Return` before the assignment leaves the variable unwritten.
    if after_exit && body[..at].iter().any(has_return) {
        return false;
    }
    let first = &body[at];
    match &first.st {
        // A loop that always runs its body once: the write may come first inside it, provided
        // nothing before it can leave the loop.
        St::While(c, inner) if c.as_const().is_some_and(|v| v != 0) => !inner.iter().take_while(|s| !mentions(std::slice::from_ref(s), var)).any(has_break) && written_first(inner, var, after_exit),
        St::Assign(p, e) => matches!(p.base, Base::Var(v) if v == var) && p.off == 0 && p.bit.is_none() && p.idx.is_none() && !e.touches(var, true),
        // A `For` sets its variable to `from` before the first test.
        St::For { var: p, from, limit, .. } => matches!(p.base, Base::Var(v) if v == var) && p.off == 0 && p.bit.is_none() && p.idx.is_none() && !from.touches(var, true) && !limit.touches(var, true),
        _ => false,
    }
}

/// The variables a routine body writes and reads itself (not through its callees), and the routines
/// it calls. `None` when that cannot be known: raw assembly, or an access through a `ByRef` pointer
/// (which may reach any object whose address was passed).
#[derive(Clone, Debug, Default)]
pub struct Effects {
    pub writes: std::collections::BTreeSet<VarId>,
    pub reads: std::collections::BTreeSet<VarId>,
    pub calls: std::collections::BTreeSet<FuncId>,
}

impl Effects {
    fn place(&mut self, p: &Place, write: bool) -> Option<()> {
        match p.base {
            Base::Var(v) => {
                if write {
                    self.writes.insert(v);
                } else {
                    self.reads.insert(v);
                }
            }
            Base::Ptr(_) => return None,
            // An indirect-access register reaches whatever RAM its FSR points at.
            Base::Abs { ref name, .. } if indirect_sfr(name) => return None,
            Base::Abs { .. } | Base::Flash(_) | Base::FlashNext(_) => {}
        }
        if let Some(i) = &p.idx {
            self.ex(i)?;
        }
        if let Some(b) = &p.dbit {
            self.ex(b)?;
        }
        Some(())
    }
    fn src(&mut self, s: &StrSrc) -> Option<()> {
        match s {
            StrSrc::Ram(p) => self.place(p, false),
            StrSrc::Lit(_) => Some(()),
            StrSrc::Char(e) => self.ex(e),
            StrSrc::Cat { tmp, parts } => {
                self.place(tmp, true)?;
                self.place(tmp, false)?;
                parts.iter().try_for_each(|p| self.src(p))
            }
        }
    }
    fn call(&mut self, f: FuncId, args: &[(Place, Ex)]) -> Option<()> {
        self.calls.insert(f);
        for (p, e) in args {
            self.place(p, true)?;
            self.ex(e)?;
        }
        Some(())
    }
    fn ex(&mut self, e: &Ex) -> Option<()> {
        match &e.k {
            ExK::Const(_) | ExK::FuncAddr(_) | ExK::FlashAddr(..) => Some(()),
            ExK::Load(p) => self.place(p, false),
            // The address escapes; whatever writes through it is a `ByRef` access, which is unknown.
            ExK::Addr(p) => self.place(p, false),
            ExK::Neg(x) | ExK::Com(x) | ExK::Conv(x) | ExK::NotB(x) | ExK::Abs(x) => self.ex(x),
            ExK::Bin(_, a, b) | ExK::Cmp(_, a, b) | ExK::AndAlso(a, b) | ExK::OrElse(a, b) => {
                self.ex(a)?;
                self.ex(b)
            }
            ExK::Call(f, args) => self.call(*f, args),
            ExK::StrEq(a, b) => {
                self.src(a)?;
                self.src(b)
            }
        }
    }
    /// A read-modify-write of `p` (`Inc`, a bit set, a loop variable).
    fn rmw(&mut self, p: &Place) -> Option<()> {
        self.place(p, true)?;
        self.place(p, false)
    }
    pub fn block(&mut self, body: &[S]) -> Option<()> {
        for s in body {
            match &s.st {
                St::Assign(p, e) => {
                    self.ex(e)?;
                    self.place(p, true)?;
                    // A part of a variable (a byte, a bit) keeps the rest of it.
                    self.place(p, false)?;
                }
                St::Add(p, _) | St::SetBit(p, _) | St::ToggleBit(p) | St::Clear(p) | St::ClearMem(p, _) | St::Direction { place: p, .. } => self.rmw(p)?,
                St::Copy { dst, src, .. } => {
                    self.place(src, false)?;
                    self.rmw(dst)?;
                }
                St::StrSet { dst, parts, .. } => {
                    parts.iter().try_for_each(|p| self.src(p))?;
                    self.rmw(dst)?;
                }
                St::Call(f, args) => self.call(*f, args)?,
                St::FlashSeek(_, _, e) => {
                    if let Some(e) = e {
                        self.ex(e)?;
                    }
                }
                St::If(arms, other) => {
                    for (c, b) in arms {
                        self.ex(c)?;
                        self.block(b)?;
                    }
                    self.block(other)?;
                }
                St::While(c, b) | St::Repeat(b, c) => {
                    self.ex(c)?;
                    self.block(b)?;
                }
                St::For { var, from, limit, body, .. } => {
                    self.ex(from)?;
                    self.ex(limit)?;
                    self.rmw(var)?;
                    self.block(body)?;
                }
                St::Count { counter, body, step, .. } => {
                    self.rmw(counter)?;
                    if let Some((p, _)) = step {
                        self.rmw(p)?;
                    }
                    self.block(body)?;
                }
                St::Asm(_) => return None,
                St::Save { items, body, .. } => {
                    for i in items {
                        match i {
                            SaveIt::Var(v) => {
                                self.writes.insert(*v);
                                self.reads.insert(*v);
                            }
                            SaveIt::Func(_) => return None,
                            SaveIt::Regs => {}
                        }
                    }
                    self.block(body)?;
                }
                St::DelayUs(e) | St::DelayMs(e) => self.ex(e)?,
                St::Break | St::Continue | St::Return | St::Goto(_) | St::GoSub(_) | St::SubRet | St::Label(_) | St::Halt | St::Int { .. } => {}
            }
        }
        Some(())
    }
}

/// `INDFn`, `POSTINCn`, `POSTDECn`, `PREINCn`, `PLUSWn`: a register whose access reads or writes the RAM byte an FSR
/// points at.
pub fn indirect_sfr(name: &str) -> bool {
    let n = name.to_ascii_uppercase();
    ["INDF", "POSTINC", "POSTDEC", "PREINC", "PLUSW"].iter().any(|p| n.strip_prefix(p).is_some_and(|d| d.len() == 1 && d.as_bytes()[0].is_ascii_digit()))
}

/// Whether evaluating `e` reads memory through a pointer: a `ByRef` parameter or an indirect-access register (an
/// array element is a known object and does not count).
pub fn reads_through_pointer(e: &Ex) -> bool {
    let place = |p: &Place| matches!(&p.base, Base::Ptr(_)) || matches!(&p.base, Base::Abs { name, .. } if indirect_sfr(name)) || p.idx.as_ref().is_some_and(|i| reads_through_pointer(i));
    match &e.k {
        ExK::Const(_) | ExK::FuncAddr(_) | ExK::FlashAddr(..) => false,
        ExK::Load(p) | ExK::Addr(p) => place(p),
        ExK::Neg(x) | ExK::Com(x) | ExK::Conv(x) | ExK::NotB(x) | ExK::Abs(x) => reads_through_pointer(x),
        ExK::Bin(_, a, b) | ExK::Cmp(_, a, b) | ExK::AndAlso(a, b) | ExK::OrElse(a, b) => reads_through_pointer(a) || reads_through_pointer(b),
        ExK::Call(_, args) => args.iter().any(|(p, a)| place(p) || reads_through_pointer(a)),
        ExK::StrEq(..) => true,
    }
}

/// For each routine, everything it and the routines it calls may write and read, or `None` when
/// that is unknown for it or for anything it can reach (raw assembly, `ByRef` accesses, C code).
pub fn routine_effects(p: &Program) -> Vec<Option<Effects>> {
    let direct: Vec<Option<Effects>> = p
        .funcs
        .iter()
        .map(|f| {
            if f.ext || f.reg {
                return None;
            }
            let mut e = Effects::default();
            e.block(&f.body)?;
            Some(e)
        })
        .collect();
    (0..direct.len())
        .map(|f| {
            let mut out = Effects::default();
            let mut seen = std::collections::BTreeSet::new();
            let mut todo = vec![f];
            while let Some(g) = todo.pop() {
                if !seen.insert(g) {
                    continue;
                }
                let d = direct.get(g)?.as_ref()?;
                out.writes.extend(d.writes.iter().copied());
                out.reads.extend(d.reads.iter().copied());
                todo.extend(d.calls.iter().copied());
            }
            Some(out)
        })
        .collect()
}

/// Whether the scalar `var` may be read before it is written on some path through `body`: the opposite of the
/// guarantee the entry clear of a local relies on. Conservative: raw assembly, a jump or label, a `Save` of it,
/// a partial write (a byte or bit of it) before a whole write, and any mention that is not a whole write count as a
/// read. With `after_exit` (the `Result`), leaving the routine before a whole write also counts as a read.
pub fn may_read_unset(body: &[S], var: VarId, bytes: u32, after_exit: bool) -> bool {
    if has_jump_target(body) {
        return true;
    }
    let mut set = false;
    let read = rbw_block(body, var, bytes, after_exit, &mut set);
    read || (after_exit && !set)
}

/// The whole of `var` (all `bytes` of it, no bit, no index): `w.Byte0 = k` writes only part of it.
fn whole_of(p: &Place, var: VarId, bytes: u32) -> bool {
    matches!(p.base, Base::Var(v) if v == var) && p.off == 0 && p.bit.is_none() && p.dbit.is_none() && p.idx.is_none() && p.bytes() == bytes
}

fn may_run_zero(from: &Ex, limit: &Ex, step: i64) -> bool {
    match (from.as_const(), limit.as_const()) {
        (Some(a), Some(b)) => {
            let (a, b) = (as_signed(a, from), as_signed(b, limit));
            if step > 0 { a > b } else { a < b }
        }
        _ => true,
    }
}

fn as_signed(v: u32, e: &Ex) -> i64 {
    if e.signed && e.w < 32 && v & (1 << (e.w - 1)) != 0 {
        v as i64 - (1i64 << e.w)
    } else if e.signed && e.w == 32 {
        v as i32 as i64
    } else {
        v as i64
    }
}

/// A `Break`/`Continue` that leaves (or restarts) the loop whose body is `b`: not those inside nested loops.
fn leaves_loop(b: &[S]) -> bool {
    b.iter().any(|s| match &s.st {
        St::Break | St::Continue => true,
        St::If(..) | St::Save { .. } => sub_blocks(&s.st).into_iter().any(leaves_loop),
        _ => false,
    })
}

/// Walks `body` in order with `set` (the variable is certainly written whole on every path so far); returns true
/// at the first possible read while it is not set.
fn rbw_block(body: &[S], var: VarId, bytes: u32, after_exit: bool, set: &mut bool) -> bool {
    let ex = |e: &Ex, set: bool| !set && e.touches(var, true);
    for s in body {
        match &s.st {
            St::Assign(p, e) => {
                if ex(e, *set) || p.idx.as_ref().is_some_and(|i| ex(i, *set)) {
                    return true;
                }
                if whole_of(p, var, bytes) {
                    *set = true;
                } else if p.touches(var, true) && !*set {
                    return true;
                }
            }
            St::Clear(p) => {
                if whole_of(p, var, bytes) {
                    *set = true;
                } else if p.touches(var, true) && !*set {
                    return true;
                }
            }
            St::Add(p, _) | St::SetBit(p, _) | St::ToggleBit(p) | St::ClearMem(p, _) | St::Direction { place: p, .. } => {
                if p.touches(var, true) && !*set {
                    return true;
                }
            }
            St::Copy { dst, src, .. } => {
                if !*set && (dst.touches(var, true) || src.touches(var, true)) {
                    return true;
                }
            }
            St::StrSet { dst, parts, .. } => {
                if !*set && (dst.touches(var, true) || parts.iter().any(|p| p.touches(var, true))) {
                    return true;
                }
            }
            St::Call(_, args) => {
                if args.iter().any(|(p, e)| ex(e, *set) || (!*set && p.touches(var, true))) {
                    return true;
                }
            }
            St::FlashSeek(_, _, e) => {
                if e.as_ref().is_some_and(|e| ex(e, *set)) {
                    return true;
                }
            }
            St::DelayUs(e) | St::DelayMs(e) => {
                if ex(e, *set) {
                    return true;
                }
            }
            St::If(arms, other) => {
                let before = *set;
                let mut all = true;
                for (c, b) in arms {
                    if ex(c, before) {
                        return true;
                    }
                    let mut s2 = before;
                    if rbw_block(b, var, bytes, after_exit, &mut s2) {
                        return true;
                    }
                    all &= s2;
                }
                let mut s2 = before;
                if rbw_block(other, var, bytes, after_exit, &mut s2) {
                    return true;
                }
                *set = before || (all && s2);
            }
            St::While(c, b) => {
                if ex(c, *set) {
                    return true;
                }
                let mut s2 = *set;
                if rbw_block(b, var, bytes, after_exit, &mut s2) {
                    return true;
                }
                // The test runs again after the body, with at least what was set before it; the body may not run at
                // all, so nothing it sets carries past the loop.
            }
            St::Repeat(b, c) => {
                let mut s2 = *set;
                if rbw_block(b, var, bytes, after_exit, &mut s2) {
                    return true;
                }
                let s2 = s2 && !leaves_loop(b);
                if ex(c, s2) {
                    return true;
                }
                *set = s2;
            }
            St::For { var: p, from, limit, step, body } => {
                if ex(from, *set) || ex(limit, *set) {
                    return true;
                }
                if whole_of(p, var, bytes) {
                    *set = true;
                } else if p.touches(var, true) && !*set {
                    return true;
                }
                let mut s2 = *set;
                if rbw_block(body, var, bytes, after_exit, &mut s2) {
                    return true;
                }
                if !may_run_zero(from, limit, *step) && !leaves_loop(body) {
                    *set = s2;
                }
            }
            St::Count { counter, body, step, .. } => {
                if !*set && (counter.touches(var, true) || step.as_ref().is_some_and(|(p, _)| p.touches(var, true))) {
                    return true;
                }
                let mut s2 = *set;
                if rbw_block(body, var, bytes, after_exit, &mut s2) {
                    return true;
                }
                // `count` is 1 to 255: the body runs at least once.
                if !leaves_loop(body) {
                    *set = s2;
                }
            }
            St::Asm(_) => return true,
            St::Save { items, body, .. } => {
                if items.iter().any(|i| *i == SaveIt::Var(var)) {
                    return true;
                }
                if rbw_block(body, var, bytes, after_exit, set) {
                    return true;
                }
            }
            St::Return => {
                if after_exit && !*set {
                    return true;
                }
            }
            St::Goto(_) | St::GoSub(_) | St::SubRet | St::Label(_) => return true,
            St::Break | St::Continue | St::Halt | St::Int { .. } => {}
        }
    }
    false
}
