//! Data RAM placement for the enhanced mid-range core.
//!
//! Banked RAM is a run of 80-byte blocks, one per bank (data addresses `bank * 128 + 20h..70h`). They are
//! placed in a linear coordinate `bank * 80 + (offset - 20h)`, which is also how the linear data memory
//! (FSR 2000h up) numbers them, so a block-crossing array is one run of bytes there. An object of at most
//! 80 bytes stays inside one block (one `movlb` reaches all of it); a larger one may cross blocks.
//! Common RAM (visible from every bank) is a separate region, filled with the hottest objects first.

use crate::codegen::{Layout, Obj, Pic16Mem};

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
    fn find(&self, n: u32, owner: Option<usize>, indep: &[Vec<bool>], fits: &dyn Fn(u32, u32) -> bool, cands: &[u32]) -> Option<u32> {
        let mut c: Vec<u32> = cands.to_vec();
        for &(s, l, _) in &self.placed {
            c.push(s);
            c.push(s + l);
        }
        c.sort_unstable();
        c.dedup();
        c.into_iter().find(|&a| fits(a, n) && self.placed.iter().all(|&(s, l, o)| a + n <= s || s + l <= a || matches!((owner, o), (Some(x), Some(y)) if indep[x][y])))
    }
}

pub fn plan_layout16(objs: &[Obj], mem: &Pic16Mem, indep: &[Vec<bool>]) -> Result<Layout, String> {
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
            let Some(a) = common.find(o.bytes, None, indep, &fits_common, &[clo]) else {
                return Err("out of common RAM for compiler scratch registers".into());
            };
            addr[i] = Some(a);
            common.placed.push((a, o.bytes, None));
        }
    }
    let mut order: Vec<usize> = (0..objs.len()).filter(|&i| !objs[i].force_access && objs[i].bytes > 0).collect();
    order.sort_by(|&x, &y| objs[y].weight.cmp(&objs[x].weight).then(x.cmp(&y)));
    for &i in &order {
        let o = &objs[i];
        if let Some(a) = common.find(o.bytes, o.owner, indep, &fits_common, &[clo]) {
            addr[i] = Some(a);
            common.placed.push((a, o.bytes, o.owner));
            continue;
        }
        let Some(l) = banked.find(o.bytes, o.owner, indep, &fits_banked, &starts) else {
            return Err(format!("out of data RAM placing `{}` ({} bytes)", o.name, o.bytes));
        };
        addr[i] = Some(phys(l));
        banked.placed.push((l, o.bytes, o.owner));
    }
    Ok(Layout { addr, size: objs.iter().map(|o| o.bytes).collect() })
}
