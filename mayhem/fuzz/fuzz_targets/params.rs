//! Fuzz target: snow NoiseParams parser.
//!
//! Fuzz the Noise pattern string parser. The `parse()` implementation decodes
//! algorithm identifiers (DH, cipher, hash, handshake pattern) and validates
//! them. Arbitrary byte sequences — valid UTF-8 or not — are exercised; only
//! valid UTF-8 is forwarded to the parser.
#![no_main]

use libfuzzer_sys::fuzz_target;

fuzz_target!(|data: &[u8]| {
    if let Ok(s) = std::str::from_utf8(data) {
        if let Ok(p) = s.parse::<snow::params::NoiseParams>() {
            let _ = snow::Builder::new(p).build_initiator();
        }
    }
});
