//! Abstract syntax tree. Names keep their written spelling; compare them with `Ident::key`.
//! Every expression and designator has a unique `NodeId` that the semantic pass uses to attach
//! types and resolutions without mutating the tree.

use crate::diag::Span;

pub type NodeId = u32;

#[derive(Clone, Debug)]
pub struct Ident {
    pub name: String,
    pub span: Span,
}

impl Ident {
    /// Case-folded form used for all comparisons (D10).
    pub fn key(&self) -> String {
        self.name.to_ascii_lowercase()
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum UnitKind {
    Program,
    Module,
}

#[derive(Debug)]
pub struct Unit {
    pub kind: UnitKind,
    pub name: Option<Ident>,
    pub file: u32,
    pub headers: Vec<Header>,
    pub includes: Vec<Include>,
    pub decls: Vec<Decl>,
    pub stmts: Vec<Stmt>,
}

#[derive(Debug)]
pub struct Include {
    pub name: String,
    pub span: Span,
}

#[derive(Debug)]
pub enum HeaderKind {
    /// `Device = 18F27Q10` / `PIC18F27Q10`; the text is the canonical spelling without spaces.
    Device(String),
    Clock(Expr),
    Config(Vec<ConfigItem>),
    /// `CFile "crc.c"`: a C source file linked into the program (see `Extern`).
    CFile(String),
}

#[derive(Debug)]
pub struct Header {
    pub kind: HeaderKind,
    pub span: Span,
}

#[derive(Debug)]
pub struct ConfigItem {
    pub name: Ident,
    pub value: ConfigValue,
}

#[derive(Debug)]
pub enum ConfigValue {
    Name(Ident),
    Int(u64, Span),
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Vis {
    Public,
    Private,
}

#[derive(Debug)]
pub struct Decl {
    pub vis: Option<Vis>,
    pub span: Span,
    pub kind: DeclKind,
}

#[derive(Debug)]
pub enum DeclKind {
    Const(Vec<ConstItem>),
    Dim(DimDecl),
    Structure(StructDecl),
    /// `Type TName = Event()`
    EventType(Ident, Vec<Param>),
    /// `Symbol Name [=] Value`: a constant or an alias, decided by the semantic pass.
    Symbol(Ident, Expr),
    Routine(Routine),
    Interrupt(InterruptDecl),
    Event(EventDecl),
}

#[derive(Debug)]
pub struct ConstItem {
    pub name: Ident,
    pub size: Option<Expr>,
    pub ty: Option<TypeSpec>,
    pub init: ConstInit,
}

#[derive(Debug)]
pub enum ConstInit {
    Scalar(Expr),
    List(Vec<Expr>),
}

#[derive(Debug)]
pub struct DimDecl {
    /// `Static Dim`: a local that keeps its value between calls.
    pub is_static: bool,
    /// `Volatile Dim`: every access reaches memory, in the order written.
    pub is_volatile: bool,
    pub items: Vec<DimItem>,
    pub as_clause: Option<AsClause>,
    /// Initialiser written after the `As` clause (`Dim n As Byte = 10`).
    pub trailing_init: Option<Expr>,
    /// Array initialiser written after the `As` clause (`Dim a(3) As Byte = (1, 2, 3)`).
    pub trailing_list: Option<Vec<Expr>>,
}

#[derive(Debug)]
pub struct DimItem {
    pub name: Ident,
    pub size: Option<Expr>,
    /// The sizes of the second and later dimensions of `Dim m(3, 4)`; `size` is the first.
    pub more_dims: Vec<Expr>,
    pub init: Option<Expr>,
    /// Array initialiser written before the `As` clause: `Dim a(3) = (1, 2, 3) As Byte`.
    pub list: Option<Vec<Expr>>,
}

/// What follows `As`: a built-in type, or a designator that is either a user type name or the
/// target of an alias. Which one is decided by the semantic pass.
#[derive(Debug)]
pub enum AsClause {
    Type(TypeSpec),
    Designator(Designator),
}

#[derive(Debug)]
pub enum TypeSpec {
    Boolean,
    Bit,
    Byte,
    ShortInt,
    Word,
    Integer,
    LongWord,
    LongInt,
    Float,
    Char,
    String(Option<Box<Expr>>),
    Named(Ident),
}

#[derive(Debug)]
pub struct StructDecl {
    pub name: Ident,
    pub fields: Vec<Field>,
}

#[derive(Debug)]
pub struct Field {
    pub name: Ident,
    pub size: Option<Expr>,
    pub as_clause: AsClause,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Inlining {
    Default,
    Inline,
    NoInline,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ParamMode {
    ByVal,
    ByRef,
    ByRefConst,
}

#[derive(Debug)]
pub struct Param {
    pub mode: ParamMode,
    pub mode_explicit: bool,
    pub name: Ident,
    /// Written `name() As Type`.
    pub is_array: bool,
    pub ty: TypeSpec,
    pub default: Option<Expr>,
}

#[derive(Debug)]
pub struct Body {
    pub decls: Vec<Decl>,
    pub stmts: Vec<Stmt>,
}

#[derive(Debug)]
pub struct Routine {
    pub name: Ident,
    pub is_function: bool,
    pub inlining: Inlining,
    pub reentrant: bool,
    /// `Extern Sub/Function`: implemented in C; the body is empty.
    pub ext: bool,
    pub params: Vec<Param>,
    pub ret: Option<TypeSpec>,
    pub body: Body,
}

#[derive(Debug)]
pub struct InterruptDecl {
    pub name: Ident,
    pub priority: Option<Expr>,
    pub body: Body,
}

#[derive(Debug)]
pub struct EventDecl {
    pub name: Ident,
    pub params: Vec<Param>,
    pub body: Body,
}

#[derive(Debug)]
pub struct Stmt {
    pub span: Span,
    pub kind: StmtKind,
}

#[derive(Debug)]
pub enum StmtKind {
    Assign { target: Designator, value: Expr },
    Call(Designator),
    If { arms: Vec<(Expr, Vec<Stmt>)>, otherwise: Option<Vec<Stmt>> },
    IfGoto { cond: Expr, label: Ident },
    Select { subject: Expr, cases: Vec<Case>, otherwise: Option<Vec<Stmt>> },
    While { cond: Expr, body: Vec<Stmt> },
    Repeat { body: Vec<Stmt>, until: Expr },
    For { var: Designator, from: Expr, to: Expr, step: Option<Expr>, body: Vec<Stmt> },
    Break,
    Continue,
    Exit,
    GoTo(Ident),
    Label(Ident),
    Save { items: Vec<SaveItem>, body: Vec<Stmt> },
    Asm { preserves: Vec<Ident>, lines: Vec<String> },
    Enable(Ident),
    Disable(Ident),
}

#[derive(Debug)]
pub struct Case {
    pub conds: Vec<CaseCond>,
    pub body: Vec<Stmt>,
    pub span: Span,
}

#[derive(Debug)]
pub enum CaseCond {
    Value(Expr),
    Range(Expr, Expr),
    Rel(BinOp, Expr),
}

#[derive(Debug)]
pub enum SaveItem {
    Designator(Designator),
    /// `0`: the compiler's working registers.
    Int(u64, Span),
}

#[derive(Debug)]
pub struct Expr {
    pub id: NodeId,
    pub span: Span,
    pub kind: ExprKind,
}

#[derive(Debug)]
pub enum ExprKind {
    Int(u64),
    Float(f64),
    Str(String),
    Char(u32),
    Bool(bool),
    Null,
    Designator(Designator),
    Unary(UnOp, Box<Expr>),
    Binary(BinOp, Box<Expr>, Box<Expr>),
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum UnOp {
    Neg,
    Plus,
    Not,
    AddressOf,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum BinOp {
    Or,
    Xor,
    And,
    Eq,
    Ne,
    Lt,
    Gt,
    Le,
    Ge,
    Shl,
    Shr,
    Add,
    Sub,
    Mul,
    Div,
    Mod,
}

impl BinOp {
    pub fn is_relational(self) -> bool {
        matches!(self, BinOp::Eq | BinOp::Ne | BinOp::Lt | BinOp::Gt | BinOp::Le | BinOp::Ge)
    }
    pub fn is_logical_or_bitwise(self) -> bool {
        matches!(self, BinOp::Or | BinOp::Xor | BinOp::And)
    }
}

/// `name { .field | .bit | (args) }`: a variable, field, modifier, index or call.
#[derive(Debug)]
pub struct Designator {
    pub id: NodeId,
    pub span: Span,
    pub head: Ident,
    pub parts: Vec<Part>,
}

#[derive(Debug)]
pub enum Part {
    /// `.name`: a field, a modifier or a qualified name.
    Member(Ident),
    /// `.7`: a bit number.
    BitIndex(u64, Span),
    /// `(a, b)`: an index or call arguments.
    Args(Vec<Expr>, Span),
}
