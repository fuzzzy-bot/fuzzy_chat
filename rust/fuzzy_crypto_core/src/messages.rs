//! Text messages on the live Olm session (plan §B.2 step 4, §B.4).
//!
//! Pure functions over [`ChatState`] — no I/O. The API layer (`api/messages.rs`)
//! wraps them in `OpenStore::with_state_mut`, which persists **before** the
//! result leaves Rust and, crucially, saves **only on `Ok`**: every `Err` path
//! here leaves the chat's state file byte-identical, so the validation chain can
//! mutate a cloned session freely and still never advance the on-disk ratchet on
//! a rejection (plan §B.4 "persist before returning", §B.6 crash semantics).

use subtle::ConstantTimeEq;
use vodozemac::olm::{Message as OlmNormalMessage, OlmMessage, PreKeyMessage};
use zeroize::Zeroizing;

use crate::counters;
use crate::error::CoreError;
use crate::formats::{ContentType, Direction, InnerHeader, Message, OlmType};
use crate::state::{ChatState, Role};

/// The direction this device stamps on the messages it sends: the inviter is
/// A→B, the accepter is B→A (F2-3).
fn our_direction(role: Role) -> Direction {
    match role {
        Role::Inviter => Direction::AToB,
        Role::Accepter => Direction::BToA,
    }
}

/// The direction the peer stamps on what we receive — the opposite side.
fn peer_direction(role: Role) -> Direction {
    match role {
        Role::Inviter => Direction::BToA,
        Role::Accepter => Direction::AToB,
    }
}

/// Encrypts `text` as a 0x03 message on the session, stamping the inner header
/// with our next send counter, then returns the `Fuzz/` blob. The counter is
/// incremented and the ratcheted session written into `state`; the caller
/// persists before the blob is returned, so a crash can only lose a blob the
/// user never saw — a counter is never reused (plan §B.4).
pub fn encrypt_text(state: &mut ChatState, text: &str) -> Result<String, CoreError> {
    // The chat must be connected; a pending invite has no session.
    let mut session = state.session()?.ok_or(CoreError::Internal)?;
    let peer_ed25519 = state.peer_ed25519.ok_or(CoreError::Internal)?;

    let counter = state.send_counter;
    let header = InnerHeader {
        chat_id: state.chat_id.clone(),
        sender_ed25519: state.our_ed25519,
        recipient_ed25519: peer_ed25519,
        direction: our_direction(state.role),
        counter,
        content_type: ContentType::Text,
        body: text.as_bytes().to_vec(),
    }
    .encode()?;

    let (olm_type, olm_body) = match session.encrypt(&header).map_err(|_| CoreError::Internal)? {
        OlmMessage::PreKey(message) => (OlmType::PreKey, message.to_bytes()),
        OlmMessage::Normal(message) => (OlmType::Normal, message.to_bytes()),
    };
    let blob = Message { olm_type, olm_body }.encode()?;

    // Commit only after the blob is built.
    state.session = Some(session.pickle());
    state.send_counter = counter.checked_add(1).ok_or(CoreError::Internal)?;
    Ok(crate::formats::encode_text(&blob))
}

/// Decrypts a pasted 0x03 message blob. The checks run in the fixed order of
/// plan §B.4 and stop at the first failure; nothing is committed to `state`
/// until every one has passed (and the caller only persists on `Ok`):
/// 1. envelope is a message (`UnsupportedFormat`);
/// 2. Olm decrypt — `MissingMessageKey` → `Replay`, `TooBigMessageGap` → `TooOld`,
///    any MAC/other failure → `Corrupt` (a blob from another chat fails here, its
///    MAC being under a different session);
/// 3. inner header decode + binding: chat id (`WrongChat`), identity keys
///    (constant-time, `WrongChat`), direction (`Corrupt`), content type text
///    (`Corrupt`), UTF-8 body (`Corrupt`);
/// 4. the per-direction counter window (`Replay` / `TooOld`).
pub fn decrypt_text(state: &mut ChatState, blob: &[u8]) -> Result<String, CoreError> {
    // 1. Envelope → Olm message.
    let message = Message::decode(blob)?;
    let olm = match message.olm_type {
        OlmType::PreKey => OlmMessage::PreKey(
            PreKeyMessage::from_bytes(&message.olm_body).map_err(|_| CoreError::Corrupt)?,
        ),
        OlmType::Normal => OlmMessage::Normal(
            OlmNormalMessage::from_bytes(&message.olm_body).map_err(|_| CoreError::Corrupt)?,
        ),
    };

    // 2. Olm decrypt on a cloned session (the clone ratchets; state is untouched
    //    until the commit at the end, so a later failure leaves the chain intact).
    let mut session = state.session()?.ok_or(CoreError::Internal)?;
    let plaintext = Zeroizing::new(session.decrypt(&olm).map_err(|error| {
        use vodozemac::olm::DecryptionError::{MissingMessageKey, TooBigMessageGap};
        match error {
            MissingMessageKey(_) => CoreError::Replay,
            TooBigMessageGap(..) => CoreError::TooOld,
            _ => CoreError::Corrupt,
        }
    })?);

    // 3. Inner header binding.
    let header = InnerHeader::decode(&plaintext).map_err(|_| CoreError::Corrupt)?;
    if header.chat_id != state.chat_id {
        return Err(CoreError::WrongChat);
    }
    let peer_ed25519 = state.peer_ed25519.ok_or(CoreError::Internal)?;
    let keys_match = header.sender_ed25519.ct_eq(&peer_ed25519)
        & header.recipient_ed25519.ct_eq(&state.our_ed25519);
    if !bool::from(keys_match) {
        return Err(CoreError::WrongChat);
    }
    if header.direction != peer_direction(state.role) {
        return Err(CoreError::Corrupt);
    }
    if header.content_type != ContentType::Text {
        return Err(CoreError::Corrupt);
    }
    let counter = header.counter;
    let text = String::from_utf8(header.body).map_err(|_| CoreError::Corrupt)?;

    // 4. Counter window.
    let (recv_highest, recv_seen_bitmap) =
        counters::accept(state.recv_highest, state.recv_seen_bitmap, counter)?;

    // 5. Commit (the caller persists before returning).
    state.session = Some(session.pickle());
    state.recv_highest = recv_highest;
    state.recv_seen_bitmap = recv_seen_bitmap;
    Ok(text)
}
