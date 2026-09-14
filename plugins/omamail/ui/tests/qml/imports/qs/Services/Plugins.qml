pragma Singleton
import QtQuick
QtObject { property var service: null; property int toggleCount: 0; function serviceFor(id) { return service } function toggle(id,payload) { toggleCount++ } }
