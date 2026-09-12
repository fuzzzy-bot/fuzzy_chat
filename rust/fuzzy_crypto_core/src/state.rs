//! Per-chat state — the body of every sealed `<chat_id>.state` file (plan §B.6).
//!
//! `serde` here is for the file body only; nothing in this module is a wire
//! format. The Olm pickles are serialised as the structs vodozemac ships, never
//! through `AccountPickle::encrypt` (deterministic IV, 8-byte MAC — pitfall §F.12).

use serde::{Deserialize, Serialize};
use vodozemac::olm::{Account, AccountPickle, SessionPickle};
use zeroize::{Zeroize, ZeroizeOnDrop, Zeroizing};

use crate::error::CoreError;

/// The state body version written into every file; anything else is `UnsupportedFormat`.
pub const STATE_FORMAT_VERSION: u8 = 1;

/// Which side of the handshake this device took.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Zeroize)]
pub enum Role {
    Inviter,
    Accepter,
}

/// Everything the core remembers about one chat. Zeroised on drop; the two
/// pickles are skipped because vodozemac already zeroises the key material they
/// hold when they drop (plan §A.2).
#[derive(Serialize, Deserialize, ZeroizeOnDrop)]
pub struct ChatState {
    pub format_version: u8,
    pub role: Role,
    pub chat_id: String,
    #[zeroize(skip)]
    pub account: AccountPickle,
    #[zeroize(skip)]
    pub session: Option<SessionPickle>,
    pub our_ed25519: [u8; 32],
    pub peer_curve25519: Option<[u8; 32]>,
    pub peer_ed25519: Option<[u8; 32]>,
    pub send_counter: u64,
    pub recv_highest: u64,
    pub recv_seen_bitmap: u64,
    pub verified: bool,
    pub last_invitation: Option<Vec<u8>>,
    pub last_acceptance: Option<Vec<u8>>,
}

impl ChatState {
    /// A freshly created chat: no session, no peer, nothing sent or received.
    pub fn new(role: Role, chat_id: String, account: AccountPickle, our_ed25519: [u8; 32]) -> Self {
        Self {
            format_version: STATE_FORMAT_VERSION,
            role,
            chat_id,
            account,
            session: None,
            our_ed25519,
            peer_curve25519: None,
            peer_ed25519: None,
            send_counter: 0,
            recv_highest: 0,
            recv_seen_bitmap: 0,
            verified: false,
            last_invitation: None,
            last_acceptance: None,
        }
    }

    /// The live Olm account behind the stored pickle. `AccountPickle` is not
    /// `Clone` and `Account::from_pickle` moves, so the copy goes through the
    /// pickle's serde form in a `Zeroizing` buffer (pitfall §F.12). Write the
    /// mutated account back with `account.pickle()`.
    pub fn account(&self) -> Result<Account, CoreError> {
        let json =
            Zeroizing::new(serde_json::to_vec(&self.account).map_err(|_| CoreError::Internal)?);
        let pickle: AccountPickle =
            serde_json::from_slice(&json).map_err(|_| CoreError::Internal)?;
        Ok(Account::from_pickle(pickle))
    }
}
