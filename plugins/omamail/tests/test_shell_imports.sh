#!/usr/bin/env bash
# Compile the application and instantiate Settings with nbshell's real modules.
set -euo pipefail
plugin=$(cd "$(dirname "$0")/.." && pwd)
repo=$(cd "$plugin/../.." && pwd)
probe=$(mktemp -d /tmp/omamail-shell-imports.XXXXXX)
trap 'rm -rf "$probe"' EXIT
for module in Common Commons Ui Widgets; do
  ln -s "$repo/shell/$module" "$probe/$module"
done
ln -s "$plugin" "$probe/mail"
mkdir -p "$probe/config" "$probe/cache" "$probe/state"
cat > "$probe/shell.qml" <<'QML'
import QtQuick
import Quickshell
import qs.Common

ShellRoot {
  Component.onCompleted: {
    var compose = Qt.createComponent("file://" + Quickshell.env("OMAMAIL_IMPORT_TEST_PLUGIN") + "/components/ComposeView.qml")
    if (compose.status !== Component.Ready) throw new Error(compose.errorString())
    var app = Qt.createComponent("file://" + Quickshell.env("OMAMAIL_IMPORT_TEST_PLUGIN") + "/App.qml")
    if (app.status !== Component.Ready) throw new Error(app.errorString())
    var component = Qt.createComponent("file://" + Quickshell.env("OMAMAIL_IMPORT_TEST_PLUGIN") + "/components/SettingsPage.qml")
    if (component.status !== Component.Ready) throw new Error(component.errorString())
    var page = component.createObject(null, {
      service: null, calendarController: null,
      textColor: Theme.fg, dimColor: Theme.fgDim,
      accentColor: Theme.accent, urgentColor: Theme.red,
      panelFontFamily: Theme.fontFamily
    })
    if (!page) throw new Error(component.errorString())
    page.destroy()
    console.log("MAIL_REAL_IMPORTS_OK")
  }
}
QML
OMAMAIL_IMPORT_TEST_PLUGIN="$plugin" QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software \
  XDG_CONFIG_HOME="$probe/config" XDG_CACHE_HOME="$probe/cache" XDG_STATE_HOME="$probe/state" \
  timeout 3 qs -p "$probe" > "$probe/output" 2>&1 || {
    status=$?
    if [[ $status != 124 ]]; then cat "$probe/output"; exit "$status"; fi
  }
cat "$probe/output"
grep -q MAIL_REAL_IMPORTS_OK "$probe/output"
! grep -E 'TypeError|ReferenceError|Error:|is not a type' "$probe/output"
