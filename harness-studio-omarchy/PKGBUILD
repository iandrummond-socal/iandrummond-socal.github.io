# Maintainer: Ian Drummond <ian.colin.drummond@gmail.com>
#
# Harness Studio for Arch Linux and Omarchy. Repackages the upstream release .deb
# (https://github.com/vigneshv1cky/harness-studio); nothing is rebuilt.
pkgname=harness-studio-bin
_pkgname=harness-studio
pkgver=0.3.4
pkgrel=1
pkgdesc='Desktop coding agent that works with any model provider (Omarchy/Wayland build)'
arch=('x86_64')
url='https://github.com/vigneshv1cky/harness-studio'
license=('MIT')
# bubblewrap: the app only finds the system bwrap. Without it the sandbox falls back to
# Landlock, which cannot hide secret files from commands or limit their network access.
depends=('gtk3' 'libnotify' 'nss' 'libxss' 'libxtst' 'xdg-utils' 'at-spi2-core'
         'util-linux-libs' 'libsecret' 'alsa-lib' 'mesa' 'bubblewrap')
optdepends=('gnome-keyring: stores provider API keys through libsecret (installed with Omarchy)'
            'libappindicator-gtk3: tray icon'
            'git: Git page, worktrees and diffs'
            'python: lets the agent run Python scripts directly')
provides=("$_pkgname")
conflicts=("$_pkgname")
options=('!strip' '!debug' '!lto')
install="$_pkgname.install"
source_x86_64=("${_pkgname}_${pkgver}_amd64.deb::$url/releases/download/v$pkgver/${_pkgname}_${pkgver}_amd64.deb"
               "$_pkgname.desktop")
noextract=("${_pkgname}_${pkgver}_amd64.deb")
sha256sums_x86_64=('ddfbe04e5a441d2c722333b8457e7dea492e1d6971438fb89dd7db0cc7439b70'
                   'SKIP')

prepare() {
  mkdir -p deb
  bsdtar -xf "${_pkgname}_${pkgver}_amd64.deb" -C deb
  mkdir -p root
  bsdtar -xf deb/data.tar.xz -C root
}

package() {
  cp -a root/opt "$pkgdir/opt"

  # The deb's launcher entry execs the app directly; ours adds Wayland flags for Hyprland.
  install -Dm644 "$srcdir/$_pkgname.desktop" "$pkgdir/usr/share/applications/$_pkgname.desktop"
  cp -a root/usr/share/icons "$pkgdir/usr/share/icons"
  install -Dm644 root/usr/share/doc/$_pkgname/changelog.gz "$pkgdir/usr/share/doc/$_pkgname/changelog.gz"

  # /usr/bin/harness-studio is the command-line launcher (as in the deb's postinst).
  install -d "$pkgdir/usr/bin"
  ln -s '/opt/Harness Studio/resources/runtime/cli/bin/dsh' "$pkgdir/usr/bin/$_pkgname"

  # Electron's chrome-sandbox: plain 0755 where user namespaces work (Arch's default kernel).
  # The .install hook switches it to setuid when they do not (linux-hardened).
  chmod 0755 "$pkgdir/opt/Harness Studio/chrome-sandbox"

  install -Dm644 "$startdir/LICENSE" "$pkgdir/usr/share/licenses/$pkgname/LICENSE"
}
