# Changelog

## 2026-03-16
- Updated `cxhere` to forward a GitHub token into Docker sessions by preferring host `GH_TOKEN` or `GITHUB_TOKEN` and falling back to `gh auth token`, so containerized `gh` can reuse host auth even when the host stores credentials in the macOS keychain.

## 2026-03-12
- Updated `cxhere` to mount host `~/.ssh` read-only into Docker sessions by default so Git-over-SSH can reuse host keys and `known_hosts`.
- Updated `cxhere` to forward `SSH_AUTH_SOCK` into Docker sessions when the host exposes an ssh-agent, so passphrase-protected keys can still authenticate without copying private key material.
- Added `CXHERE_SSH=0` and `CXHERE_SSH_AGENT=0` escape hatches to disable the SSH config mount or agent forwarding per session.

## 2026-03-11
- Added `ngrok` to the Docker image so it is available in Codex Docker sessions without extra per-container setup.
- Updated `cxhere` to mount an existing host ngrok config directory into `/tmp/ngrok-home/.config/ngrok`, and added an `ngrok` wrapper that uses that path as the default config file so host auth and tunnel definitions persist across runs.

## 2026-03-10
- Added PulseAudio to the Docker image and container startup so Playwright sessions can route browser audio through an internal null sink.
- Updated `cxhere` to export Pulse/ffmpeg capture defaults for Docker sessions, enabling full audio+video screencast recording without manual per-container setup.
- Hardened PulseAudio startup to wait for a reachable server socket and auto-detect the monitor source before launching Codex, avoiding intermittent `pactl` connection failures during container boot.
- Switched PulseAudio health checks from `pulseaudio --check` to `pactl`, since the former can report failure even when the server is reachable in this container setup.
- Moved PulseAudio home/config/cookie paths under `/tmp` so Codex shell commands do not hit permission errors under `/home/codex` when they need to inspect or bootstrap audio.
- Updated `cxhere` to replace an already-running worktree container when `codex-cli:local` has been rebuilt, so existing worktrees pick up the latest image instead of reusing stale runtime state.
- Changed PulseAudio startup to run under entrypoint supervision instead of PulseAudio's own daemonization path, which avoids generic container startup failures and preserves detailed logs under `/tmp/pulseaudio.log`.

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
