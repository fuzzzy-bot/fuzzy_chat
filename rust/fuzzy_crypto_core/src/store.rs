//! Key hygiene — the wrapped store key, the sealed per-chat state files and the
//! local seal (plan §A.2, §B.6, §D). Every secret lives in a `Zeroizing` buffer
//! or a `ZeroizeOnDrop` struct; nothing here returns key bytes.
//!
//! Layouts are the codec's (`formats::WrappedStoreKey` 0x10, `formats::LocalSeal`
//! 0x20); this module only adds the crypto around them.

use std::collections::HashMap;
use std::fs::{self, File};
use std::io::{self, Write};
use std::path::{Path, PathBuf};
use std::sync::Mutex;

use argon2::{Algorithm, Argon2, Params, Version};
use chacha20poly1305::aead::{Aead, Payload};
use chacha20poly1305::{KeyInit, XChaCha20Poly1305};
use hkdf::Hkdf;
use sha2::Sha256;
use zeroize::{ZeroizeOnDrop, Zeroizing};

use crate::error::CoreError;
use crate::formats::{Argon2Params, LocalSeal, WrappedStoreKey, WRAPPED_STORE_KEY_CT_LEN};
use crate::state::{ChatState, STATE_FORMAT_VERSION};

/// Directory under the app's support dir that holds every `<chat_id>.state`.
pub const STORE_SUBDIR: &str = "fuzzy_crypto_store";
/// Argon2id cost for every store key we wrap (plan §D): 64 MiB, 4 passes, 1 lane.
pub const ARGON2_PARAMS: Argon2Params = Argon2Params {
    m_cost: 65536,
    t_cost: 4,
    p_cost: 1,
};
/// Largest memory cost (KiB) accepted from a blob header — 1 GiB; beyond that a
/// tampered header is a denial of service, not a slower unlock.
const MAX_ARGON2_M_COST: u32 = 1 << 20;
/// Largest pass count accepted from a blob header.
const MAX_ARGON2_T_COST: u32 = 64;
/// Bytes a serialised state body is expected to fit in without reallocating (pitfall §F.11).
const STATE_BODY_CAPACITY: usize = 16 * 1024;

const STORE_KEY_AAD: &[u8] = b"store-key";
const STATE_AAD_PREFIX: &[u8] = b"chat-state";
const LOCAL_SEAL_AAD: &[u8] = b"local-seal";
const LOCAL_SEAL_INFO: &[u8] = b"fuzzy-local-seal-v1";
const STATE_EXTENSION: &str = "state";
const STATE_TMP_EXTENSION: &str = "state.tmp";

/// Serialises every Argon2id run in the process — each one holds 64 MiB (pitfall §F.21).
static ARGON_LOCK: Mutex<()> = Mutex::new(());

/// A 32-byte key that wipes itself on drop.
pub type Key32 = Zeroizing<[u8; 32]>;

/// Fills `dest` from the OS CSPRNG.
pub fn fill_random(dest: &mut [u8]) -> Result<(), CoreError> {
    getrandom::fill(dest).map_err(|_| CoreError::Internal)
}

fn random_array<const N: usize>() -> Result<[u8; N], CoreError> {
    let mut out = [0u8; N];
    fill_random(&mut out)?;
    Ok(out)
}

// ---------------------------------------------------------------------------
// AEAD + KDF primitives (all from the pinned crates)
// ---------------------------------------------------------------------------

fn seal(key: &[u8; 32], nonce: &[u8; 24], aad: &[u8], msg: &[u8]) -> Result<Vec<u8>, CoreError> {
    XChaCha20Poly1305::new(key.into())
        .encrypt(nonce.into(), Payload { msg, aad })
        .map_err(|_| CoreError::Internal)
}

/// Tag failure is `Corrupt`; callers that know better (the wrapped key) remap it.
fn open(key: &[u8; 32], nonce: &[u8; 24], aad: &[u8], ct: &[u8]) -> Result<Vec<u8>, CoreError> {
    XChaCha20Poly1305::new(key.into())
        .decrypt(nonce.into(), Payload { msg: ct, aad })
        .map_err(|_| CoreError::Corrupt)
}

/// Argon2id(password, salt, params) → 32-byte KEK. Parameters come from a blob
/// header, so an unusable set is `Corrupt`, never a panic or a runaway allocation.
fn derive_kek(password: &[u8], salt: &[u8; 16], params: Argon2Params) -> Result<Key32, CoreError> {
    if params.m_cost > MAX_ARGON2_M_COST || params.t_cost > MAX_ARGON2_T_COST {
        return Err(CoreError::Corrupt);
    }
    let params = Params::new(
        params.m_cost,
        params.t_cost,
        u32::from(params.p_cost),
        Some(32),
    )
    .map_err(|_| CoreError::Corrupt)?;
    let argon2 = Argon2::new(Algorithm::Argon2id, Version::V0x13, params);
    let mut kek = Zeroizing::new([0u8; 32]);
    let _serialised = ARGON_LOCK
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());
    argon2
        .hash_password_into(password, salt, kek.as_mut())
        .map_err(|_| CoreError::Corrupt)?;
    Ok(kek)
}

/// `local_key = HKDF-SHA256(ikm = store_key, salt = none, info = "fuzzy-local-seal-v1")`.
fn local_key(store_key: &[u8; 32]) -> Result<Key32, CoreError> {
    let mut key = Zeroizing::new([0u8; 32]);
    Hkdf::<Sha256>::new(None, store_key)
        .expand(LOCAL_SEAL_INFO, key.as_mut())
        .map_err(|_| CoreError::Internal)?;
    Ok(key)
}

// ---------------------------------------------------------------------------
// Wrapped store key (0x10)
// ---------------------------------------------------------------------------

/// Wraps `store_key` under `password` with a fresh salt and nonce.
pub fn wrap_store_key(store_key: &[u8; 32], password: &[u8]) -> Result<Vec<u8>, CoreError> {
    wrap_store_key_with(store_key, password, random_array()?, random_array()?)
}

/// [`wrap_store_key`] with the randomness supplied — the golden test pins its output.
pub fn wrap_store_key_with(
    store_key: &[u8; 32],
    password: &[u8],
    salt: [u8; 16],
    nonce: [u8; 24],
) -> Result<Vec<u8>, CoreError> {
    let kek = derive_kek(password, &salt, ARGON2_PARAMS)?;
    let ciphertext: [u8; WRAPPED_STORE_KEY_CT_LEN] = seal(&kek, &nonce, STORE_KEY_AAD, store_key)?
        .try_into()
        .map_err(|_| CoreError::Internal)?;
    Ok(WrappedStoreKey {
        salt,
        params: ARGON2_PARAMS,
        nonce,
        ciphertext,
    }
    .encode())
}

/// Inverse of [`wrap_store_key`]. A tag failure is `WrongPassword` — the AEAD
/// cannot tell a wrong password from a tampered blob, and the password is the
/// only input the user controls.
pub fn unwrap_store_key(blob: &[u8], password: &[u8]) -> Result<Key32, CoreError> {
    let wrapped = WrappedStoreKey::decode(blob)?;
    let kek = derive_kek(password, &wrapped.salt, wrapped.params)?;
    let plain = Zeroizing::new(
        open(&kek, &wrapped.nonce, STORE_KEY_AAD, &wrapped.ciphertext)
            .map_err(|_| CoreError::WrongPassword)?,
    );
    let mut store_key = Zeroizing::new([0u8; 32]);
    if plain.len() != store_key.len() {
        return Err(CoreError::Corrupt);
    }
    store_key.copy_from_slice(&plain);
    Ok(store_key)
}

// ---------------------------------------------------------------------------
// Local seal (0x20)
// ---------------------------------------------------------------------------

/// Seals `bytes` under the HKDF-derived local key with a random nonce.
pub fn seal_local(store_key: &[u8; 32], bytes: &[u8]) -> Result<Vec<u8>, CoreError> {
    let key = local_key(store_key)?;
    let nonce: [u8; 24] = random_array()?;
    let ciphertext = seal(&key, &nonce, LOCAL_SEAL_AAD, bytes)?;
    Ok(LocalSeal { nonce, ciphertext }.encode())
}

/// Inverse of [`seal_local`]; a tag failure is `Corrupt`.
pub fn open_local(store_key: &[u8; 32], blob: &[u8]) -> Result<Vec<u8>, CoreError> {
    let sealed = LocalSeal::decode(blob)?;
    let key = local_key(store_key)?;
    open(&key, &sealed.nonce, LOCAL_SEAL_AAD, &sealed.ciphertext)
}

// ---------------------------------------------------------------------------
// State files
// ---------------------------------------------------------------------------

/// A chat id is also a file name (`<chat_id>.state`) and a map key, and the
/// codec only guarantees 1..=255 bytes of UTF-8 (FACTS, F2-1 review). Before it
/// touches a path it must have the uuid-v4 shape: 36 chars of lowercase hex with
/// dashes at 8/13/18/23. Anything else is `Corrupt`.
pub fn validate_chat_id(chat_id: &str) -> Result<(), CoreError> {
    const DASHES: [usize; 4] = [8, 13, 18, 23];
    let well_formed = chat_id.len() == 36
        && chat_id.bytes().enumerate().all(|(index, byte)| {
            if DASHES.contains(&index) {
                byte == b'-'
            } else {
                byte.is_ascii_digit() || (b'a'..=b'f').contains(&byte)
            }
        });
    if well_formed {
        Ok(())
    } else {
        Err(CoreError::Corrupt)
    }
}

fn state_aad(chat_id: &str) -> Vec<u8> {
    let mut aad = Vec::with_capacity(STATE_AAD_PREFIX.len() + chat_id.len());
    aad.extend_from_slice(STATE_AAD_PREFIX);
    aad.extend_from_slice(chat_id.as_bytes());
    aad
}

fn seal_state(store_key: &[u8; 32], state: &ChatState) -> Result<Vec<u8>, CoreError> {
    let mut body = Zeroizing::new(Vec::with_capacity(STATE_BODY_CAPACITY));
    serde_json::to_writer(&mut *body, state).map_err(|_| CoreError::Internal)?;
    let nonce: [u8; 24] = random_array()?;
    let ciphertext = seal(store_key, &nonce, &state_aad(&state.chat_id), &body)?;
    Ok(LocalSeal { nonce, ciphertext }.encode())
}

fn open_state(store_key: &[u8; 32], chat_id: &str, file: &[u8]) -> Result<ChatState, CoreError> {
    let sealed = LocalSeal::decode(file)?;
    let body = Zeroizing::new(open(
        store_key,
        &sealed.nonce,
        &state_aad(chat_id),
        &sealed.ciphertext,
    )?);
    let state: ChatState = serde_json::from_slice(&body).map_err(|_| CoreError::Corrupt)?;
    if state.format_version != STATE_FORMAT_VERSION {
        return Err(CoreError::UnsupportedFormat);
    }
    if state.chat_id != chat_id {
        return Err(CoreError::Corrupt);
    }
    Ok(state)
}

/// `<file>.tmp` → write → fsync → rename over `path` (pitfall §F.14). A failed
/// attempt leaves no temp file behind and never touches the previous `path`.
fn write_atomically(path: &Path, bytes: &[u8]) -> Result<(), CoreError> {
    let tmp = path.with_extension(STATE_TMP_EXTENSION);
    let written = (|| -> io::Result<()> {
        let mut file = File::create(&tmp)?;
        file.write_all(bytes)?;
        file.sync_all()?;
        drop(file);
        fs::rename(&tmp, path)
    })();
    if written.is_err() {
        let _ = fs::remove_file(&tmp);
    }
    written.map_err(|_| CoreError::Io)
}

/// An unlocked store: the store key, its directory and the lazily loaded states.
/// The cache only ever holds states that are on disk — any failure evicts.
#[derive(ZeroizeOnDrop)]
pub struct OpenStore {
    store_key: Key32,
    #[zeroize(skip)]
    root: PathBuf,
    #[zeroize(skip)]
    cache: HashMap<String, ChatState>,
}

impl OpenStore {
    /// Creates `<store_dir>/fuzzy_crypto_store/` if missing and takes ownership of the key.
    pub fn open(store_dir: &Path, store_key: Key32) -> Result<Self, CoreError> {
        let root = store_dir.join(STORE_SUBDIR);
        fs::create_dir_all(&root).map_err(|_| CoreError::Io)?;
        let root = fs::canonicalize(root).map_err(|_| CoreError::Io)?;
        Ok(Self {
            store_key,
            root,
            cache: HashMap::new(),
        })
    }

    /// `<root>/<chat_id>.state`, validated and proven to stay inside `root`.
    fn state_path(&self, chat_id: &str) -> Result<PathBuf, CoreError> {
        validate_chat_id(chat_id)?;
        let path = self.root.join(chat_id).with_extension(STATE_EXTENSION);
        if path.starts_with(&self.root) {
            Ok(path)
        } else {
            Err(CoreError::Corrupt)
        }
    }

    /// Seals and writes `state` atomically; does not touch the cache.
    pub fn save_state(&self, state: &ChatState) -> Result<(), CoreError> {
        let path = self.state_path(&state.chat_id)?;
        let file = seal_state(&self.store_key, state)?;
        write_atomically(&path, &file)
    }

    /// Reads and opens `<chat_id>.state`; missing → `UnknownChat`.
    pub fn load_state(&self, chat_id: &str) -> Result<ChatState, CoreError> {
        let file = fs::read(self.state_path(chat_id)?).map_err(|error| {
            if error.kind() == io::ErrorKind::NotFound {
                CoreError::UnknownChat
            } else {
                CoreError::Io
            }
        })?;
        open_state(&self.store_key, chat_id, &file)
    }

    /// Persists a new or replaced state and caches it.
    pub fn put_state(&mut self, state: ChatState) -> Result<(), CoreError> {
        self.save_state(&state)?;
        self.cache.insert(state.chat_id.clone(), state);
        Ok(())
    }

    /// Loads (lazily), mutates and **saves before returning**. If the mutation
    /// or the save fails the cached copy is evicted, so the next call re-reads
    /// whatever is on disk.
    pub fn with_state_mut<T>(
        &mut self,
        chat_id: &str,
        mutate: impl FnOnce(&mut ChatState) -> Result<T, CoreError>,
    ) -> Result<T, CoreError> {
        if !self.cache.contains_key(chat_id) {
            let state = self.load_state(chat_id)?;
            self.cache.insert(chat_id.to_string(), state);
        }
        let path = self.state_path(chat_id)?;
        let result = match self.cache.get_mut(chat_id) {
            Some(state) => mutate(state)
                .and_then(|value| seal_state(&self.store_key, state).map(|file| (value, file))),
            None => Err(CoreError::Internal),
        };
        let saved = result.and_then(|(value, file)| write_atomically(&path, &file).map(|()| value));
        if saved.is_err() {
            self.cache.remove(chat_id);
        }
        saved
    }

    /// Overwrites the state file with zeros (best effort), unlinks it and evicts
    /// the cache. A chat with no state file is already deleted.
    pub fn delete_chat(&mut self, chat_id: &str) -> Result<(), CoreError> {
        let path = self.state_path(chat_id)?;
        self.cache.remove(chat_id);
        let existing = match fs::metadata(&path) {
            Ok(metadata) => metadata,
            Err(error) if error.kind() == io::ErrorKind::NotFound => return Ok(()),
            Err(_) => return Err(CoreError::Io),
        };
        let zeros = vec![0u8; usize::try_from(existing.len()).unwrap_or(0)];
        let _ = File::create(&path).and_then(|mut file| {
            file.write_all(&zeros)?;
            file.sync_all()
        });
        fs::remove_file(&path).map_err(|_| CoreError::Io)
    }

    pub fn seal_local(&self, bytes: &[u8]) -> Result<Vec<u8>, CoreError> {
        seal_local(&self.store_key, bytes)
    }

    pub fn open_local(&self, blob: &[u8]) -> Result<Vec<u8>, CoreError> {
        open_local(&self.store_key, blob)
    }

    #[cfg(test)]
    fn is_cached(&self, chat_id: &str) -> bool {
        self.cache.contains_key(chat_id)
    }
}

#[cfg(test)]
pub(crate) mod test_support {
    use std::path::PathBuf;

    use vodozemac::olm::Account;

    use crate::error::CoreError;
    use crate::state::{ChatState, Role};

    /// A fresh, unique directory under the OS temp dir.
    pub fn temp_dir() -> PathBuf {
        let mut tag = [0u8; 8];
        super::fill_random(&mut tag).expect("os rng");
        let dir = std::env::temp_dir().join(format!(
            "fuzzy_crypto_core_test_{}_{}",
            std::process::id(),
            u64::from_be_bytes(tag)
        ));
        std::fs::create_dir_all(&dir).expect("temp dir");
        dir
    }

    /// The error of a result whose `Ok` type has no `Debug` (`ChatState` must not print itself).
    pub fn err_of<T>(result: Result<T, CoreError>) -> CoreError {
        match result {
            Ok(_) => panic!("expected an error"),
            Err(error) => error,
        }
    }

    /// The minimal state F2-3 will fill: an unpaired inviter with a fresh Olm account.
    pub fn fresh_state(chat_id: &str) -> ChatState {
        let account = Account::new();
        let our_ed25519 = *account.ed25519_key().as_bytes();
        ChatState::new(
            Role::Inviter,
            chat_id.to_string(),
            account.pickle(),
            our_ed25519,
        )
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const PASSWORD: &[u8] = b"pw";
    const STORE_KEY: [u8; 32] = [0x33; 32];

    mod store_key {
        use super::*;

        #[test]
        fn wrong_password_rejected() {
            let blob = wrap_store_key(&STORE_KEY, PASSWORD).unwrap();

            assert_eq!(
                unwrap_store_key(&blob, b"px").unwrap_err(),
                CoreError::WrongPassword
            );
            assert_eq!(
                unwrap_store_key(&blob, b"").unwrap_err(),
                CoreError::WrongPassword
            );
            assert_eq!(*unwrap_store_key(&blob, PASSWORD).unwrap(), STORE_KEY);
        }

        #[test]
        fn tampered_blob_is_wrong_password_not_a_panic() {
            let blob = wrap_store_key(&STORE_KEY, PASSWORD).unwrap();

            // One byte of the salt, the nonce, the ciphertext and the tag (the Argon2
            // parameter bytes are a different KDF, not a tag failure — covered below).
            for index in [6, 31, 55, 102] {
                let mut tampered = blob.clone();
                tampered[index] ^= 0x01;
                assert_eq!(
                    unwrap_store_key(&tampered, PASSWORD).unwrap_err(),
                    CoreError::WrongPassword,
                    "byte {index}"
                );
            }
        }

        #[test]
        fn rewrap_round_trip() {
            let old_blob = wrap_store_key(&STORE_KEY, PASSWORD).unwrap();
            let key = unwrap_store_key(&old_blob, PASSWORD).unwrap();
            let new_blob = wrap_store_key(&key, b"new").unwrap();

            assert_ne!(old_blob, new_blob, "fresh salt and nonce every time");
            assert_eq!(*unwrap_store_key(&old_blob, PASSWORD).unwrap(), STORE_KEY);
            assert_eq!(
                unwrap_store_key(&old_blob, b"new").unwrap_err(),
                CoreError::WrongPassword
            );
            assert_eq!(*unwrap_store_key(&new_blob, b"new").unwrap(), STORE_KEY);
            assert_eq!(
                unwrap_store_key(&new_blob, PASSWORD).unwrap_err(),
                CoreError::WrongPassword
            );
        }

        #[test]
        fn wrapped_blob_format_exact_bytes() {
            // Generated from the spec tables with argon2-cffi + pycryptodome (log §2),
            // not from this crate: FUZZ 01 10 · salt16 · m u32 · t u32 · p u8 · nonce24 · ct+tag48.
            let golden = hex(concat!(
                "46555a5a0110",
                "11111111111111111111111111111111",
                "00010000",
                "00000004",
                "01",
                "222222222222222222222222222222222222222222222222",
                "ca92d2caa5a5120ca9b162dab36620db05f2829d86e6df4fefe299cbb96637a4",
                "0343f644cbf09c412a250cb69e1550bd",
            ));

            let blob = wrap_store_key_with(&STORE_KEY, PASSWORD, [0x11; 16], [0x22; 24]).unwrap();

            assert_eq!(blob.len(), 103);
            assert_eq!(blob, golden);
            assert_eq!(*unwrap_store_key(&golden, PASSWORD).unwrap(), STORE_KEY);
        }

        #[test]
        fn empty_password_is_valid() {
            let blob = wrap_store_key(&STORE_KEY, b"").unwrap();

            assert_eq!(*unwrap_store_key(&blob, b"").unwrap(), STORE_KEY);
            assert_eq!(
                unwrap_store_key(&blob, b"x").unwrap_err(),
                CoreError::WrongPassword
            );
        }

        #[test]
        fn foreign_or_broken_blobs_are_errors_not_panics() {
            let blob = wrap_store_key(&STORE_KEY, PASSWORD).unwrap();

            let local = seal_local(&STORE_KEY, b"x").unwrap();
            assert_eq!(
                unwrap_store_key(&local, PASSWORD).unwrap_err(),
                CoreError::UnsupportedFormat
            );
            assert_eq!(
                unwrap_store_key(&blob[..blob.len() - 1], PASSWORD).unwrap_err(),
                CoreError::Corrupt
            );
            assert_eq!(
                unwrap_store_key(&[], PASSWORD).unwrap_err(),
                CoreError::UnsupportedFormat
            );
            // An absurd memory cost in the header is refused before any allocation.
            let mut huge = blob.clone();
            huge[22..26].copy_from_slice(&u32::MAX.to_be_bytes());
            assert_eq!(
                unwrap_store_key(&huge, PASSWORD).unwrap_err(),
                CoreError::Corrupt
            );
            let mut zero_lanes = blob.clone();
            zero_lanes[30] = 0;
            assert_eq!(
                unwrap_store_key(&zero_lanes, PASSWORD).unwrap_err(),
                CoreError::Corrupt
            );
        }
    }

    mod state {
        use super::test_support::{err_of, fresh_state, temp_dir};
        use super::*;

        const CHAT_ID: &str = "6f1e9b2c-3d4a-4f5b-8c6d-7e8f9a0b1c2d";

        fn open_store(dir: &Path, key: [u8; 32]) -> OpenStore {
            OpenStore::open(dir, Zeroizing::new(key)).unwrap()
        }

        fn state_files(store: &OpenStore) -> Vec<String> {
            let mut names: Vec<String> = fs::read_dir(&store.root)
                .unwrap()
                .map(|entry| entry.unwrap().file_name().to_string_lossy().into_owned())
                .collect();
            names.sort();
            names
        }

        #[test]
        fn save_load_round_trip() {
            let dir = temp_dir();
            let mut store = open_store(&dir, STORE_KEY);
            let mut state = fresh_state(CHAT_ID);
            state.send_counter = 7;
            state.verified = true;
            state.last_invitation = Some(vec![1, 2, 3]);
            let account_json = serde_json::to_string(&state.account).unwrap();
            let our_ed25519 = state.our_ed25519;
            store.put_state(state).unwrap();

            let reopened = open_store(&dir, STORE_KEY);
            let loaded = reopened.load_state(CHAT_ID).unwrap();

            assert_eq!(loaded.format_version, STATE_FORMAT_VERSION);
            assert_eq!(loaded.role, crate::state::Role::Inviter);
            assert_eq!(loaded.chat_id, CHAT_ID);
            assert_eq!(
                serde_json::to_string(&loaded.account).unwrap(),
                account_json
            );
            assert!(loaded.session.is_none());
            assert_eq!(loaded.our_ed25519, our_ed25519);
            assert_eq!(loaded.send_counter, 7);
            assert!(loaded.verified);
            assert_eq!(loaded.last_invitation, Some(vec![1, 2, 3]));
            assert_eq!(state_files(&store), vec![format!("{CHAT_ID}.state")]);
            let _ = fs::remove_dir_all(dir);
        }

        #[test]
        fn save_overwrites_existing() {
            let dir = temp_dir();
            let mut store = open_store(&dir, STORE_KEY);
            store.put_state(fresh_state(CHAT_ID)).unwrap();
            let first = fs::read(store.state_path(CHAT_ID).unwrap()).unwrap();

            let mut second_state = fresh_state(CHAT_ID);
            second_state.send_counter = 2;
            store.put_state(second_state).unwrap();
            let second = fs::read(store.state_path(CHAT_ID).unwrap()).unwrap();

            assert_ne!(first, second);
            assert_eq!(store.load_state(CHAT_ID).unwrap().send_counter, 2);
            assert_eq!(state_files(&store), vec![format!("{CHAT_ID}.state")]);
            let _ = fs::remove_dir_all(dir);
        }

        #[test]
        fn tmp_file_never_left_behind() {
            let dir = temp_dir();
            let mut store = open_store(&dir, STORE_KEY);

            for counter in 0..3 {
                let mut state = fresh_state(CHAT_ID);
                state.send_counter = counter;
                store.put_state(state).unwrap();
                assert_eq!(state_files(&store), vec![format!("{CHAT_ID}.state")]);
            }
            let _ = fs::remove_dir_all(dir);
        }

        #[test]
        fn crash_between_write_and_rename_leaves_a_stale_tmp_that_is_ignored() {
            let dir = temp_dir();
            let mut store = open_store(&dir, STORE_KEY);
            let tmp = store
                .state_path(CHAT_ID)
                .unwrap()
                .with_extension(STATE_TMP_EXTENSION);

            // Crash before any state existed: only the temp file survives.
            fs::write(&tmp, b"half-written garbage").unwrap();
            assert_eq!(err_of(store.load_state(CHAT_ID)), CoreError::UnknownChat);
            store.put_state(fresh_state(CHAT_ID)).unwrap();
            assert_eq!(state_files(&store), vec![format!("{CHAT_ID}.state")]);
            assert!(store.load_state(CHAT_ID).is_ok());

            // Crash while replacing a good state: the old file is still the one that opens.
            let good = fs::read(store.state_path(CHAT_ID).unwrap()).unwrap();
            fs::write(&tmp, b"half-written garbage").unwrap();
            assert_eq!(fs::read(store.state_path(CHAT_ID).unwrap()).unwrap(), good);
            assert!(open_store(&dir, STORE_KEY).load_state(CHAT_ID).is_ok());
            let _ = fs::remove_dir_all(dir);
        }

        #[test]
        fn wrong_store_key_cannot_open() {
            let dir = temp_dir();
            let mut store = open_store(&dir, STORE_KEY);
            store.put_state(fresh_state(CHAT_ID)).unwrap();

            let other = open_store(&dir, [0x44; 32]);

            assert_eq!(err_of(other.load_state(CHAT_ID)), CoreError::Corrupt);
            let _ = fs::remove_dir_all(dir);
        }

        #[test]
        fn corrupt_missing_and_foreign_files() {
            let dir = temp_dir();
            let mut store = open_store(&dir, STORE_KEY);
            store.put_state(fresh_state(CHAT_ID)).unwrap();
            let path = store.state_path(CHAT_ID).unwrap();
            let good = fs::read(&path).unwrap();

            let mut flipped = good.clone();
            flipped[40] ^= 0x80;
            fs::write(&path, &flipped).unwrap();
            assert_eq!(err_of(store.load_state(CHAT_ID)), CoreError::Corrupt);

            fs::write(&path, &good[..20]).unwrap();
            assert_eq!(err_of(store.load_state(CHAT_ID)), CoreError::Corrupt);

            fs::write(&path, wrap_store_key(&STORE_KEY, PASSWORD).unwrap()).unwrap();
            assert_eq!(
                err_of(store.load_state(CHAT_ID)),
                CoreError::UnsupportedFormat
            );

            // The AAD binds the file to its chat id: a renamed file does not open.
            let other_id = "0badf00d-0000-4000-8000-000000000000";
            fs::write(store.state_path(other_id).unwrap(), &good).unwrap();
            assert_eq!(err_of(store.load_state(other_id)), CoreError::Corrupt);

            assert_eq!(
                err_of(store.load_state("00000000-0000-4000-8000-000000000000")),
                CoreError::UnknownChat
            );
            let _ = fs::remove_dir_all(dir);
        }

        #[test]
        fn with_state_mut_persists_before_returning_and_evicts_on_error() {
            let dir = temp_dir();
            let mut store = open_store(&dir, STORE_KEY);
            store.put_state(fresh_state(CHAT_ID)).unwrap();

            let counter = store
                .with_state_mut(CHAT_ID, |state| {
                    state.send_counter += 1;
                    Ok(state.send_counter)
                })
                .unwrap();
            assert_eq!(counter, 1);
            assert_eq!(
                open_store(&dir, STORE_KEY)
                    .load_state(CHAT_ID)
                    .unwrap()
                    .send_counter,
                1
            );

            let failed = store.with_state_mut(CHAT_ID, |state| {
                state.send_counter = 99;
                Err::<(), _>(CoreError::Replay)
            });
            assert_eq!(failed.unwrap_err(), CoreError::Replay);
            assert!(!store.is_cached(CHAT_ID), "a failed mutation is forgotten");
            assert_eq!(store.load_state(CHAT_ID).unwrap().send_counter, 1);

            // Lazily loads from disk into the cache on first use.
            let mut fresh = open_store(&dir, STORE_KEY);
            assert!(!fresh.is_cached(CHAT_ID));
            fresh.with_state_mut(CHAT_ID, |_| Ok(())).unwrap();
            assert!(fresh.is_cached(CHAT_ID));
            assert_eq!(
                fresh
                    .with_state_mut("00000000-0000-4000-8000-000000000000", |_| Ok(()))
                    .unwrap_err(),
                CoreError::UnknownChat
            );
            let _ = fs::remove_dir_all(dir);
        }

        #[test]
        fn chat_id_must_be_a_uuid_v4_shape() {
            let dir = temp_dir();
            let mut store = open_store(&dir, STORE_KEY);
            let long = "a".repeat(255);
            let bad = [
                "",
                "../../x",
                "a/b",
                "a\\b",
                long.as_str(),
                "6F1E9B2C-3D4A-4F5B-8C6D-7E8F9A0B1C2D",
                "6f1e9b2c-3d4a-4f5b-8c6d-7e8f9a0b1c2",
                "6f1e9b2c-3d4a-4f5b-8c6d-7e8f9a0b1c2d0",
                "6f1e9b2c03d4a-4f5b-8c6d-7e8f9a0b1c2d",
                "6f1e9b2c-3d4a-4f5b-8c6d-7e8f9a0b1c2g",
                "6f1e9b2c-3d4a-4f5b-8c6d-7e8f9a0b1c2\u{e9}",
                "../e9b2c-3d4a-4f5b-8c6d-7e8f9a0b1c2d",
            ];

            for chat_id in bad {
                assert_eq!(
                    validate_chat_id(chat_id).unwrap_err(),
                    CoreError::Corrupt,
                    "{chat_id:?}"
                );
                assert_eq!(
                    store.put_state(fresh_state(chat_id)).unwrap_err(),
                    CoreError::Corrupt,
                    "{chat_id:?}"
                );
                assert_eq!(err_of(store.load_state(chat_id)), CoreError::Corrupt);
                assert_eq!(store.delete_chat(chat_id).unwrap_err(), CoreError::Corrupt);
                assert_eq!(
                    store.with_state_mut(chat_id, |_| Ok(())).unwrap_err(),
                    CoreError::Corrupt
                );
            }
            assert!(state_files(&store).is_empty());

            validate_chat_id(CHAT_ID).unwrap();
            let path = store.state_path(CHAT_ID).unwrap();
            assert!(path.starts_with(&store.root));
            assert_eq!(
                path.file_name().unwrap().to_str().unwrap(),
                format!("{CHAT_ID}.state")
            );
            let _ = fs::remove_dir_all(dir);
        }

        #[test]
        fn delete_chat_zeroes_unlinks_and_is_idempotent() {
            let dir = temp_dir();
            let mut store = open_store(&dir, STORE_KEY);
            store.put_state(fresh_state(CHAT_ID)).unwrap();
            assert!(store.is_cached(CHAT_ID));

            store.delete_chat(CHAT_ID).unwrap();

            assert!(!store.is_cached(CHAT_ID));
            assert!(state_files(&store).is_empty());
            assert_eq!(err_of(store.load_state(CHAT_ID)), CoreError::UnknownChat);
            store.delete_chat(CHAT_ID).unwrap();
            let _ = fs::remove_dir_all(dir);
        }
    }

    mod local {
        use super::*;

        #[test]
        fn seal_open_round_trip() {
            for message in [&b""[..], b"hi", &[0u8; 4096]] {
                let blob = seal_local(&STORE_KEY, message).unwrap();
                assert_eq!(&blob[..6], b"FUZZ\x01\x20");
                assert_eq!(blob.len(), 6 + 24 + message.len() + 16);
                assert_eq!(open_local(&STORE_KEY, &blob).unwrap(), message);
            }

            let first = seal_local(&STORE_KEY, b"same").unwrap();
            let second = seal_local(&STORE_KEY, b"same").unwrap();
            assert_ne!(first[6..30], second[6..30], "fresh nonce per seal");
        }

        #[test]
        fn tamper_detected() {
            let blob = seal_local(&STORE_KEY, b"history entry").unwrap();

            for index in 6..blob.len() {
                let mut tampered = blob.clone();
                tampered[index] ^= 0x01;
                assert_eq!(
                    open_local(&STORE_KEY, &tampered).unwrap_err(),
                    CoreError::Corrupt,
                    "byte {index}"
                );
            }
            assert_eq!(
                open_local(&[0x44; 32], &blob).unwrap_err(),
                CoreError::Corrupt
            );
            assert_eq!(
                open_local(&STORE_KEY, &blob[..blob.len() - 1]).unwrap_err(),
                CoreError::Corrupt
            );
            let wrapped = wrap_store_key(&STORE_KEY, PASSWORD).unwrap();
            assert_eq!(
                open_local(&STORE_KEY, &wrapped).unwrap_err(),
                CoreError::UnsupportedFormat
            );
        }

        #[test]
        fn opens_the_golden_blob() {
            // HKDF-SHA256(store_key 0x33*32, no salt, "fuzzy-local-seal-v1") + XChaCha20-Poly1305
            // with AAD "local-seal", computed with pycryptodome from the spec (log §2).
            let golden = hex(concat!(
                "46555a5a0120",
                "444444444444444444444444444444444444444444444444",
                "bdb7ba2dad",
                "f086ea5a7bfe6363058bc0843dfae116",
            ));

            assert_eq!(open_local(&STORE_KEY, &golden).unwrap(), b"hello");
        }
    }

    fn hex(text: &str) -> Vec<u8> {
        (0..text.len())
            .step_by(2)
            .map(|index| u8::from_str_radix(&text[index..index + 2], 16).unwrap())
            .collect()
    }
}
