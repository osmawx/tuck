# Instructions for AI agents

Read [README.md](README.md) and [CONTRIBUTING.md](CONTRIBUTING.md) at the start of each task.

## Session workflow

- Enable Caveman in full mode at the start of each task. Load `skills/caveman/SKILL.md` from the installed skills directory. Use normal prose in source, comments, commit bodies, documentation, and pull requests.
- Enable the installed ECC (Everything Claude Code) workflow at the start of each task. Apply its relevant engineering guidance within the task's scope. If ECC is missing, report that and continue with this file and `CONTRIBUTING.md`.
- Load `skills/feature-sliced-design/SKILL.md` at the start of each task. Use it when changing UI structure or feature boundaries. Use the installed skill directory, such as `~/.agents/skills/`. Apply its responsibility and dependency guidance to SwiftUI where appropriate. Keep Swift code in the existing native target.
- Inspect the current branch, worktree, relevant implementation, and tests. Preserve unrelated changes and reuse existing code.
- For complex changes, write a short plan. Add targeted regression coverage for new or changed behavior. Review the diff and run the relevant checks before committing.

## Native app constraints

- Keep AppKit windows and UI state on the main actor. Run status scans and pixel processing in the background.
- Preserve the original application identity and preference compatibility across upgrades. Keep Always Hidden icons out of the hidden items panel.
- Give every function a documentation comment. Explain non-obvious logic inline. Use descriptive Swift and shell names.
- Keep artifacts, signing material, credentials, and diagnostics out of version control.

## Git

- Follow the branch, review, and Conventional Commits rules in [CONTRIBUTING.md](CONTRIBUTING.md).
- Preserve Git author and committer identities. Record the active model and reasoning level using `AI-Model` and `AI-Reasoning-Effort`. Add `Co-authored-by: Codex <noreply@openai.com>`.
- Push, open pull requests, merge, or change GitHub settings only with the owner's authorization.
