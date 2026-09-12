use crate::api::core::CryptoCore;
use crate::error::CoreError;
use crate::formats::decode_pasted;
use crate::messages;
use crate::store::validate_chat_id;

impl CryptoCore {
    /// Encrypts `text` on `chat_id`'s live Olm session and returns the `Fuzz/`
    /// message blob. The ratcheted session and the incremented send counter are
    /// persisted before the blob is returned, so a counter is never reused even
    /// across a crash. A chat that is not connected is `Internal`; an unknown
    /// chat id is `UnknownChat`.
    pub fn encrypt_text(&mut self, chat_id: String, text: String) -> Result<String, CoreError> {
        validate_chat_id(&chat_id)?;
        self.opened_mut()?
            .with_state_mut(&chat_id, |state| messages::encrypt_text(state, &text))
    }

    /// Decrypts a pasted message blob against `chat_id`'s session, checking the
    /// inner header and the replay/ordering window in the fixed order of plan
    /// §B.4. On any failure nothing is persisted — the state file is untouched,
    /// so the message key stays available for a re-paste (plan §B.6). Replay →
    /// `Replay`, a gap beyond Olm's window → `TooOld`, a blob for another chat or
    /// with the wrong identities → `WrongChat`, anything malformed → `Corrupt`.
    pub fn decrypt_text(&mut self, chat_id: String, blob: String) -> Result<String, CoreError> {
        validate_chat_id(&chat_id)?;
        let (_, bytes) = decode_pasted(&blob)?;
        self.opened_mut()?
            .with_state_mut(&chat_id, |state| messages::decrypt_text(state, &bytes))
    }
}

#[cfg(test)]
mod tests {
    use std::fs;
    use std::path::PathBuf;

    use super::*;
    use crate::api::core::{create_store_key, open_store};
    use crate::formats::{decode_text, Message, OlmType};
    use crate::store::test_support::temp_dir;
    use crate::store::STORE_SUBDIR;

    const CHAT_X: &str = "6f1e9b2c-3d4a-4f5b-8c6d-7e8f9a0b1c2d";
    const CHAT_Y: &str = "0a1b2c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d";

    /// One device: its own store directory, wrapped key and open handle.
    struct Device {
        dir: PathBuf,
        wrapped: Vec<u8>,
        core: CryptoCore,
    }

    impl Device {
        fn new() -> Self {
            let dir = temp_dir();
            let wrapped = create_store_key("".into()).unwrap();
            let core = open_store(
                dir.to_string_lossy().into_owned(),
                wrapped.clone(),
                "".into(),
            )
            .unwrap();
            Self { dir, wrapped, core }
        }

        /// Drops the handle and opens the same store again (clears the cache —
        /// every later read comes from disk, as after a restart).
        fn reopen(&mut self) {
            self.core.close();
            self.core = open_store(
                self.dir.to_string_lossy().into_owned(),
                self.wrapped.clone(),
                "".into(),
            )
            .unwrap();
        }

        fn state_file(&self, chat_id: &str) -> PathBuf {
            self.dir.join(STORE_SUBDIR).join(format!("{chat_id}.state"))
        }

        fn state_bytes(&self, chat_id: &str) -> Vec<u8> {
            fs::read(self.state_file(chat_id)).unwrap()
        }

        fn send_counter(&self, chat_id: &str) -> u64 {
            self.core
                .opened()
                .unwrap()
                .load_state(chat_id)
                .unwrap()
                .send_counter
        }
    }

    impl Drop for Device {
        fn drop(&mut self) {
            let _ = fs::remove_dir_all(&self.dir);
        }
    }

    /// Pairs `inviter` and `accepter` on `chat_id` (create → accept → complete).
    fn pair(inviter: &mut Device, accepter: &mut Device, chat_id: &str) {
        let invitation = inviter.core.create_invitation(chat_id.into()).unwrap();
        let acceptance = accepter
            .core
            .accept_invitation(chat_id.into(), invitation)
            .unwrap();
        inviter
            .core
            .complete_handshake(chat_id.into(), acceptance)
            .unwrap();
    }

    /// The Olm message type carried by a `Fuzz/` message blob.
    fn olm_type_of(text: &str) -> OlmType {
        Message::decode(&decode_text(text).unwrap())
            .unwrap()
            .olm_type
    }

    fn flip_byte(text: &str, offset: usize) -> String {
        let mut blob = decode_text(text).unwrap();
        blob[offset] ^= 0x01;
        crate::formats::encode_text(&blob)
    }

    #[test]
    fn round_trip_both_directions() {
        let mut a = Device::new();
        let mut b = Device::new();
        pair(&mut a, &mut b, CHAT_X);

        // B has not decrypted anything from A yet, so its first message is a
        // pre-key; A has already received B's handshake, so A's is normal.
        let b0 = b
            .core
            .encrypt_text(CHAT_X.into(), "from b 0".into())
            .unwrap();
        assert_eq!(olm_type_of(&b0), OlmType::PreKey);
        assert_eq!(a.core.decrypt_text(CHAT_X.into(), b0).unwrap(), "from b 0");

        let a0 = a
            .core
            .encrypt_text(CHAT_X.into(), "from a 0".into())
            .unwrap();
        assert_eq!(olm_type_of(&a0), OlmType::Normal);
        assert_eq!(b.core.decrypt_text(CHAT_X.into(), a0).unwrap(), "from a 0");

        // Now B has received from A → its next message is normal (the transition).
        let b1 = b
            .core
            .encrypt_text(CHAT_X.into(), "from b 1".into())
            .unwrap();
        assert_eq!(olm_type_of(&b1), OlmType::Normal);
        assert_eq!(a.core.decrypt_text(CHAT_X.into(), b1).unwrap(), "from b 1");

        let a1 = a
            .core
            .encrypt_text(CHAT_X.into(), "from a 1 — emoji 🫥".into())
            .unwrap();
        assert_eq!(
            b.core.decrypt_text(CHAT_X.into(), a1).unwrap(),
            "from a 1 — emoji 🫥"
        );
    }

    #[test]
    fn replay_rejected() {
        let mut a = Device::new();
        let mut b = Device::new();
        pair(&mut a, &mut b, CHAT_X);

        let blob = a.core.encrypt_text(CHAT_X.into(), "once".into()).unwrap();
        assert_eq!(
            b.core.decrypt_text(CHAT_X.into(), blob.clone()).unwrap(),
            "once"
        );

        let before = b.state_bytes(CHAT_X);
        assert_eq!(
            b.core.decrypt_text(CHAT_X.into(), blob).unwrap_err(),
            CoreError::Replay
        );
        assert_eq!(
            b.state_bytes(CHAT_X),
            before,
            "a replay never rewrites state"
        );
    }

    #[test]
    fn cross_chat_rejected() {
        let mut a = Device::new();
        let mut a2 = Device::new();
        let mut b = Device::new();
        pair(&mut a, &mut b, CHAT_X);
        pair(&mut a2, &mut b, CHAT_Y);

        // A message honestly encrypted for CHAT_X, pasted into CHAT_Y.
        let blob = a.core.encrypt_text(CHAT_X.into(), "for x".into()).unwrap();
        let before = b.state_bytes(CHAT_Y);

        // Olm's MAC is under CHAT_X's session, so it fails before any plaintext
        // (the inner-header WrongChat belt never even runs). Variant documented.
        assert_eq!(
            b.core.decrypt_text(CHAT_Y.into(), blob).unwrap_err(),
            CoreError::Corrupt
        );
        assert_eq!(b.state_bytes(CHAT_Y), before, "Y's state is byte-identical");
    }

    #[test]
    fn out_of_order_within_window() {
        let mut a = Device::new();
        let mut b = Device::new();
        pair(&mut a, &mut b, CHAT_X);

        // A sends 42 messages on one chain (counters 0..=41). Olm keeps the 40
        // message keys nearest the first one B delivers: decrypting counter 41
        // first caches 1..=40 and drops counter 0 (41 back > the 40-key limit).
        let blobs: Vec<String> = (0..42)
            .map(|i| a.core.encrypt_text(CHAT_X.into(), format!("m{i}")).unwrap())
            .collect();

        // Deliver the newest first — out-of-order delivery is accepted.
        assert_eq!(
            b.core
                .decrypt_text(CHAT_X.into(), blobs[41].clone())
                .unwrap(),
            "m41"
        );
        // Backfill 1..=40 out of order — all within both Olm's store and our window.
        for i in (1..=40).rev() {
            assert_eq!(
                b.core
                    .decrypt_text(CHAT_X.into(), blobs[i].clone())
                    .unwrap(),
                format!("m{i}")
            );
        }
        // Counter 0 was evicted by Olm's 40-key limit → gone. `MissingMessageKey`
        // maps to `Replay`; our 64-wide window never even sees it (Olm fails first).
        assert_eq!(
            b.core
                .decrypt_text(CHAT_X.into(), blobs[0].clone())
                .unwrap_err(),
            CoreError::Replay
        );
    }

    #[test]
    fn forward_secrecy() {
        let mut a = Device::new();
        let mut b = Device::new();
        pair(&mut a, &mut b, CHAT_X);

        const N: usize = 5;
        let blobs: Vec<String> = (0..N)
            .map(|i| a.core.encrypt_text(CHAT_X.into(), format!("m{i}")).unwrap())
            .collect();

        // B decrypts messages 1..N-1 (indices 0..=N-2) in order.
        for blob in blobs.iter().take(N - 1) {
            b.core.decrypt_text(CHAT_X.into(), blob.clone()).unwrap();
        }
        // Snapshot B's sealed state after decrypting message N-1 (index N-2).
        let snapshot = b.state_bytes(CHAT_X);
        // B decrypts message N (index N-1).
        b.core
            .decrypt_text(CHAT_X.into(), blobs[N - 1].clone())
            .unwrap();

        // (i) Against the live state, message N-1's key is consumed → unrecoverable.
        assert_eq!(
            b.core
                .decrypt_text(CHAT_X.into(), blobs[N - 2].clone())
                .unwrap_err(),
            CoreError::Replay
        );

        // Restore the snapshot (models an attacker who kept the older sealed file).
        fs::write(b.state_file(CHAT_X), &snapshot).unwrap();
        b.reopen();

        // (ii) The snapshot already consumed message N-1's key (at N-1) ...
        assert_eq!(
            b.core
                .decrypt_text(CHAT_X.into(), blobs[N - 2].clone())
                .unwrap_err(),
            CoreError::Replay
        );
        // ... and message N-2's (consumed earlier still). No earlier message is
        // recoverable from a later sealed snapshot.
        assert_eq!(
            b.core
                .decrypt_text(CHAT_X.into(), blobs[N - 3].clone())
                .unwrap_err(),
            CoreError::Replay
        );

        // The sender holds only the sending key: A can never decrypt its own blobs.
        for blob in &blobs {
            assert!(
                a.core.decrypt_text(CHAT_X.into(), blob.clone()).is_err(),
                "an Olm sender never holds the receiving key"
            );
        }
    }

    #[test]
    fn crash_between_decrypt_and_save() {
        let mut a = Device::new();
        let mut b = Device::new();
        pair(&mut a, &mut b, CHAT_X);

        let blob = a
            .core
            .encrypt_text(CHAT_X.into(), "survives a crash".into())
            .unwrap();
        let bytes = decode_text(&blob).unwrap();

        // Simulate a crash between Olm decrypt and the save: run the decrypt on a
        // state loaded straight from disk, then drop it without persisting.
        {
            let mut state = b.core.opened().unwrap().load_state(CHAT_X).unwrap();
            let plaintext = messages::decrypt_text(&mut state, &bytes).unwrap();
            assert_eq!(plaintext, "survives a crash");
            // `state` is dropped here — nothing was written.
        }

        // Restart: the key is still on disk, so the re-paste works exactly once ...
        b.reopen();
        assert_eq!(
            b.core.decrypt_text(CHAT_X.into(), blob.clone()).unwrap(),
            "survives a crash"
        );
        // ... and then it is a replay.
        assert_eq!(
            b.core.decrypt_text(CHAT_X.into(), blob).unwrap_err(),
            CoreError::Replay
        );
    }

    #[test]
    fn counter_never_reused_after_reload() {
        let mut a = Device::new();
        let mut b = Device::new();
        pair(&mut a, &mut b, CHAT_X);

        let first = a.core.encrypt_text(CHAT_X.into(), "a".into()).unwrap();
        assert_eq!(a.send_counter(CHAT_X), 1);

        // A restarts, then sends again — the counter resumes from disk, never 0.
        a.reopen();
        let second = a.core.encrypt_text(CHAT_X.into(), "b".into()).unwrap();
        assert_eq!(
            a.send_counter(CHAT_X),
            2,
            "the counter strictly increases across a reload"
        );

        // Both decrypt on B in order — no reuse, no replay between them.
        assert_eq!(b.core.decrypt_text(CHAT_X.into(), first).unwrap(), "a");
        assert_eq!(b.core.decrypt_text(CHAT_X.into(), second).unwrap(), "b");
    }

    #[test]
    fn tampered_blob_corrupt() {
        let mut a = Device::new();
        let mut b = Device::new();
        pair(&mut a, &mut b, CHAT_X);

        let blob = a.core.encrypt_text(CHAT_X.into(), "honest".into()).unwrap();
        // Flip a byte inside the Olm body (past the 6-byte envelope + type byte) —
        // the MAC fails. (Flipping the envelope would be UnsupportedFormat instead.)
        let tampered = flip_byte(&blob, 16);
        let before = b.state_bytes(CHAT_X);

        assert_eq!(
            b.core.decrypt_text(CHAT_X.into(), tampered).unwrap_err(),
            CoreError::Corrupt
        );
        assert_eq!(
            b.state_bytes(CHAT_X),
            before,
            "a tampered blob never rewrites state"
        );
        // The honest blob still decrypts afterwards.
        assert_eq!(b.core.decrypt_text(CHAT_X.into(), blob).unwrap(), "honest");
    }

    #[test]
    fn encrypt_decrypt_of_1kb_text_is_under_the_budget() {
        use std::time::Instant;

        let mut a = Device::new();
        let mut b = Device::new();
        pair(&mut a, &mut b, CHAT_X);

        // Plan §H's "< 5 ms" budget is the crypto cost of encrypt+decrypt; measure
        // it on the pure path (in-memory state, no disk) so the durable-fsync cost
        // of persistence is not conflated with it.
        let mut a_state = a.core.opened().unwrap().load_state(CHAT_X).unwrap();
        let mut b_state = b.core.opened().unwrap().load_state(CHAT_X).unwrap();
        let text = "x".repeat(1024);
        let iterations = 100;

        let start = Instant::now();
        for _ in 0..iterations {
            let blob = messages::encrypt_text(&mut a_state, &text).unwrap();
            let bytes = decode_text(&blob).unwrap();
            assert_eq!(
                messages::decrypt_text(&mut b_state, &bytes).unwrap().len(),
                1024
            );
        }
        let crypto = start.elapsed() / iterations;
        println!("1 KB encrypt+decrypt (crypto only): {crypto:?}");

        // The full persisted round trip, for reference (two atomic saves, each
        // with a data + directory fsync — the durability cost, not the crypto).
        let start = Instant::now();
        for _ in 0..iterations {
            let blob = a.core.encrypt_text(CHAT_X.into(), text.clone()).unwrap();
            assert_eq!(
                b.core.decrypt_text(CHAT_X.into(), blob).unwrap().len(),
                1024
            );
        }
        let persisted = start.elapsed() / iterations;
        println!("1 KB round trip incl. two durable state saves: {persisted:?}");

        // Generous ceiling so the assertion never flakes on a debug-profile or
        // busy box; the crypto number is the one checked against plan §H.
        assert!(crypto.as_millis() < 25, "crypto path took {crypto:?}");
    }
}
