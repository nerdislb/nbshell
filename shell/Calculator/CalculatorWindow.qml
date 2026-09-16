import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Common
import qs.Services
import qs.Widgets

FloatingWindow {
    id: root

    property string expression: "0"
    property string previous: ""
    property string result: "0"
    property bool evaluated: false
    property bool invalid: false

    visible: Runtime.calculatorOpen
    title: "nbshell Calculator"
    color: Theme.bg
    // Native resizable tool, adapted to the approved Omarchy panel language.
    // Unlike a summoned menu it remains a normal compositor-managed window.
    readonly property real availableWidth: Math.max(1, (screen?.width || 800) - Theme.spaceXl * 2)
    readonly property real availableHeight: Math.max(1, (screen?.height || 600) - Theme.spaceXl * 2 - Theme.barHeight)
    implicitWidth: Math.min(Math.round(Theme.cellW * 48), availableWidth)
    implicitHeight: Math.min(Math.round(Theme.cellH * 26), availableHeight)
    minimumSize: Qt.size(Math.min(Math.round(Theme.cellW * 32), availableWidth), Math.min(Math.round(Theme.cellH * 22), availableHeight))

    function preview() {
        try {
            result = CalculatorEngine.evaluate(expression);
            invalid = false;
        } catch (error) {
            // Move focus before disabling Copy; a disabled control loses focus
            // before an onInvalidChanged handler can recover it reliably.
            if (copyLabel.activeFocus)
                input.forceActiveFocus();
            invalid = true;
        }
    }

    function clearAll() {
        expression = "0";
        previous = "";
        result = "0";
        evaluated = false;
        invalid = false;
    }

    function append(value) {
        const operators = "+−×÷";
        if (evaluated) {
            expression = operators.indexOf(value) >= 0 ? result + value : "";
            evaluated = false;
        }
        if (expression === "0" && /[0-9.(]/.test(value))
            expression = "";
        if (operators.indexOf(value) >= 0 && operators.indexOf(expression.slice(-1)) >= 0)
            expression = expression.slice(0, -1);
        expression += value;
        preview();
    }

    function backspace() {
        if (evaluated) {
            clearAll();
            return;
        }
        expression = expression.length > 1 ? expression.slice(0, -1) : "0";
        preview();
    }

    function toggleSign() {
        expression = expression === "0" ? "0" : "-(" + expression + ")";
        evaluated = false;
        preview();
    }

    function equals() {
        preview();
        if (invalid)
            return;
        previous = expression + " =";
        expression = result;
        evaluated = true;
    }

    function copyResult() {
        if (invalid)
            return;
        Quickshell.execDetached(["wl-copy", "--", result]);
        previous = "Result copied";
    }

    function keyName(action, label) {
        const names = {
            "clear": "Clear",
            "sign": "Toggle sign",
            "equals": "Equals",
            "÷": "Divide",
            "×": "Multiply",
            "−": "Subtract",
            "+": "Add",
            ".": "Decimal point"
        };
        return names[action] || label;
    }

    function activate(action) {
        switch (action) {
        case "clear":
            clearAll();
            break;
        case "backspace":
            backspace();
            break;
        case "sign":
            toggleSign();
            break;
        case "equals":
            equals();
            break;
        default:
            append(action);
            break;
        }
    }

    onExpressionChanged: Qt.callLater(display.revealResult)

    onClosed: Runtime.calculatorOpen = false
    onVisibleChanged: if (visible)
        input.forceActiveFocus()

    FocusScope {
        id: keys
        anchors.fill: parent
        focus: root.visible

        // A leaf focus target clears the previously focused keypad control.
        Item {
            id: input
            focus: true
        }

        Keys.onPressed: event => {
            if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_C) {
                root.copyResult();
                event.accepted = true;
                return;
            }
            if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_L) {
                root.clearAll();
                event.accepted = true;
                return;
            }
            if (event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))
                return;
            if (event.key === Qt.Key_PageUp || event.key === Qt.Key_PageDown) {
                display.contentY = Math.max(0, Math.min(display.contentHeight - display.height, display.contentY + (event.key === Qt.Key_PageUp ? -display.height : display.height)));
                event.accepted = true;
                return;
            }
            if (event.key === Qt.Key_Escape) {
                Runtime.calculatorOpen = false;
                event.accepted = true;
                return;
            }
            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.text === "=") {
                root.equals();
                event.accepted = true;
                return;
            }
            if (event.key === Qt.Key_Backspace) {
                root.backspace();
                event.accepted = true;
                return;
            }
            if (event.key === Qt.Key_Delete) {
                root.clearAll();
                event.accepted = true;
                return;
            }
            const text = event.text;
            if (/^[0-9()+\-*/%.,]$/.test(text)) {
                root.append(text === "*" ? "×" : text === "/" ? "÷" : text === "-" ? "−" : text === "," ? "." : text);
                event.accepted = true;
            }
        }

        PanelSurface {
            id: panel
            anchors.fill: parent
            color: Theme.bg
            border.width: Theme.menuBorderWidth
            border.color: Theme.fg

            Column {
                anchors.fill: parent
                anchors.margins: Theme.menuInset
                spacing: Theme.spaceLg

                Row {
                    id: header
                    width: parent.width
                    height: Theme.controlHeight
                    Line {
                        text: "Calculator"
                        width: parent.width - copyLabel.width
                        height: parent.height
                        verticalAlignment: Text.AlignVCenter
                        font.pixelSize: Theme.menuFontSize
                        elide: Text.ElideRight
                    }
                    ControlButton {
                        id: copyLabel
                        text: "Copy"
                        enabled: !root.invalid
                        accessibleName: "Copy result"
                        accessibleDescription: "Copy result to the clipboard (Ctrl+C)"
                        pointerFocusTarget: input
                        onTriggered: root.copyResult()
                    }
                }

                Flickable {
                    id: display
                    width: parent.width
                    height: Theme.cellH * 6
                    contentWidth: width
                    contentHeight: displayContent.height
                    function revealResult() {
                        contentY = Math.max(0, contentHeight - height);
                    }
                    onContentHeightChanged: Qt.callLater(revealResult)
                    onHeightChanged: Qt.callLater(revealResult)
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    flickableDirection: Flickable.VerticalFlick
                    ScrollBar.vertical: ScrollBar {
                        policy: ScrollBar.AsNeeded
                    }

                    Column {
                        id: displayContent
                        width: parent.width - Theme.spaceMd
                        spacing: Theme.spaceSm
                        Line {
                            width: parent.width
                            text: root.previous || "Type an expression"
                            color: Theme.fgDim
                            horizontalAlignment: Text.AlignRight
                            elide: Text.ElideLeft
                        }
                        Line {
                            id: expressionLabel
                            width: parent.width
                            text: root.expression
                            font.pixelSize: Theme.menuFontSize
                            horizontalAlignment: Text.AlignRight
                            wrapMode: Text.WrapAnywhere
                            Accessible.role: Accessible.StaticText
                            Accessible.name: text
                        }
                        Line {
                            id: resultLabel
                            width: parent.width
                            text: root.invalid ? "Invalid expression" : root.result
                            color: root.invalid ? Theme.readable(Theme.red, Theme.bg, 4.5) : Theme.readable(Theme.accent, Theme.bg, 4.5)
                            font.pixelSize: root.invalid ? Theme.fontBody : Theme.fontHeading
                            horizontalAlignment: Text.AlignRight
                            wrapMode: Text.WrapAnywhere
                            Accessible.role: Accessible.StaticText
                            Accessible.name: text
                        }
                    }
                }

                Rule {
                    id: separator
                    rowWidth: parent.width
                    lead: 0
                }

                Grid {
                    id: keypad
                    width: parent.width
                    height: parent.height - header.height - display.height - separator.height - footer.height - parent.spacing * 4
                    columns: 4
                    spacing: Theme.menuRowSpacing

                    Repeater {
                        id: buttons
                        model: [
                            {
                                label: "C",
                                action: "clear"
                            },
                            {
                                label: "(",
                                action: "("
                            },
                            {
                                label: ")",
                                action: ")"
                            },
                            {
                                label: "÷",
                                action: "÷"
                            },
                            {
                                label: "7",
                                action: "7"
                            },
                            {
                                label: "8",
                                action: "8"
                            },
                            {
                                label: "9",
                                action: "9"
                            },
                            {
                                label: "×",
                                action: "×"
                            },
                            {
                                label: "4",
                                action: "4"
                            },
                            {
                                label: "5",
                                action: "5"
                            },
                            {
                                label: "6",
                                action: "6"
                            },
                            {
                                label: "−",
                                action: "−"
                            },
                            {
                                label: "1",
                                action: "1"
                            },
                            {
                                label: "2",
                                action: "2"
                            },
                            {
                                label: "3",
                                action: "3"
                            },
                            {
                                label: "+",
                                action: "+"
                            },
                            {
                                label: "±",
                                action: "sign"
                            },
                            {
                                label: "0",
                                action: "0"
                            },
                            {
                                label: ".",
                                action: "."
                            },
                            {
                                label: "=",
                                action: "equals"
                            }
                        ]

                        ControlButton {
                            required property var modelData
                            width: (keypad.width - keypad.spacing * 3) / 4
                            height: (keypad.height - keypad.spacing * 4) / 5
                            text: modelData.label
                            pointerFocusTarget: input
                            textColor: modelData.action === "equals" ? Theme.readable(Theme.accent, color, 4.5) : Theme.fg
                            color: keyHover.hovered || visualFocus || accessiblePressed ? Theme.menuSelection : Theme.bg
                            HoverHandler {
                                id: keyHover
                            }
                            border.width: visualFocus ? Theme.menuBorderWidth : 0
                            border.color: Theme.focusBorder
                            accessibleName: root.keyName(modelData.action, modelData.label)
                            onTriggered: root.activate(modelData.action)
                        }
                    }
                }

                Line {
                    id: footer
                    width: parent.width
                    text: (input.activeFocus ? "Enter result · Tab keys" : "Space / Enter key · Tab next") + "\nCtrl+C copy · Esc close"
                    color: Theme.fgDim
                    horizontalAlignment: Text.AlignRight
                    font.pixelSize: Theme.fontCaption
                    wrapMode: Text.WordWrap
                }
            }
        }
    }
}
