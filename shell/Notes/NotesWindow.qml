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
        editor.forceActiveFocus();
    }

    function editNote(note) {
        if (!note) return;
        editingId = String(note.id);
        baseline = String(note.text);
        editor.text = baseline;
        confirmDiscard = false;
        editor.forceActiveFocus();
    }

    function saveAndClose() {
        if (editor.text.trim() !== "") Notes.saveText(editingId, editor.text);
        Runtime.notesOpen = false;
    }

    function requestClose() {
        if (dirty && !confirmDiscard) {
            confirmDiscard = true;
            return;
        }
        Runtime.notesOpen = false;
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
    Shortcut { sequence: "Ctrl+N"; onActivated: root.newNote() }

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
                        Line {
                            id: addButton
                            text: "+ NEW"
                            color: Theme.fg
                            MouseArea { anchors.fill: parent; anchors.margins: -Theme.spaceSm; cursorShape: Qt.PointingHandCursor; onClicked: root.newNote() }
                        }
                    }

                    ListView {
                        id: noteList
                        width: parent.width
                        height: parent.height - Theme.cellH * 3
                        clip: true
                        model: Notes.list
                        spacing: Theme.spaceXs
                        delegate: Rectangle {
                            required property var modelData
                            width: noteList.width
                            height: Theme.rowHeight
                            radius: Theme.radius
                            color: String(root.editingId) === String(modelData.id) ? Theme.selectedSurface() : "transparent"
                            Column {
                                anchors.left: parent.left; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                                anchors.margins: Theme.spaceSm
                                Line { width: parent.width; text: modelData.title; color: Theme.fg; elide: Text.ElideRight }
                                Line { width: parent.width; text: Qt.formatDateTime(new Date(modelData.updated), "dd.MM.  HH:mm"); color: Theme.muted; font.pixelSize: Theme.fontCaption }
                            }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.editNote(modelData) }
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
                        Line {
                            id: removeButton
                            visible: root.editingId !== ""
                            text: "DELETE"
                            color: Theme.red
                            MouseArea {
                                anchors.fill: parent; anchors.margins: -Theme.spaceSm; cursorShape: Qt.PointingHandCursor
                                onClicked: { Notes.remove(root.editingId); root.newNote(); }
                            }
                        }
                    }

                    ScrollView {
                        width: parent.width
                        height: parent.height - Theme.cellH * 4
                        clip: true
                        TextArea {
                            id: editor
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
                            onTextChanged: if (root.confirmDiscard) root.confirmDiscard = false
                        }
                    }

                    Line {
                        width: parent.width
                        text: root.confirmDiscard ? "Unsaved changes — press Esc again to discard" : "Alt+S save & close  ·  Esc close  ·  Ctrl+N new"
                        color: root.confirmDiscard ? Theme.yellow : Theme.muted
                        horizontalAlignment: Text.AlignRight
                    }
                }
            }
        }
    }
}
