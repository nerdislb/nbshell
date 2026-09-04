//@ pragma UseQApplication
//@ pragma AppId dev.nerdi.nbshell.greeter
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Greetd
import Quickshell.Wayland

ShellRoot {
    id: shell

    readonly property bool previewMode: Quickshell.env("NBSHELL_GREETER_PREVIEW") === "1"
    readonly property bool integrationTestMode: Quickshell.env("NBSHELL_GREETER_INTEGRATION_TEST") === "1"
    readonly property string integrationTestResponse: Quickshell.env("NBSHELL_GREETER_TEST_RESPONSE")
    readonly property string configPath: Quickshell.env("NBSHELL_GREETER_CONFIG") || "/usr/local/share/nbshell/greeter/config.json"

    property string username: ""
    property string wallpaper: ""
    property color background: "#1a1b26"
    property color foreground: "#c0caf5"
    property color bright: "#ffffff"
    property color muted: "#565f89"
    property color accent: "#7aa2f7"
    property color danger: "#f7768e"
    property string fontFamily: "JetBrainsMono Nerd Font"
    property int fontSize: 14
    property real dimOpacity: 0.48
    property string hourFormat: "24"
    property bool reducedMotion: false
    property bool showSecondsRing: true
    property bool showPowerActions: true
    property bool autoStartAuthentication: true
    property var sessions: []
    property int selectedSessionIndex: 0

    property bool responseRequired: false
    property bool echoResponse: false
    property bool externalAuthActive: false
    property string promptMessage: ""
    property bool launching: false
    property string statusMessage: previewMode ? "PREVIEW · AUTHENTICATION DISABLED" : "READY"
    property bool statusError: false
    property int failedAttempts: 0
    property int passwordResetSerial: 0
    property int promptSerial: 0
    property bool authenticationRetryPending: false
    property int authenticationRetryChecks: 0

    readonly property bool authenticating: !previewMode && Greetd.state === GreetdState.Authenticating
    readonly property bool greetdAvailable: previewMode || Greetd.available
    readonly property var selectedSession: sessions.length > 0 ? sessions[Math.max(0, Math.min(selectedSessionIndex, sessions.length - 1))] : null
    readonly property string selectedSessionName: selectedSession && selectedSession.name ? String(selectedSession.name) : "NO SESSION"

    function clamp(value, minimum, maximum) {
        return Math.max(minimum, Math.min(maximum, value));
    }

    function loadConfig() {
        let document = {};
        try {
            document = JSON.parse(configFile.text() || "{}");
        } catch (error) {
            statusMessage = "INVALID GREETER CONFIGURATION";
            statusError = true;
            return;
        }

        username = String(document.username || "").trim();
        wallpaper = String(document.wallpaper || "");
        background = document.background || background;
        foreground = document.foreground || foreground;
        bright = document.bright || foreground;
        muted = document.muted || muted;
        accent = document.accent || accent;
        danger = document.red || danger;
        fontFamily = String(document.font || fontFamily).replace(/[\r\n]/g, " ");
        fontSize = clamp(Number(document.fontSize) || 14, 8, 24);
        dimOpacity = clamp(Number(document.dimOpacity), 0, 0.85);
        if (!isFinite(dimOpacity))
            dimOpacity = 0.48;
        hourFormat = String(document.hourFormat) === "12" ? "12" : "24";
        reducedMotion = document.reducedMotion === true;
        showSecondsRing = document.showSecondsRing !== false;
        showPowerActions = document.showPowerActions !== false;
        autoStartAuthentication = document.autoStartAuthentication !== false;

        const candidates = Array.isArray(document.sessions) ? document.sessions : [];
        sessions = candidates.filter(session => {
            return session && typeof session.name === "string" && Array.isArray(session.command)
                && session.command.length > 0 && session.command.every(argument => typeof argument === "string" && argument.length > 0);
        });
        selectedSessionIndex = clamp(Number(document.defaultSessionIndex) || 0, 0, Math.max(0, sessions.length - 1));

        if (!username || sessions.length === 0) {
            statusMessage = "GREETER CONFIGURATION IS INCOMPLETE";
            statusError = true;
            return;
        }
        if (!previewMode && !Greetd.available) {
            statusMessage = "GREETD CONNECTION IS UNAVAILABLE";
            statusError = true;
            return;
        }
        statusMessage = previewMode ? "PREVIEW · AUTHENTICATION DISABLED" : "ENTER PASSWORD";
        statusError = false;
        if (!previewMode && autoStartAuthentication)
            externalAuthTimer.restart();
    }

    function cycleSession(step) {
        if (launching || sessions.length < 2)
            return;
        selectedSessionIndex = (selectedSessionIndex + step + sessions.length) % sessions.length;
    }

    function startAuthentication() {
        if (previewMode || launching || !username || !Greetd.available)
            return;
        if (Greetd.state === GreetdState.Inactive) {
            authenticationRetryPending = false;
            authenticationRetryTimer.stop();
            responseRequired = false;
            echoResponse = false;
            promptMessage = "";
            // greetd uses one serial PAM conversation. The installed nbshell
            // setup deliberately requests a password immediately instead of
            // pretending that password and fingerprint can run in parallel.
            externalAuthActive = false;
            statusError = false;
            statusMessage = "REQUESTING PASSWORD";
            Greetd.createSession(username);
        }
    }

    function submitResponse(response) {
        if (previewMode || launching || !responseRequired)
            return;
        if (typeof response !== "string" || !response.length)
            return;
        passwordResetSerial += 1;
        statusError = false;
        responseRequired = false;
        echoResponse = false;
        promptMessage = "";
        externalAuthActive = false;
        statusMessage = "AUTHENTICATING";
        Greetd.respond(response);
    }

    function cancelAuthentication() {
        authenticationRetryPending = false;
        authenticationRetryTimer.stop();
        passwordResetSerial += 1;
        responseRequired = false;
        echoResponse = false;
        promptMessage = "";
        externalAuthActive = false;
        if (!previewMode && Greetd.state !== GreetdState.Inactive && Greetd.state !== GreetdState.Launched)
            Greetd.cancelSession();
        statusMessage = previewMode ? "PREVIEW · AUTHENTICATION DISABLED" : "AUTHENTICATION CANCELED";
        statusError = false;
    }

    function requestPower(action) {
        if (previewMode || launching || (action !== "reboot" && action !== "poweroff"))
            return;
        powerProcess.command = ["/usr/bin/systemctl", action];
        powerProcess.running = true;
    }

    FileView {
        id: configFile
        path: shell.configPath
        blockLoading: true
        printErrors: true
    }

    Timer {
        id: externalAuthTimer
        interval: 350
        repeat: false
        onTriggered: shell.startAuthentication()
    }

    Timer {
        id: authenticationRetryTimer
        interval: 250
        repeat: true
        onTriggered: {
            if (!shell.authenticationRetryPending || shell.previewMode || shell.launching) {
                stop();
                return;
            }
            if (Greetd.state === GreetdState.Inactive) {
                stop();
                shell.startAuthentication();
                return;
            }
            shell.authenticationRetryChecks += 1;
            if (shell.authenticationRetryChecks >= 20) {
                stop();
                shell.authenticationRetryPending = false;
                shell.statusMessage = "AUTHENTICATION RESET TIMED OUT · PRESS ESC TO CANCEL";
                shell.statusError = true;
            }
        }
    }

    Timer {
        id: launchTimer
        interval: 100
        repeat: false
        onTriggered: {
            const session = shell.selectedSession;
            if (!session || !Array.isArray(session.command) || session.command.length === 0) {
                shell.launching = false;
                shell.statusMessage = "NO VALID SESSION SELECTED";
                shell.statusError = true;
                Greetd.cancelSession();
                return;
            }
            Greetd.launch(session.command, ["XDG_SESSION_TYPE=wayland"]);
        }
    }

    Process {
        id: powerProcess
        command: []
        onExited: function(exitCode) {
            if (exitCode !== 0) {
                shell.statusMessage = "POWER ACTION FAILED";
                shell.statusError = true;
            }
        }
    }

    Connections {
        target: Greetd

        function onAuthMessage(message, error, requiresResponse, shouldEcho) {
            shell.echoResponse = shouldEcho;
            if (requiresResponse) {
                shell.responseRequired = true;
                shell.externalAuthActive = false;
                shell.promptMessage = message ? String(message) : (shouldEcho ? "ENTER RESPONSE" : "ENTER SECRET");
                shell.statusError = false;
                shell.statusMessage = shell.promptMessage.toUpperCase();
                shell.promptSerial += 1;
                if (shell.integrationTestMode && shell.integrationTestResponse.length)
                    Qt.callLater(() => shell.submitResponse(shell.integrationTestResponse));
                return;
            }
            shell.responseRequired = false;
            shell.echoResponse = false;
            shell.promptMessage = "";
            const normalizedMessage = message ? String(message).toLowerCase() : "";
            shell.externalAuthActive = !error && (normalizedMessage.includes("finger") || normalizedMessage.includes("sensor"));
            if (message) {
                shell.statusMessage = String(message).toUpperCase();
                shell.statusError = error;
            }
        }

        function onReadyToLaunch() {
            // cancelSession() is acknowledged through the same success signal
            // as completed authentication. Consume that acknowledgement before
            // creating the replacement conversation, otherwise the two
            // requests can overlap and the cancel success can launch a session.
            if (shell.authenticationRetryPending) {
                // A cancel acknowledgement is not an authenticated session.
                // The bounded reset timer starts the replacement only after
                // the service reports Inactive.
                return;
            }
            shell.authenticationRetryPending = false;
            shell.responseRequired = false;
            shell.echoResponse = false;
            shell.promptMessage = "";
            shell.externalAuthActive = false;
            shell.passwordResetSerial += 1;
            shell.launching = true;
            shell.statusMessage = "AUTHENTICATED · STARTING " + shell.selectedSessionName.toUpperCase();
            shell.statusError = false;
            launchTimer.restart();
        }

        function onAuthFailure(message) {
            shell.responseRequired = false;
            shell.echoResponse = false;
            shell.promptMessage = "";
            shell.externalAuthActive = false;
            shell.passwordResetSerial += 1;
            shell.launching = false;
            shell.failedAttempts += 1;
            shell.statusMessage = message ? String(message).toUpperCase() : "AUTHENTICATION FAILED";
            shell.statusError = true;
            // A rejected PAM conversation is closed by greetd. Recreate only
            // the empty password prompt after cancel acknowledgement; no
            // credential is submitted and pam_faillock remains authoritative.
            shell.authenticationRetryPending = true;
            shell.authenticationRetryChecks = 0;
            if (Greetd.state !== GreetdState.Inactive)
                Greetd.cancelSession();
            authenticationRetryTimer.restart();
        }

        function onError(error) {
            shell.responseRequired = false;
            shell.echoResponse = false;
            shell.promptMessage = "";
            shell.externalAuthActive = false;
            shell.passwordResetSerial += 1;
            shell.launching = false;
            shell.statusMessage = error ? String(error).toUpperCase() : "GREETD ERROR";
            shell.statusError = true;
        }
    }

    Component.onCompleted: loadConfig()

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: surface
            required property var modelData
            readonly property bool primary: !Quickshell.screens.length || modelData.name === Quickshell.screens[0].name

            screen: modelData
            anchors { left: true; right: true; top: true; bottom: true }
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"
            WlrLayershell.namespace: "nbshell:orbital-greeter"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: primary ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

            GreeterView {
                anchors.fill: parent
                primary: surface.primary
                previewMode: shell.previewMode
                username: shell.username
                wallpaper: shell.wallpaper
                background: shell.background
                foreground: shell.foreground
                bright: shell.bright
                muted: shell.muted
                accent: shell.accent
                danger: shell.danger
                fontFamily: shell.fontFamily
                fontSize: shell.fontSize
                dimOpacity: shell.dimOpacity
                hourFormat: shell.hourFormat
                reducedMotion: shell.reducedMotion
                showSecondsRing: shell.showSecondsRing
                showPowerActions: shell.showPowerActions
                authenticating: shell.authenticating
                externalAuthActive: shell.externalAuthActive
                launching: shell.launching
                responseRequired: shell.responseRequired
                echoResponse: shell.echoResponse
                promptMessage: shell.promptMessage
                statusMessage: shell.statusMessage
                statusError: shell.statusError
                failedAttempts: shell.failedAttempts
                sessionName: shell.selectedSessionName
                sessionCount: shell.sessions.length
                passwordResetSerial: shell.passwordResetSerial
                promptSerial: shell.promptSerial

                onSubmitResponse: response => shell.submitResponse(response)
                onStartExternalAuth: shell.startAuthentication()
                onCancelAuthentication: shell.cancelAuthentication()
                onCycleSession: step => shell.cycleSession(step)
                onPowerAction: action => shell.requestPower(action)
                onQuitPreview: Qt.quit()
            }
        }
    }
}
