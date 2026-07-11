//! Fuzz target: snow handshake initiator write_message.
//!
//! Fuzz the noise initiator's write_message with arbitrary plaintext input.
//! The initiator writes the first handshake message. Input drives the plaintext
//! bytes; the handshake framing / crypto paths are exercised.
#![no_main]

use libfuzzer_sys::fuzz_target;

fuzz_target!(|data: &[u8]| {
    static PATTERN: &str = "Noise_NN_25519_ChaChaPoly_BLAKE2s";
    let mut out_buf = vec![0u8; 65536];
    let Ok(params) = PATTERN.parse() else { return; };
    let Ok(mut noise) = snow::Builder::new(params).build_initiator() else { return; };
    // write_message of the first handshake message (data is the optional payload).
    // The Noise_NN pattern requires an empty payload on step 0; snow returns an
    // error for non-empty payloads — we exercise the validation path regardless.
    let _ = noise.write_message(data, &mut out_buf);
});
