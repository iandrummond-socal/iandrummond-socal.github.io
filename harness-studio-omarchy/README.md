# Harness Studio for Omarchy

Arch/Omarchy packaging for [Harness Studio](https://github.com/vigneshv1cky/harness-studio) v0.3.4, the MIT-licensed any-model desktop coding agent. It is not affiliated with the upstream project. The app itself is unchanged: `PKGBUILD` repackages upstream's released x86_64 `.deb` as a native pacman package, so there is no 5-minute Electron build. It adds what Omarchy needs and the `.deb` lacks.

## Install

```sh
git clone https://github.com/iandrummond-socal/iandrummond-socal.github.io
cd iandrummond-socal.github.io/harness-studio-omarchy
./install.sh
```

This runs `makepkg -si`. It downloads the release `.deb` (about 290 MB), checks its SHA-256, installs pacman dependencies, and installs the package. Then press `Super+Space` and search for **Harness Studio**, or run `harness-studio` for the CLI.

Remove it with `sudo pacman -Rns harness-studio-bin`. Your data in `~/.harness-studio` stays.

## What differs from the stock `.deb`

| | Stock `.deb` | This package |
|---|---|---|
| Package manager | apt | pacman (`harness-studio-bin`) |
| Dependencies | Debian names | Arch names, including **`bubblewrap`** |
| Wayland | launcher runs the app with no flags | `--ozone-platform-hint=auto --enable-features=WaylandWindowDecorations`, so Hyprland runs it native Wayland instead of XWayland |
| AppArmor profile | installed on Ubuntu 24+ | dropped (Omarchy has no AppArmor) |
| `chrome-sandbox` | setuid only without user namespaces | same check, in `harness-studio.install` |

`bubblewrap` matters. The app bundles only a Landlock runner and uses the system `bwrap` when it finds one. With bwrap it can hide `~/.ssh`, cloud credentials and `.env` files from the agent's commands and limit their network access. With Landlock only, upstream says commands can still read those files and network limits fail closed.

## Notes for Hyprland

- The window's app id should be `harness-studio`. Check it with `hyprctl clients`. If it is different, change `StartupWMClass` in `harness-studio.desktop` and any window rules to match.
- Provider API keys go through libsecret. Omarchy ships `gnome-keyring`; if the app can't save a key, check that the keyring is unlocked at login.
- Opening a project folder uses the XDG file chooser, so `xdg-desktop-portal-hyprland` and `xdg-desktop-portal-gtk` should be running (Omarchy installs both).
- Optional Hyprland bind to launch it, in `~/.config/hypr/bindings.conf`:
  ```
  bindd = SUPER, H, Harness Studio, exec, uwsm app -- "/opt/Harness Studio/harness-studio" --ozone-platform-hint=auto
  ```

## Status: read before trusting

I built and checked this without access to an Arch machine. What was verified:

- Downloaded upstream's v0.3.4 `.deb` and confirmed its SHA-256 (`ddfbe04e…db0cc7439b70`) matches `PKGBUILD`.
- Inspected the `.deb`'s contents and maintainer scripts, and ran `package()` against it with a stand-in for `bsdtar`: the `/opt`, `/usr/bin` and icon layout come out right and the launcher symlink resolves.

**Not verified:** a real `makepkg` run, launching on Omarchy/Hyprland, and the Wayland flags with this Electron version. Please run it once and report anything that breaks. Likely trouble spots are a missing runtime library in `depends` (`namcap` will find it) and a different Wayland app id.

Only x86_64 is packaged. Upstream also publishes an arm64 `.deb`; adding `aarch64` means a second `source_aarch64` and checksum in `PKGBUILD`.

## Updating to a new upstream release

Change `pkgver` in `PKGBUILD`, run `updpkgsums` (from `pacman-contrib`), and rebuild.
