//! basil front end: lexer, parser, AST and semantic analysis (milestone M3).

pub mod asm;
pub mod ast;
pub mod codegen;
pub mod diag;
pub mod dwarf;
pub mod driver;
pub mod ir;
pub mod lexer;
pub mod lower;
pub mod opt;
pub mod parser;
pub mod peephole;
pub mod pp;
pub mod project;
pub mod sema;
pub mod types;
