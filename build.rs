//! Embeds `lib/*.bas` and `devices/<part>.toml` in the compiler (see `src/embedded.rs`), so a
//! `basil` binary carries the modules and device descriptions it was built with.

use std::fmt::Write as _;
use std::path::Path;

/// Files of `dir` with extension `ext`, sorted by name; `skip` drops names ending in it.
fn files(dir: &str, ext: &str, skip: &str) -> Vec<String> {
    let mut v: Vec<String> = std::fs::read_dir(dir)
        .map(|rd| rd.flatten().filter_map(|e| e.file_name().into_string().ok()).collect())
        .unwrap_or_default();
    v.retain(|n| n.ends_with(ext) && (skip.is_empty() || !n.ends_with(skip)));
    v.sort();
    v
}

fn main() {
    // PIC16 code generation for larger programs can exceed Windows' default
    // 1 MiB main-thread stack, especially in debug builds. Reserve 8 MiB for
    // the compiler executable (pages are committed only as they are used).
    if std::env::var("CARGO_CFG_TARGET_OS").as_deref() == Ok("windows") {
        let arg = if std::env::var("CARGO_CFG_TARGET_ENV").as_deref() == Ok("msvc") {
            "/STACK:8388608"
        } else {
            "-Wl,--stack,8388608"
        };
        println!("cargo:rustc-link-arg-bin=basil={arg}");
    }
    let root = std::env::var("CARGO_MANIFEST_DIR").unwrap();
    let mut out = String::new();
    let mut hash: u64 = 0xcbf2_9ce4_8422_2325;
    for (konst, dir, ext, skip) in [("LIB", "lib", ".bas", ""), ("DEVICES", "devices", ".toml", ".expect.toml")] {
        println!("cargo:rerun-if-changed={dir}");
        writeln!(out, "pub const {konst}: &[(&str, &str)] = &[").unwrap();
        for name in files(&format!("{root}/{dir}"), ext, skip) {
            let path = format!("{root}/{dir}/{name}");
            println!("cargo:rerun-if-changed={dir}/{name}");
            for b in dir.bytes().chain(name.bytes()).chain(std::fs::read(&path).unwrap()) {
                hash = (hash ^ u64::from(b)).wrapping_mul(0x100_0000_01b3);
            }
            writeln!(out, "    ({name:?}, include_str!({path:?})),").unwrap();
        }
        out.push_str("];\n");
    }
    writeln!(out, "pub const HASH: &str = \"{hash:016x}\";").unwrap();
    let dest = Path::new(&std::env::var("OUT_DIR").unwrap()).join("embedded.rs");
    std::fs::write(dest, out).unwrap();
}
