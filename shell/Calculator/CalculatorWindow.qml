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
    implicitWidth: Math.round(Theme.cellW * 48)
    implicitHeight: Math.round(Theme.cellH * 34)
    minimumSize: Qt.size(Math.round(Theme.cellW * 40), Math.round(Theme.cellH * 28))

    function preview() {
        try {
            result = CalculatorEngine.evaluate(expression);
            invalid = false;
        } catch (error) {
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
        if (expression === "0" && /[0-9.(]/.test(value)) expression = "";
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
        if (invalid) return;
        previous = expression + " =";
        expression = result;
        evaluated = true;
    }

    function copyResult() {
        if (invalid)
            return;
        Quickshell.execDetached(["wl-copy", result]);
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
        case "clear": clearAll(); break;
        case "backspace": backspace(); break;
        case "sign": toggleSign(); break;
        case "equals": equals(); break;
        default: append(action); break;
        }
    }

    onClosed: Runtime.calculatorOpen = false
    onVisibleChanged: if (visible) keys.forceActiveFocus()

    FocusScope {
        id: keys
        anchors.fill: parent
        focus: root.visible

        Keys.onPressed: event => {
            if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_C) {
                root.copyResult();
                event.accepted = true;
                return;
            }
            if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_L) {
                root.clearAll(); event.accepted = true; return;
            }
            if (event.key === Qt.Key_Escape) {
                Runtime.calculatorOpen = false; event.accepted = true; return;
            }
            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.text === "=") {
                root.equals(); event.accepted = true; return;
            }
            if (event.key === Qt.Key_Backspace) {
                root.backspace(); event.accepted = true; return;
            }
            if (event.key === Qt.Key_Delete) {
                root.clearAll(); event.accepted = true; return;
            }
            const text = event.text;
            if (/^[0-9()+\-*/%.,]$/.test(text)) {
                root.append(text === "*" ? "×" : text === "/" ? "÷" : text === "-" ? "−" : text === "," ? "." : text);
                event.accepted = true;
            }
        }

        Rectangle {
            anchors.fill: parent
            color: Theme.bg
            radius: Theme.radius
            border.width: Theme.borderWidth
            border.color: Theme.focusBorder

            Column {
                anchors.fill: parent
                anchors.margins: Theme.spaceXl
                spacing: Theme.spaceLg

                Row {
                    id: header
                    width: parent.width
                    Line { text: "CALCULATOR"; color: Theme.accent; font.bold: true; width: parent.width - copyLabel.width }
                    ActionButton {
                        id: copyLabel
                        text: "COPY"
                        compact: true
                        enabled: !root.invalid
                        accessibleDescription: "Copy result to the clipboard"
                        onTriggered: root.copyResult()
                    }
                }

                Rectangle {
                    id: display
                    width: parent.width
                    height: Theme.cellH * 7
                    color: Theme.bgDarker
                    radius: Theme.radius
                    border.width: Theme.borderWidth
                    border.color: root.invalid ? Theme.red : Theme.panelBorder

                    Column {
                        anchors.fill: parent
                        anchors.margins: Theme.spaceLg
                        spacing: Theme.spaceSm
                        Line { width: parent.width; text: root.previous || "TYPE AN EXPRESSION"; color: Theme.muted; horizontalAlignment: Text.AlignRight; elide: Text.ElideLeft }
                        Line { width: parent.width; text: root.expression; color: Theme.fg; font.pixelSize: Theme.fontTitle; horizontalAlignment: Text.AlignRight; elide: Text.ElideLeft }
                        Line { width: parent.width; text: root.invalid ? "INVALID" : root.result; color: root.invalid ? Theme.red : Theme.accent; font.pixelSize: Theme.fontDisplay; font.bold: true; horizontalAlignment: Text.AlignRight; elide: Text.ElideLeft }
                    }
                }

                Grid {
                    id: keypad
                    width: parent.width
                    height: parent.height - header.height - display.height - footer.height - parent.spacing * 3
                    columns: 4
                    spacing: Theme.spaceSm

                    Repeater {
                        model: [
                            { label: "C", action: "clear", tone: "danger" }, { label: "(", action: "(" }, { label: ")", action: ")" }, { label: "÷", action: "÷", tone: "operator" },
                            { label: "7", action: "7" }, { label: "8", action: "8" }, { label: "9", action: "9" }, { label: "×", action: "×", tone: "operator" },
                            { label: "4", action: "4" }, { label: "5", action: "5" }, { label: "6", action: "6" }, { label: "−", action: "−", tone: "operator" },
                            { label: "1", action: "1" }, { label: "2", action: "2" }, { label: "3", action: "3" }, { label: "+", action: "+", tone: "operator" },
                            { label: "±", action: "sign" }, { label: "0", action: "0" }, { label: ".", action: "." }, { label: "=", action: "equals", tone: "equals" }
                        ]

                        ControlButton {
                            id: button
                            required property var modelData
                            width: (keypad.width - keypad.spacing * 3) / 4
                            height: (keypad.height - keypad.spacing * 4) / 5
                            text: modelData.label
                            pointerFocusTarget: keys
                            danger: modelData.tone === "danger"
                            textColor: modelData.tone === "operator" || modelData.tone === "equals" ? Theme.accent : Theme.fg
                            border.color: visualFocus || modelData.tone === "equals" ? Theme.focusBorder : Theme.controlBorder(false, false, danger)
                            accessibleName: root.keyName(modelData.action, modelData.label)
                            onTriggered: root.activate(modelData.action)
                        }
                    }
                }

                Line { id: footer; width: parent.width; text: "ENTER RESULT  ·  ⌫ DELETE  ·  ESC CLOSE"; color: Theme.muted; horizontalAlignment: Text.AlignRight; font.pixelSize: Theme.fontCaption; elide: Text.ElideRight }
            }
        }
    }
}
