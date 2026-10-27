//! The library modules and device descriptions built into the compiler.
//!
//! The rest of the compiler reads both from folders, so the embedded copy is written once to a cache
//! folder named by a hash of its contents and searched last. A `lib/` or `devices/` folder found
//! next to the program, or given with `-L` / `--devices`, still wins.

use std::path::{Path, PathBuf};

include!(concat!(env!("OUT_DIR"), "/embedded.rs"));

/// The cache folder holding the embedded `lib/` and `devices/`, written first if it is missing.
/// `None` when no folder can be written; the compiler then only uses the folders it can find.
pub fn dirs() -> Option<(PathBuf, PathBuf)> {
    let base = std::env::var_os("XDG_CACHE_HOME")
        .map(PathBuf::from)
        .or_else(|| std::env::var_os("HOME").map(|h| Path::new(&h).join(".cache")))
        .unwrap_or_else(std::env::temp_dir)
        .join("basil")
        .join(HASH);
    let (lib, dev) = (base.join("lib"), base.join("devices"));
    // The marker is written last, so a run that stopped half way is redone, not trusted.
    let done = base.join("complete");
    if !done.is_file() {
        for (dir, set) in [(&lib, LIB), (&dev, DEVICES)] {
            std::fs::create_dir_all(dir).ok()?;
            for (name, text) in set {
                write_atomic(&dir.join(name), text)?;
            }
        }
        std::fs::write(&done, HASH).ok()?;
    }
    Some((lib, dev))
}

/// Write through a temporary name and rename, so a second `basil` starting at the same moment
/// never reads a half-written file.
fn write_atomic(path: &Path, text: &str) -> Option<()> {
    let tmp = path.with_extension(format!("tmp{}", std::process::id()));
    std::fs::write(&tmp, text).ok()?;
    std::fs::rename(&tmp, path).ok()
}
