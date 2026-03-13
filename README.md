# sandbox-docker

This repo is what I currently use to sandbox my development environment for Codex CLI, shared in the spirit of openness. It runs Codex in a Docker container and mounts your repo and default Codex config.  It has helper flows that creates/cleans a dedicated git worktree and launches the container against it, to enable isolated parallel sessions.

## Build the Docker image

```bash
./scripts/build-local.sh
```

## Set up the shell shortcuts

Add this to your shell config:

```bash
source /path/to/sandbox-docker/scripts/codex-worktrees.zsh
```

Reload your shell:

```bash
source ~/.bashrc
source ~/.zshrc
```

Notes:

- For Bash, use `~/.bashrc` (or `~/.bash_profile` on macOS if that is what your shell reads).
- For Zsh, use `~/.zshrc`.

Optional: copy the default rules template:

```bash
mkdir -p ~/.codex/rules
cp /path/to/sandbox-docker/default.example.rules ~/.codex/rules/default.rules
```

Optional: integrate the example config into your local Codex config:

```bash
mkdir -p ~/.codex
cat /path/to/sandbox-docker/config.example.toml >> ~/.codex/config.toml
```

## Use `cxhere`, `cxclose`, and `cxlist`

Start a Codex session in a dedicated git worktree + branch:

```bash
cxhere mpm/my-feature
```

Resume a Codex chat by passing the session ID as the second argument:

```bash
cxhere mpm/my-feature <session-id>
```

Skip Docker and run the local `codex` CLI (still uses worktrees):

```bash
CXHERE_NO_DOCKER=1 cxhere mpm/my-feature
```

By default `cxhere` mounts your GitHub CLI config from `~/.config/gh` so `gh` can push and open PRs.
Disable it with:

```bash
CXHERE_GH=0 cxhere mpm/my-feature
```

By default `cxhere` also mounts your host `~/.ssh` into Docker sessions as read-only at the container's effective home, and forwards `SSH_AUTH_SOCK` when present so Git-over-SSH works with agent-backed keys. Disable either behavior with:

```bash
CXHERE_SSH=0 cxhere mpm/my-feature
CXHERE_SSH_AGENT=0 cxhere mpm/my-feature
```

By default `cxhere` also looks for an existing host ngrok config and mounts it into Docker sessions under `/tmp/ngrok-home` so `ngrok` reuses your saved authtoken and tunnel config. Disable or override that detection with:

```bash
CXHERE_NGROK=0 cxhere mpm/my-feature
CXHERE_NGROK_CONFIG_DIR="$HOME/Library/Application Support/ngrok" cxhere mpm/my-feature
```

Cleanup when you're done:

```bash
cxclose mpm/my-feature
```

List active Codex worktrees and flag anything prunable/stale:

```bash
cxlist
```

## Implementation and behavior notes

`cxhere` runs Codex in a dedicated git worktree and branch. You pass a worktree name, which is also used as the
branch name. This keeps multiple Codex sessions isolated and lets you run them concurrently in the same repo.
Slashes in the name are supported (for example `mpm/my-feature`) and are only sanitized for the worktree
directory on disk. Worktrees are created next to the repo in a sibling directory named
`<PROJECT-DIR-NAME>-worktrees/<WORKTREENAME>`.

Example paths:

```text
/path/to/sandbox-docker
/path/to/sandbox-docker-worktrees/mpm__my-feature
```

### Behavior notes:

- If the branch already exists and no worktree exists for it, `cxhere` will reuse the branch and create a worktree.
- If the target worktree directory exists on disk but is not registered with git, `cxhere` will stop and print guidance.
- If a worktree already exists, `cxhere` checks for running containers with a bind mount to that worktree (Docker mode only):
  - Exactly one container on the current `codex-cli:local` image: print a message and exit 0.
  - Exactly one container on an older `codex-cli:local` image: stop it and launch a fresh container from the rebuilt image.
  - More than one: print a message and exit non-zero.
  - None: launch Docker with the existing worktree.
- If `CXHERE_NO_DOCKER=1`, container checks are skipped and `codex` is run directly on the worktree.
- After creating or reusing a worktree, `cxhere` checks for `.agent/PLANS.md` and offers to create it from the project template if missing.
- Before launching Docker, `cxhere` checks for `$CODEX_HOME/AGENTS.md` and offers to create it from the global template if missing.
- In Docker mode, `cxhere` mounts the main repo at its original absolute path as read-only, and mounts only `<repo>/.git` read-write. This lets git worktree metadata function while preventing writes to the main non-worktree files.
- In Docker mode, `cxhere` mounts host `~/.ssh` read-only into `/home/codex/.ssh` by default, and forwards `SSH_AUTH_SOCK` to `/tmp/ssh-agent.sock` when the host exposes an agent socket.
- In Docker mode, `cxhere` mounts the first matching host ngrok config directory from `CXHERE_NGROK_CONFIG_DIR`, `~/.config/ngrok`, `~/Library/Application Support/ngrok`, or `~/.ngrok2` into `/tmp/ngrok-home/.config/ngrok`, and the image's `ngrok` wrapper uses that path as its default config file.
- The Docker image includes `xvfb-run`, so Playwright can launch headless browsers via `xvfb-run` if needed.
- The Docker image includes the `ngrok` CLI.
- The Docker image now boots an internal PulseAudio server with a null sink, keeps its runtime/config state under `/tmp`, waits for it to become reachable, and exports `PULSE_SERVER`, `HARNESS_CAPTURE_WITH_FFMPEG=1`, and `HARNESS_CAPTURE_AUDIO_FORMAT=pulse` so ffmpeg-based Playwright screencasts can include browser audio by default.
- If Docker is not running or the daemon is unreachable, `cxhere` will surface the Docker error output and exit non-zero.
