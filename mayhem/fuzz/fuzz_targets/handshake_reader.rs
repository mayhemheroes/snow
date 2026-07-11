//! Fuzz target: snow handshake responder read_message.
//!
//! Fuzz the noise responder's read_message parsing of arbitrary handshake
//! bytes. The responder expects to receive the first handshake message from
//! the initiator. Malformed input should be rejected gracefully (no panic,
//! no UB).
#![no_main]

use libfuzzer_sys::fuzz_target;

fuzz_target!(|data: &[u8]| {
    static PATTERN: &str = "Noise_NN_25519_ChaChaPoly_BLAKE2s";
    let mut out_buf = vec![0u8; 65536];
    let Ok(params) = PATTERN.parse() else { return; };
    let Ok(mut noise) = snow::Builder::new(params).build_responder() else { return; };
    let _ = noise.read_message(data, &mut out_buf);
});
