# cxhere

`cxhere` runs Codex CLI inside a Linux container and gives each session its own git worktree, so you can run multiple Codex sessions against the same repo without sharing a checkout.

## Runtime Model

- `cxhere` and `./scripts/build-local.sh` support Apple `container`, Docker, and explicit local mode.
- `auto` prefers a ready Apple `container` runtime on Apple silicon running macOS 26+, otherwise a ready Docker daemon.
- Docker and Apple `container` use separate image stores. Build both with `CX_BUILD_RUNTIME=all` if you want instant fallback between them.
- Apple `container` sessions default to a lighter `1280x720x24` headed display for more reliable Playwright + ffmpeg recording. Docker keeps `1920x1080x24`.

## Prerequisites

- `git`
- Docker Desktop or Apple `container`
- `codex` in `PATH` if you want `CXHERE_RUNTIME=local`
- For Apple `container`: Apple silicon, macOS 26+, `container` installed, and `container system start`
- Optional host config reused by sessions: `gh`, `~/.ssh`, `SSH_AUTH_SOCK`, `ngrok`

## Install

The intended end-user path is a per-user install under `~/.cxhere` backed by the latest GitHub release.

```bash
curl -fsSL https://raw.githubusercontent.com/moorage/cxhere/main/install.sh | bash
```

or:

```bash
wget -qO- https://raw.githubusercontent.com/moorage/cxhere/main/install.sh | bash
```

`install.sh` does the following:

- On macOS 26+, checks the latest `apple/container` GitHub release against `container --version`, and offers to open the release page if the host is missing or behind.
- Downloads the latest `moorage/cxhere` release into `~/.cxhere/releases/<version>` and repoints `~/.cxhere/current`.
- Offers to add `source "$HOME/.cxhere/current/scripts/codex-worktrees.zsh"` to the active shell RC file.
- If the installer itself was sourced, re-sources the freshly installed commands into the current shell.
- If no ready runtime has a local `codex-cli:local` image yet, builds it immediately. If one already exists, offers to rebuild it.

Note: this repository currently needs a published GitHub release for `install.sh` and `cxupdate` to fetch from. Until a first tagged release exists, the release-backed installer path will fail intentionally instead of silently falling back to an arbitrary checkout.

## Build The Local Image

The image tag is `codex-cli:local`.

```bash
./scripts/build-local.sh
```

Typical build flows:

```bash
container system start
CX_BUILD_RUNTIME=container ./scripts/build-local.sh
CX_BUILD_RUNTIME=docker ./scripts/build-local.sh
CX_BUILD_RUNTIME=all ./scripts/build-local.sh
```

### Build Flags

| Variable | Default | Applies to | Effect |
| --- | --- | --- | --- |
| `CX_BUILD_RUNTIME` | `auto` | `./scripts/build-local.sh` | Selects `container`, `docker`, or `all`. `auto` prefers a ready Apple runtime, then a ready Docker daemon. |
| `CX_BUILD_CPUS` | unset | Apple `container` builds | Passed through as `container build --cpus`. |
| `CX_BUILD_MEMORY` | unset | Apple `container` builds | Passed through as `container build --memory`. |
| `CX_BUILD_PLATFORM` | unset | Apple `container` builds | Passed through as `container build --platform`. Use `linux/amd64` when you need Google Chrome on Apple silicon. |

## Shell Setup

If you are working from a checkout instead of a `~/.cxhere` install, source the helper script from your shell config:

```bash
source /path/to/cxhere/scripts/codex-worktrees.zsh
```

Reload the shell config you actually use:

```bash
source ~/.zshrc
# or
source ~/.bashrc
```

Optional setup:

```bash
mkdir -p ~/.codex/rules
cp /path/to/cxhere/default.example.rules ~/.codex/rules/default.rules
```

```bash
mkdir -p ~/.codex
cat /path/to/cxhere/config.example.toml >> ~/.codex/config.toml
```

## Commands

| Command | What it does |
| --- | --- |
| `cxhere <worktree-name>` | Create or reuse a dedicated git worktree and launch Codex there. |
| `cxhere <worktree-name> <session-id>` | Reuse the worktree and resume an existing Codex chat. |
| `cxclose <worktree-name>` | Remove a clean worktree and delete its branch. |
| `cxkill <worktree-name>` | Stop running container session(s) for that worktree without removing the worktree. |
| `cxlist` | List managed Codex worktrees and show whether each one is `ok`, `locked`, or `prunable`. |
| `cxupdate` | Stage the latest GitHub release under `~/.cxhere`, swap `current`, and re-source the updated commands into the current shell. |
| `cxharness` | Import the live `moorage/new-codex-project-harness` repo into the current directory, prompting to run `git init` first when needed, then prompting before copy, before overwriting any existing file, and finally before creating a `cxharness` git commit for the imported files. |

Typical usage:

```bash
cxhere mpm/my-feature
CXHERE_RUNTIME=container cxhere mpm/my-feature
CXHERE_RUNTIME=docker cxhere mpm/my-feature
CXHERE_RUNTIME=local cxhere mpm/my-feature
CXHERE_NO_DOCKER=1 cxhere mpm/my-feature
```

Publish loopback ports from the session back to the host:

```bash
cxhere -p 5173 mpm/my-feature
cxhere -p 5173:5713 mpm/my-feature
cxhere -p 5173 -p 9229 mpm/my-feature
```

`-p` / `--port` only applies to containerized sessions and always binds `127.0.0.1` on the host. `-p 5173` maps host `127.0.0.1:5173` to container port `5173`; `-p 5173:5713` maps host `127.0.0.1:5173` to container port `5713`. Repeat the flag to bind multiple ports.

With shell completion enabled, `cxhere`, `cxclose`, and `cxkill` autocomplete known Codex worktree branch names.

`cxharness` downloads the current contents of `moorage/new-codex-project-harness`, recreates its directory/file structure in the current directory, and asks before overwriting any existing file. If the current directory is not already inside a Git repository, it prompts to run `git init` before importing the harness. After the import finishes, it offers to create a `cxharness` commit containing only the downloaded harness files, defaulting that last prompt to yes.

## Updates

- Every `cxhere`, `cxclose`, `cxkill`, `cxlist`, `cxupdate`, and `cxharness` invocation kicks off a non-blocking release check in the background.
- The latest discovered release is cached under `~/.cxhere/state/latest-release`.
- When the cached version is newer than the sourced version, commands print an update notice and tell the user to run `cxupdate`.
- On supported Apple silicon Macs, the same command prelude also caches the latest `apple/container` release under `~/.cxhere/state/latest-apple-container-release` and prints a non-interactive notice when the host runtime is missing or behind.
- If the shell still has an older sourced copy after `~/.cxhere/current` moved forward, commands warn once and print the `source "$HOME/.cxhere/current/scripts/codex-worktrees.zsh"` fixup command.

## Session Flags

### Runtime And Integration Flags

| Variable | Default | Applies to | Effect |
| --- | --- | --- | --- |
| `CXHERE_RUNTIME` | `auto` | `cxhere`, `cxkill` | Selects `container`, `docker`, or `local`. `auto` prefers a ready Apple runtime, then a ready Docker daemon. |
| `CXHERE_NO_DOCKER` | unset | `cxhere`, `cxkill` | Legacy alias for local-mode runtime selection. |
| `CXHERE_GH` | `1` | Containerized sessions | Reuses host GitHub auth. Docker mounts `~/.config/gh`; Apple `container` copies it into a writable session-local config and bootstraps it from `GH_TOKEN`, `GITHUB_TOKEN`, or `gh auth token` when available. |
| `GH_TOKEN` / `GITHUB_TOKEN` | unset | Containerized sessions | Preferred GitHub token source forwarded into the session before falling back to `gh auth token`. |
| `CXHERE_SSH` | `1` | Containerized sessions | Mounts host `~/.ssh` read-only into the session. |
| `CXHERE_SSH_AGENT` | `1` | Containerized sessions | Forwards the host ssh-agent when the host exposes a socket. Docker uses a bind-mounted socket; Apple `container` uses native `--ssh` forwarding. |
| `SSH_AUTH_SOCK` | host-dependent | Containerized sessions | Used as the host-side source socket for agent forwarding when `CXHERE_SSH_AGENT=1`. |
| `CXHERE_NGROK` | `1` | Containerized sessions | Mounts the detected host ngrok config into the session. |
| `CXHERE_NGROK_CONFIG_DIR` | auto-detect | Containerized sessions | Overrides ngrok config discovery. Checked paths are `~/.config/ngrok`, `~/Library/Application Support/ngrok`, and `~/.ngrok2`. |

### Runtime Tuning Flags

| Variable | Default | Applies to | Effect |
| --- | --- | --- | --- |
| `CXHERE_CONTAINER_CPUS` | `4` | Apple `container` sessions | Sets the VM CPU allocation. |
| `CXHERE_CONTAINER_MEMORY` | `4G` | Apple `container` sessions | Sets the VM memory allocation. |
| `CXHERE_CONTAINER_PLATFORM` | unset | Apple `container` sessions | Passed through as `container run --platform`. Set `linux/amd64` to match an amd64 image build. |
| `CXHERE_CONTAINER_ROSETTA` | auto for `linux/amd64` | Apple `container` sessions | When true, adds `container run --rosetta`. Auto-enabled when `CXHERE_CONTAINER_PLATFORM=linux/amd64`. |
| `CXHERE_CONTAINER_XVFB_SCREEN` | `1280x720x24` | Apple `container` sessions | Default headed display size when `XVFB_SCREEN` is not set. |
| `CXHERE_CONTAINER_REPO_ROOT_MODE` | `rw` | Apple `container` sessions | Mount mode for the host repo root at its absolute path. Leave this at `rw` for Git worktree compatibility. |
| `XVFB_SCREEN` | runtime-specific | Containerized sessions | Overrides the display size directly for one run. Docker defaults to `1920x1080x24`; Apple `container` defaults to `1280x720x24`. |
| `CXHERE_PIDS_LIMIT` | `2048` | Docker sessions | Passed as Docker `--pids-limit`. |
| `CXHERE_TMPFS_TMP_SIZE` | `2g` | Docker sessions | Size of the Docker `/tmp` tmpfs mount. |
| `CXHERE_TMPFS_HOME_SIZE` | `2g` | Docker sessions | Size of the Docker `/home/codex` tmpfs mount. |
| `CXHERE_SHM_SIZE` | `1g` | Docker sessions | Passed as Docker `--shm-size`. |
| `CXHERE_ULIMIT_NPROC` | `8192` | Docker sessions | Passed as Docker `--ulimit nproc`. |
| `CXHERE_ULIMIT_NOFILE` | `1048576` | Docker sessions | Passed as Docker `--ulimit nofile`. |

### Display And Capture Flags

| Variable | Default | Applies to | Effect |
| --- | --- | --- | --- |
| `HARNESS_CAPTURE_WITH_FFMPEG` | `1` | Containerized sessions | Keeps ffmpeg capture enabled by default. |
| `HARNESS_CAPTURE_AUDIO_FORMAT` | `pulse` | Containerized sessions | Keeps PulseAudio as the default audio capture source. |
| `CODEX_DISABLE_PULSEAUDIO` | unset | Session entrypoint | Skips internal PulseAudio startup. |
| `CODEX_DISABLE_XVFB` | unset | Session entrypoint | Skips internal Xvfb startup. |

## How Sessions Behave

- Worktrees live next to the repo in a sibling directory named `<repo-name>-worktrees/<worktree-name>`, with `/` replaced by `__` in the directory name.
- `cxhere` reuses an existing branch if the branch already exists and no worktree exists for it.
- If a worktree already exists, `cxhere` looks for a running session for that worktree in the selected runtime. New sessions are discovered by stable labels; Docker also falls back to bind-mount discovery so older unlabeled sessions are still found.
- If exactly one session already exists on the current `codex-cli:local` image, `cxhere` exits cleanly instead of starting a duplicate session.
- If exactly one session exists on an older `codex-cli:local` image, `cxhere` replaces it so the worktree picks up the rebuilt image.
- If the same worktree is already running in the other runtime, `cxhere` stops and tells you to either reuse that runtime or run `cxkill`.
- If you explicitly request a runtime and it is unavailable, the command exits with that runtime's error instead of silently switching.
- `cxkill` stops sessions for one worktree without deleting the worktree. With `CXHERE_RUNTIME=auto`, it checks all ready runtimes.
- `cxclose` refuses to remove a locked worktree, a dirty worktree, or a worktree with Git lock files still present.

## Files, Mounts, And Prompts

- Containerized sessions mount the worktree at `/workspace`.
- Docker sessions also mount the main repo path read-only and `<repo>/.git` read-write so git worktree metadata still works.
- Apple `container` sessions instead mount the full main repo path read-write at its host absolute path so Git worktree metadata resolves without relying on nested bind mounts.
- Docker sessions forward the host ssh-agent by bind-mounting the socket. Apple `container` sessions use the runtime's native `--ssh` forwarding instead.
- `~/.gitconfig` is exported into a session-local readable copy for containerized sessions, and `~/.codex` is mounted into the session by default.
- Root-level `.env*` files from the main repo are copied into the worktree when it is created, and a root-level `.env/` directory is copied recursively when present. If present, `.env.cx.local` is passed to the session as an env file.
- `cxhere` offers to create `docs/PLANS.md` from the project template when it is missing.
- `cxhere` offers to create `$CODEX_HOME/AGENTS.md` from the global template when it is missing.
- `cxhere` ensures your Codex config has a trusted `/workspace` project entry and prompts before writing it.
- If `.pw-browsers` is under `/workspace`, `cxhere` offers to add it to the repo `.gitignore`.
- On Docker runs, `cxhere` may also offer to copy `seccomp_profile.example.json` to `seccomp_profile.json` and add it to the repo `.gitignore`.

## Image Contents

- Base image: `ubuntu:25.10`
- Node.js: `25.8.1`
- Included tooling: Playwright Linux dependencies, `xvfb`, PulseAudio, `ffmpeg`, `xdotool`, `ngrok`, and R. Google Chrome is included on `amd64` builds only.
- Browser cache path: `PLAYWRIGHT_BROWSERS_PATH=/workspace/.pw-browsers`
- Entry point behavior: starts PulseAudio with a null sink, exposes the monitor source for ffmpeg audio capture, starts Xvfb, then execs `codex`

Install browsers per project when needed:

```bash
npx playwright install chromium
```

If you want the migration research and validation notes behind the current runtime behavior, see `docs/apple-container-migration.execplan.md`.

## Chrome Status

- `amd64` image builds install `google-chrome-stable`.
- Native `arm64` image builds do not currently include a system Chrome or Chromium package.
- On Apple silicon, use `CX_BUILD_RUNTIME=container CX_BUILD_PLATFORM=linux/amd64 ./scripts/build-local.sh` if you specifically need Google Chrome in the image.
- To run that `amd64` image through `cxhere`, set `CXHERE_RUNTIME=container` and `CXHERE_CONTAINER_PLATFORM=linux/amd64`. Rosetta is enabled automatically for that path.
