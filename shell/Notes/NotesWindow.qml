import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Common
import qs.Services
import qs.Widgets

FloatingWindow {
    id: root

    property string editingId: ""
    property string baseline: ""
    property bool confirmDiscard: false
    property bool confirmDelete: false
    property string pendingNavigation: ""
    readonly property bool dirty: editor.text !== baseline

    visible: Runtime.notesOpen
    title: "nbshell Notes"
    color: Theme.bg
    implicitWidth: Math.round(Theme.cellW * 96)
    implicitHeight: Math.round(Theme.cellH * 38)
    minimumSize: Qt.size(Math.round(Theme.cellW * 68), Math.round(Theme.cellH * 25))

    function newNote() {
        editingId = "";
        baseline = "";
        editor.text = "";
        confirmDiscard = false;
        pendingNavigation = "";
        discardConfirmationTimer.stop();
        confirmDelete = false;
        deleteConfirmationTimer.stop();
        editor.forceActiveFocus();
    }

    function editNote(note) {
        if (!note) return;
        editingId = String(note.id);
        baseline = String(note.text);
        editor.text = baseline;
        confirmDiscard = false;
        pendingNavigation = "";
        discardConfirmationTimer.stop();
        confirmDelete = false;
        deleteConfirmationTimer.stop();
        editor.forceActiveFocus();
    }

    function saveAndClose() {
        if (editor.text.trim() !== "") Notes.saveText(editingId, editor.text);
        Runtime.notesOpen = false;
    }

    function armDiscardConfirmation(key) {
        confirmDiscard = true;
        pendingNavigation = key;
        discardConfirmationTimer.restart();
    }

    function clearDiscardConfirmation() {
        confirmDiscard = false;
        pendingNavigation = "";
        discardConfirmationTimer.stop();
    }

    function requestNewNote() {
        if (dirty && pendingNavigation !== "new") {
            armDiscardConfirmation("new");
            return;
        }
        newNote();
    }

    function requestEditNote(note) {
        if (!note)
            return;
        if (String(note.id) === editingId) {
            editor.forceActiveFocus();
            return;
        }
        const key = "note:" + String(note.id);
        if (dirty && pendingNavigation !== key) {
            armDiscardConfirmation(key);
            return;
        }
        editNote(note);
    }

    function requestClose() {
        if (dirty && pendingNavigation !== "close") {
            armDiscardConfirmation("close");
            return;
        }
        Runtime.notesOpen = false;
    }

    function requestDelete() {
        if (editingId === "")
            return;
        if (!confirmDelete) {
            confirmDelete = true;
            deleteConfirmationTimer.restart();
            return;
        }
        deleteConfirmationTimer.stop();
        Notes.remove(editingId);
        newNote();
    }

    onVisibleChanged: {
        if (!visible) return;
        Notes.foldConflicts();
        const requested = Runtime.notesRequestedId !== "" ? Notes.find(Runtime.notesRequestedId) : null;
        Runtime.notesRequestedId = "";
        if (requested) editNote(requested); else newNote();
    }
    onClosed: requestClose()

    Shortcut { sequence: "Alt+S"; onActivated: root.saveAndClose() }
    Shortcut { sequence: "Escape"; onActivated: root.requestClose() }
    Shortcut { sequence: "Ctrl+N"; onActivated: root.requestNewNote() }
    Timer { id: discardConfirmationTimer; interval: 5000; onTriggered: root.clearDiscardConfirmation() }
    Timer { id: deleteConfirmationTimer; interval: 5000; onTriggered: root.confirmDelete = false }

    Rectangle {
        anchors.fill: parent
        color: Theme.bg
        border.width: Math.max(1, Theme.borderWidth)
        border.color: Theme.focusBorder
        radius: Theme.radius

        Row {
            anchors.fill: parent
            anchors.margins: Theme.borderWidth + 1
            spacing: 0

            Rectangle {
                width: Math.round(parent.width * 0.28)
                height: parent.height
                color: Theme.bgDarker

                Column {
                    anchors.fill: parent
                    anchors.margins: Theme.spaceLg
                    spacing: Theme.spaceMd

                    Row {
                        width: parent.width
                        Line { text: "NOTES"; color: Theme.accent; width: parent.width - addButton.width }
                        ActionButton {
                            id: addButton
                            text: root.pendingNavigation === "new" ? "CONFIRM NEW" : "NEW"
                            compact: true
                            accessibleDescription: "Create a new note"
                            onTriggered: root.requestNewNote()
                        }
                    }

                    ListView {
                        id: noteList
                        width: parent.width
                        height: parent.height - Theme.cellH * 3
                        clip: true
                        model: Notes.list
                        spacing: Theme.spaceXs
                        delegate: InteractiveSurface {
                            id: noteRow
                            required property var modelData
                            required property int index
                            accessibleName: modelData.title
                            accessibleDescription: "Updated " + Qt.formatDateTime(new Date(modelData.updated), "dd.MM.  HH:mm")
                            accessibleSelected: String(root.editingId) === String(modelData.id)
                            width: noteList.width
                            height: Theme.rowHeight
                            radius: Theme.radius
                            color: String(root.editingId) === String(modelData.id) ? Theme.selectedSurface() : (visualFocus ? Theme.hover : "transparent")
                            border.width: visualFocus ? Theme.borderWidth : 0
                            border.color: Theme.focusBorder
                            onTriggered: root.requestEditNote(modelData)
                            onActiveFocusChanged: if (activeFocus) noteList.positionViewAtIndex(index, ListView.Contain)
                            Column {
                                anchors.left: parent.left; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                                anchors.margins: Theme.spaceSm
                                Line { width: parent.width; text: modelData.title; color: Theme.fg; elide: Text.ElideRight }
                                Line { width: parent.width; text: Qt.formatDateTime(new Date(modelData.updated), "dd.MM.  HH:mm"); color: Theme.muted; font.pixelSize: Theme.fontCaption }
                            }
                            HoverHandler { cursorShape: Qt.PointingHandCursor }
                            TapHandler {
                                onTapped: {
                                    noteRow.forceActiveFocus(Qt.MouseFocusReason);
                                    noteRow.activate();
                                }
                            }
                        }
                    }
                }
            }

            Rectangle { width: Theme.borderWidth; height: parent.height; color: Theme.panelBorder }

            Item {
                width: parent.width - Math.round(parent.width * 0.28) - Theme.borderWidth
                height: parent.height

                Column {
                    anchors.fill: parent
                    anchors.margins: Theme.spaceXl
                    spacing: Theme.spaceMd

                    Row {
                        width: parent.width
                        Line { text: root.editingId === "" ? "NEW NOTE" : Notes.titleFor(editor.text); color: Theme.fgDim; width: parent.width - removeButton.width }
                        ActionButton {
                            id: removeButton
                            visible: root.editingId !== ""
                            text: root.confirmDelete ? "CONFIRM DELETE" : "DELETE"
                            tone: "danger"
                            compact: true
                            accessibleDescription: root.confirmDelete
                                ? "Permanently delete this note"
                                : "Ask before deleting this note"
                            onTriggered: root.requestDelete()
                        }
                    }

                    ScrollView {
                        width: parent.width
                        height: parent.height - Theme.cellH * 4
                        clip: true
                        TextArea {
                            id: editor
                            Accessible.role: Accessible.EditableText
                            Accessible.name: root.editingId === "" ? "New note" : "Note editor"
                            Accessible.description: "Alt+S saves and closes"
                            placeholderText: "Write a quick note…"
                            color: Theme.fg
                            placeholderTextColor: Theme.muted
                            selectionColor: Theme.selection
                            selectedTextColor: Theme.selectedForeground()
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontBody
                            wrapMode: TextEdit.Wrap
                            background: Rectangle { color: Theme.bg; radius: Theme.radius; border.width: Theme.borderWidth; border.color: editor.activeFocus ? Theme.focusBorder : Theme.panelBorder }
                            padding: Theme.spaceLg
                            onTextChanged: {
                                if (root.confirmDiscard) root.clearDiscardConfirmation();
                                if (root.confirmDelete) root.confirmDelete = false;
                            }
                        }
                    }

                    Line {
                        width: parent.width
                        text: root.confirmDiscard
                            ? "Unsaved changes — activate " + (root.pendingNavigation === "close" ? "close" : root.pendingNavigation === "new" ? "new note" : "the selected note") + " again to discard"
                            : "Alt+S save & close  ·  Esc close  ·  Ctrl+N new"
                        color: root.confirmDiscard ? Theme.yellow : Theme.muted
                        horizontalAlignment: Text.AlignRight
                    }
                }
            }
        }
    }
}
