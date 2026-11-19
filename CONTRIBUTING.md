# Contributing

## Setup

Build and sign Tuck as described in [README.md](README.md). Swift sources live in `Sources/` and regression checks in `Tests/main.swift`. The app uses SwiftUI and AppKit with macOS frameworks.

## Checks

Build the signed app and run the regression executable on macOS:

```bash
./build.sh
bash -n build.sh && bash -n setup-signing.sh
test_dir=$(mktemp -d)
sources=()
for source in Sources/*.swift; do
  if [[ "$source" != Sources/main.swift ]]; then sources+=("$source"); fi
done
swiftc -O -swift-version 5 "${sources[@]}" Tests/main.swift -o "$test_dir/tuck-tests"
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
