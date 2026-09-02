import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Widgets
import qs.Ui as Ui

// Read-only portability advisor for public community plugins. Remote source is
// fetched as text by a bounded Python analyzer; this component never loads,
// executes, installs, or modifies third-party code.
Item {
    id: root

    property string sourceUrl: ""
    property var report: null
    property string errorText: ""
    property bool busy: false
    property string launchStatus: ""

    readonly property string script: Qt.resolvedUrl("../scripts/plugin-porting-lab.py").toString().replace("file://", "")
    readonly property var findings: report?.findings ?? []
    readonly property bool canStartPort: report !== null
        && String(report?.implementation_prompt ?? "") !== ""
        && String(report?.verdict?.recommendation ?? "") !== "not-recommended"
    readonly property string launchAgent: root.configuredLaunchAgent()
    readonly property bool defaultAgentReady: Agents.agents.some(agent =>
        String(agent.id) === root.launchAgent && Boolean(agent.installed))
    readonly property color verdictColor: {
        const value = report?.verdict?.recommendation ?? "";
        if (value === "not-recommended") return Theme.red;
        if (value === "native-port") return Theme.green;
        if (value === "compare-existing") return Theme.yellow;
        return Theme.accent;
    }

    function focusInput() {
        Qt.callLater(source.forceActiveFocus);
    }

    function analyze() {
        const value = sourceUrl.trim();
        if (busy) return;
        if (value === "") {
            errorText = "Enter a public GitHub repository or Omarchy plugin URL.";
            report = null;
            return;
        }
        busy = true;
        errorText = "";
        launchStatus = "";
        report = null;
        analyzer.command = ["python3", script, value];
        analyzer.running = true;
    }

    function reset() {
        sourceUrl = "";
        report = null;
        errorText = "";
        launchStatus = "";
        focusInput();
    }

    function startPort() {
        const prompt = String(report?.implementation_prompt ?? "");
        if (!canStartPort || !defaultAgentReady || prompt === "") return;
        if (launchAgent === "hermes") {
            Quickshell.execDetached(["wl-copy", prompt]);
            launchStatus = "Hermes opened · implementation prompt copied for pasting";
        } else {
            launchStatus = "Implementation prompt sent to " + launchAgent;
        }
        Agents.launchQuick(prompt);
    }

    function configuredLaunchAgent() {
        const routes = Agents.config.modelProfiles ?? ({});
        const route = routes[Agents.modelProfile] ?? ({});
        return String(route.agent || Agents.defaultAgent);
    }

    function severityColor(value) {
        if (value === "danger") return Theme.red;
        if (value === "warning") return Theme.yellow;
        if (value === "positive") return Theme.green;
        return Theme.accent;
    }

    function severityMark(value) {
        if (value === "danger") return "BLOCK";
        if (value === "warning") return "ADAPT";
        if (value === "positive") return "REUSE";
        return "REVIEW";
    }

    Process {
        id: analyzer
        stdout: StdioCollector { id: analyzerOut }
        stderr: StdioCollector { id: analyzerErr }
        onExited: code => {
            root.busy = false;
            const output = String(analyzerOut.text || "").trim();
            try {
                const document = JSON.parse(output || "{}");
                if (code !== 0 || document.error) {
                    root.errorText = String(document.error || analyzerErr.text || "The source could not be analyzed.").trim();
                    root.report = null;
                } else {
                    root.report = document;
                    root.errorText = "";
                    reportView.contentY = 0;
                    Qt.callLater(reportView.forceActiveFocus);
                }
            } catch (error) {
                root.report = null;
                root.errorText = "The analyzer returned an invalid report.";
            }
        }
    }

    Column {
        anchors.fill: parent
        spacing: Theme.spaceSm

        Row {
            width: parent.width
            height: Theme.controlHeight
            spacing: Theme.spaceSm

            Ui.TextField {
                id: source
                width: parent.width - analyzeButton.width - clearButton.width - parent.spacing * 2
                height: Theme.controlHeight
                text: root.sourceUrl
                placeholderText: "GitHub repository or Omarchy plugin URL"
                accessibleName: "Plugin source URL"
                accessibleDescription: "Public GitHub repository or Omarchy marketplace plugin page to analyze"
                enabled: !root.busy
                onTextEdited: root.sourceUrl = text
                onAccepted: root.analyze()
            }

            ControlButton {
                id: analyzeButton
                text: root.busy ? "ANALYZING…" : "ANALYZE"
                enabled: !root.busy
                onTriggered: root.analyze()
            }

            ControlButton {
                id: clearButton
                text: "CLEAR"
                enabled: !root.busy && (root.sourceUrl !== "" || root.report !== null || root.errorText !== "")
                onTriggered: root.reset()
            }
        }

        Line {
            width: parent.width
            text: root.busy
                ? "Fetching bounded public source text · no code is executed"
                : (root.errorText !== "" ? root.errorText
                    : "Static advisory only · no install, execution, source edit, or compatibility guarantee")
            color: root.errorText !== "" ? Theme.red : (root.busy ? Theme.accent : Theme.muted)
            elide: Text.ElideRight
        }

        Rule { rowWidth: parent.width }

        Item {
            width: parent.width
            height: parent.height - Theme.controlHeight - Theme.cellH * 2 - Theme.spaceSm * 3

            Column {
                visible: root.report === null && !root.busy && root.errorText === ""
                width: Math.min(parent.width, Theme.cellW * 76)
                anchors.centerIn: parent
                spacing: Theme.spaceMd

                Line {
                    width: parent.width
                    text: "PASTE A PLUGIN LINK. GET A PORTING DECISION."
                    color: Theme.fg
                    font.pixelSize: Theme.fontTitle
                    font.bold: true
                    horizontalAlignment: Text.AlignHCenter
                }
                Line {
                    width: parent.width
                    text: "The lab checks shell APIs, compositor coupling, process and network use, filesystem changes, licensing, nbshell overlap, and the likely runtime kind."
                    color: Theme.fgDim
                    wrapMode: Text.WordWrap
                    horizontalAlignment: Text.AlignHCenter
                }
                Facts {
                    rowWidth: parent.width
                    columns: 1
                    pairs: [
                        {"label": "SUPPORTED", "value": "GitHub repositories · Omarchy plugin pages"},
                        {"label": "OUTPUT", "value": "Compatibility verdict · findings · ordered porting plan"},
                        {"label": "SAFETY", "value": "Public text only · bounded fetch · no code execution"}
                    ]
                }
                Line {
                    width: parent.width
                    text: "Third-party QML still runs unsandboxed if you later install and enable it. Review the source separately."
                    color: Theme.yellow
                    wrapMode: Text.WordWrap
                    horizontalAlignment: Text.AlignHCenter
                }
            }

            Column {
                visible: root.busy
                anchors.centerIn: parent
                spacing: Theme.spaceSm
                Line { text: "ANALYZING SOURCE"; color: Theme.accent; font.pixelSize: Theme.fontTitle; font.bold: true; horizontalAlignment: Text.AlignHCenter }
                Line { text: "Resolving source · reading bounded text · applying deterministic rules"; color: Theme.fgDim; horizontalAlignment: Text.AlignHCenter }
            }

            Column {
                visible: root.errorText !== ""
                width: Math.min(parent.width, Theme.cellW * 72)
                anchors.centerIn: parent
                spacing: Theme.spaceMd
                Line { width: parent.width; text: "ANALYSIS STOPPED"; color: Theme.red; font.pixelSize: Theme.fontTitle; font.bold: true; horizontalAlignment: Text.AlignHCenter }
                Line { width: parent.width; text: root.errorText; color: Theme.fgDim; wrapMode: Text.WordWrap; horizontalAlignment: Text.AlignHCenter }
                ControlButton { anchors.horizontalCenter: parent.horizontalCenter; text: "EDIT SOURCE"; onTriggered: root.focusInput() }
            }

            Flickable {
                id: reportView
                visible: root.report !== null && !root.busy
                anchors.fill: parent
                contentWidth: width
                contentHeight: reportColumn.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                focus: visible
                activeFocusOnTab: true
                readonly property real maxContentY: Math.max(0, contentHeight - height)
                Accessible.role: Accessible.Pane
                Accessible.name: "Plugin portability report"

                Keys.onPressed: event => {
                    const step = Theme.cellH * 3;
                    const page = Math.max(step, reportView.height - Theme.cellH * 4);
                    if (event.key === Qt.Key_Down || event.key === Qt.Key_J) reportView.contentY = Math.min(reportView.maxContentY, reportView.contentY + step);
                    else if (event.key === Qt.Key_Up || event.key === Qt.Key_K) reportView.contentY = Math.max(0, reportView.contentY - step);
                    else if (event.key === Qt.Key_PageDown) reportView.contentY = Math.min(reportView.maxContentY, reportView.contentY + page);
                    else if (event.key === Qt.Key_PageUp) reportView.contentY = Math.max(0, reportView.contentY - page);
                    else if (event.key === Qt.Key_Home) reportView.contentY = 0;
                    else if (event.key === Qt.Key_End) reportView.contentY = reportView.maxContentY;
                    else return;
                    event.accepted = true;
                }

                Column {
                    id: reportColumn
                    width: reportView.width
                    spacing: Theme.spaceMd

                    Row {
                        width: parent.width
                        spacing: Theme.spaceLg

                        Column {
                            width: parent.width - verdictFacts.width - Theme.spaceLg
                            spacing: Theme.spaceXs
                            Line { width: parent.width; text: root.report?.plugin?.name ?? "Plugin"; color: Theme.fg; font.pixelSize: Theme.fontTitle; font.bold: true; elide: Text.ElideRight }
                            Line { width: parent.width; text: root.report?.plugin?.description ?? ""; color: Theme.fgDim; wrapMode: Text.WordWrap; maximumLineCount: 2; elide: Text.ElideRight }
                            Line { width: parent.width; text: root.report?.verdict?.label?.toUpperCase() ?? "REVIEW"; color: root.verdictColor; font.pixelSize: Theme.fontSubtitle; font.bold: true }
                            Line { width: parent.width; text: root.report?.verdict?.summary ?? ""; color: Theme.fg; wrapMode: Text.WordWrap }
                        }

                        Facts {
                            id: verdictFacts
                            width: Theme.cellW * 33
                            rowWidth: width
                            columns: 1
                            pairs: [
                                {"label": "COMPATIBILITY", "value": String(root.report?.verdict?.compatibility ?? 0) + "%", "color": root.verdictColor},
                                {"label": "EFFORT", "value": String(root.report?.verdict?.effort ?? "unknown").toUpperCase()},
                                {"label": "CONFIDENCE", "value": String(root.report?.verdict?.confidence ?? "unknown").toUpperCase()}
                            ]
                        }
                    }

                    Line { width: parent.width; text: root.report?.verdict?.confidence_note ?? ""; color: Theme.muted; font.pixelSize: Theme.fontCaption; wrapMode: Text.WordWrap }
                    Rule { rowWidth: parent.width }
                    SectionHeader { text: "FINDINGS"; detail: String(root.findings.length) }

                    Repeater {
                        model: root.findings
                        Rectangle {
                            required property var modelData
                            width: reportColumn.width
                            height: findingContent.implicitHeight + Theme.spaceMd * 2
                            radius: Theme.radius
                            color: Theme.alpha(Theme.fg, 0.035)
                            border.width: Theme.borderWidth
                            border.color: Theme.alpha(root.severityColor(modelData.severity), 0.45)

                            Column {
                                id: findingContent
                                x: Theme.spaceMd
                                y: Theme.spaceMd
                                width: parent.width - Theme.spaceMd * 2
                                spacing: Theme.spaceXs
                                Row {
                                    width: parent.width
                                    spacing: Theme.spaceMd
                                    Line { text: root.severityMark(modelData.severity); color: root.severityColor(modelData.severity); font.bold: true; font.pixelSize: Theme.fontCaption }
                                    Line { width: parent.width - Theme.cellW * 10; text: modelData.title; color: Theme.fg; font.bold: true; elide: Text.ElideRight }
                                }
                                Line { width: parent.width; text: modelData.detail; color: Theme.fgDim; wrapMode: Text.WordWrap }
                                Line { width: parent.width; text: "→ " + modelData.hint; color: Theme.fg; wrapMode: Text.WordWrap }
                                Line { width: parent.width; visible: (modelData.locations ?? []).length > 0; text: (modelData.locations ?? []).join(" · "); color: Theme.muted; font.pixelSize: Theme.fontCaption; elide: Text.ElideMiddle }
                            }
                        }
                    }

                    Rule { rowWidth: parent.width }
                    SectionHeader { text: "PORTING PLAN"; detail: String((root.report?.plan ?? []).length) + " steps" }
                    Repeater {
                        model: root.report?.plan ?? []
                        Row {
                            required property string modelData
                            required property int index
                            width: reportColumn.width
                            spacing: Theme.spaceMd
                            Line { width: Theme.cellW * 3; text: String(index + 1).padStart(2, "0"); color: Theme.accent; font.bold: true }
                            Line { width: parent.width - Theme.cellW * 3 - Theme.spaceMd; text: modelData; color: Theme.fg; wrapMode: Text.WordWrap }
                        }
                    }

                    Rule { rowWidth: parent.width }
                    Flow {
                        width: parent.width
                        spacing: Theme.spaceSm
                        ControlButton {
                            text: "START PORT"
                            visible: root.canStartPort
                            enabled: root.defaultAgentReady
                            selected: true
                            accessibleDescription: "Open the configured coding agent in nbshell with this report's implementation prompt"
                            onTriggered: root.startPort()
                        }
                        ControlButton { text: "OPEN SOURCE"; onTriggered: Quickshell.execDetached(["xdg-open", String(root.report?.source?.repository ?? "")]) }
                        ControlButton { text: "ANALYZE ANOTHER"; onTriggered: root.reset() }
                    }
                    Line {
                        width: parent.width
                        visible: root.canStartPort && (!root.defaultAgentReady || root.launchStatus !== "")
                        text: root.defaultAgentReady
                            ? root.launchStatus
                            : "The configured agent is not installed. Install or select an agent in Agent Center."
                        color: root.defaultAgentReady ? Theme.green : Theme.yellow
                        font.pixelSize: Theme.fontCaption
                        wrapMode: Text.WordWrap
                    }
                    Line { width: parent.width; text: root.report?.disclaimer ?? ""; color: Theme.yellow; font.pixelSize: Theme.fontCaption; wrapMode: Text.WordWrap }
                }
            }
        }
    }
}
