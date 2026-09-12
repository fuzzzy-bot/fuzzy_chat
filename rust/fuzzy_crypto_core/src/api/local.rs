use crate::api::core::CryptoCore;
use crate::error::CoreError;

impl CryptoCore {
    /// Seals `bytes` for local storage (message history, F2-8) under the
    /// HKDF-derived local key: a 0x20 blob with a fresh random nonce.
    pub fn seal_local(&self, bytes: Vec<u8>) -> Result<Vec<u8>, CoreError> {
        self.opened()?.seal_local(&bytes)
    }

    /// Inverse of [`CryptoCore::seal_local`]; a tampered or foreign blob is `Corrupt`.
    pub fn open_local(&self, blob: Vec<u8>) -> Result<Vec<u8>, CoreError> {
        self.opened()?.open_local(&blob)
    }
}

#[cfg(test)]
mod tests {
    use std::fs;

    use super::*;
    use crate::api::core::{create_store_key, open_store};
    use crate::store::test_support::temp_dir;

    #[test]
    fn seal_open_round_trip_and_tamper_through_the_handle() {
        let dir = temp_dir();
        let wrapped = create_store_key("".into()).unwrap();
        let core = open_store(dir.to_string_lossy().into_owned(), wrapped, "".into()).unwrap();

        let blob = core.seal_local(b"history".to_vec()).unwrap();
        assert_eq!(core.open_local(blob.clone()).unwrap(), b"history");

        let mut tampered = blob;
        tampered[40] ^= 1;
        assert_eq!(core.open_local(tampered).unwrap_err(), CoreError::Corrupt);
        let _ = fs::remove_dir_all(dir);
    }
}
