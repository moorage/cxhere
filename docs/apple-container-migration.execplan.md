# Migrate Codex Sandbox Runtime to `apple/container` with Docker Fallback

This ExecPlan is a living document. The sections `Progress`, `Surprises & Discoveries`, `Decision Log`, and `Outcomes & Retrospective` must be kept up to date as work proceeds.

This repository does not currently have a checked-in `docs/PLANS.md`. Maintain this document as the authoritative execution plan for the `apple/container` migration until such a file exists.

## Purpose / Big Picture

After this change, an Apple silicon Mac running macOS 26 can start Codex worktree sessions with Apple's `container` runtime instead of Docker Desktop, while still being able to fall back to Docker when the Apple runtime is unavailable or a project needs the older path. The observable result is that `cxhere` chooses the right container engine automatically, `./scripts/build-local.sh` can build the same image for the selected engine, and Playwright-based work inside the sandbox still has a working Linux display, PulseAudio, and ffmpeg capture path.

This plan also preserves a safe escape hatch. A user who already relies on Docker can set one environment variable and continue using the old behavior. A user on a non-Apple-silicon host or an older macOS release should not be pushed onto a runtime that cannot work there.

## Progress

- [x] (2026-03-20 20:22Z) Read the repository entry points (`README.md`, `Dockerfile`, `scripts/build-local.sh`, `scripts/codex-entrypoint.sh`, `scripts/codex-worktrees.zsh`) and identified every Docker-specific integration point that the runtime migration touches.
- [x] (2026-03-20 20:22Z) Researched released `apple/container` behavior and current command surface using the upstream README, tutorial, how-to, command reference, and technical overview.
- [x] (2026-03-20 20:22Z) Rebuilt `Dockerfile` on Ubuntu `25.10`, pinned Node.js to `25.8.1`, and kept the explicit Playwright/Xvfb/PulseAudio/ffmpeg runtime surface, with package selection still derived from the current Ubuntu 24.04 arm64 Playwright dependency map until upstream publishes a 25.x-specific one.
- [x] (2026-03-20) Replaced the Docker-only build and run paths in `scripts/build-local.sh` and `scripts/codex-worktrees.zsh` with runtime selection that can use either `container` or Docker, including runtime-neutral labels for worktree session discovery.
- [x] (2026-03-20 23:58Z) Validated the rebuilt image under both Apple `container` and Docker Desktop, including headed Playwright launch under `Xvfb` plus non-empty screenshot, video-only ffmpeg capture, and audio+video ffmpeg capture artifacts on both runtimes.
- [x] (2026-03-20) Updated the README command examples and runtime notes so the default path, requirements, Apple-specific resource knobs, and Docker fallback behavior are unambiguous.
- [x] (2026-03-20) Tuned Apple `container` defaults to use a lighter `1280x720x24` `XVFB_SCREEN` plus explicit CPU and memory knobs so headed Playwright recording is more reliable out of the box on Apple silicon.

## Surprises & Discoveries

- Observation: `apple/container` is not a generic Docker CLI replacement. It runs each container in its own lightweight virtual machine, not inside one shared Linux VM.
  Evidence: Upstream technical overview states that `container` runs "a lightweight VM for each container" and exposes different management commands than Docker.

- Observation: The installed host already matches the intended migration target.
  Evidence: `sw_vers` reports macOS `26.3.1`, `container --version` reports `container CLI version 0.10.0`, and the machine is Apple silicon.

- Observation: The released README for `container` says support is macOS 26 only, while the current `BUILDING.md` on `main` says macOS 15 minimum and macOS 26 recommended.
  Evidence: Upstream `README.md` at release `0.4.1` says "`container` is supported on macOS 26"; upstream `BUILDING.md` on `main` says "macOS 15 minimum, macOS 26 recommended."

- Observation: `container` supports most of the mounts, labels, env-file, `--init`, `--read-only`, `--tmpfs`, CPU, memory, and port publish features needed here, but it does not expose Docker-only flags like `--ipc=host`, `--security-opt`, `--cap-drop`, `--shm-size`, or `--ulimit`.
  Evidence: Upstream command reference documents `container run` flags and omits the Docker-only flags used today in `scripts/codex-worktrees.zsh`.

- Observation: Docker and `container` do not share an image store.
  Evidence: Docker uses the Docker daemon image store, while `container build` produces images in the `container image` store with its own `container image inspect/list/delete` commands.

- Observation: The current sandbox blocked `container system status` and `container system version` with "Operation not permitted" under the CLI sandbox even though the binary is installed.
  Evidence: Local probe commands failed until escalation would be granted, which means final validation must be run with escalated permissions.

- Observation: The safest Linux base for Playwright on Apple silicon is Ubuntu 24.04, not Alpine.
  Evidence: Playwright's official Docker docs point to the Noble image and say Alpine or other `musl`-based distributions are unsupported because Firefox and WebKit are built against `glibc`.

- Observation: Playwright does not currently publish a dedicated Ubuntu 25.x dependency map.
  Evidence: The upstream docs still point to Ubuntu 24.04 Noble images, and `nativeDeps.ts` includes `ubuntu24.04-arm64` but not an Ubuntu 25.x entry.

- Observation: Ubuntu 25.10 renames at least a few Noble-era Playwright support packages.
  Evidence: The first 25.10 validation build failed until `libavcodec60`, `libicu74`, and `libxml2` were updated to `libavcodec61`, `libicu76`, and `libxml2-16`.

- Observation: CRAN does not currently publish an Ubuntu repo for Questing.
  Evidence: `https://cloud.r-project.org/bin/linux/ubuntu questing-cran40/` returned a 404 during the first 25.10 build attempt.

- Observation: The Apple runtime may need tuned capture settings or higher VM resources for heavier ffmpeg recording workloads.
  Evidence: The first headed smoke used a 1920x1080 two-second x11grab capture and was killed during ffmpeg encode. A reduced 1280x720 one-second `libx264 -preset ultrafast` capture succeeded for both video-only and audio+video smoke validation.

- Observation: The official Node.js `25.8.1` tarballs for both `arm64` and `x64` ship `node`, `npm`, and `npx`, but not `corepack`.
  Evidence: Listing the tarball contents showed no `bin/corepack`, and the first Apple `container build` failed with `/bin/sh: 1: corepack: not found`.

- Observation: Runtime auto-selection has to prefer engines that are actually ready, not just installed, or the Docker fallback never activates on a host where `container` is present but `container system start` has not been run.
  Evidence: The first auto-selection pass would otherwise choose `container` on a supported Mac and fail before trying Docker even when Docker Desktop was healthy.

## Decision Log

- Decision: Keep the runtime migration and the image-base refresh in one plan, but only land the image-base refresh immediately.
  Rationale: The Dockerfile rewrite is self-contained and already useful. The runtime switch touches more files and needs real host validation, so it should not be half-implemented without an explicit plan and live testing.
  Date/Author: 2026-03-20 / Codex

- Decision: Use `ubuntu:25.10` as the replacement base image.
  Rationale: The user asked for the latest stable Ubuntu 25 release. Ubuntu 25.10 is the current released 25.x build, and the official `ubuntu:25.10` image publishes an `arm64` variant. Because Playwright does not yet document Ubuntu 25.x directly, the package surface still tracks the Ubuntu 24.04 arm64 dependency baseline and must be validated empirically on 25.10.
  Date/Author: 2026-03-20 / Codex

- Decision: Pin Node.js to `25.8.1` from `nodejs.org` tarballs instead of inheriting whatever Node version a base image currently ships.
  Rationale: The user requested the current Node version explicitly. Downloading the official tarball keeps the version exact on both `arm64` and `amd64`.
  Date/Author: 2026-03-20 / Codex

- Decision: Install `r-base` and `r-base-dev` from the Ubuntu 25.10 archive instead of CRAN.
  Rationale: The Questing CRAN apt repo is not published yet. Using Ubuntu's own packages keeps the image buildable without mixing Noble-targeted binaries into a 25.10 base image.
  Date/Author: 2026-03-20 / Codex

- Decision: Move Playwright browser binaries into `/workspace/.pw-browsers` instead of baking Microsoft-provided browsers into the base image.
  Rationale: This keeps browser versions project-local, avoids coupling the shared sandbox image to one Playwright browser revision, and preserves a writable path inside the read-only container filesystem.
  Date/Author: 2026-03-20 / Codex

- Decision: Preserve Docker as a first-class fallback instead of replacing it outright.
  Rationale: Docker remains the only working path on unsupported Macs, and it provides an escape hatch if `container` hits runtime bugs or missing features on a specific project.
  Date/Author: 2026-03-20 / Codex

- Decision: In `auto` mode, prefer a ready Apple runtime first, then a ready Docker daemon, then fall back to the preferred-but-not-ready runtime only when no ready engine exists.
  Rationale: This preserves the Apple-first default on supported hosts without breaking the requested Docker fallback behavior when `container` is installed but not started.
  Date/Author: 2026-03-20 / Codex

- Decision: Default Apple `container` sessions to `XVFB_SCREEN=1280x720x24` and expose `CXHERE_CONTAINER_CPUS`, `CXHERE_CONTAINER_MEMORY`, and `CXHERE_CONTAINER_XVFB_SCREEN` as the public tuning surface.
  Rationale: The lighter headed display profile matches the successful ffmpeg smoke on Apple silicon and is more reliable out of the box than the heavier Docker-oriented defaults.
  Date/Author: 2026-03-20 / Codex

## Outcomes & Retrospective

The image itself no longer depends on `mcr.microsoft.com/playwright` and is aligned with Ubuntu 25.10 arm64 plus Node.js `25.8.1`. Both Docker and Apple `container` can build that same plain `Dockerfile`, and both runtimes have already passed the headed Chromium plus ffmpeg video and audio+video smoke validation.

The runtime migration is now implemented in the host scripts. `scripts/cx-runtime-lib.sh` centralizes runtime detection and image/container inspection, `scripts/build-local.sh` supports `CX_BUILD_RUNTIME=auto|container|docker|all`, and `scripts/codex-worktrees.zsh` supports `CXHERE_RUNTIME=auto|container|docker|local` with runtime-neutral labels for worktree session discovery. Auto mode now prefers a ready Apple runtime on supported Macs and falls back to a ready Docker daemon when needed.

The Apple-specific recording question is also settled for the default path. The launcher now uses a lighter `1280x720x24` display on Apple `container` sessions and exposes explicit CPU/memory/display knobs for cases that need a larger headed surface. The remaining risk is operational, not architectural: `cxhere` is still interactive, so future changes should continue to be spot-checked with a manual launch on both runtimes after major shell-script edits.

## Context and Orientation

This repository is a thin shell wrapper around a Codex sandbox image. The important files are:

`Dockerfile` builds the Linux image that runs the Codex CLI. Before this turn it inherited `mcr.microsoft.com/playwright:v1.58.0-noble`. It now starts from `ubuntu:25.10` and installs the runtime surface explicitly.

`scripts/build-local.sh` now sources `scripts/cx-runtime-lib.sh`, honors `CX_BUILD_RUNTIME=auto|container|docker|all`, and rebuilds `codex-cli:local` in Docker, Apple `container`, or both image stores as requested.

`scripts/codex-worktrees.zsh` is the main entry point that users source into their shell. It now sources `scripts/cx-runtime-lib.sh`; `cxhere` creates or reuses a git worktree, copies helper files, and then launches either Docker, Apple `container`, or local `codex` based on `CXHERE_RUNTIME`. The same file also provides `cxclose`, `cxkill`, and `cxlist`.

`scripts/codex-entrypoint.sh` runs inside the container. It ensures `DISPLAY` exists, creates writable runtime directories under `/tmp`, starts PulseAudio with a null sink, discovers the monitor source for audio capture, starts `Xvfb`, and finally execs `codex`.

`README.md` describes the public behavior. Any runtime change that alters prerequisites, environment variables, or recovery steps must be reflected there.

In this repository, "runtime" means the host-side container engine used to build and launch the Codex image. The supported runtimes are Docker and Apple's `container` CLI, with a separate local non-container mode for users who explicitly opt out of container orchestration.

## Plan of Work

The migration now uses explicit runtime selection for both build and launch behavior. `scripts/cx-runtime-lib.sh` answers which runtime should be used, whether it is actually ready, and how to perform the runtime-specific operations for build, list, inspect, run, stop, and image inspection. `CXHERE_RUNTIME` supports `auto`, `container`, `docker`, and `local`. `auto` now prefers a ready Apple runtime on supported Macs, otherwise a ready Docker daemon, and only falls back to a not-yet-ready runtime when neither engine is currently usable. `CXHERE_NO_DOCKER=1` remains as a backward-compatible alias for `CXHERE_RUNTIME=local`.

Worktree session discovery no longer depends only on bind mounts. Every new container started by either runtime gets stable labels for repository, worktree, image tag, and runtime. Those labels drive reuse/replacement decisions and cross-runtime conflict detection. Docker keeps a bind-mount discovery fallback so older unlabeled sessions created before this migration can still be found and replaced cleanly.

The launch path is now split cleanly between Docker-only and Apple-supported flags. Docker keeps the existing seccomp and resource behavior. The Apple path uses only supported flags such as `--init`, `--read-only`, `--tmpfs`, `--volume`, `--env-file`, `--label`, `--user`, `--workdir`, `--cpus`, and `--memory`, with separate Apple-only CPU/memory/display defaults because `container` uses VM-level resources rather than Docker cgroup tuning.

`scripts/build-local.sh` now understands the same runtime selection model. The public command is still `./scripts/build-local.sh`, but it chooses its backend from `CX_BUILD_RUNTIME=auto|container|docker|all`. `all` remains important because Docker and `container` do not share image stores, and `CX_BUILD_CPUS` plus `CX_BUILD_MEMORY` are now available when Apple builds need explicit resource limits.

The image refresh landed as part of the migration rather than a side quest. The base image stays on `ubuntu:25.10`, Node.js stays pinned to `25.8.1`, and the image keeps the explicit union of Playwright runtime libraries, `xvfb`, PulseAudio, and `ffmpeg`. The image continues to run as the `codex` user and to rely on `scripts/codex-entrypoint.sh` for display and audio setup. `PLAYWRIGHT_BROWSERS_PATH=/workspace/.pw-browsers` keeps browser binaries in the worktree and out of the shared image.

The README is now organized around runtime choice rather than "Docker mode" alone. It explains that Docker remains supported, that Apple `container` is the preferred runtime on Apple silicon Macs running macOS 26 or later, that the Apple runtime requires `container system start`, that browser binaries live under `.pw-browsers` inside each worktree, and that Apple sessions default to a lighter headed display for recording reliability.

## Concrete Steps

Run the following commands from the repository root at `/Users/matthewmoore/Projects/cxhere`.

First, validate the Apple runtime prerequisites and version:

    sw_vers
    uname -m
    container --version

If the Apple runtime will be used, start its services:

    container system start

Then rebuild the image for the Apple runtime:

    CX_BUILD_RUNTIME=container ./scripts/build-local.sh

For Docker fallback coverage, rebuild the Docker image store too:

    CX_BUILD_RUNTIME=docker ./scripts/build-local.sh

Or, once the script supports it:

    CX_BUILD_RUNTIME=all ./scripts/build-local.sh

Create a test worktree session on the Apple runtime:

    CXHERE_RUNTIME=container cxhere test/apple-container

Inside the launched session, verify the core tooling:

    node --version
    npm --version
    ffmpeg -version | head -n 1
    Xvfb -help >/dev/null
    pactl info

Install a browser into the project-local Playwright cache and run a smoke launch:

    npx playwright install chromium
    node -e "const { chromium } = require('playwright'); (async () => { const browser = await chromium.launch({ headless: false }); const page = await browser.newPage(); await page.goto('data:text/html,<title>ok</title><h1>ok</h1>'); await page.screenshot({ path: '/tmp/playwright-smoke.png' }); await browser.close(); })();"

If a project records with ffmpeg, confirm the video side explicitly:

    ffmpeg -y -video_size 1280x720 -f x11grab -i "${DISPLAY}" -t 2 /tmp/xvfb-smoke.mp4

If `HARNESS_CAPTURE_AUDIO_INPUT` is present after the entrypoint starts PulseAudio, confirm combined audio/video capture:

    ffmpeg -y -video_size 1280x720 -f x11grab -i "${DISPLAY}" -f pulse -i "${HARNESS_CAPTURE_AUDIO_INPUT}" -t 2 /tmp/pw-audio-smoke.mp4

Then verify the fallback path from the host shell:

    CXHERE_RUNTIME=docker cxhere test/docker-fallback

The Docker fallback should still launch a session or fail with a direct Docker daemon error. It must not try to route that request through `container`.

## Validation and Acceptance

Acceptance is behavioral.

On an Apple silicon Mac running macOS 26 or newer with `container` installed, `CXHERE_RUNTIME=auto cxhere some/worktree` should choose the Apple runtime and launch Codex successfully. The container should have `node --version` equal to `v25.8.1`, `ffmpeg` on the path, a working `DISPLAY`, and a reachable PulseAudio server.

Inside that Apple-managed session, `npx playwright install chromium` should place browser binaries under `/workspace/.pw-browsers`, not inside the immutable system image. A headed Chromium smoke launch should succeed under the `Xvfb` display started by `scripts/codex-entrypoint.sh`. A short ffmpeg capture command using `DISPLAY` must produce a non-empty video file, and if `HARNESS_CAPTURE_AUDIO_INPUT` is available, the combined audio/video smoke file must also be non-empty.

When `CXHERE_RUNTIME=docker` is set, the repository must continue to use Docker-specific build and run commands. When Docker is unavailable, the command should fail with a Docker-specific error message rather than silently switching runtimes. When `CXHERE_RUNTIME=local` or `CXHERE_NO_DOCKER=1` is set, the repository must skip container orchestration entirely and run the local `codex` CLI in the worktree as it does today.

## Idempotence and Recovery

The build and runtime selection commands must be safe to repeat. Rebuilding the same runtime should simply replace the `codex-cli:local` image in that runtime's image store. Building both runtimes should not delete the other runtime's image store, because they are independent.

If the Apple runtime fails for a specific project, the recovery path is to leave the image in place and switch only the runtime selector:

    CXHERE_RUNTIME=docker cxhere some/worktree

If the Docker fallback needs the image refreshed, rebuild the Docker image store explicitly:

    CX_BUILD_RUNTIME=docker ./scripts/build-local.sh

Do not remove a user's worktree as part of runtime recovery. Only stop or replace the runtime-managed container for that worktree.

## Artifacts and Notes

Key upstream facts that shaped this plan:

    `container` latest release observed during research: 0.10.0 (published 2026-02-26).
    Host probe observed during research: macOS 26.3.1, Apple silicon, `container CLI version 0.10.0`.
    Playwright official Docker docs currently recommend Ubuntu 24.04 Noble images and explicitly say Alpine is unsupported.
    Playwright `nativeDeps.ts` contains a dedicated `ubuntu24.04-arm64` dependency map, but no Ubuntu 25.x entry, so the explicit package list in `Dockerfile` still starts from that baseline.
    Node.js current channel observed during research: v25.8.1, with published `linux-arm64` and `linux-x64` tarballs.

The current repository state after the first milestone already includes the new `Dockerfile`, updated `README.md`, and updated `CHANGELOG.md`. Preserve those changes while implementing the runtime abstraction so the image and runtime work do not drift apart.

## Interfaces and Dependencies

The runtime selector interface must exist in the host scripts after implementation:

In `scripts/codex-worktrees.zsh`, define shell helpers that behave like:

    cx_detect_runtime() -> prints one of: container, docker, local
    cx_require_runtime <runtime> -> exits non-zero with a human-readable message if the runtime cannot be used
    cx_list_worktree_containers <runtime> <worktree_dir> -> prints zero or more container IDs
    cx_local_image_identity <runtime> -> prints the image ID or digest for `codex-cli:local`
    cx_container_image_identity <runtime> <container_id> -> prints the running container image ID or digest
    cx_run_codex_container <runtime> <worktree_dir> [session_id] -> launches the session

In `scripts/build-local.sh`, add equivalent build-time behavior:

    cx_build_runtime="${CX_BUILD_RUNTIME:-auto}"
    cx_build_image_docker
    cx_build_image_container

Use these environment variables as the stable public surface:

    CXHERE_RUNTIME=auto|container|docker|local
    CX_BUILD_RUNTIME=auto|container|docker|all
    CXHERE_NO_DOCKER=1              # legacy alias for local mode
    CXHERE_CONTAINER_CPUS=<int>     # new, Apple runtime only
    CXHERE_CONTAINER_MEMORY=<size>  # new, Apple runtime only
    CX_BUILD_CPUS=<int>             # optional, forwarded to `container build`
    CX_BUILD_MEMORY=<size>          # optional, forwarded to `container build`

Labels added to launched containers should be stable and runtime-neutral. At minimum, define:

    com.moorage.cxhere.repo=<repo_root>
    com.moorage.cxhere.worktree=<worktree_dir>
    com.moorage.cxhere.image=codex-cli:local
    com.moorage.cxhere.runtime=<container|docker>

Revision note: Created on 2026-03-20 after researching Apple `container`, Playwright Linux dependencies, and Node.js `25.8.1`, and after landing the first milestone that replaced the Microsoft Playwright base image with an explicit Ubuntu image build now targeting Ubuntu 25.10.
