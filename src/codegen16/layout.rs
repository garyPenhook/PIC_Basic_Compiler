//! Data RAM placement for the enhanced mid-range core.
//!
//! Banked RAM is a run of 80-byte blocks, one per bank (data addresses `bank * 128 + 20h..70h`). They are
//! placed in a linear coordinate `bank * 80 + (offset - 20h)`, which is also how the linear data memory
//! (FSR 2000h up) numbers them, so a block-crossing array is one run of bytes there. An object of at most
//! 80 bytes stays inside one block (one `movlb` reaches all of it); a larger one may cross blocks.
//! Common RAM (visible from every bank) is a separate region, filled with the hottest objects first.

use crate::codegen::{Layout, Obj, Pic16Mem};
use crate::asm::Item;
use crate::fxhash::HashMap;
use std::collections::BTreeMap;

const BLOCK: u32 = 80;

/// Data address of linear byte `l`.
pub fn phys(l: u32) -> u32 {
    (l / BLOCK) * 128 + 0x20 + l % BLOCK
}

/// Linear coordinate of a banked GPR data address; None for common RAM and the SFR half of a bank.
pub fn lin(addr: u32) -> Option<u32> {
    let off = addr & 0x7F;
    (0x20..0x70).contains(&off).then(|| (addr >> 7) * BLOCK + off - 0x20)
}

/// Data address of byte `off` of an object that starts at `addr`.
pub fn phys_off(addr: u32, off: u32) -> u32 {
    match lin(addr) {
        Some(l) if off > 0 => phys(l + off),
        _ => addr + off,
    }
}

struct Region {
    /// Placed blocks: start, length, owner.
    placed: Vec<(u32, u32, Option<usize>)>,
}

impl Region {
    fn find(&self, n: u32, owner: Option<usize>, indep: &[Vec<bool>], fits: &dyn Fn(u32, u32) -> bool, cands: &[u32], score: &dyn Fn(u32) -> u64) -> Option<u32> {
        let mut c: Vec<u32> = cands.to_vec();
        for &(s, l, _) in &self.placed {
            c.push(s);
            c.push(s + l);
        }
        c.sort_unstable();
        c.dedup();
        c.into_iter().filter(|&a| fits(a, n) && self.placed.iter().all(|&(s, l, o)| a + n <= s || s + l <= a || matches!((owner, o), (Some(x), Some(y)) if indep[x][y])))
            .max_by_key(|&a| (score(a), std::cmp::Reverse(a)))
    }
}

pub fn plan_layout16(objs: &[Obj], mem: &Pic16Mem, indep: &[Vec<bool>]) -> Result<Layout, String> {
    plan(objs, mem, indep, &[])
}

/// A placement trial using transitions between directly accessed objects in the symbolic instruction stream.
pub(crate) fn plan_affinity(objs: &[Obj], mem: &Pic16Mem, indep: &[Vec<bool>], items: &[Item]) -> Result<Layout, String> {
    plan(objs, mem, indep, &affinities(objs, items))
}

fn plan(objs: &[Obj], mem: &Pic16Mem, indep: &[Vec<bool>], edges: &[(usize, usize, u64)]) -> Result<Layout, String> {
    let mut addr: Vec<Option<u32>> = vec![None; objs.len()];
    // Length of each bank's block (0 when the part has none).
    let top_bank = mem.gpr.iter().map(|g| g.0 >> 7).max().unwrap_or(0);
    let mut blen = vec![0u32; top_bank as usize + 1];
    for &(s, e) in &mem.gpr {
        blen[(s >> 7) as usize] = e - s;
    }
    let lin_end = (top_bank + 1) * BLOCK;
    let fits_banked = |a: u32, n: u32| -> bool {
        if a + n > lin_end {
            return false;
        }
        if n <= BLOCK && a / BLOCK != (a + n - 1) / BLOCK {
            return false;
        }
        (a..a + n).all(|l| l % BLOCK < blen[(l / BLOCK) as usize])
    };
    let starts: Vec<u32> = (0..=top_bank).map(|b| b * BLOCK).collect();
    let mut banked = Region { placed: Vec::new() };
    let mut common = Region { placed: Vec::new() };
    let (clo, chi) = mem.common;
    let fits_common = |a: u32, n: u32| a >= clo && a + n <= chi;
    for (i, o) in objs.iter().enumerate() {
        if o.force_access && o.bytes > 0 {
            let Some(a) = common.find(o.bytes, None, indep, &fits_common, &[clo], &|_| 0) else {
                return Err("out of common RAM for compiler scratch registers".into());
            };
            addr[i] = Some(a);
            common.placed.push((a, o.bytes, None));
        }
    }
    let mut order: Vec<usize> = (0..objs.len()).filter(|&i| !objs[i].force_access && objs[i].bytes > 0).collect();
    order.sort_by(|&x, &y| objs[y].weight.cmp(&objs[x].weight).then(x.cmp(&y)));
    let mut remaining = Vec::new();
    for &i in &order {
        let o = &objs[i];
        if let Some(a) = common.find(o.bytes, o.owner, indep, &fits_common, &[clo], &|_| 0) {
            addr[i] = Some(a);
            common.placed.push((a, o.bytes, o.owner));
            continue;
        }
        remaining.push(i);
    }
    let mut links = vec![Vec::new(); objs.len()];
    for &(a, b, w) in edges {
        links[a].push((b, w));
        links[b].push((a, w));
    }
    while !remaining.is_empty() {
        // Grow a cluster from the hottest unplaced object, preferring its strongest neighbours.
        let next = if edges.is_empty() { 0 } else {
            (0..remaining.len()).max_by_key(|&k| {
                let i = remaining[k];
                let connected: u64 = links[i].iter().filter(|&&(j, _)| addr[j].is_some_and(|a| lin(a).is_some())).map(|&(_, w)| w).sum();
                (connected, objs[i].weight, std::cmp::Reverse(i))
            }).unwrap()
        };
        let i = remaining.remove(next);
        let o = &objs[i];
        let score = |l: u32| -> u64 {
            if o.bytes > BLOCK { return 0; }
            links[i].iter().filter(|&&(j, _)| addr[j].is_some_and(|a| lin(a).is_some() && a >> 7 == l / BLOCK) && objs[j].bytes <= BLOCK).map(|&(_, w)| w).sum()
        };
        let Some(l) = banked.find(o.bytes, o.owner, indep, &fits_banked, &starts, &score) else {
            return Err(format!("out of data RAM placing `{}` ({} bytes)", o.name, o.bytes));
        };
        addr[i] = Some(phys(l));
        banked.placed.push((l, o.bytes, o.owner));
    }
    Ok(Layout { addr, size: objs.iter().map(|o| o.bytes).collect() })
}

/// Count consecutive direct RAM operands. Common scratch does not change the selected bank;
/// control-flow boundaries and raw assembly end a run. This is a heuristic, never an alias proof.
fn affinities(objs: &[Obj], items: &[Item]) -> Vec<(usize, usize, u64)> {
    let ids: HashMap<&str, usize> = objs.iter().enumerate().filter(|(_, o)| !o.force_access && o.bytes > 0 && o.bytes <= BLOCK).map(|(i, o)| (o.name.as_str(), i)).collect();
    let mut edges = BTreeMap::new();
    let mut previous = None;
    for item in items {
        match item {
            Item::Ins(t) => {
                let Some((op, rest)) = t.split_once(' ') else { continue };
                if !matches!(op, "movf" | "movwf" | "clrf" | "addwf" | "addwfc" | "subwf" | "subwfb" | "andwf" | "iorwf" | "xorwf" | "comf" | "incf" | "decf" | "incfsz" | "decfsz" | "rlf" | "rrf" | "lslf" | "lsrf" | "asrf" | "swapf" | "btfsc" | "btfss" | "bsf" | "bcf") { continue; }
                let name = rest.split([',', '+', ' ']).next().unwrap_or("");
                if let Some(&i) = ids.get(name) {
                    if let Some(j) = previous {
                        if i != j { *edges.entry((i.min(j), i.max(j))).or_insert(0u64) += 1; }
                    }
                    previous = Some(i);
                } else if !name.starts_with("__") && !matches!(name, "WREG" | "STATUS") {
                    previous = None;
                }
            }
            Item::Comment(_) => {}
            _ => previous = None,
        }
    }
    edges.into_iter().map(|((a, b), w)| (a, b, w)).collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    fn obj(name: &str, bytes: u32, weight: u64, owner: Option<usize>) -> Obj {
        Obj { name: name.into(), bytes, weight, force_access: false, zero: true, owner }
    }
    fn memory() -> Pic16Mem {
        Pic16Mem { gpr: vec![(0x20, 0x70), (0xa0, 0xf0), (0x120, 0x170)], common: (0x70, 0x80), prog_words: 8192 }
    }
    fn accesses() -> Vec<Item> {
        ["movf A, w", "movwf __A0", "movlw 1", "movwf C+1"].map(|s| Item::Ins(s.into())).to_vec()
    }
    fn check(objs: &[Obj], layout: &Layout, mem: &Pic16Mem, indep: &[Vec<bool>]) {
        let mut occupied: HashMap<u32, usize> = HashMap::default();
        for (i, o) in objs.iter().enumerate() {
            let Some(start) = layout.addr[i] else { continue };
            for off in 0..o.bytes {
                let a = phys_off(start, off);
                assert!(mem.gpr.iter().any(|&(s, e)| (s..e).contains(&a)) || (mem.common.0..mem.common.1).contains(&a));
                if let Some(j) = occupied.insert(a, i) {
                    assert!(matches!((o.owner, objs[j].owner), (Some(x), Some(y)) if indep[x][y]));
                }
            }
        }
    }
    #[test]
    fn related_objects_share_a_bank_without_changing_common_ram() {
        let mut scratch = obj("__A", 4, u64::MAX, None);
        scratch.force_access = true;
        let objs = vec![scratch, obj("HOT", 4, 1000, None), obj("A", 30, 100, None), obj("B", 30, 90, None), obj("C", 30, 80, None)];
        let mem = memory();
        let old = plan_layout16(&objs, &mem, &[]).unwrap();
        let new = plan_affinity(&objs, &mem, &[], &accesses()).unwrap();
        assert_ne!(old.addr[2].unwrap() >> 7, old.addr[4].unwrap() >> 7);
        assert_eq!(new.addr[2].unwrap() >> 7, new.addr[4].unwrap() >> 7);
        assert_eq!(&old.addr[..2], &new.addr[..2]);
        check(&objs, &new, &mem, &[]);
    }
    #[test]
    fn affinity_respects_partial_banks_large_arrays_and_frame_conflicts() {
        let mut mem = memory();
        mem.gpr[0].1 = 0x40;
        let indep = vec![vec![false, true, false], vec![true, false, false], vec![false, false, false]];
        let objs = vec![obj("A", 24, 30, Some(0)), obj("B", 24, 20, Some(1)), obj("C", 24, 10, Some(2)), obj("ARRAY", 81, 1, None)];
        let new = plan_affinity(&objs, &mem, &indep, &accesses()).unwrap();
        check(&objs, &new, &mem, &indep);
        assert_eq!(new.addr[0], new.addr[1]);
        assert_ne!(new.addr[0], new.addr[2]);
        assert_eq!(new.addr, plan_affinity(&objs, &mem, &indep, &accesses()).unwrap().addr);
    }
    #[test]
    fn access_edges_stop_at_control_flow_and_ignore_common_scratch() {
        let objs = vec![obj("A", 1, 1, None), obj("C", 1, 1, None)];
        assert_eq!(affinities(&objs, &accesses()), vec![(0, 1, 1)]);
        let mut items = accesses();
        items.insert(3, Item::Label("_L1".into()));
        assert!(affinities(&objs, &items).is_empty());
    }
}
