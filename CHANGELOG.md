# Changelog

## 2026-03-10
- Added PulseAudio to the Docker image and container startup so Playwright sessions can route browser audio through an internal null sink.
- Updated `cxhere` to export Pulse/ffmpeg capture defaults for Docker sessions, enabling full audio+video screencast recording without manual per-container setup.
- Hardened PulseAudio startup to wait for a reachable server socket and auto-detect the monitor source before launching Codex, avoiding intermittent `pactl` connection failures during container boot.
- Switched PulseAudio health checks from `pulseaudio --check` to `pactl`, since the former can report failure even when the server is reachable in this container setup.
- Moved PulseAudio home/config/cookie paths under `/tmp` so Codex shell commands do not hit permission errors under `/home/codex` when they need to inspect or bootstrap audio.
- Updated `cxhere` to replace an already-running worktree container when `codex-cli:local` has been rebuilt, so existing worktrees pick up the latest image instead of reusing stale runtime state.

## 2026-03-09
- Added R to the Docker image from CRAN's official Ubuntu `noble-cran40` repository and installed `r-base` plus `r-base-dev`.

## 2026-03-03
- Fixed `cxclose` target resolution so it can close worktrees by directory name/path even when the tracked branch name differs.
- Updated `cxclose` to delete the resolved tracked branch (when present) instead of assuming the user argument is the branch name.
- Added ambiguity handling in `cxclose` to fail with matching candidates when an argument matches multiple codex worktrees.

## 2026-02-24
- Fixed `cxclose` when run from inside a tracked worktree:
  - Resolve the main repo root via `git rev-parse --git-common-dir` instead of the current worktree top-level path.
  - Run `git worktree remove` and `git branch -d` with `-C <main-repo-root>` for consistent behavior.

## 2026-02-23
- Hardened `cxclose` error behavior:
  - Run in a subshell to avoid terminating the caller shell on failure.
  - Return a clear error when executed outside a git repository.
  - Return a clear error when the target is not a valid tracked codex worktree for the specified branch/path.
- Updated `cxlist` to print `no active codex worktrees.` when no managed worktrees are active.
- Added shell completion for `cxclose`:
  - Zsh completion via `compdef`.
  - Bash fallback completion via `complete -F`.
