#!/usr/bin/env bash
# Make a worktree for one role's branch, next to the repo, from origin/main.
# Usage: scripts/worktree.sh <head|core|ui|qa|android|ai> <branch>
#   e.g. scripts/worktree.sh core core/split-shell
set -euo pipefail
cd "$(dirname "$0")/.."
role="${1:?role: head, core, ui, qa, android or ai}"
branch="${2:?branch name, e.g. ui/today-sections}"
case "$role" in
  head) sim="C3E44428-02AC-4D0E-B3D2-8F69FEE2D703 (iPhone 17 Pro Max)" ;;
  ui) sim="F96E4771-D1B0-42DD-8F45-3DC691192F62 (iPhone 18 Pro)" ;;
  qa) sim="4A119F41-BF95-4D7A-A43C-744193BD853E (iPhone 17e)" ;;
  core) sim="none; cargo test is the check" ;;
  ai) sim="CFAAFAE1-9C75-47E3-9B38-143A150156B8 (iPhone 17, CPU only)" ;;
  android) sim="the emulator (scripts/emu.sh)" ;;
  *) echo "unknown role: $role" >&2; exit 1 ;;
esac
# A branch under head/ can't be fetched on macOS: refs/remotes/origin/head
# collides with origin/HEAD on a case-insensitive disk.
[[ "$branch" == head/* ]] && { echo "use another prefix than head/" >&2; exit 1; }
dir="$(cd .. && pwd)/intportal-wt/${branch//\//-}"
git fetch -q origin main
git worktree add -q -b "$branch" "$dir" origin/main
cd "$dir"
pnpm install --frozen-lockfile --silent
command -v codegraph >/dev/null && codegraph init -y . >/dev/null
echo "Worktree: $dir"
echo "Branch:   $branch"
echo "Simulator: $sim"
