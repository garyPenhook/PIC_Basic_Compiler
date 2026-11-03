//! Stimulus file: what the outside world does to the part over time (TOML).
//!
//! ```toml
//! [[uart]]            # characters sent to the receiver of an EUSART
//! port = 1            # EUSART number, default 1
//! at = 5000           # instruction cycle the first Start bit falls
//! bytes = "Hello\r"   # a string, or  data = [0x48, 0x165]  (values up to 0x1FF with nine = true)
//! bit = 139           # sender's bit time in instruction cycles; default: the receiver's own rate
//! gap = 0             # idle cycles between characters, default 0
//! nine = false        # 11-bit characters (the ninth data bit is bit 8 of the value)
//! bad_stop = false    # send the Stop bit as 0 (framing error)
//! ```

use crate::periph::RxStream;
use devdesc::Device;

#[derive(Debug, Default, PartialEq, Eq)]
pub struct Stimulus {
    pub uart: Vec<(u8, RxStream)>,
}

impl Stimulus {
    pub fn parse(text: &str) -> Result<Stimulus, String> {
        let doc: toml::Table = text.parse().map_err(|e: toml::de::Error| e.to_string())?;
        let mut st = Stimulus::default();
        for (k, v) in &doc {
            if k != "uart" {
                return Err(format!("unknown section [{k}]"));
            }
            for e in v.as_array().ok_or("uart must be [[uart]] entries")? {
                let t = e.as_table().ok_or("uart entry must be a table")?;
                let int = |n: &str| -> Result<Option<u64>, String> {
                    match t.get(n) {
                        None => Ok(None),
                        Some(x) => x.as_integer().and_then(|i| u64::try_from(i).ok()).map(Some).ok_or(format!("uart.{n} must be a non-negative integer")),
                    }
                };
                let flag = |n: &str| t.get(n).map_or(Ok(false), |x| x.as_bool().ok_or(format!("uart.{n} must be true or false")));
                for k in t.keys() {
                    if !["port", "at", "bytes", "data", "bit", "gap", "nine", "bad_stop"].contains(&k.as_str()) {
                        return Err(format!("uart: unknown key {k}"));
                    }
                }
                let nine = flag("nine")?;
                let words: Vec<u16> = match (t.get("bytes"), t.get("data")) {
                    (Some(b), None) => b.as_str().ok_or("uart.bytes must be a string")?.chars().map(|c| c as u16 & 0xFF).collect(),
                    (None, Some(d)) => d
                        .as_array()
                        .ok_or("uart.data must be an array")?
                        .iter()
                        .map(|x| {
                            x.as_integer()
                                .and_then(|i| u16::try_from(i).ok())
                                .filter(|i| *i <= if nine { 0x1FF } else { 0xFF })
                                .ok_or(format!("uart.data value {x} out of range"))
                        })
                        .collect::<Result<_, _>>()?,
                    _ => return Err("uart needs exactly one of bytes or data".into()),
                };
                let bit = int("bit")?;
                if bit == Some(0) {
                    return Err("uart.bit must be at least 1".into());
                }
                let port = int("port")?.unwrap_or(1);
                st.uart.push((
                    u8::try_from(port).map_err(|_| "bad uart.port")?,
                    RxStream { at: int("at")?.unwrap_or(0), words: words.into(), bit, gap: int("gap")?.unwrap_or(0), nine, bad_stop: flag("bad_stop")? },
                ));
            }
        }
        Ok(st)
    }

    /// Hand the characters to the receivers of `cpu`. An EUSART the part does not have is an error.
    pub fn apply(self, dev: &Device, p: &mut crate::periph::Periph) -> Result<(), String> {
        for (port, s) in self.uart {
            if !p.rx_send(port, s) {
                return Err(format!("{}: no EUSART{port} receiver in the simulator", dev.device.name));
            }
        }
        Ok(())
    }
}
