//! Finding the Microchip tools (pic-as, xc8-cc) and the device packs on the user's machine.
//!
//! Every lookup is a pure function of its inputs (explicit path, environment value, `PATH`, install roots), so
//! the tests drive it with temporary folders; the `find_*` functions at the bottom feed it the real environment.

use std::ffi::OsString;
use std::path::{Path, PathBuf};

/// The user's home folder: `HOME`, else `USERPROFILE` (Windows).
pub fn home_dir() -> Option<PathBuf> {
    ["HOME", "USERPROFILE"].iter().filter_map(|v| std::env::var_os(v)).find(|v| !v.is_empty()).map(PathBuf::from)
}

/// The numbers in a folder name, so `v2.46` sorts after `v2.5` (a plain string sort puts it before).
pub fn version_key(name: &str) -> Vec<u64> {
    let mut key = Vec::new();
    let mut cur: Option<u64> = None;
    for c in name.chars() {
        match c.to_digit(10) {
            Some(d) => cur = Some(cur.unwrap_or(0).saturating_mul(10).saturating_add(d as u64)),
            None => key.extend(cur.take()),
        }
    }
    key.extend(cur);
    key
}

/// The subfolders of `root` for which `has` holds, newest version first.
fn versions_in(root: &Path, has: impl Fn(&Path) -> bool) -> Vec<(String, PathBuf)> {
    let mut v: Vec<(String, PathBuf)> = std::fs::read_dir(root)
        .into_iter()
        .flatten()
        .filter_map(|e| e.ok())
        .filter(|e| has(&e.path()))
        .map(|e| (e.file_name().to_string_lossy().into_owned(), e.path()))
        .collect();
    v.sort_by(|a, b| version_key(&b.0).cmp(&version_key(&a.0)).then_with(|| b.0.cmp(&a.0)));
    v
}

/// Where MPLAB XC8 installs (one folder per version below each).
pub fn xc8_roots() -> Vec<PathBuf> {
    if cfg!(windows) {
        let pf = std::env::var_os("ProgramFiles").map(PathBuf::from).unwrap_or_else(|| PathBuf::from(r"C:\Program Files"));
        vec![pf.join("Microchip").join("xc8")]
    } else if cfg!(target_os = "macos") {
        vec![PathBuf::from("/Applications/microchip/xc8")]
    } else {
        vec![PathBuf::from("/opt/microchip/xc8")]
    }
}

/// Where MPLAB X installs (one folder per version below each; its packs are in `<version>/packs`).
fn mplabx_roots() -> Vec<PathBuf> {
    if cfg!(windows) {
        let pf = std::env::var_os("ProgramFiles").map(PathBuf::from).unwrap_or_else(|| PathBuf::from(r"C:\Program Files"));
        vec![pf.join("Microchip").join("MPLABX")]
    } else if cfg!(target_os = "macos") {
        vec![PathBuf::from("/Applications/microchip/mplabx")]
    } else {
        vec![PathBuf::from("/opt/microchip/mplabx")]
    }
}

fn exe(name: &str) -> String {
    format!("{name}{}", std::env::consts::EXE_SUFFIX)
}

/// Where a lookup looked, in order, for the error message.
pub type Searched = Vec<String>;

/// The inputs of the pic-as lookup.
pub struct PicAsSearch<'a> {
    /// `--pic-as`
    pub cli: Option<&'a Path>,
    /// `BASIL_PICAS`
    pub env: Option<OsString>,
    /// the folders of `PATH`
    pub path_dirs: Vec<PathBuf>,
    /// the XC8 install roots
    pub roots: Vec<PathBuf>,
}

/// The first pic-as found: `--pic-as`, `BASIL_PICAS`, `PATH`, then the newest XC8 install.
/// An explicit path that is not a file is an error, not a reason to fall through to another pic-as.
pub fn search_pic_as(s: &PicAsSearch) -> Result<PathBuf, Searched> {
    let mut searched = Vec::new();
    for (what, p) in [("--pic-as", s.cli.map(Path::to_path_buf)), ("BASIL_PICAS", s.env.as_ref().filter(|v| !v.is_empty()).map(PathBuf::from))] {
        if let Some(p) = p {
            if p.is_file() {
                return Ok(p);
            }
            searched.push(format!("{what} = {} (no such file)", p.display()));
            return Err(searched);
        }
    }
    let name = exe("pic-as");
    for d in &s.path_dirs {
        let p = d.join(&name);
        if p.is_file() {
            return Ok(p);
        }
    }
    searched.push(format!("{name} on PATH"));
    for root in &s.roots {
        if let Some((_, dir)) = versions_in(root, |d| d.join("pic-as").join("bin").join(&name).is_file()).into_iter().next() {
            return Ok(dir.join("pic-as").join("bin").join(&name));
        }
        searched.push(format!("{}{}*{}pic-as{}bin{}{name}", root.display(), std::path::MAIN_SEPARATOR, std::path::MAIN_SEPARATOR, std::path::MAIN_SEPARATOR, std::path::MAIN_SEPARATOR));
    }
    Err(searched)
}

/// The xc8-cc of the same install as `pic_as`: `<xc8>/pic-as/bin/pic-as` sits beside `<xc8>/bin/xc8-cc`.
/// `env` is `BASIL_XC8CC`.
pub fn search_xc8_cc(pic_as: &Path, env: Option<OsString>) -> Result<PathBuf, Searched> {
    if let Some(p) = env.filter(|v| !v.is_empty()).map(PathBuf::from) {
        return if p.is_file() { Ok(p) } else { Err(vec![format!("BASIL_XC8CC = {} (no such file)", p.display())]) };
    }
    let name = exe("xc8-cc");
    let p = pic_as.parent().and_then(Path::parent).and_then(Path::parent).map(|x| x.join("bin").join(&name));
    match p {
        Some(p) if p.is_file() => Ok(p),
        Some(p) => Err(vec![p.display().to_string()]),
        None => Err(vec![format!("{name} beside {}", pic_as.display())]),
    }
}

/// A device pack's `xc8` folder and which version of the pack it is.
#[derive(Debug, PartialEq)]
pub struct Dfp {
    pub dir: PathBuf,
    pub version: String,
    /// false when the version the device file names is not installed and this is the newest other one
    pub exact: bool,
}

/// The inputs of the pack lookup.
pub struct DfpSearch<'a> {
    /// `--dfp` (the pack's `xc8` folder), else `BASIL_DFP`
    pub explicit: Option<PathBuf>,
    /// folders holding `<pack>/<version>/xc8`
    pub roots: Vec<PathBuf>,
    pub pack: &'a str,
    pub version: &'a str,
}

/// The pack to build with. An explicit folder wins; otherwise the exact version in the first root that has it;
/// otherwise the newest installed version of the same pack, which the caller warns about.
pub fn search_dfp(s: &DfpSearch) -> Result<Dfp, Searched> {
    if let Some(p) = &s.explicit {
        return if p.is_dir() { Ok(Dfp { dir: p.clone(), version: s.version.to_string(), exact: true }) } else { Err(vec![format!("--dfp / BASIL_DFP = {} (no such folder)", p.display())]) };
    }
    let mut searched = Vec::new();
    for root in &s.roots {
        let p = root.join(s.pack).join(s.version).join("xc8");
        if p.is_dir() {
            return Ok(Dfp { dir: p, version: s.version.to_string(), exact: true });
        }
        searched.push(p.display().to_string());
    }
    for root in &s.roots {
        if let Some((v, dir)) = versions_in(&root.join(s.pack), |d| d.join("xc8").is_dir()).into_iter().next() {
            return Ok(Dfp { dir: dir.join("xc8"), version: v, exact: false });
        }
    }
    Err(searched)
}

/// The folders searched for packs: the Microchip pack folder in the home folder, then each MPLAB X install's, newest first.
pub fn pack_roots() -> Vec<PathBuf> {
    let mut roots: Vec<PathBuf> = home_dir().map(|h| h.join(".mchp_packs").join("Microchip")).into_iter().collect();
    for x in mplabx_roots() {
        roots.extend(versions_in(&x, |d| d.join("packs").join("Microchip").is_dir()).into_iter().map(|(_, d)| d.join("packs").join("Microchip")));
    }
    roots
}

fn env_var(name: &str) -> Option<OsString> {
    std::env::var_os(name)
}

fn path_dirs() -> Vec<PathBuf> {
    std::env::var_os("PATH").map(|p| std::env::split_paths(&p).collect()).unwrap_or_default()
}

/// pic-as for this machine, or the message to print when there is none.
pub fn resolve_pic_as(cli: Option<&Path>) -> Result<PathBuf, String> {
    search_pic_as(&PicAsSearch { cli, env: env_var("BASIL_PICAS"), path_dirs: path_dirs(), roots: xc8_roots() }).map_err(|searched| {
        let mut m = String::from("pic-as not found. Looked in:\n");
        for s in &searched {
            m.push_str(&format!("  {s}\n"));
        }
        m.push_str("Install MPLAB XC8 (https://www.microchip.com/mplab/compilers), set BASIL_PICAS to the pic-as file, or pass --pic-as PATH.");
        m
    })
}

/// xc8-cc for this machine, or the message to print when there is none.
pub fn resolve_xc8_cc(pic_as: &Path) -> Result<PathBuf, String> {
    search_xc8_cc(pic_as, env_var("BASIL_XC8CC")).map_err(|searched| {
        format!("xc8-cc not found (looked for {}). A program that calls C needs the MPLAB XC8 C compiler: install it, or set BASIL_XC8CC to the xc8-cc file.", searched.join(", "))
    })
}

/// The device pack for this machine, or the message to print when there is none.
pub fn resolve_dfp(cli: Option<&Path>, pack: &str, version: &str) -> Result<Dfp, String> {
    let explicit = cli.map(Path::to_path_buf).or_else(|| env_var("BASIL_DFP").filter(|v| !v.is_empty()).map(PathBuf::from));
    let roots = pack_roots();
    search_dfp(&DfpSearch { explicit, roots: roots.clone(), pack, version }).map_err(|searched| {
        let mut m = format!("device pack {pack} {version} not found. Looked for:\n");
        for s in &searched {
            m.push_str(&format!("  {s}\n"));
        }
        if searched.is_empty() {
            m.push_str("  (no pack folders found)\n");
        }
        m.push_str(&format!("Pack folders searched: {}\n", roots.iter().map(|r| r.display().to_string()).collect::<Vec<_>>().join(", ")));
        m.push_str(&format!("Install it with MPLAB X (Tools > Packs) or unpack it to <home>/.mchp_packs/Microchip/{pack}/{version}, or pass --dfp DIR / set BASIL_DFP to the pack's xc8 folder."));
        m
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn tmp(name: &str) -> PathBuf {
        let d = std::env::temp_dir().join(format!("basil-toolchain-{}-{name}", std::process::id()));
        let _ = std::fs::remove_dir_all(&d);
        std::fs::create_dir_all(&d).unwrap();
        d
    }

    fn touch(p: &Path) {
        std::fs::create_dir_all(p.parent().unwrap()).unwrap();
        std::fs::write(p, "").unwrap();
    }

    #[test]
    fn versions_compare_numerically() {
        assert!(version_key("v2.46") > version_key("v2.5"));
        assert!(version_key("v10.0") > version_key("v9.9"));
        assert!(version_key("1.17.312") > version_key("1.17.31"));
        assert_eq!(version_key("v4.00"), vec![4, 0]);
    }

    fn picas_in(root: &Path, ver: &str) -> PathBuf {
        let p = root.join(ver).join("pic-as/bin").join(exe("pic-as"));
        touch(&p);
        p
    }

    #[test]
    fn pic_as_order() {
        let root = tmp("order");
        let old = picas_in(&root, "v2.5");
        let new = picas_in(&root, "v2.46");
        std::fs::create_dir_all(root.join("v9.99")).unwrap(); // a remnant without pic-as is skipped
        let mut s = PicAsSearch { cli: None, env: None, path_dirs: vec![], roots: vec![root.clone()] };
        assert_eq!(search_pic_as(&s).unwrap(), new);
        // PATH beats the install roots
        let bin = root.join("pathbin");
        let on_path = bin.join(exe("pic-as"));
        touch(&on_path);
        s.path_dirs = vec![bin];
        assert_eq!(search_pic_as(&s).unwrap(), on_path);
        // BASIL_PICAS beats PATH
        s.env = Some(old.clone().into_os_string());
        assert_eq!(search_pic_as(&s).unwrap(), old);
        // --pic-as beats BASIL_PICAS
        s.cli = Some(&new);
        assert_eq!(search_pic_as(&s).unwrap(), new);
    }

    #[test]
    fn pic_as_missing() {
        let root = tmp("missing");
        let s = PicAsSearch { cli: None, env: None, path_dirs: vec![], roots: vec![root.clone()] };
        let e = search_pic_as(&s).unwrap_err();
        assert!(e.iter().any(|l| l.contains("PATH")) && e.iter().any(|l| l.contains(&root.display().to_string())));
        // a bad explicit path is an error, not a fall-through to the install
        picas_in(&root, "v1.0");
        let bad = root.join("nope");
        let s = PicAsSearch { cli: Some(&bad), env: None, path_dirs: vec![], roots: vec![root] };
        assert!(search_pic_as(&s).unwrap_err()[0].contains("no such file"));
    }

    #[test]
    fn xc8_cc_beside_pic_as() {
        let root = tmp("xc8cc");
        let pic_as = picas_in(&root, "v4.00");
        assert!(search_xc8_cc(&pic_as, None).is_err());
        let cc = root.join("v4.00/bin").join(exe("xc8-cc"));
        touch(&cc);
        assert_eq!(search_xc8_cc(&pic_as, None).unwrap(), cc);
    }

    fn pack(root: &Path, name: &str, ver: &str) -> PathBuf {
        let p = root.join(name).join(ver).join("xc8");
        std::fs::create_dir_all(&p).unwrap();
        p
    }

    #[test]
    fn dfp_exact_then_newest_then_missing() {
        let root = tmp("dfp");
        let other = tmp("dfp2");
        pack(&root, "PIC18F-K_DFP", "1.9.1");
        let newest = pack(&root, "PIC18F-K_DFP", "1.17.312");
        let mk = |roots: Vec<PathBuf>, version| DfpSearch { explicit: None, roots, pack: "PIC18F-K_DFP", version };
        let d = search_dfp(&mk(vec![root.clone()], "1.9.1")).unwrap();
        assert!(d.exact && d.version == "1.9.1");
        // the exact version in a later root beats a newer one in an earlier root
        let exact_later = pack(&other, "PIC18F-K_DFP", "1.5.0");
        let d = search_dfp(&mk(vec![root.clone(), other.clone()], "1.5.0")).unwrap();
        assert_eq!((d.dir, d.exact), (exact_later, true));
        // missing version: the newest installed one, flagged inexact
        let d = search_dfp(&mk(vec![root.clone()], "9.9.9")).unwrap();
        assert_eq!((d.dir, d.version.as_str(), d.exact), (newest, "1.17.312", false));
        // missing pack: the expected path is reported
        let s = DfpSearch { explicit: None, roots: vec![root.clone()], pack: "Nope_DFP", version: "1.0" };
        assert!(search_dfp(&s).unwrap_err()[0].contains("Nope_DFP"));
        // explicit folder wins; a bad one is an error
        let s = DfpSearch { explicit: Some(other.clone()), roots: vec![root.clone()], pack: "PIC18F-K_DFP", version: "1.9.1" };
        assert_eq!(search_dfp(&s).unwrap().dir, other);
        let s = DfpSearch { explicit: Some(root.join("nope")), roots: vec![root], pack: "PIC18F-K_DFP", version: "1.9.1" };
        assert!(search_dfp(&s).is_err());
    }
}
