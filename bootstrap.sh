#!/usr/bin/env bash
# One-liner entry point. Installs git, clones the setup repo, runs install.sh.
#   bash <(curl -fsSL https://raw.githubusercontent.com/GITHUB_USER/GITHUB_REPO/main/bootstrap.sh)
# Optional: REPO_URL=https://github.com/you/your-fork.git bash <(curl ...)
set -euo pipefail
: "${REPO_URL:=https://github.com/GITHUB_USER/GITHUB_REPO.git}"
: "${DEST:=$HOME/fedora-setup}"
[[ $EUID -eq 0 ]] && { echo "Run as your normal user, not root."; exit 1; }
command -v git >/dev/null || sudo dnf -y install git
if [[ -d "$DEST/.git" ]]; then git -C "$DEST" pull --ff-only; else git clone "$REPO_URL" "$DEST"; fi
exec bash "$DEST/install.sh"
