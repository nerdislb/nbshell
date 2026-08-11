import QtQuick
import qs.Common

// Kennwerte als Raster: Beschriftung gedimmt links, Wert hell rechtsbuendig,
// zwei Paare je Zeile.
//
//   Ping          7.4 ms   Packet Loss        0%
//   Receiving    4.1 KB/s  Sending      4.3 KB/s
//
// Abgeschaut bei Omarchy 4, und zwar weil es dort mehr nach Terminal aussieht
// als bei uns: acht Werte auf vier Zeilen, ohne ein einziges grafisches
// Element. Unsere Popouts stapelten dieselbe Information untereinander und
// brauchten die doppelte Hoehe.
//
// Der Wert steht rechts am Rand SEINER Spalte, nicht am Rand des Popouts --
// dadurch stehen die Zahlen in beiden Spalten untereinander, und das Auge
// findet sie, ohne zu lesen.
//
//   Facts {
//       rowWidth: panel.rowWidth
//       pairs: [
//           { "label": "Ping", "value": "7.4 ms" },
//           { "label": "Verlust", "value": "0 %", "color": Theme.red }
//       ]
//   }
//
// `color` ist freiwillig und faerbt nur den Wert: eine Temperatur darf rot
// werden, ihre Beschriftung nicht.
Grid {
    id: root

    // [{ label, value, color? }] -- Eintraege mit leerem `label` UND leerem
    // `value` werden uebersprungen, damit ein Aufrufer Zeilen einfach
    // weglassen kann, ohne die Liste umzubauen.
    property var pairs: []
    property real rowWidth: 0

    // Wie viele Paare nebeneinander. Zwei ist der Normalfall; bei langen
    // Werten (Pfaden, Namen) ist eins richtig.
    columns: 2

    readonly property var shown: (root.pairs ?? []).filter(p => p && (String(p.label ?? "") !== "" || String(p.value ?? "") !== ""))
    readonly property real cellWidth: (root.rowWidth - columnSpacing * (columns - 1)) / Math.max(1, columns)

    columnSpacing: Theme.cellW * 2
    rowSpacing: 0

    Repeater {
        model: root.shown

        Item {
            id: pair

            required property var modelData

            width: root.cellWidth
            height: Theme.cellH * 1.3

            Line {
                id: key

                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                // Die Beschriftung weicht, nicht der Wert: eine abgeschnittene
                // Zahl ist wertlos, ein abgeschnittenes Wort noch lesbar.
                width: Math.max(0, pair.width - value.implicitWidth - Theme.cellW)
                text: String(pair.modelData.label ?? "")
                color: Theme.fgDim
                elide: Text.ElideRight
            }

            Line {
                id: value

                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: String(pair.modelData.value ?? "")
                color: pair.modelData.color ?? Theme.fg
            }
        }
    }
}
