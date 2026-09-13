# Release procedure, attestations and reproducibility

How a Fuzzy Chat release is cut from `.github/workflows/main.yaml`, what the pipeline proves about the
artifacts, what it does **not** prove, and how anyone can check both.

## 1. Cutting a release

Every push already runs the full matrix (`rust`, `flutter-test`, `android`, `linux`, `windows`, `macos`,
`rust-repro` ×2 + `rust-repro-compare`). A release is the same workflow on a `v*` tag, which additionally
runs `attest`.

1. The commit to release is on a branch with a green run. Bump `version:` in `pubspec.yaml` (release
   candidates keep the previous version; only the final tag bumps it) and commit.
2. Tag it — annotated, from that exact commit — and push the tag:
   ```sh
   git tag -a v1.2.3 -m "fuzzy_chat v1.2.3"
   git push origin v1.2.3
   ```
3. Wait for the tag run (`gh run list --workflow fuzzy_chat --event push --branch v1.2.3`, ≈ 11 min; the
   Android job is the long pole). Every job must be green — `attest` needs all of them, so a red job means
   no attestation and no release.
4. Download and check everything the run produced (§3), then attach the artifacts and `SHA256SUMS` to a
   GitHub Release (`gh release create v1.2.3 …`). Creating the Release is the publisher's step after the
   owner's go; the pipeline only produces and attests the files.

### 1.1 As run for `v1.1.0` (2026-09-13, from the branch worktree, `agent/chat-harden-rust-crypto-core`)

The bump touches **two** files: `pubspec.yaml` and the Flutter SBOM, which embeds the pub version
(`pkg:pub/fuzzy_chat@<version>`) — without regenerating it `./sbom.sh flutter --check` fails the `flutter-test` job.

```sh
# 1. bump + changelog + this section, on a green tip (d3b24e3)
sed -i '' 's/^version: 1\.0\.0+1$/version: 1.1.0+2/' pubspec.yaml
./sbom.sh flutter && ./sbom.sh flutter --check                  # SBOM diff must be the version lines only
$EDITOR CHANGELOG.md documents/security/RELEASE.md
git add pubspec.yaml CHANGELOG.md documents/security/RELEASE.md documents/security/sbom/flutter.cdx.json
git diff --cached --check && git diff --cached | grep -iEc 'api[_-]?key|secret|token|password|BEGIN.*PRIVATE'
git commit -F msg.txt                                           # chore(release): v1.1.0 — …
git push origin agent/chat-harden-rust-crypto-core && git ls-remote --heads origin agent/chat-harden-rust-crypto-core
gh run list -R fuzzzy-bot/fuzzy_chat --commit "$(git rev-parse HEAD)" ; gh run watch <push-run-id> --exit-status

# 2. full regression on that exact tip, locally (the same gates CI runs)
( cd rust/fuzzy_crypto_core && cargo fmt --check && cargo clippy --all-targets --locked -- -D warnings && cargo test --locked )
fvm flutter analyze --fatal-infos --fatal-warnings
fvm dart format --output=none --set-exit-if-changed lib test
( cd rust/fuzzy_crypto_core && cargo build --release --locked ) && fvm flutter test
./sbom.sh rust --check && ./sbom.sh flutter --check

# 3. tag the release commit, annotated, and watch the tag run (ten jobs incl. attest)
git tag -a v1.1.0 -m "Fuzzy Chat 1.1.0 — Rust crypto core; see documents/security/HARDENING_2026.md"
git push origin v1.1.0 && git ls-remote --tags origin v1.1.0
gh run list -R fuzzzy-bot/fuzzy_chat --event push --branch v1.1.0 ; gh run watch <tag-run-id> --exit-status

# 4. verify the tag's artifacts once (§3), then delete the download
gh run download <tag-run-id> -R fuzzzy-bot/fuzzy_chat -D rel && cd rel
shasum -a 256 -c sha256sums/SHA256SUMS
for f in android-apk/app-production-release.apk linux-bundle/lib/libfuzzy_crypto_core.so macos-app/fuzzy_chat-macos.zip; do
  gh attestation verify "$f" -R fuzzzy-bot/fuzzy_chat; done
unzip -p android-apk/app-production-release.apk lib/arm64-v8a/libfuzzy_crypto_core.so | shasum -a 256   # == rust-repro-1/SHA256SUMS android line
cd .. && rm -rf rel
```

The GitHub Release itself (step 4 above, `gh release create`) is created after the owner's go, not by the tag.

Artifacts of a run (`gh run download <run-id> -D rel` puts each one in a directory of its name):

| Artifact | Content | In `SHA256SUMS` / attested |
|---|---|---|
| `android-apk` | `app-production-release.apk` (production flavor, `--split-debug-info`) | the APK |
| `linux-bundle` | `fuzzy_chat` + `lib/` + `data/` (the whole bundle directory) | `fuzzy_chat`, `lib/libfuzzy_crypto_core.so` |
| `windows-bundle` | `fuzzy_chat.exe` + plugin DLLs + `data/` | `fuzzy_chat.exe`, `fuzzy_crypto_core.dll` |
| `macos-app` | `fuzzy_chat-macos.zip` (`ditto` archive of `Fuzzy Chat.app`, symlinks and modes kept) | the zip |
| `sha256sums` | `SHA256SUMS` — `sha256sum` lines over the six files above, paths relative to the download directory | — |
| `sbom-rust`, `sbom-flutter` | the CycloneDX SBOMs committed under `documents/security/sbom/` | — |
| `rust-repro-1`, `rust-repro-2` | the Rust core built twice on separate runners + each run's `SHA256SUMS` (§4) | — |

## 2. What is attested — and what is not

`attest` runs `actions/attest-build-provenance` with `SHA256SUMS` as the subject list, so GitHub signs a
SLSA build-provenance statement binding every listed digest to this repository, the workflow file, the tag
and the run that built it (Sigstore, keyless). Verifying an artifact therefore proves *which commit and
which workflow produced these exact bytes* — nothing more.

**Not proven, and stated here so nobody assumes it:**

- **macOS is unsigned and not notarized.** The macOS job builds with code signing disabled
  (`FLUTTER_XCODE_CODE_SIGNING_ALLOWED=NO`): the Xcode project is signed for team `C9387PQ63V` and CI
  has no certificate. Gatekeeper will refuse the app unless the user overrides it. Signing needs an Apple
  Developer certificate as a CI secret or a signing step on a Mac that holds it — an owner decision
  (hardening decision D-3).
- **iOS is not built.** There is no iOS job; nothing in a release is an iOS artifact.
- **The Android APK is signed with a throwaway key.** The `android` job generates a fresh keystore per run
  (`keytool -genkeypair … -validity 1`, `CN=fuzzy_chat CI throwaway`) because the `release` build type
  refuses to build without one. The APK installs and runs, and is a faithful build of the commit, but it is
  **not a store build**: it cannot update an installation signed with the real key, and the real key is
  never in this repository or in CI until the owner provides it as the `ANDROID_KEYSTORE_*` secrets
  (hardening decision D-6).
- **Provenance is not a review.** The attestation says who built the bytes, not that the code is correct.
  What the code does is documented in `PROTOCOL.md`; what it defends against, in `THREAT_MODEL.md`.

## 3. Verifying a release

Needs `gh` ≥ 2.49 (`gh attestation`) and `sha256sum` (macOS: `shasum -a 256 -c`).

```sh
gh run download <run-id> -R fuzzzy-bot/fuzzy_chat -D rel        # or download the files from the Release page
cd rel
sha256sum -c sha256sums/SHA256SUMS                               # every line must print OK
gh attestation verify android-apk/app-production-release.apk -R fuzzzy-bot/fuzzy_chat
gh attestation verify linux-bundle/fuzzy_chat -R fuzzzy-bot/fuzzy_chat
```

`gh attestation verify` fetches the attestation for the file's digest from GitHub, checks the Sigstore
signature and that the signer is a workflow of `fuzzzy-bot/fuzzy_chat`, and prints the workflow, the ref
and the commit it was built from. Compare that commit with the tag: `git rev-parse v1.2.3^{commit}`. Any
file listed in `SHA256SUMS` can be verified the same way; the two crate libraries inside the bundles are
listed so that the Rust core can be checked on its own (§4).

## 4. Reproducibility — honest status

**The Rust core (`rust/fuzzy_crypto_core`) is reproducible; the Flutter app around it is not.** Exactly
what we promise:

1. **Pinned toolchains.** Flutter 3.41.7 (`.fvmrc`, `FLUTTER_VERSION` in the workflow), Rust 1.98.1
   (`rust-toolchain.toml`), `Cargo.lock` and `pubspec.lock` committed and built with `--locked`,
   NDK 28.2.13676358, `cargo-ndk` 4.1.2.
2. **The Rust core builds bit-for-bit identically on two independent machines.** `rust-repro` builds the
   crate twice, on two separate runners with no shared cache, for the host (`x86_64-unknown-linux-gnu`,
   the linux-bundle target) and for `aarch64-linux-android` (the Android target), `--release --locked`;
   `rust-repro-compare` prints both runs' SHA-256 of `libfuzzy_crypto_core.so` and `.a` and **fails the
   workflow if any pair differs**. It also fails if a runner path survives in the binary (below).
3. **The hashes do not depend on the build machine.** With `strip = true` and no debuginfo, the only
   machine path a release library embeds is `CARGO_HOME` in the panic-location strings of registry crates
   (measured: the crate's own paths are relative, std's are `/rustc/<commit>/…`). `.cargo/config.toml`
   remaps the GitHub hosted-runner homes to `/cargo/registry/src`, so a CI build carries no runner path.
   To reproduce a published hash on your own machine, supply your own mapping (it replaces the config's,
   which is a no-op off the runners) with the pinned toolchain:
   ```sh
   cd rust/fuzzy_crypto_core
   export RUSTFLAGS="--remap-path-prefix=$HOME/.cargo/registry/src=/cargo/registry/src"
   cargo build --release --locked --target x86_64-unknown-linux-gnu             # the linux-bundle core
   RUSTFLAGS="$RUSTFLAGS -C link-arg=-Wl,--hash-style=both -C link-arg=-Wl,-z,max-page-size=16384" \
     cargo ndk -t arm64-v8a -P 24 build --release --locked                       # the Android core, NDK 28.2.13676358
   $ANDROID_NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-strip --strip-debug \
     target/aarch64-linux-android/release/libfuzzy_crypto_core.so                # what AGP does before packaging
   sha256sum target/x86_64-unknown-linux-gnu/release/libfuzzy_crypto_core.so \
             target/aarch64-linux-android/release/libfuzzy_crypto_core.so
   ```
   and compare with the `rust-repro-1` artifact's `SHA256SUMS` of the tag run — and directly with the cores
   inside the release: `linux-bundle/lib/libfuzzy_crypto_core.so` and the APK's
   `lib/arm64-v8a/libfuzzy_crypto_core.so` (`unzip` it) are the same bytes. (`-P 24` is Flutter's default
   `minSdkVersion`, which cargokit passes — cargo-ndk alone would default to 21 and link `pthread_atfork`
   instead of `__register_atfork`; the two `link-arg`s are cargokit's Android link flags, which cargo-ndk
   4.1.2 does not add on NDK 28; the `llvm-strip --strip-debug` is the Android Gradle plugin's packaging
   strip, which only rewrites the section-name table.) (Cargo's portable `[profile.release] trim-paths` would replace the
   remap; it is nightly-only on 1.98.1.)
   Known limits, both measured: **the host matters** — rebuilding the Android core from a macOS host with the
   same NDK, cargo-ndk and rustc gives a different binary (§5), so reproduce on a Linux x86_64 host, which is
   what CI uses; and a macOS `.dylib` additionally embeds the linker's `LC_UUID`, which changes with the
   *target directory path* (two builds into different `--target-dir`s differ in the UUID and the ad-hoc
   signature only; same path → identical).
4. **`SHA256SUMS` + attestations per release** (§2, §3), and the Android release built with
   `--split-debug-info`.

**What we do not promise:** the Flutter AOT output (`libapp.so`, the desktop executables, the app
bundles) is not bit-for-bit reproducible today — it embeds build paths and ids
(dart-lang/sdk#52506; F-Droid rebuilds Flutter apps only by pinning the exact absolute build path). The
Rust core *inside* the shipped Linux bundle and the APK **is** the `rust-repro` build: the `attest` job
extracts both and fails the tag run unless their SHA-256 appear in `rust-repro-1/SHA256SUMS` (the Windows
and macOS cores are attested and path-clean but not gated against a rebuild). The measured relation for
each release is recorded in §5.

The measured result for the first attested tag, `v1.0.0-rc.1`, is in §5.

## 5. Measurements per release

### v1.0.0-rc.1
Rust core at this tag (unchanged since the measurement run
<https://github.com/fuzzzy-bot/fuzzy_chat/actions/runs/34719697155>; the tag run re-proves the same values):

| Target | File | SHA-256 (runner 1 = runner 2) |
|---|---|---|
| `x86_64-unknown-linux-gnu` | `libfuzzy_crypto_core.so` | `b13462d86d7ebc7abe435dc7fe1ac0938d1f1fd64a6e9adcf59e57e947ea02f6` |
| `x86_64-unknown-linux-gnu` | `libfuzzy_crypto_core.a` | `985795c287f030744259b05ca6c75088792789c9c33f1170e476f61942f96ea3` |
| `aarch64-linux-android` (API 24) | `libfuzzy_crypto_core.so` | `b8e30d0cfada0e6e55f7b9a37ad960a70fa597918b6b7d126f6523e2d98d6c3a` |
| `aarch64-linux-android` (API 24) | `libfuzzy_crypto_core.a` | `7aa7442eb0caad6688e152af583f09b046c98381d86b13397b4e88d56325a46c` |

- **Linux: the shipped core is the reproducible core.** `linux-bundle/lib/libfuzzy_crypto_core.so`, built by
  cargokit inside `flutter build linux`, is byte-identical to the standalone rebuild above
  (`b13462d8…`), and was already that hash on the previous commit's run — so the attested Linux bundle
  carries a core anyone can rebuild and match.
- **Android: the shipped core is the reproducible core too — established after the tag.** At the tag the
  APK's `lib/arm64-v8a/libfuzzy_crypto_core.so` (`ad625a3a876d1cd3b76d19d368827b0309e12f1fe9f3b28a5f380346d80f2dd3`,
  1,394,568 B) differed from the `rust-repro` rebuild (`b8e30d0c…`, 1,393,664 B) only by a SysV `.hash` section
  (0x340 B) plus its `DT_HASH` entry — cargokit links with `--hash-style=both`, cargo-ndk 4.1.2 does not; `.text`,
  `.rodata`, both relocation tables, `.dynsym`, imports and `.comment` were otherwise equal. With cargokit's link
  flags the rebuild (`626b7041a645beb5317f04c521d227eda5fc97b206508b81d7fa2b84fcb9a85a`, 1,394,576 B) matched the
  APK core in every loaded byte and differed only in the non-loaded section-name table (`.shstrtab` 0xff vs
  0xf4 B, and the section-header offset that follows it): the Android Gradle plugin passes every packaged `.so`
  through `llvm-strip --strip-debug`, which rewrites that table. `llvm-strip --strip-debug` on the rebuild →
  **`ad625a3a…` — byte-identical to the APK core** (verified on run
  <https://github.com/fuzzzy-bot/fuzzy_chat/actions/runs/34721691080>, the first commit after the tag; the
  `rust-repro` job now applies the same strip, and `attest` gates both shipped cores against the rebuild from
  the next tag on).
- **rc.1 evidence caveat.** On the tag run the `rust-repro-compare` step's `diff` was `&&`-chained to an `echo`, which
  exempts it from `set -e` — the step could not have failed on a mismatch. The rc.1 hashes above are therefore
  established by the two `rust-repro-1` / `rust-repro-2` artifacts of the tag run (identical `SHA256SUMS`, `cmp` of the
  Android `.so` = 0 bytes), re-verified by an independent reviewer, not by the gate; the gate is fixed on the commit
  after the tag (`echo` on its own line; mismatch → exit 1 verified with the step script).
- **No runner path in any shipped core**: 0 occurrences of `/home/runner`, `/Users/runner` or `runneradmin`
  in the Android, Linux, Windows and macOS cores of the run; the remapped `/cargo/registry/src` prefix
  appears 88 / 87 / 89 / 334 times respectively (`strings -a`).
- **Host dependence (measured):** the same Android build from a macOS arm64 host (same NDK 28.2.13676358,
  cargo-ndk 4.1.2, rustc 1.98.1, same `RUSTFLAGS` remap) differed from the CI binary in 17,159 bytes
  spread over `.text`/`.rodata`/`.eh_frame`/`.gcc_except_table` at identical section sizes, plus an extra
  `.comment` line from the darwin-hosted NDK clang (`-bolt, -mlgo` build of the same LLVM commit), which is
  what compiles `dart-sys`'s `dart_api_dl.c` — the only C in the crate. Two builds on the same Mac were
  identical. Reproduce on a Linux x86_64 host.
