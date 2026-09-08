#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf -- "$work"' EXIT
srcdir="$work/source"
pkgdir="$work/package"
mkdir -p "$srcdir/bin" "$srcdir/shell/scripts"
printf '#!/bin/sh\nexit 0\n' > "$srcdir/install.sh"
cp "$srcdir/install.sh" "$srcdir/bin/nbshell"
cp "$srcdir/install.sh" "$srcdir/bin/nbshell-install-recover"
printf 'pass\n' > "$srcdir/shell/scripts/helper.py"
chmod 700 "$srcdir/install.sh" "$srcdir/bin/"* "$srcdir/shell"
chmod 600 "$srcdir/shell/scripts/helper.py"
ln -s "$work/source-archive" "$srcdir/nbshell-src.tar.gz"
source "$root/pkgbuilds/nbshell/PKGBUILD"
package
test "$(stat -c %a "$pkgdir/usr/share/nbshell/install.sh")" = 755
test "$(stat -c %a "$pkgdir/usr/share/nbshell/bin/nbshell")" = 755
test "$(stat -c %a "$pkgdir/usr/share/nbshell/shell")" = 755
test "$(stat -c %a "$pkgdir/usr/share/nbshell/shell/scripts/helper.py")" = 644
test ! -L "$pkgdir/usr/share/nbshell/nbshell-src.tar.gz"
[[ " ${depends[*]} " == *' python '* ]]
echo 'Packaged runtime permissions and Python dependency: OK'
