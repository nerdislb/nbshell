#!/usr/bin/env bash
set -euo pipefail

source_root=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$source_root"

repo_root=$(CDPATH= cd -- "$source_root/../.." && pwd)
bash "$repo_root/shell/scripts/plugins.sh" validate "$source_root"

python3 "$source_root/backend/server.py" --self-test
python3 -m unittest discover -s "$source_root/tests" -p 'test_*.py' -v

if command -v qmllint >/dev/null 2>&1; then
  qmllint -I "$repo_root/shell" Api.js \
    ArtistLinks.qml Artwork.qml Chicklet.qml EqBar.qml MediaByline.qml \
    MediaRow.qml MediaCollection.qml RoundedField.qml SidebarItem.qml \
    PlaybackSlider.qml FastScrollHandler.qml LyricsInstallPrompt.qml \
    BackendClient.qml DaemonManager.qml Service.qml BarWidget.qml Panel.qml
fi

qml_test_runner=/usr/lib/qt6/bin/qmltestrunner
if [[ -x $qml_test_runner ]]; then
  QT_QPA_PLATFORM=offscreen "$qml_test_runner" \
    -input tests \
    -import "$source_root" \
    -o -,txt
fi

if command -v rg >/dev/null 2>&1; then
  if rg -n 'QtWebEngine|WebEngineView|WebView|node_modules|electron' \
    --glob '*.qml' --glob '*.js' --glob '*.sh' --glob '*.service' \
    --glob '!scripts/test.sh' .; then
    echo "test.sh: forbidden heavyweight runtime dependency found" >&2
    exit 1
  fi
fi

echo "All validation and tests passed."
