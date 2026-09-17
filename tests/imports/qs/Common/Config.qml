pragma Singleton

import QtQuick

QtObject {
    property string meterStyle: "line"
    // Mirror of the production default; qs.Commons.Style.gapsOut reads it.
    property int gap: 6
}