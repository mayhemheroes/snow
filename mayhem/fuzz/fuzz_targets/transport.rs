//! Fuzz target: snow transport-mode read_message / write_message.
//!
//! Complete a Noise_NN handshake to enter transport mode, then fuzz read/write
//! of transport messages with arbitrary byte inputs. Exercises the AEAD cipher
//! and counter management under adversarial input.
#![no_main]

use libfuzzer_sys::fuzz_target;

fuzz_target!(|data: &[u8]| {
    static PATTERN: &str = "Noise_NN_25519_ChaChaPoly_BLAKE2s";
    let Ok(params_i) = PATTERN.parse() else { return; };
    let Ok(params_r) = PATTERN.parse() else { return; };
    let Ok(mut initiator) = snow::Builder::new(params_i).build_initiator() else { return; };
    let Ok(mut responder) = snow::Builder::new(params_r).build_responder() else { return; };
    let mut buf = vec![0u8; 65536];

    // Noise_NN: -> e ; <- e, ee
    let Ok(len) = initiator.write_message(&[], &mut buf) else { return; };
    let _ = responder.read_message(&buf[..len], &mut buf.clone());
    let Ok(len) = responder.write_message(&[], &mut buf) else { return; };
    let _ = initiator.read_message(&buf[..len], &mut buf.clone());

    let Ok(mut initiator) = initiator.into_transport_mode() else { return; };
    let Ok(mut responder) = responder.into_transport_mode() else { return; };

    // Fuzz transport-phase read and write with arbitrary data.
    let _ = initiator.write_message(data, &mut buf);
    let _ = responder.read_message(data, &mut buf);
});
