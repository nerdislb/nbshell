import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import qs.Common
import qs.Services
import qs.Widgets
import "../Common/MenuLayout.js" as MenuLayout

// Anwendungsstarter und Befehlspalette in einem.
//
// Ein Vollbildfenster auf der obersten Ebene, das die Tastatur exklusiv
// bekommt, solange es offen ist -- anders liesse sich nicht tippen, waehrend
// darunter ein Fenster den Fokus haelt. Sichtbar ist davon nur der Kasten in
// der Mitte; die restliche Flaeche ist durchsichtig und schliesst beim Klick.
//
// Es gibt es nur einmal, nicht je Bildschirm: ein zweiter Starter auf dem
// zweiten Monitor waere ein zweites Eingabefeld mit eigenem Zustand.
//
// Gesucht wird in beidem gleichzeitig: Anwendungen UND alles, was die Shell
// selbst kann (siehe Services/Commands.qml). Ein fuehrendes ">" schraenkt auf
// die Befehle ein, ein "!" auf die Anwendungen. Sortiert wird nach Punkten,
// nicht nach Herkunft -- wer "gruv" tippt, will das Theme, wer "fire" tippt,
// den Browser, und keiner von beiden will erst durch die andere Liste.
PanelWindow {
    id: root

    // Anwendungen tragen ihren Namen im Namen; Befehle bekommen einen kleinen
    // Abschlag, damit bei gleichem Treffer die Anwendung vorn steht. Sie ist
    // das, wofuer der Starter urspruenglich da war.
    readonly property real commandBias: 0.9
    readonly property bool closing: box.closing

    readonly property string mode: {
        const t = input.text;
        if (t.startsWith(">"))
            return "cmd";
        if (t.startsWith("!"))
            return "app";
        if (t.startsWith("#"))
            return "window";
        if (t.startsWith("^"))
            return "clipboard";
        if (t.startsWith("="))
            return "calculator";
        if (t.startsWith("@"))
            return "file";
        return "all";
    }

    readonly property string query: root.mode === "all" ? input.text : input.text.substring(1).trim()

    // The explicit property reads keep this binding reactive when an
    // asynchronous provider completes after the text itself stopped changing.
    readonly property var results: {
        const q = root.query;
        if (root.mode === "cmd")
            return Commands.rank(q).map(x => x.entry);
        if (root.mode === "app")
            return Apps.rank(q).map(x => x.entry);
        if (root.mode === "window")
            return SearchProviders.rankWindows(q).map(x => x.entry);
        if (root.mode === "clipboard")
            return SearchProviders.rankClipboard(q).map(x => x.entry);
        if (root.mode === "calculator")
            return SearchProviders.calculator(q).map(x => x.entry);
        if (root.mode === "file") {
            // Late file results must not rebuild unrelated modes or disturb
            // their keyboard/pointer selection and pending confirmations.
            const fileRevision = SearchProviders.files;
            return SearchProviders.fileRows(q).map(x => x.entry);
        }

        const apps = Apps.rank(q);
        const cmds = Commands.rank(q);
        const windows = SearchProviders.rankWindows(q);
        const calculator = SearchProviders.calculator(q);

        // Ohne Eingabe gibt es nichts zu vergleichen -- dann stehen die
        // Anwendungen nach Haeufigkeit oben und die Befehle darunter.
        if (!q)
            return apps.map(x => x.entry).concat(cmds.map(x => x.entry));

        const merged = apps.concat(cmds.map(x => ({
                    "entry": x.entry,
                    "points": x.points * root.commandBias
                }))).concat(windows).concat(calculator);
        merged.sort((a, b) => b.points - a.points || a.entry.name.localeCompare(b.entry.name));
        return merged.map(x => x.entry);
    }

    // Share the menu geometry; pin its top after the first edit.
    property int selected: 0
    property real pinnedTop: -1
    property real maxRowsHeight: -1
    property var pointerPosition: null
    readonly property bool showDetails: root.query !== ""
    readonly property var rowHeights: results.length ? results.map(e => showDetails && (e.genericName || e.comment) ? Theme.menuDetailRowHeight : Theme.menuBaseRowHeight) : [Theme.menuBaseRowHeight]
    readonly property real rowsHeight: MenuLayout.foldedHeight(rowHeights, Theme.menuRowSpacing, Math.min(root.height * 0.7, maxRowsHeight >= 0 ? maxRowsHeight : root.height, root.height - (pinnedTop >= 0 ? pinnedTop : Theme.menuScreenMargin) - Theme.menuScreenMargin - Theme.menuInset * 2 - Theme.menuHeaderHeight - Theme.menuGap - footer.height))
    onResultsChanged: {
        selected = Math.min(selected, Math.max(0, results.length - 1));
        pointerPosition = null;
    }
    function freezePosition() {
        if (visible && pinnedTop < 0) { pinnedTop = box.y; maxRowsHeight = list.height; }
        pointerPosition = null;
    }
    function pointTo(index, item, mouse) {
        const point = item.mapToItem(root.contentItem, mouse.x, mouse.y);
        if (MenuLayout.moved(pointerPosition, point)) {
            if (selected !== index) pending = null;
            selected = index;
        }
        if (pointerPosition === null || MenuLayout.moved(pointerPosition, point)) pointerPosition = point;
    }

    // Was sich nicht zurueckdrehen laesst (Ausschalten, Abmelden), verlangt
    // ein zweites Enter. In einer Suchpalette liegt sonst der Feierabend einen
    // Tippfehler entfernt.
    property var pending: null

    // Das Fenster bleibt bestehen und wird nur ein- und ausgeblendet: so ist
    // die Liste beim naechsten Oeffnen sofort da.
    visible: Runtime.launcherOpen

    screen: Compositor.focusedScreen
    color: "transparent"

    WlrLayershell.namespace: "nbshell:launcher"
    WlrLayershell.layer: WlrLayershell.Overlay
    WlrLayershell.keyboardFocus: Runtime.launcherOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    anchors.left: true
    anchors.right: true
    anchors.top: true
    anchors.bottom: true

    function close() {
        box.dismiss(() => Runtime.launcherOpen = false);
    }
    function open() {
        const wasClosing = box.closing;
        Runtime.launcherOpen = true;
        if (wasClosing) box.enter();
    }

    Component.onCompleted: Runtime.launcherController = root
    Component.onDestruction: if (Runtime.launcherController === root) Runtime.launcherController = null

    function accept() {
        const entry = results[selected];
        if (!entry) {
            // Nichts getroffen: die Eingabe war offenbar ein Befehl fuer die
            // Shell darunter, kein Suchbegriff.
            Apps.run(root.mode === "all" ? input.text : root.query);
            close();
            return;
        }

        if (entry.kind === "cmd") {
            if (entry.confirm && root.pending !== entry) {
                root.pending = entry;
                return;
            }
            Commands.invoke(entry);
        } else if (entry.kind === "app" || entry.command) {
            Apps.launch(entry);
        } else {
            SearchProviders.activate(entry);
        }
        close();
    }

    function move(delta) {
        if (results.length === 0)
            return;
        root.pending = null;
        pointerPosition = null;
        selected = MenuLayout.nextIndex(selected, delta, results.length);
        list.positionViewAtIndex(selected, ListView.Contain);
    }

    onVisibleChanged: {
        if (visible) {
            box.enter();
            root.pinnedTop = -1; root.maxRowsHeight = -1; root.pointerPosition = null;
            input.text = Runtime.launcherPrefill;
            root.pinnedTop = -1; root.maxRowsHeight = -1;
            input.cursorPosition = input.text.length;
            selected = 0;
            list.positionViewAtBeginning();
            pending = null;
            input.forceActiveFocus();
        } else {
            // Der Praefix gilt fuer EIN Oeffnen. Bliebe er stehen, kaeme der
            // Starter beim naechsten Mal wieder als Palette hoch, ohne dass
            // jemand danach gefragt haette.
            Runtime.launcherPrefill = "";
        }
    }

    Connections {
        target: Runtime
        function onLauncherPrefillChanged() {
            if (!root.visible || Runtime.launcherPrefill === input.text)
                return;
            input.text = Runtime.launcherPrefill;
            input.cursorPosition = input.text.length;
            root.selected = 0;
            input.forceActiveFocus();
        }
    }

    Rectangle { anchors.fill: parent; color: Theme.menuScrim; opacity: box.opacity }

    // Klick daneben schliesst.
    MouseArea {
        anchors.fill: parent
        onClicked: root.close()
    }

    MotionSurface {
        id: box
        motionEnabled: false
        anchors.horizontalCenter: parent.horizontalCenter
        y: Math.max(Theme.menuScreenMargin, Math.min(root.pinnedTop >= 0 ? root.pinnedTop : Math.round((parent.height - height) / 2), parent.height - height - Theme.menuScreenMargin))
        width: Math.max(1, Math.min(Theme.menuWidth, parent.width - Theme.menuScreenMargin * 2))
        height: Math.max(1, Math.min(Theme.menuInset * 2 + Theme.menuHeaderHeight + Theme.menuGap + root.rowsHeight + footer.height, parent.height - Theme.menuScreenMargin * 2))
        color: Theme.bg
        border.width: Theme.menuBorderWidth
        border.color: Theme.fg
        clip: true
        MouseArea { anchors.fill: parent }

        TextField {
            id: input
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: Theme.menuInset
            height: Theme.menuHeaderHeight
            color: Theme.fg
            font.family: Theme.fontFamily
            font.pixelSize: Theme.menuFontSize
            background: null
            horizontalPadding: 0
            accessibleName: "Search applications and commands"
            accessibleDescription: "Prefixes: > commands, ! applications, # windows, ^ clipboard, @ files, = calculator"
            focus: true
            selectByMouse: true
            placeholderText: "Apps…"
            placeholderTextColor: Theme.alpha(Theme.fg, 0.58)
            selectionColor: Theme.menuSelection
            selectedTextColor: Theme.menuSelectedText
            onTextChanged: {
                root.freezePosition();
                root.selected = 0;
                root.pending = null;
                list.positionViewAtBeginning();
                const typed = input.text;
                Qt.callLater(() => {
                    if (input.text === typed && typed.startsWith("@")) SearchProviders.requestFiles(typed.substring(1));
                });
            }
            Keys.onEscapePressed: {
                if (root.pending) root.pending = null;
                else if (input.text) input.clear();
                else root.close();
            }
            Keys.onReturnPressed: root.accept()
            Keys.onEnterPressed: root.accept()
            Keys.onUpPressed: root.move(-1)
            Keys.onDownPressed: root.move(1)
            Keys.onPressed: event => {
                if (event.key === Qt.Key_PageUp || event.key === Qt.Key_PageDown) {
                    root.move(event.key === Qt.Key_PageUp ? -6 : 6); event.accepted = true;
                } else if (event.modifiers & Qt.ControlModifier) {
                    if (event.key === Qt.Key_N || event.key === Qt.Key_P) {
                        root.move(event.key === Qt.Key_N ? 1 : -1); event.accepted = true;
                    }
                }
            }
        }

        ListView {
            id: list
            anchors.top: input.bottom
            anchors.topMargin: Theme.menuGap
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: Theme.menuInset
            anchors.rightMargin: Theme.menuInset
            height: root.rowsHeight
            spacing: Theme.menuRowSpacing
            clip: true
            model: root.visible ? root.results : []
            currentIndex: root.selected
            boundsBehavior: Flickable.StopAtBounds
            onHeightChanged: if (currentIndex >= 0) Qt.callLater(() => list.positionViewAtIndex(currentIndex, ListView.Contain))
            delegate: InteractiveSurface {
                id: row
                required property var modelData
                required property int index
                readonly property bool active: index === root.selected
                readonly property string detail: modelData.genericName || modelData.comment || ""
                width: list.width
                height: root.showDetails && detail ? Theme.menuDetailRowHeight : Theme.menuBaseRowHeight
                radius: Theme.radius
                color: active ? Theme.menuSelection : "transparent"
                keyboardFocusable: false
                accessibleName: modelData.name || "Search result"
                accessibleDescription: [detail, modelData.category || modelData.kind || ""].filter(Boolean).join("; ")
                accessibleSelected: active
                onTriggered: { root.selected = index; root.accept(); }
                Item {
                    id: appIcon
                    anchors.left: parent.left
                    anchors.leftMargin: Theme.menuRowInset
                    width: Theme.menuIconSlot
                    height: Theme.menuIconSize
                    y: rowText.y + (labelText.height - height) / 2
                    readonly property bool isCommand: row.modelData.kind === "cmd"
                    readonly property bool isApp: row.modelData.kind === "app" || !!row.modelData.command
                    readonly property string iconSource: isApp ? Apps.iconFor(row.modelData) : ""
                    IconImage {
                        anchors.centerIn: parent
                        width: Theme.menuIconSize; height: width
                        visible: appIcon.iconSource !== ""
                        source: appIcon.iconSource
                    }
                    Line {
                        anchors.centerIn: parent
                        visible: appIcon.iconSource === ""
                        text: appIcon.isCommand ? ">" : row.modelData.kind === "window" ? "#"
                            : row.modelData.kind === "clipboard" ? "^" : row.modelData.kind === "calculator" ? "="
                            : row.modelData.kind === "file" ? "@" : (row.modelData.name || "?").charAt(0).toUpperCase()
                        color: row.active ? Theme.menuSelectedText : Theme.fg
                        font.pixelSize: Theme.menuIconSize
                    }
                }
                Column {
                    id: rowText
                    anchors.left: appIcon.right
                    anchors.leftMargin: Theme.menuGap
                    anchors.right: parent.right
                    anchors.rightMargin: Theme.menuRowInset + Theme.menuTrailWidth + Theme.menuGap
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.menuRowSpacing
                    Line {
                        id: labelText
                        width: parent.width; text: row.modelData.name
                        color: row.active ? Theme.menuSelectedText : Theme.fg
                        font.pixelSize: Theme.menuFontSize; font.weight: Font.Medium
                        elide: Text.ElideRight
                    }
                    Line {
                        width: parent.width; visible: root.showDetails && row.detail !== ""
                        text: row.detail; color: Theme.fg; opacity: 0.52
                        font.pixelSize: Theme.menuDetailFontSize; elide: Text.ElideRight
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: root.pointTo(row.index, row, {x: mouseX, y: mouseY})
                    onPositionChanged: mouse => root.pointTo(row.index, row, mouse)
                    onClicked: row.activate()
                }
            }
            Line {
                parent: list
                anchors.fill: parent
                visible: root.results.length === 0
                text: "No results"
                color: Theme.fg; opacity: 0.58
                font.pixelSize: Theme.menuFontSize
                verticalAlignment: Text.AlignVCenter
            }
        }

        // Keep the extra command execution/confirmation behavior, but show its
        // explanation only when relevant, not as permanent launcher chrome.
        Item {
            id: footer
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: Theme.menuInset
            height: visible ? footerText.implicitHeight + Theme.menuGap : 0
            visible: !!root.pending || (root.results.length === 0 && input.text !== "")
            Line {
                id: footerText
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                wrapMode: Text.Wrap
                maximumLineCount: 3
                elide: Text.ElideRight
                text: root.pending
                    ? "\"" + root.pending.name + "\" — Enter again confirms, Esc cancels"
                    : "Enter runs \"" + root.query + "\" as a command"
                color: root.pending ? Theme.readable(Theme.red, Theme.bg, 4.5) : Theme.fgDim
                font.pixelSize: Theme.menuDetailFontSize
            }
        }
    }
}
