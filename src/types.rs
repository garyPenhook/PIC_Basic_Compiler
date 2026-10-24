//! The language's types and compile-time values (LANGUAGE.md §3, §5.3).

use std::fmt;

pub type SymId = usize;

#[derive(Clone, Debug, PartialEq)]
pub enum Ty {
    Bool,
    Bit,
    /// Integer of the given width in bits (8, 16, 24 or 32) and signedness. 24 only appears as an
    /// internal width chosen by later passes (D19); the language types are 8, 16 and 32.
    Int(u8, bool),
    Float,
    Char,
    /// `String(n)`: up to n characters plus the terminating Null.
    Str(u32),
    Struct(SymId),
    /// A variable of an `Event()` type.
    EventVar(SymId),
    /// The type of an event handler name; assignable to any `EventVar`.
    EventAny,
    Array(Box<Ty>, u32),
    /// No value: the result of a subroutine call.
    Void,
}

pub const BYTE: Ty = Ty::Int(8, false);
pub const SHORTINT: Ty = Ty::Int(8, true);
pub const WORD: Ty = Ty::Int(16, false);
pub const INTEGER: Ty = Ty::Int(16, true);
pub const LONGWORD: Ty = Ty::Int(32, false);
pub const LONGINT: Ty = Ty::Int(32, true);

pub const DEFAULT_STRING_SIZE: u32 = 24;

impl Ty {
    pub fn is_int(&self) -> bool {
        matches!(self, Ty::Int(..))
    }
    /// Integers, and `Bit` which takes part in arithmetic as an unsigned 0/1.
    pub fn is_numeric_int(&self) -> bool {
        matches!(self, Ty::Int(..) | Ty::Bit)
    }
    pub fn is_numeric(&self) -> bool {
        self.is_numeric_int() || matches!(self, Ty::Float)
    }
    /// Width in bits when used as an arithmetic operand.
    pub fn width(&self) -> Option<u8> {
        match self {
            Ty::Int(w, _) => Some(*w),
            Ty::Bit => Some(8),
            Ty::Float => Some(32),
            _ => None,
        }
    }
    pub fn signed(&self) -> bool {
        matches!(self, Ty::Int(_, true) | Ty::Float)
    }
    /// RAM bytes the type occupies. Bit and Boolean arrays are packed.
    pub fn size_bytes(&self, struct_size: &dyn Fn(SymId) -> u32) -> u32 {
        match self {
            Ty::Bool | Ty::Bit | Ty::Char => 1,
            Ty::Int(w, _) => (*w as u32).div_ceil(8),
            Ty::Float => 4,
            Ty::Str(n) => n + 1,
            Ty::Struct(s) => struct_size(*s),
            Ty::EventVar(_) | Ty::EventAny => 3,
            Ty::Array(e, n) => match **e {
                Ty::Bit | Ty::Bool => n.div_ceil(8),
                _ => e.size_bytes(struct_size) * n,
            },
            Ty::Void => 0,
        }
    }
    /// Value range of an integer type.
    pub fn int_range(&self) -> Option<(i128, i128)> {
        match self {
            Ty::Int(w, true) => Some((-(1i128 << (w - 1)), (1i128 << (w - 1)) - 1)),
            Ty::Int(w, false) => Some((0, (1i128 << w) - 1)),
            Ty::Bit => Some((0, 1)),
            _ => None,
        }
    }
}

impl fmt::Display for Ty {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Ty::Bool => write!(f, "Boolean"),
            Ty::Bit => write!(f, "Bit"),
            Ty::Int(8, false) => write!(f, "Byte"),
            Ty::Int(8, true) => write!(f, "ShortInt"),
            Ty::Int(16, false) => write!(f, "Word"),
            Ty::Int(16, true) => write!(f, "Integer"),
            Ty::Int(32, false) => write!(f, "LongWord"),
            Ty::Int(32, true) => write!(f, "LongInt"),
            Ty::Int(w, s) => write!(f, "{}{w}", if *s { "Int" } else { "UInt" }),
            Ty::Float => write!(f, "Float"),
            Ty::Char => write!(f, "Char"),
            Ty::Str(n) => write!(f, "String({n})"),
            Ty::Struct(_) => write!(f, "structure"),
            Ty::EventVar(_) => write!(f, "event variable"),
            Ty::EventAny => write!(f, "event handler"),
            Ty::Array(e, n) => write!(f, "array of {n} {e}"),
            Ty::Void => write!(f, "no value"),
        }
    }
}

/// A value known at compile time.
#[derive(Clone, Debug, PartialEq)]
pub enum CVal {
    Int(i128),
    Float(f64),
    Bool(bool),
    Str(String),
}

impl CVal {
    pub fn as_int(&self) -> Option<i128> {
        match self {
            CVal::Int(v) => Some(*v),
            CVal::Bool(_) | CVal::Float(_) | CVal::Str(_) => None,
        }
    }
    pub fn as_f64(&self) -> Option<f64> {
        match self {
            CVal::Int(v) => Some(*v as f64),
            CVal::Float(v) => Some(*v),
            _ => None,
        }
    }
}

/// The narrowest language integer type that holds `v`: unsigned for non-negative values.
pub fn narrowest(v: i128) -> Ty {
    if v >= 0 {
        if v <= 0xFF {
            BYTE
        } else if v <= 0xFFFF {
            WORD
        } else {
            LONGWORD
        }
    } else if v >= -0x80 {
        SHORTINT
    } else if v >= -0x8000 {
        INTEGER
    } else {
        LONGINT
    }
}

/// Smallest width (8, 16, 32) at which `v` fits as a signed value, or None when it does not fit
/// 32 bits.
pub fn signed_width_for(v: i128) -> Option<u8> {
    [8u8, 16, 32].into_iter().find(|w| v >= -(1i128 << (w - 1)) && v <= (1i128 << (w - 1)) - 1)
}

/// Smallest width at which `v` fits as an unsigned value.
pub fn unsigned_width_for(v: i128) -> Option<u8> {
    if v < 0 { None } else { [8u8, 16, 32].into_iter().find(|w| v < (1i128 << w)) }
}
