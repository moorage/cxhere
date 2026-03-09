# Changelog

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
