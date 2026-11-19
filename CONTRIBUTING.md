# Contributing

## Setup

Build and sign Tuck as described in [README.md](README.md). Swift sources live in `app/Sources/` and regression checks in `app/Tests/main.swift`. The app uses SwiftUI and AppKit with macOS frameworks.

## Checks

Build the signed app and run the regression executable on macOS:

```bash
./scripts/build.sh
bash -n scripts/build.sh && bash -n scripts/setup-signing.sh
bash scripts/test-sparkle-key.sh
test_dir=$(mktemp -d)
sources=()
while IFS= read -r -d '' source; do
  if [[ "${source##*/}" != main.swift ]]; then sources+=("$source"); fi
done < <(find app/Sources -type f -name '*.swift' -print0)
swiftc -O -swift-version 5 "${sources[@]}" app/Tests/main.swift -o "$test_dir/tuck-tests"
"$test_dir/tuck-tests"
```

For behavior involving the live menu bar, verify the affected path with Accessibility and Screen Recording enabled. For sorting changes, check all three sections and relaunch Tuck to confirm that the saved order comes back.

## Style and architecture

- Give every function a documentation comment. Use inline comments for non-obvious logic and descriptive names throughout.
- Keep Accessibility scans and screenshot work off the main thread. Keep AppKit window updates and published UI state on the main actor.
- Keep bundle identity, signing requirements, and saved layout keys compatible across releases. Review impact on existing settings before changing any of them.
- Keep changes focused. Add regression tests for behavior the existing suite does not cover.
- Use synthetic icons and isolated preference domains in tests. Keep builds, local signing files, credentials, and diagnostics out of Git.

## Branches and pull requests

- Start from current `main`. Use one branch per change and name it `<type>/<short-name>`, for example `fix/menu-focus`.
- Use a pull request for changes after repository bootstrap. Describe the reason, user-visible behavior, and checks performed.
- Keep unrelated work intact. Wait for checks and review before merging.

## Commits

Use [Conventional Commits](https://www.conventionalcommits.org/) with a short English imperative subject. Explain the reason in the body when it is unclear from the subject. Keep the configured Git author and committer.

For AI-assisted commits, add these trailers. Replace placeholders with the active session values. If a value is unavailable, write `unknown`.

```text
AI-Model: <current model>
AI-Reasoning-Effort: <current reasoning level>
Co-authored-by: Codex <noreply@openai.com>
```

## Releases

The [Publish Tuck workflow](.github/workflows/release.yml) runs after updates to `main`. It tests the code, builds Tuck for Apple Silicon and Intel, and signs it with a dedicated self-signed certificate. Sparkle signs and verifies `Tuck.zip` and `appcast.xml` before GitHub publishes them together. Version `1.0.N` uses the workflow run number. Use **Run workflow** on `main` to retry setup. No Apple Developer Program membership or notarization credentials are needed.

### One-time signing setup

Use a dedicated release identity. Keep the same certificate and Sparkle key across releases. Changing either can break the existing update path or invalidate macOS privacy permissions. Keep both keys backed up securely.

Create a password-protected `.p12` with `scripts/create-release-identity.sh`. Set `TUCK_SIGNING_P12_PASSWORD` to a strong export password in your shell environment before running the script. Save the fingerprint printed by the script.

```bash
scripts/create-release-identity.sh /path/to/TuckRelease.p12
```

In **GitHub Settings → Secrets and variables → Actions**, add these settings.

| Secret | Value |
| --- | --- |
| `TUCK_SIGNING_P12_BASE64` | Base64-encoded release `.p12` |
| `TUCK_SIGNING_P12_PASSWORD` | Export password for the `.p12` |
| `TUCK_SPARKLE_PRIVATE_KEY` | Sparkle private seed exported below |

| Variable | Value |
| --- | --- |
| `TUCK_SIGNING_CERT_SHA1` | Uppercase certificate fingerprint printed by the identity script |
| `TUCK_SPARKLE_PUBLIC_KEY` | Sparkle public key printed by `generate_keys -p` |

Upload the `.p12` without displaying its encoded contents.

```bash
base64 -i /path/to/TuckRelease.p12 | gh secret set TUCK_SIGNING_P12_BASE64 --repo osmawx/tuck
```

Generate a Sparkle key in your macOS Keychain and read its public key.

```bash
sparkle_dir=$(mktemp -d)
scripts/fetch-sparkle.sh "$sparkle_dir"
"$sparkle_dir/bin/generate_keys" --account tuck-release
"$sparkle_dir/bin/generate_keys" --account tuck-release -p
```

Upload its private key using an authenticated `gh` session.

```bash
(
  set -euo pipefail
  umask 077
  key_dir=$(mktemp -d)
  trap 'rm -rf "$key_dir"' EXIT
  "$sparkle_dir/bin/generate_keys" --account tuck-release -x "$key_dir/sparkle.key"
  gh secret set TUCK_SPARKLE_PRIVATE_KEY --repo osmawx/tuck < "$key_dir/sparkle.key"
)
```
