#!/usr/bin/env bash
# Ronan's Fedora KDE setup — one command to rebuild the whole machine.
# Run as your normal user (NOT with sudo). It asks for your sudo password once.
#
#   bash <(curl -fsSL https://raw.githubusercontent.com/GITHUB_USER/GITHUB_REPO/main/bootstrap.sh)
#
# Re-running is safe: every phase records a marker in ~/.local/state/fedora-setup
# and is skipped next time. Delete a marker (or the folder) to redo a phase.

set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_DIR="$HOME/.local/state/fedora-setup"
LOG="$STATE_DIR/install.log"
mkdir -p "$STATE_DIR"
exec > >(tee -a "$LOG") 2>&1

# ---------- knobs (override by exporting before running) ----------
: "${SETUP_HOSTNAME:=}"              # e.g. ronan-laptop-2 ; empty = ask
: "${SETUP_TIMEZONE:=America/Chicago}"
: "${SETUP_GAMESHOW_REPO:=}"         # git URL of RonanGameshowConsole, empty = skip
: "${SETUP_AUTO_REBOOT:=ask}"        # yes | no | ask
: "${SETUP_SKIP_LOGINS:=0}"          # 1 = don't stop for tailscale / claude logins

source "$REPO_DIR/lib/common.sh"

banner "Ronan's Fedora KDE setup"
echo "repo:  $REPO_DIR"
echo "log:   $LOG"
echo

# ---------- preflight ----------
[[ $EUID -eq 0 ]] && die "Run this as your normal user, not root/sudo."
. /etc/os-release
[[ "$ID" == "fedora" ]] || die "This is for Fedora (found $ID)."
FEDORA_VER="$VERSION_ID"
info "Fedora $FEDORA_VER, kernel $(uname -r), user $USER"
command -v plasmashell >/dev/null || warn "KDE Plasma not found; desktop phases will still copy configs."
if command -v mokutil >/dev/null && mokutil --sb-state 2>/dev/null | grep -q enabled; then
  warn "Secure Boot is ON: VirtualBox/NVIDIA kernel modules (akmods) will not load until it is turned off in BIOS."
fi

sudo_keepalive

# ====================================================================
phase 10-repos "Add repositories (RPM Fusion, Flathub, Chrome, VS Code, Tailscale)" && {
  sudo dnf -y install "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-${FEDORA_VER}.noarch.rpm" \
                      "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${FEDORA_VER}.noarch.rpm" || true
  sudo dnf -y install fedora-workstation-repositories dnf5-plugins
  sudo dnf config-manager setopt google-chrome.enabled=1

  sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
  sudo tee /etc/yum.repos.d/vscode.repo >/dev/null <<'R'
[code]
name=Visual Studio Code
baseurl=https://packages.microsoft.com/yumrepos/vscode
enabled=1
autorefresh=1
type=rpm-md
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc
R

  sudo dnf config-manager addrepo --overwrite --from-repofile=https://pkgs.tailscale.com/stable/fedora/tailscale.repo

  sudo flatpak remote-add --if-not-exists --system flathub https://dl.flathub.org/repo/flathub.flatpakrepo
  flatpak remote-add --if-not-exists --user flathub https://dl.flathub.org/repo/flathub.flatpakrepo
  done_phase
}

# ====================================================================
phase 20-update "Full system update" && {
  sudo dnf -y upgrade --refresh
  touch "$STATE_DIR/reboot-needed"
  done_phase
}

# ====================================================================
phase 30-packages "Install packages" && {
  mapfile -t PKGS < <(grep -vE '^\s*(#|$)' "$REPO_DIR/packages.txt")
  sudo dnf -y install --skip-unavailable "${PKGS[@]}"
  done_phase
}

# ====================================================================
phase 35-multimedia "Codecs and GPU drivers" && {
  # Full ffmpeg + multimedia group (RPM Fusion recommended steps)
  sudo dnf -y swap ffmpeg-free ffmpeg --allowerasing || true
  sudo dnf -y group install multimedia --setopt="install_weak_deps=False" --exclude=PackageKit-gstreamer-plugin || true

  if lspci -nn | grep -iE 'vga|3d|display' | grep -qi intel; then
    info "Intel GPU: installing intel-media-driver (hardware video decode)"
    sudo dnf -y install intel-media-driver libva-utils || true
  fi
  if lspci -nn | grep -iE 'vga|3d|display' | grep -qi amd; then
    info "AMD GPU: installing mesa freeworld drivers"
    sudo dnf -y swap mesa-va-drivers mesa-va-drivers-freeworld || true
    sudo dnf -y swap mesa-vdpau-drivers mesa-vdpau-drivers-freeworld || true
  fi
  if lspci -nn | grep -iE 'vga|3d|display' | grep -qi nvidia; then
    info "NVIDIA GPU: installing akmod-nvidia (builds the module, takes a few minutes)"
    sudo dnf -y install akmod-nvidia xorg-x11-drv-nvidia-cuda || true
    touch "$STATE_DIR/reboot-needed"
  fi
  done_phase
}

# ====================================================================
phase 40-flatpaks "Install Flatpak apps" && {
  while read -r scope app; do
    [[ -z "$app" || "$scope" == \#* ]] && continue
    info "flatpak ($scope): $app"
    if [[ "$scope" == system ]]; then
      sudo flatpak install -y --noninteractive --system flathub "$app" || warn "failed: $app"
    else
      flatpak install -y --noninteractive --user flathub "$app" || warn "failed: $app"
    fi
  done < "$REPO_DIR/flatpaks.txt"

  # permission overrides (Sober <-> Discord IPC, fonts/icons for every app)
  mkdir -p "$HOME/.local/share/flatpak/overrides"
  cp -f "$REPO_DIR"/config/home/.local/share/flatpak/overrides/* "$HOME/.local/share/flatpak/overrides/"
  done_phase
}

# ====================================================================
phase 50-virtualbox "VirtualBox (RPM Fusion build, auto-rebuilds with kernel updates)" && {
  sudo dnf -y install VirtualBox akmod-VirtualBox kernel-devel kernel-headers akmods || warn "VirtualBox install failed"
  sudo usermod -aG vboxusers "$USER" || true
  sudo akmods --force || true
  sudo systemctl enable --now vboxdrv.service 2>/dev/null || sudo modprobe vboxdrv 2>/dev/null || true
  done_phase
}

# ====================================================================
phase 60-devtools "Node, Claude Code, VS Code settings" && {
  sudo dnf -y install nodejs npm git
  # Claude Code native installer (puts `claude` in ~/.local/bin)
  if ! command -v claude >/dev/null; then
    curl -fsSL https://claude.ai/install.sh | bash || warn "Claude Code install failed"
  fi
  mkdir -p "$HOME/.claude" "$HOME/.config/Code/User"
  cp -f "$REPO_DIR/config/home/.claude/settings.json" "$HOME/.claude/settings.json"
  cp -f "$REPO_DIR/config/home/.config/Code/User/settings.json" "$HOME/.config/Code/User/settings.json"
  done_phase
}

# ====================================================================
phase 70-look "Fonts, icons, splash screens, start-button logo" && {
  mkdir -p "$HOME/.local/share/fonts/custom" "$HOME/.local/share/icons/custom" \
           "$HOME/.local/share/plasma/look-and-feel" "$HOME/Pictures/Wallpapers"
  cp -f "$REPO_DIR"/assets/fonts/*.ttf "$HOME/.local/share/fonts/custom/"
  fc-cache -f >/dev/null
  cp -f "$REPO_DIR/assets/icons/nebula-start.png" "$HOME/.local/share/icons/custom/"
  cp -rf "$REPO_DIR"/assets/look-and-feel/* "$HOME/.local/share/plasma/look-and-feel/"
  cp -f "$REPO_DIR/assets/wallpapers/desktop.webp" "$HOME/Pictures/Wallpapers/desktop.webp"
  cp -f "$REPO_DIR/assets/wallpapers/lockscreen.jpg" "$HOME/Pictures/Wallpapers/lockscreen.jpg"
  # Papirus icons come from the Fedora package (installed in 30-packages)
  done_phase
}

# ====================================================================
phase 75-avatar "User avatar" && {
  cp -f "$REPO_DIR/assets/avatar/ronan.png" "$HOME/.face.icon"
  ln -sf "$HOME/.face.icon" "$HOME/.face"
  sudo install -D -m 0644 "$REPO_DIR/assets/avatar/ronan.png" "/var/lib/AccountsService/icons/$USER"
  sudo mkdir -p /var/lib/AccountsService/users
  if sudo test -f "/var/lib/AccountsService/users/$USER"; then
    sudo sed -i "/^Icon=/d" "/var/lib/AccountsService/users/$USER"
    grep -q '^\[User\]' <(sudo cat "/var/lib/AccountsService/users/$USER") || echo "[User]" | sudo tee -a "/var/lib/AccountsService/users/$USER" >/dev/null
    sudo sed -i "/^\[User\]/a Icon=/var/lib/AccountsService/icons/$USER" "/var/lib/AccountsService/users/$USER"
  else
    printf '[User]\nIcon=/var/lib/AccountsService/icons/%s\nSystemAccount=false\n' "$USER" | sudo tee "/var/lib/AccountsService/users/$USER" >/dev/null
  fi
  sudo systemctl restart accounts-daemon 2>/dev/null || true
  done_phase
}

# ====================================================================
phase 80-system "System tweaks: fingerprint, timezone, hostname, firmware" && {
  # Keep the ELAN fingerprint reader powered (04f3:0c4d); harmless on machines without it
  sudo install -m 0644 "$REPO_DIR/system/99-elan-fingerprint.rules" /etc/udev/rules.d/99-elan-fingerprint.rules
  sudo udevadm control --reload
  sudo dnf -y install fprintd fprintd-pam
  sudo authselect enable-feature with-fingerprint || true

  sudo timedatectl set-timezone "$SETUP_TIMEZONE" || true

  if [[ -z "$SETUP_HOSTNAME" && -t 0 ]]; then
    read -rp "Hostname for this machine [$(hostnamectl --static)]: " SETUP_HOSTNAME
  fi
  [[ -n "$SETUP_HOSTNAME" ]] && sudo hostnamectl set-hostname "$SETUP_HOSTNAME"

  info "Firmware updates (fwupd) — applied on next reboot"
  sudo fwupdmgr refresh --force >/dev/null 2>&1 || true
  sudo fwupdmgr get-updates 2>/dev/null | tail -n +1 || true
  if sudo fwupdmgr update -y --no-reboot-check 2>&1 | tee /dev/stderr | grep -qiE 'updated|successfully|scheduled'; then
    touch "$STATE_DIR/reboot-needed"
  fi
  done_phase
}

# ====================================================================
phase 85-services "Tailscale and login-time services" && {
  sudo systemctl enable --now tailscaled
  mkdir -p "$HOME/.config/autostart"
  cp -f "$REPO_DIR/config/home/.config/autostart/tailscale-systray.desktop" "$HOME/.config/autostart/"
  if [[ "$SETUP_SKIP_LOGINS" != 1 ]]; then
    if ! tailscale status >/dev/null 2>&1; then
      info "Tailscale login: a URL will print below; open it and sign in."
      sudo tailscale up --operator="$USER" || warn "tailscale up did not finish; run: sudo tailscale up --operator=$USER"
    fi
  fi
  done_phase
}

# ====================================================================
phase 90-gameshow "Ronan Gameshow Console (optional)" && {
  if [[ -n "$SETUP_GAMESHOW_REPO" ]]; then
    mkdir -p "$HOME/claude"
    [[ -d "$HOME/claude/RonanGameshowConsole/.git" ]] || git clone "$SETUP_GAMESHOW_REPO" "$HOME/claude/RonanGameshowConsole"
    (cd "$HOME/claude/RonanGameshowConsole" && npm install && npm run package) || warn "gameshow build failed"
  fi
  if [[ -x "$HOME/claude/RonanGameshowConsole/out/RonanGameshowConsole-linux-x64/RonanGameshowConsole" ]]; then
    sed "s#__HOME__#$HOME#g" "$REPO_DIR/config/ronan-gameshow-console.desktop" > "$HOME/.local/share/applications/ronan-gameshow-console.desktop"
  fi
  done_phase
}

# ====================================================================
phase 95-kde "KDE Plasma configuration (taskbar, theme, shortcuts, wallpaper, defaults)" && {
  bash "$REPO_DIR/lib/apply-kde-config.sh" "$REPO_DIR"
  done_phase
}

# ====================================================================
banner "Done"
echo "Log: $LOG"
echo
echo "Things that still need you (accounts can't be scripted):"
echo "  - Chrome, Spotify, Discord, Todoist, Steam, Thunderbird, Moonlight: sign in on first launch"
echo "  - Claude Code: run 'claude' once to log in"
if lsusb 2>/dev/null | grep -q '04f3:0c4d'; then
  echo "  - Fingerprint: run 'fprintd-enroll' and swipe your finger (reader detected)"
fi
echo

if [[ -f "$STATE_DIR/reboot-needed" ]]; then
  case "$SETUP_AUTO_REBOOT" in
    yes) info "Rebooting in 10 seconds (Ctrl+C to cancel)"; sleep 10; systemctl reboot ;;
    no)  warn "A reboot is needed to finish (new kernel/firmware/drivers)." ;;
    *)   if [[ -t 0 ]]; then
           read -rp "Reboot now to finish? [Y/n] " ans
           [[ "${ans:-Y}" =~ ^[Yy]$ ]] && systemctl reboot
         else
           warn "A reboot is needed to finish."
         fi ;;
  esac
else
  info "No reboot required, but log out and back in so every setting takes effect."
fi
