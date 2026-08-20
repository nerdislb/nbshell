#!/usr/bin/env bash
set -euo pipefail

source_root=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$source_root"

command -v omarchy >/dev/null 2>&1 || {
  echo "test.sh: omarchy is required" >&2
  exit 1
}

omarchy plugin validate .

python3 "$source_root/backend/server.py" --self-test
python3 "$source_root/tests/test_catalog.py"
python3 "$source_root/tests/test_auth.py"
python3 "$source_root/tests/test_player.py"
python3 "$source_root/tests/test_protocol.py"

if command -v qmllint >/dev/null 2>&1; then
  qmllint -I /usr/share/omarchy/shell Api.js \
    ArtistLinks.qml MediaByline.qml MediaRow.qml MediaCollection.qml \
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
