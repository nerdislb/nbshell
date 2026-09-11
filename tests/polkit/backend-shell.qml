import QtQuick
import Quickshell
import Quickshell.Services.Polkit
ShellRoot {
 PolkitAgent {
  id: agent
  path: "/review/Agent"
  onIsRegisteredChanged: console.log("REGISTERED", isRegistered)
  onFlowChanged: console.log("FLOW", flow ? flow.actionId : "none")
 }
 Timer { interval: 7000; running: true; onTriggered: Qt.quit() }
}
