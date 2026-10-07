# The pure-Dart encryption stack — archived, not wired in

This is the encryption Fuzzy Chat shipped before the Rust core: the AES service, the
RSA service, the handshake service and the password-based encryption service, exactly
as they were written and tested, together with every test that covered them.

It is kept because it worked and was tested, and throwing tested code away is a decision
you cannot undo. It is **not** part of the app, and nothing here should be changed — the
whole value of this folder is that it is the code that passed those tests, unaltered.

- **Lifted from:** commit `d4f7ce4^` — the last commit before `d4f7ce4`, *"delete the
  pure-dart crypto stack and the pointycastle fork"* (13 September 2026, 504 files,
  172 743 lines removed).
- **Archived on:** 22 September 2026.
- **Status:** compiles, analyses clean, all tests pass. Not a dependency of the app.

## It cannot be switched on as a fallback

This matters more than anything else on this page, so it comes first.

The two stacks cannot read each other. An invitation, an acceptance, a message or a file
made by one is meaningless to the other — different pairing, different key schedule,
different cipher, different envelope on the wire. Reviving this code would not rescue a
single existing chat. It would start a second, separate product that happens to live in
the same app.

So "backup" here means *the source is preserved and provably still works*. It does not
mean *the app can fall back to it*. If you ever do want it live again, that is a
product decision with a migration attached, not a switch.

## What is here

```
lib/                 the four services, compiled and tested
  src/aes_service/                    AES-256-GCM with a per-message derived sub-key
  src/rsa_service/                    RSA-4096, OAEP, PKCS#1 signatures
  src/handshake_service/              the invitation / acceptance JSON and its four models
  src/password_based_encryption_service/   Argon2id + AES-256-GCM
  src/utils/                          the secure random helper
  src/constants.dart                  the derivation label the AES service used
test/                54 test cases, all passing (see "the tests" below)
app_integration/     the Dart-side key storage, kept as reference only — NOT compiled
```

`app_integration/` holds the key repository, the key storage repository (including the
re-encryption and the staged-migration recovery), the chat security model, its database
row and its data source. They need Flutter, Isar and half the app to compile, so they are
kept as readable source outside `lib/` rather than dragging those dependencies into an
archive. Read them to understand how keys were stored; do not expect them to build.

## Proving this is the original code

Only import lines were touched, in exactly three files, because the originals imported
the app's barrel files. Everything else is byte-identical. Check it yourself from the
repository root:

```sh
B=lib/src/core/encryption_services
for f in aes_service/aes_service.dart aes_service/aes_service_impl.dart \
         rsa_service/rsa_service.dart rsa_service/rsa_service_impl.dart \
         handshake_service/handshake_service.dart \
         password_based_encryption_service/password_based_encryption_service.dart \
         password_based_encryption_service/password_based_encryption_service_impl.dart; do
  git show "d4f7ce4^:$B/$f" | diff - legacy/dart_crypto/lib/src/$f
done
```

The three files with changed imports are `aes_service.dart` (the app barrel gave it
`Uint8List`, the derivation label and the random helper; the Flutter annotation package
became `meta`), `handshake_service.dart` (the app barrel gave it the RSA service and its
own component models) and the password service (one relative path shortened by a level).

## The tests

```sh
cd legacy/dart_crypto && fvm dart pub get && fvm dart test
```

54 cases, about 30 seconds, no device or Flutter needed.

**One thing worth knowing:** of these, only 27 ever ran in the app. The two pen-testing
suites — 7 AES cases and 19 RSA cases — were named `..._pentesting_tests.dart` and
`..._pentesing.dart`, and the Dart test runner only collects files ending in `_test.dart`.
They were written, committed, and then silently never executed. They are renamed here so
they run, and they all pass. Worth remembering as a general lesson: a test file that does
not end in `_test.dart` is a comment.

## PointyCastle

The app used to vendor a copy of PointyCastle at `packages/pointycastle`, 441 files. It
was added in one commit and never edited afterwards, and it was version 4.0.0 — which is
the same version published on pub today. So the fork bought nothing and cost an unsynced
copy of a cryptographic library that nobody was watching for upstream fixes.

This package therefore depends on `pointycastle: 4.0.0` from pub, pinned exactly. If you
ever want the archive to be provable entirely offline, vendor it back *inside this
folder* — never back into the app.

## How the two stacks differ

| | This (pure Dart) | The Rust core |
|---|---|---|
| Pairing | RSA-4096 + OAEP; the accepter alone picks one AES-256 key and wraps it to the inviter; plain JSON, unsigned | X25519 triple Diffie-Hellman then a double ratchet (Olm); both blobs Ed25519-signed; one-time key; 60-digit safety number |
| Message key | one chat key for the life of the chat, with a fresh sub-key derived per message | a fresh ratchet key per message; used keys deleted |
| Cipher | AES-256-GCM, associated data empty | XChaCha20-Poly1305, with the chat id, the key's role and the chunk index bound in |
| Replay | none — a blob decrypts forever, any number of times | consumed-key rule plus a 64-wide counter window per direction |
| Binding | nothing inside the ciphertext says which chat or who sent it | an inner header — chat id, both identity keys, direction, counter, content type — checked field by field |
| Files | whole file through an isolate; decrypted bytes reach the disk before the tag is checked | 1 MiB authenticated chunks; nothing on disk unverified; truncation, reordering and appending all caught |
| Passwords | Argon2id verifying a token; the Basics screen used a bare SHA-256 of the passphrase | Argon2id unwrapping a 32-byte key — unwrapping *is* the check |
| Key handling | keys in Dart lists and strings, which cannot be wiped | keys never cross the bridge; opaque handles; wiped on lock |
| Library | a vendored, unsynced PointyCastle | vodozemac and RustCrypto, both audited, exact-pinned, with a bill of materials |
| Speed | about 1.2 MB/s — roughly fourteen minutes for 1 GB | about two seconds for 1 GB |

## Credit where it is due

Two design decisions in here were genuinely right and are worth remembering:

1. **The shared key was never a working key.** It was a master key. Every message drew a
   fresh 24-byte salt and ran HKDF-SHA256 over it to produce the AES key that actually
   encrypted, so the key that crossed the wire never touched a ciphertext and a nonce
   collision was never a practical worry.
2. **The constant-time AES engine was chosen over the fast table-driven one**, which is
   the correct trade and not the obvious one.

What the design could not do, structurally, was forward secrecy (one key, forever),
authentication of the pairing (nothing signed, so a relay could sit in the middle
undetected), and erasure of key material (Dart gives you no way to wipe a string). Those
are why it was replaced, not the quality of the code.

## See also

- `documents/security/WHAT_CHANGED.md` — the long-form before-and-after.
- `documents/security/PROTOCOL.md` and `THREAT_MODEL.md` — the current specification.
