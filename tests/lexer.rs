use basil::diag::Diagnostics;
use basil::lexer::{Tok, lex};

fn toks(src: &str) -> (Vec<Tok>, Diagnostics) {
    let mut d = Diagnostics::default();
    let t = lex(0, src, &mut d).into_iter().map(|t| t.tok).collect();
    (t, d)
}

fn strip(mut v: Vec<Tok>) -> Vec<Tok> {
    v.retain(|t| !matches!(t, Tok::Newline | Tok::Eof));
    v
}

#[test]
fn numbers() {
    let (t, d) = toks("100 $FF %1010 3.14 1.0e3 2.5E-2 #65 #$41");
    assert!(!d.has_errors());
    assert_eq!(
        strip(t),
        vec![Tok::Int(100), Tok::Int(255), Tok::Int(10), Tok::Float(3.14), Tok::Float(1000.0), Tok::Float(0.025), Tok::CharCode(65), Tok::CharCode(65)]
    );
}

#[test]
fn keywords_are_case_insensitive_and_identifiers_keep_spelling() {
    let (t, _) = toks("DIM Counter aS bYtE");
    assert_eq!(strip(t), vec![Tok::Kw("dim"), Tok::Ident("Counter".into()), Tok::Kw("as"), Tok::Kw("byte")]);
}

#[test]
fn bit_index_is_not_a_float() {
    let (t, _) = toks("PORTB.0 x.7");
    assert_eq!(
        strip(t),
        vec![Tok::Ident("PORTB".into()), Tok::Punct("."), Tok::Int(0), Tok::Ident("x".into()), Tok::Punct("."), Tok::Int(7)]
    );
}

#[test]
fn comments_nest_and_continue_lines() {
    let (t, d) = toks("a ' c\nb // c\n(* x (* y *) z *) c { d } e\nf _\n g");
    assert!(!d.has_errors(), "{:?}", d.items);
    let names: Vec<String> = strip(t).into_iter().filter_map(|t| if let Tok::Ident(n) = t { Some(n) } else { None }).collect();
    assert_eq!(names, ["a", "b", "c", "e", "f", "g"]);
}

#[test]
fn underscore_identifier_is_not_a_continuation() {
    let (t, _) = toks("x = _y");
    assert_eq!(strip(t), vec![Tok::Ident("x".into()), Tok::Punct("="), Tok::Ident("_y".into())]);
}

#[test]
fn asm_body_is_raw() {
    let (t, d) = toks("Asm\n  movlw 0x55 ; 'x (* not a comment\n  bra $-2\nEnd Asm\n");
    assert!(!d.has_errors());
    let raw = t.iter().find_map(|t| if let Tok::RawAsm(l) = t { Some(l.clone()) } else { None }).expect("raw asm token");
    assert_eq!(raw, vec!["  movlw 0x55 ; 'x (* not a comment", "  bra $-2"]);
    assert!(t.contains(&Tok::Kw("end")));
}

#[test]
fn lexical_errors_are_reported() {
    for (src, why) in [("\"abc", "unterminated string"), ("(* open", "unclosed comment"), ("a ` b", "bad character"), ("99999999999999999999999", "huge integer"), ("$", "bare dollar"), ("#999", "char code range")] {
        let (_, d) = toks(src);
        assert!(d.has_code("E-LEX"), "{why}");
    }
}
