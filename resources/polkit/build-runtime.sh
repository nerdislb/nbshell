#!/usr/bin/env bash
set -euo pipefail
stage="${1:?Usage: build-runtime.sh /absolute/staging-directory}"
artifacts="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
mkdir -p "$stage"
git clone --depth 1 --branch v0.3.1 https://github.com/quickshell-mirror/quickshell.git "$stage/quickshell-src"
test "$(git -C "$stage/quickshell-src" rev-parse HEAD)" = 1a4716cde794a59928d9d9fc15f2afc7a95de360
git -C "$stage/quickshell-src" apply "$artifacts/polkit-queue.patch"
git clone --depth 1 --branch v2.5.0 https://github.com/CLIUtils/CLI11.git "$stage/CLI11"
test "$(git -C "$stage/CLI11" rev-parse HEAD)" = 4160d259d961cd393fd8d67590a8c7d210207348
cmake -S "$stage/CLI11" -B "$stage/CLI11/build" -DCLI11_BUILD_TESTS=OFF -DCLI11_BUILD_EXAMPLES=OFF -DCMAKE_INSTALL_PREFIX="$stage/deps"
cmake --install "$stage/CLI11/build"
cmake -S "$stage/quickshell-src" -B "$stage/quickshell-src/build" -G Ninja \
 -DCMAKE_BUILD_TYPE=Release -DDISTRIBUTOR=nbshell-polkit-trial \
 -DCMAKE_PREFIX_PATH="$stage/deps" -DCRASH_HANDLER=OFF -DX11=OFF -DI3=OFF \
 -DHYPRLAND=OFF -DSCREENCOPY=OFF -DSCREENCOPY_ICC=OFF -DSCREENCOPY_WLR=OFF \
 -DSCREENCOPY_HYPRLAND_TOPLEVEL=OFF -DWAYLAND_SESSION_LOCK=OFF \
 -DWAYLAND_TOPLEVEL_MANAGEMENT=OFF -DSERVICE_STATUS_NOTIFIER=OFF \
 -DSERVICE_PIPEWIRE=OFF -DSERVICE_MPRIS=OFF -DSERVICE_PAM=OFF \
 -DSERVICE_GREETD=OFF -DSERVICE_UPOWER=OFF -DSERVICE_NOTIFICATIONS=OFF \
 -DBLUETOOTH=OFF -DNETWORK=OFF
cmake --build "$stage/quickshell-src/build" -j 4
