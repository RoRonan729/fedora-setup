# fedora-setup

Rebuilds my Fedora KDE Plasma laptop from a fresh install with one command:
apps, repos, codecs, drivers, firmware, fonts, icons, taskbar layout, wallpaper,
lock screen, user avatar, shortcuts, default apps, Tailscale, Claude Code, VS Code.

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/RoRonan729/fedora-setup/main/bootstrap.sh)
```

Run it as your normal user on a fresh **Fedora KDE Plasma Desktop** (44 or 45).
It asks for your sudo password once, then runs on its own. The only pauses are
things that need an account: Tailscale prints a login URL, the hostname is asked
once, and at the end it offers to reboot.

Safe to re-run: finished phases are skipped (markers in `~/.local/state/fedora-setup`).
A log is kept at `~/.local/state/fedora-setup/install.log`.

## What it does, in order

| Phase | What |
|---|---|
| 10-repos | RPM Fusion free + nonfree, Flathub (system + user), Google Chrome, VS Code, Tailscale |
| 20-update | `dnf upgrade --refresh` (new kernel if there is one) |
| 30-packages | everything in `packages.txt` |
| 35-multimedia | full ffmpeg, multimedia group, Intel `intel-media-driver`; AMD freeworld or NVIDIA `akmod-nvidia` if that hardware is found |
| 40-flatpaks | everything in `flatpaks.txt` + my Flatpak permission overrides |
| 50-virtualbox | VirtualBox from RPM Fusion with `akmod-VirtualBox` (rebuilds itself on kernel updates), adds you to `vboxusers` |
| 60-devtools | Node + npm, Claude Code (native installer), git, VS Code settings |
| 70-look | fonts (Geist Mono, Cascadia Mono, IBM Plex Mono, Lexend, Space Mono), Papirus icons, splash screens, Nebula start-button logo, wallpapers to `~/Pictures/Wallpapers` |
| 75-avatar | account picture (login screen + user switcher) |
| 80-system | ELAN fingerprint udev rule + `authselect with-fingerprint`, timezone, hostname prompt, firmware updates via fwupd |
| 85-services | Tailscale (enable, login, tray icon on startup) |
| 95-kde | all Plasma config: Windows-11-style bottom panel (pinned apps, hidden tray items, Geist Mono clock), dark theme with red accent, Geist Mono UI font, Papirus-Dark, Blur-Glassy splash, Alt+Space KRunner, blur/magic-lamp effects, 2 virtual desktops, Konsole "Terminal" profile (PureBlack), Dolphin, default apps (Chrome, VLC), touchpad (natural scroll, two-finger right click) |

Then it reboots (asks first) so the kernel, firmware and theme all land.

## Knobs

Export before running (or prefix the command):

| Variable | Default | Meaning |
|---|---|---|
| `SETUP_HOSTNAME` | ask | hostname to set |
| `SETUP_TIMEZONE` | `America/Chicago` | |
| `SETUP_AUTO_REBOOT` | `ask` | `yes` / `no` / `ask` |
| `SETUP_SKIP_LOGINS` | `0` | `1` = don't stop for `tailscale up` |

Example: `SETUP_HOSTNAME=ronan-laptop-2 SETUP_AUTO_REBOOT=yes bash <(curl -fsSL …/bootstrap.sh)`

## After it finishes

Sign in on first launch: Chrome, Spotify, Discord, Todoist, Steam, Thunderbird, Moonlight,
Sober. Run `claude` once to log in. If the laptop has a fingerprint reader: `fprintd-enroll`.

## Keeping it up to date

Changed a setting on the current machine that you want to keep? On that machine:

```bash
~/fedora-setup/snapshot.sh      # re-captures Plasma config, fonts, icons, wallpapers, flatpak list
cd ~/fedora-setup && git add -A && git commit -m "update" && git push
```

New dnf package: add a line to `packages.txt`. New Flatpak: add `user com.example.App` to `flatpaks.txt`.

## Layout

```
bootstrap.sh          curl-able entry point: installs git, clones, runs install.sh
install.sh            the phases
packages.txt          dnf packages
flatpaks.txt          flatpak apps (scope + id)
lib/common.sh         helpers (phase markers, sudo keep-alive)
lib/apply-kde-config.sh   copies config/home into $HOME, restarts plasmashell, sets touchpad via KWin
config/home/          files that land in ~ ("dot-config" becomes ".config"; paths stored as __HOME__)
assets/               fonts, wallpapers, avatar, start icon, splash themes
system/               /etc files (fingerprint udev rule)
snapshot.sh           re-capture the current machine into the repo
```

## Notes

- Config files are copied while plasmashell is stopped so it can't write its old
  layout over them. The previous config is saved to `~/kde-backup-<date>`.
- Secure Boot must be off for VirtualBox / NVIDIA kernel modules (the script warns if it is on).
- Discord comes from RPM Fusion nonfree and Modrinth from Flathub instead of hand-downloaded
  RPMs, so they update with everything else.
- Works for anyone, not just me: it never hardcodes a username. Fork it, swap the avatar,
  wallpapers and `packages.txt`, and change `RoRonan729/fedora-setup` in `bootstrap.sh` and this README.
