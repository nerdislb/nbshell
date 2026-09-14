import QtQuick
import qs.Common
import qs.Services
import qs.Widgets

PanelSurface {
    implicitHeight: content.height + Theme.panelPadding * 2
    color: Theme.alpha(Theme.panelSurface, Theme.isLight ? 0.82 : 0.48)
    radius: Theme.spaceXl
    border.color: Theme.alpha(Theme.fg, 0.22)
    Column {
        id: content
        x: Theme.panelPadding; y: Theme.panelPadding
        width: parent.width - Theme.panelPadding * 2
        spacing: Theme.spaceSm
        Line { width: parent.width; text: "MACHINE · " + (WorkState.device.host || "Local device"); font.pixelSize: Theme.fontCaption; color: Theme.fgDim; elide: Text.ElideRight }
        Line { text: "CPU  " + SysInfo.cpuPercent + "%"; color: Theme.fgBright }
        LevelBar { value: SysInfo.cpuPercent; interactive: false; cells: Math.max(1, Math.floor(content.width / (Theme.cellW * 1.2))) }
        Line { width: parent.width; text: "RAM  " + SysInfo.memUsedGb.toFixed(1) + " / " + SysInfo.memTotalGb.toFixed(1) + " GiB"; elide: Text.ElideRight; color: Theme.fgBright }
        LevelBar { value: SysInfo.memPercent; interactive: false; cells: Math.max(1, Math.floor(content.width / (Theme.cellW * 1.2))) }
        Line { width: parent.width; text: WorkState.device.disk || "Storage unavailable"; wrapMode: Text.Wrap; color: Theme.fgDim }
        Line { width: parent.width; text: "NET  " + Net.summary; wrapMode: Text.Wrap; color: Net.online ? Theme.fg : Theme.yellow }
        Line { width: parent.width; visible: PowerService.available; text: "BAT  " + PowerService.percent + "% · " + PowerService.stateText + " · " + PowerService.powerText; wrapMode: Text.Wrap; color: PowerService.percent < 20 ? Theme.yellow : Theme.fg }
        Line { width: parent.width; text: "UP   " + (WorkState.device.uptime || "unavailable"); color: Theme.fgDim; wrapMode: Text.Wrap }
    }
}
