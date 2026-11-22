//! A fast hash for the back end's maps and sets: the word-at-a-time multiply-and-rotate hash the Rust compiler uses for
//! its own tables ("FxHash"). The code generator and the peephole passes look names up a great many times in every
//! build, and the standard SipHash was a visible part of the time a build takes. The keys are the compiler's own
//! names, so SipHash's protection against keys chosen to collide is not needed.
//!
//! The output does not depend on the hash: it was the same on every run while SipHash's keys were random, so nothing
//! is emitted in the order a map happens to be walked.

use std::hash::{BuildHasherDefault, Hasher};

/// See the module documentation.
#[derive(Clone, Copy, Default)]
pub struct FxHasher {
    hash: u64,
}

const SEED: u64 = 0x51_7c_c1_b7_27_22_0a_95;

impl FxHasher {
    #[inline]
    fn add(&mut self, word: u64) {
        self.hash = (self.hash.rotate_left(5) ^ word).wrapping_mul(SEED);
    }
}

impl Hasher for FxHasher {
    #[inline]
    fn write(&mut self, mut bytes: &[u8]) {
        while let Some((w, rest)) = bytes.split_first_chunk::<8>() {
            self.add(u64::from_le_bytes(*w));
            bytes = rest;
        }
        if let Some((w, rest)) = bytes.split_first_chunk::<4>() {
            self.add(u64::from(u32::from_le_bytes(*w)));
            bytes = rest;
        }
        for &b in bytes {
            self.add(u64::from(b));
        }
    }
    #[inline]
    fn write_u8(&mut self, i: u8) {
        self.add(u64::from(i));
    }
    #[inline]
    fn write_u16(&mut self, i: u16) {
        self.add(u64::from(i));
    }
    #[inline]
    fn write_u32(&mut self, i: u32) {
        self.add(u64::from(i));
    }
    #[inline]
    fn write_u64(&mut self, i: u64) {
        self.add(i);
    }
    #[inline]
    fn write_usize(&mut self, i: usize) {
        self.add(i as u64);
    }
    #[inline]
    fn finish(&self) -> u64 {
        self.hash
    }
}

pub type FxBuildHasher = BuildHasherDefault<FxHasher>;
/// `std::collections::HashMap` with [`FxHasher`]; made with `HashMap::default()` (there is no `new`).
pub type HashMap<K, V> = std::collections::HashMap<K, V, FxBuildHasher>;
/// `std::collections::HashSet` with [`FxHasher`]; made with `HashSet::default()` (there is no `new`).
pub type HashSet<T> = std::collections::HashSet<T, FxBuildHasher>;

#[cfg(test)]
mod tests {
    use super::*;
    use std::hash::{BuildHasher, Hash};

    fn hash_of<T: Hash + ?Sized>(t: &T) -> u64 {
        FxBuildHasher::default().hash_one(t)
    }

    #[test]
    fn equal_keys_hash_alike_and_near_names_differ() {
        assert_eq!(hash_of("OLED_CMD"), hash_of(&String::from("OLED_CMD")));
        let names = ["OLED_CMD", "OLED_CMDS", "OLED_CMd", "__A0", "__A1", "__B0", "_Lr0", "_Lr1", "", "a", "ab", "abcdefghi"];
        let hashes: std::collections::HashSet<u64> = names.iter().map(|n| hash_of(*n)).collect();
        assert_eq!(hashes.len(), names.len());
    }

    #[test]
    fn maps_and_sets_work_as_usual() {
        let mut m: HashMap<String, u32> = HashMap::default();
        for i in 0..1000 {
            m.insert(format!("V{i}"), i);
        }
        assert!((0..1000).all(|i| m[&format!("V{i}")] == i));
        let s: HashSet<&str> = ["x", "y", "x"].into_iter().collect();
        assert_eq!(s.len(), 2);
    }
}
