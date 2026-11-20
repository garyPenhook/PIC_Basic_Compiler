//! basil front end: lexer, parser, AST and semantic analysis (milestone M3).

pub mod asm;
pub mod ast;
pub mod codegen;
pub mod codegen16;
pub mod diag;
pub mod dwarf;
pub mod driver;
pub mod embedded;
pub mod explain;
pub mod ir;
pub mod lexer;
pub mod listing;
pub mod lower;
pub mod opt;
pub mod parser;
pub mod outline;
pub mod peephole;
pub mod pp;
pub mod project;
pub mod sema;
pub mod suggest;
pub mod toolchain;
pub mod types;
