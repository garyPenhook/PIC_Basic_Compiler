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

/// A statically allocated object. Every routine has its own frame, so a variable is only live
/// while its routine runs (frames are not overlaid yet; M5).
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
}

#[derive(Clone, Debug, PartialEq)]
pub enum Base {
    Var(VarId),
    /// A device register or other fixed data address. The name is the symbol pic-as knows.
    Abs { addr: u32, name: String },
}

/// A scalar storage place: `bytes` bytes starting `off` bytes into `base`, or a single bit of
/// the byte at `off`.
#[derive(Clone, Debug, PartialEq)]
pub struct Place {
    pub base: Base,
    pub off: u32,
    pub bit: Option<u8>,
    pub ty: Ty,
}

impl Place {
    /// Width in bits of the value the place holds (a bit place reads as 0/1 in 8 bits).
    pub fn width(&self) -> u8 {
        match &self.ty {
            Ty::Int(w, _) => *w,
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
#[derive(Clone, Debug)]
pub struct Ex {
    pub k: ExK,
    pub w: u8,
    pub signed: bool,
}

#[derive(Clone, Debug)]
pub enum ExK {
    /// Value truncated to `w` bits (negative numbers are stored two's complement).
    Const(u32),
    Load(Place),
    Neg(Box<Ex>),
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
    pub fn has_call(&self) -> bool {
        match &self.k {
            ExK::Call(..) => true,
            ExK::Const(_) | ExK::Load(_) => false,
            ExK::Neg(x) | ExK::Com(x) | ExK::Conv(x) | ExK::NotB(x) => x.has_call(),
            ExK::Bin(_, a, b) | ExK::Cmp(_, a, b) | ExK::AndAlso(a, b) | ExK::OrElse(a, b) => a.has_call() || b.has_call(),
        }
    }
    pub fn as_const(&self) -> Option<u32> {
        match self.k {
            ExK::Const(v) => Some(v),
            _ => None,
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
    /// `Input`/`Output` on a port bit or a whole port: sets the matching TRIS bits.
    Direction { place: Place, output: bool },
    Call(FuncId, Vec<(Place, Ex)>),
    If(Vec<(Ex, Vec<S>)>, Vec<S>),
    While(Ex, Vec<S>),
    Repeat(Vec<S>, Ex),
    /// `For`: `var` runs from `from` to the value held in `limit` (a constant, or a hidden
    /// variable evaluated once) in steps of the constant `step`.
    For { var: Place, from: Ex, limit: Ex, step: i64, body: Vec<S> },
    Break,
    Continue,
    Return,
    Goto(LabelId),
    Label(LabelId),
    /// Raw pic-as lines (`Asm … End Asm`).
    Asm(Vec<String>),
    DelayUs(Ex),
    DelayMs(Ex),
    /// `Terminate`: stop forever.
    Halt,
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
}

#[derive(Debug)]
pub struct Program {
    pub vars: Vec<Var>,
    pub funcs: Vec<Func>,
    /// Module initialisation followed by the program body; runs once after reset.
    pub main: Func,
    pub label_names: Vec<String>,
    pub device: String,
    pub clock_mhz: f64,
    /// `CONFIGnX` register name and the byte written to it.
    pub config: Vec<(String, u32, u8)>,
}
