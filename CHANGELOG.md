# Changelog

## 2026-04-17
- Added a cached Apple `container` freshness check to the normal `cxhere` command prelude on supported Apple silicon Macs, so `cxhere`, `cxkill`, `cxlist`, `cxclose`, `cxupdate`, and `cxharness` now warn when the host runtime is missing or behind without prompting interactively.
- Added shell coverage for the Apple `container` runtime notice path, including both outdated and missing-install scenarios.
- Fixed containerized Git startup by exporting the host global Git config into a session-local readable file before launch, so Apple `container` Codex sessions can read `user.name`, `user.email`, aliases, and other global config even when the host `~/.gitconfig` is `0600`.
- Changed the version comparison helpers to numeric `test` operators so `cxhere` update checks no longer depend on `[[ ... > ... ]]` parsing quirks in caller shells.
- Added shell regressions covering flattened Git config export, including values from relative include files while omitting `include.path` directives from the staged copy.

## 2026-04-05
- Fixed shell compatibility in the launcher by switching version comparison helpers to `[[ ... > ... ]]` / `[[ ... < ... ]]`, which avoids `zsh` parse errors during `cxhere`, `cxkill`, and related commands.
- Fixed the `bash` `nullglob` restore path in `cxhere` so `set -e` shells no longer exit early when `nullglob` starts unset.
- Added regression tests covering version comparison behavior in both `bash` and `zsh`, plus the `bash` `nullglob` restore flow.

## 2026-04-03
- Added `cxharness`, which downloads the live `moorage/new-codex-project-harness` repo into the current directory after confirmation, creates any missing directories, and prompts before overwriting existing files.
- Added a standalone `install.sh` bootstrapper for `~/.cxhere` installs that checks Apple `container` release freshness on macOS 26+, installs the latest `cxhere` GitHub release under `~/.cxhere/current`, offers to wire the shell RC file, and builds `codex-cli:local` when needed.
- Renamed the project-facing package/repo references from `sandbox-docker` to `cxhere`, including installer URLs, GitHub release defaults, and runtime container labels.
- Added release-aware `cxupdate` plus background release checks for `cxhere`, `cxclose`, `cxkill`, and `cxlist`, so commands can cache the latest available version without blocking and prompt the user to update when a newer release is available.
- Added version tracking via `VERSION` and stale-source detection so commands can tell when the shell has older sourced functions than the version currently pointed to by `~/.cxhere/current`.
- Added `xdotool` to the image and made browser installation architecture-aware so `google-chrome-stable` is installed only on `amd64` builds while native `arm64` builds skip a system browser.
- Added `CX_BUILD_PLATFORM` to Apple `container` builds plus `CXHERE_CONTAINER_PLATFORM` and `CXHERE_CONTAINER_ROSETTA` to Apple `container` sessions, so Apple silicon hosts can build and run `linux/amd64` images when Chrome is required.
- Updated `README.md` to document the new platform flags and clarify that Google Chrome is only included on `amd64` builds.

## 2026-03-27
- Fixed `cxkill`'s timeout helper to run Apple `container` CLI calls in their own session and kill the whole process group on timeout, so wedged helper subprocesses do not survive and keep the shutdown fallback loop stuck.
- Added a last-resort Apple `container` fallback that kills the per-container launchd runtime job when `container stop`, `container kill`, and `container delete --force` all wedge on the same session.
- Added `tests/test_cx_runtime_lib.sh` to cover the regression where a timed-out command leaves a child process behind.

## 2026-03-25
- Hardened Apple `container` shutdown in `cxkill` by replacing the direct `container delete --force` path with a bounded fallback chain (`stop` -> `kill` -> `delete --force`), so a wedged container CLI no longer hangs the caller's shell indefinitely.

## 2026-03-23
- Added a `gh` wrapper in the image so Apple `container` sessions keep resolving the session-local GitHub auth dir even when Codex runs `gh` in a stripped-down environment, which makes `gh auth status` work reliably after launch or reuse.
- Updated Apple `container` sessions to copy the host `gh` config into a writable session-local config dir and materialize the host token there before Codex starts, so `gh auth status` still works even when the host stores credentials in the macOS keychain and later subprocesses do not inherit `GH_TOKEN`.
- Updated `cxhere` to mount host `~/.gitconfig` read-only at `/tmp/pulse-home/.gitconfig` and set `GIT_CONFIG_GLOBAL` to that path in both Docker and Apple `container` sessions, which keeps Git's global config isolated from `/home/codex` permission quirks while still preventing in-container edits to the host config file.
- Updated `cxhere` to mount host `~/.ssh` into both `/tmp/pulse-home/.ssh` and `/home/codex/.ssh` inside containerized sessions, which keeps the tmp-based home layout intact while letting OpenSSH and Git reliably pick up host keys, config, and `known_hosts` in Apple `container` mode.
- Updated `cxhere` to prefer ngrok config directories that actually contain `ngrok.yml`, and to replace reused containers whose launch-config fingerprint no longer matches the current host integration mounts (including `ngrok`, `gh`, and SSH), so stale sessions do not silently miss newly available host config.

## 2026-03-20
- Switched Apple `container` sessions from a raw `SSH_AUTH_SOCK` bind mount to native `container run --ssh` forwarding, which keeps the host ssh-agent usable as the non-root `codex` user for Git-over-SSH operations like pushing to GitHub.
- Changed Apple `container` sessions to mount the full host repo root at its recorded absolute path instead of relying on a read-only repo mount plus nested `.git` bind mount, which restores Git worktree metadata resolution inside Apple-native containers.
- Rebuilt `Dockerfile` on top of baseline `ubuntu:25.10` instead of `mcr.microsoft.com/playwright`, pinned Node.js to `25.8.1`, reconciled the Ubuntu 25.10 package renames needed for Playwright support, and validated the image under Apple's `container` runtime.
- Set `PLAYWRIGHT_BROWSERS_PATH=/workspace/.pw-browsers` in the image so Playwright browser binaries stay project-local instead of being baked into the shared container image.
- Switched `r-base` and `r-base-dev` to the Ubuntu 25.10 archive because CRAN does not currently publish a `questing-cran40` apt repository.
- Validated headed Playwright plus ffmpeg video and audio+video capture on the Ubuntu 25.10 image under both Apple `container` and Docker Desktop.
- Added `docs/apple-container-migration.execplan.md` to capture the `apple/container` migration work, runtime detection, validation plan, and Docker fallback strategy.
- Added `scripts/cx-runtime-lib.sh` and rewired `scripts/build-local.sh` plus `scripts/codex-worktrees.zsh` around `CX_BUILD_RUNTIME=auto|container|docker|all` and `CXHERE_RUNTIME=auto|container|docker|local`.
- Changed runtime auto-detection to prefer a ready Apple `container` runtime on supported Macs, fall back to a ready Docker daemon when needed, and keep `CXHERE_NO_DOCKER=1` as a legacy alias for local mode.
- Updated `cxhere` and `cxkill` to find worktree sessions by stable runtime-neutral labels across both engines, while preserving Docker bind-mount discovery for older unlabeled sessions.
- Tuned Apple `container` launches for more reliable default recording by lowering the default `XVFB_SCREEN` to `1280x720x24` on that runtime and exposing `CXHERE_CONTAINER_CPUS`, `CXHERE_CONTAINER_MEMORY`, and `CXHERE_CONTAINER_XVFB_SCREEN` for overrides.
- Rewrote `README.md` around the current Apple `container` plus Docker fallback workflow, removed stale Docker-only guidance, and consolidated the usage env vars into tables.

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
