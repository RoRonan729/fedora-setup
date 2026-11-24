#!/usr/bin/env bash
# Re-capture the CURRENT machine's look and settings into this repo (run after you
# change something you want to keep). Then: git add -A && git commit -m "update" && git push
set -euo pipefail
R="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
C="$R/config/home"
tpl() { sed "s#$HOME#__HOME__#g" "$1" > "$2"; }

for f in kdeglobals kwinrc plasma-org.kde.plasma.desktop-appletsrc plasmashellrc plasmarc ksplashrc \
         kglobalshortcutsrc krunnerrc kscreenlockerrc powerdevilrc dolphinrc konsolerc breezerc kded6rc \
         kded5rc baloofilerc mimeapps.list arkrc kwriterc kaccessrc discoverrc filetypesrc \
         kactivitymanagerdrc plasma-localerc kcmfonts knighttimerc; do
  [[ -f "$HOME/.config/$f" ]] && tpl "$HOME/.config/$f" "$C/dot-config/$f"
done
for d in gtk-3.0 gtk-4.0 xsettingsd fontconfig Kvantum autostart; do
  [[ -d "$HOME/.config/$d" ]] && { rm -rf "$C/dot-config/$d"; cp -r "$HOME/.config/$d" "$C/dot-config/$d"; }
done
[[ -f "$HOME/.gtkrc-2.0" ]] && tpl "$HOME/.gtkrc-2.0" "$C/dot-gtkrc-2.0"
cp -f "$HOME"/.local/share/konsole/* "$C/dot-local/share/konsole/" 2>/dev/null || true
# custom color schemes / window decorations / plasma styles, if any were installed
for d in color-schemes aurorae plasma/desktoptheme plasma/plasmoids; do
  [[ -d "$HOME/.local/share/$d" ]] && { mkdir -p "$C/dot-local/share/$(dirname $d)"; rm -rf "$C/dot-local/share/$d"; cp -r "$HOME/.local/share/$d" "$C/dot-local/share/$d"; }
done
cp -f "$HOME"/.local/share/flatpak/overrides/* "$C/dot-local/share/flatpak/overrides/" 2>/dev/null || true
cp -f "$HOME/.config/Code/User/settings.json" "$C/dot-config/Code/User/settings.json" 2>/dev/null || true
cp -f "$HOME/.claude/settings.json" "$C/dot-claude/settings.json" 2>/dev/null || true
cp -f "$HOME"/.local/share/fonts/custom/*.ttf "$R/assets/fonts/" 2>/dev/null || true
cp -f "$HOME/.local/share/icons/custom/nebula-start.png" "$R/assets/icons/" 2>/dev/null || true
rm -rf "$R/assets/look-and-feel"/*; cp -r "$HOME"/.local/share/plasma/look-and-feel/* "$R/assets/look-and-feel/" 2>/dev/null || true
[[ -f /var/lib/AccountsService/icons/$USER ]] && cp -f "/var/lib/AccountsService/icons/$USER" "$R/assets/avatar/ronan.png"

# wallpapers: whatever is set right now
wp=$(grep -m1 '^Image=' "$HOME/.config/plasma-org.kde.plasma.desktop-appletsrc" | cut -d= -f2- | sed 's#^file://##')
[[ -f "$wp" ]] && cp -f "$wp" "$R/assets/wallpapers/desktop.${wp##*.}"
lk=$(grep -m1 '^Image=' "$HOME/.config/kscreenlockerrc" | cut -d= -f2- | sed 's#^file://##')
[[ -f "$lk" ]] && cp -f "$lk" "$R/assets/wallpapers/lockscreen.${lk##*.}"
# the configs must point at the repo's wallpaper copies, not wherever they were downloaded
[[ -f "$wp" ]] && sed -i "s#__HOME__${wp#$HOME}#__HOME__/Pictures/Wallpapers/desktop.${wp##*.}#g" "$C/dot-config/plasma-org.kde.plasma.desktop-appletsrc"
[[ -f "$lk" ]] && sed -i "s#__HOME__${lk#$HOME}#__HOME__/Pictures/Wallpapers/lockscreen.${lk##*.}#g" "$C/dot-config/kscreenlockerrc"

# flatpaks
{ echo "# scope  app-id"; flatpak list --system --app --columns=application | sed 's/^/system /';
  flatpak list --user --app --columns=application | sed 's/^/user   /'; } > "$R/flatpaks.txt"

if grep -rl "$USER" "$C" "$R/flatpaks.txt" >/dev/null; then echo "WARNING: username leaked into:"; grep -rl "$USER" "$C"; fi
echo "snapshot done — review with: git -C $R status"
