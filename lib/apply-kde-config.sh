#!/usr/bin/env bash
# Copies the KDE/Plasma config files from the repo into $HOME, swapping __HOME__
# for the real home dir, then reloads the desktop so they take effect.
# In the repo, hidden names are spelled "dot-X" (GitHub's web uploader refuses
# real dot-files); they land in $HOME as ".X".
# Called by install.sh; can also be run on its own:  lib/apply-kde-config.sh /path/to/repo
set -uo pipefail
REPO_DIR="${1:?repo dir}"
SRC="$REPO_DIR/config/home"
: "${SETUP_NO_RESTART:=0}"

in_plasma() { [[ "$SETUP_NO_RESTART" != 1 ]] && pgrep -u "$USER" -x plasmashell >/dev/null; }

echo "[+] backing up current config to $HOME/kde-backup-$(date +%Y%m%d-%H%M%S)"
BK="$HOME/kde-backup-$(date +%Y%m%d-%H%M%S)"; mkdir -p "$BK"
dest() { echo "$1" | sed -E 's#(^|/)dot-#\1.#g'; }
(cd "$SRC" && find . -type f) | while read -r f; do
  t="$(dest "$f")"
  [[ -e "$HOME/$t" ]] && { mkdir -p "$BK/$(dirname "$t")"; cp -a "$HOME/$t" "$BK/$t"; }
done

if in_plasma; then
  echo "[+] stopping plasmashell and kglobalaccel so they don't overwrite the new files"
  kquitapp6 plasmashell 2>/dev/null || systemctl --user stop plasma-plasmashell.service
  systemctl --user stop plasma-kglobalaccel.service 2>/dev/null || true
  sleep 2
fi

echo "[+] copying config files"
(cd "$SRC" && find . -type f) | while read -r f; do
  t="$(dest "$f")"
  mkdir -p "$HOME/$(dirname "$t")"
  if grep -qI . "$SRC/$f" 2>/dev/null; then
    sed "s#__HOME__#$HOME#g" "$SRC/$f" > "$HOME/$t"
  else
    cp -f "$SRC/$f" "$HOME/$t"
  fi
done

# Konsole shows up as "Terminal" in menus/taskbar (local override of the system .desktop)
if [[ -f /usr/share/applications/org.kde.konsole.desktop ]]; then
  mkdir -p "$HOME/.local/share/applications"
  sed -E '/^(Name|GenericName)\[/d; s/^Name=.*/Name=Terminal/; s/^GenericName=.*/GenericName=Terminal/' \
    /usr/share/applications/org.kde.konsole.desktop > "$HOME/.local/share/applications/org.kde.konsole.desktop"
fi

# Default apps
command -v xdg-settings >/dev/null && xdg-settings set default-web-browser google-chrome.desktop 2>/dev/null || true
command -v update-desktop-database >/dev/null && update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true

if in_plasma; then
  echo "[+] restarting plasmashell / kglobalaccel, reloading kwin"
  systemctl --user start plasma-kglobalaccel.service 2>/dev/null || true
  systemctl --user restart plasma-plasmashell.service 2>/dev/null || (kstart plasmashell >/dev/null 2>&1 &)
  busctl --user call org.kde.KWin /KWin org.kde.KWin reconfigure 2>/dev/null || true

  # Touchpad: natural scrolling, two-finger right click, middle-button emulation, slow scroll.
  # Done through KWin so it is keyed to THIS laptop's touchpad, whatever model it is.
  devs=$(busctl --user get-property org.kde.KWin /org/kde/KWin/InputDevice org.kde.KWin.InputDeviceManager devicesSysNames 2>/dev/null | sed -E 's/^as [0-9]+ //; s/"//g')
  for d in $devs; do
    [[ "$(busctl --user get-property org.kde.KWin /org/kde/KWin/InputDevice/$d org.kde.KWin.InputDevice touchpad 2>/dev/null)" == "b true" ]] || continue
    echo "[+] touchpad $d: natural scroll, clickfinger, middle emulation, scrollFactor 0.1, disable while typing"
    busctl --user set-property org.kde.KWin /org/kde/KWin/InputDevice/$d org.kde.KWin.InputDevice disableWhileTyping b true
    busctl --user set-property org.kde.KWin /org/kde/KWin/InputDevice/$d org.kde.KWin.InputDevice naturalScroll b true
    busctl --user set-property org.kde.KWin /org/kde/KWin/InputDevice/$d org.kde.KWin.InputDevice clickMethodClickfinger b true
    busctl --user set-property org.kde.KWin /org/kde/KWin/InputDevice/$d org.kde.KWin.InputDevice middleEmulation b true
    busctl --user set-property org.kde.KWin /org/kde/KWin/InputDevice/$d org.kde.KWin.InputDevice scrollFactor d 0.1
  done
fi
echo "[+] KDE config applied. Colors/fonts fully apply after logout or reboot."
