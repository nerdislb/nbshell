import QtQuick
import QtQuick.Shapes

// A 16-cell pixel silhouette derived from the nbshell floppy: clipped upper
// corner, metal shutter and large label. Cutouts reveal the actual bar surface.
Item {
    id: root

    required property int size
    required property color color
    width: size
    height: size

    function point(x, y) {
        return Math.round(x * size / 16) + " " + Math.round(y * size / 16);
    }

    Shape {
        anchors.fill: parent
        antialiasing: false

        ShapePath {
            strokeWidth: -1
            fillColor: root.color
            fillRule: ShapePath.OddEvenFill
            PathSvg {
                path: "M" + root.point(0, 0)
                    + "H" + Math.round(12 * root.size / 16)
                    + "V" + Math.round(root.size / 16)
                    + "H" + Math.round(13 * root.size / 16)
                    + "V" + Math.round(2 * root.size / 16)
                    + "H" + Math.round(14 * root.size / 16)
                    + "V" + Math.round(3 * root.size / 16)
                    + "H" + root.size + "V" + root.size + "H0Z"
                    + " M" + root.point(3, 1) + "L" + root.point(11, 1)
                    + "L" + root.point(11, 6) + "L" + root.point(3, 6) + "Z"
                    + " M" + root.point(8, 2) + "L" + root.point(10, 2)
                    + "L" + root.point(10, 5) + "L" + root.point(8, 5) + "Z"
                    + " M" + root.point(3, 9) + "L" + root.point(13, 9)
                    + "L" + root.point(13, 14) + "L" + root.point(3, 14) + "Z"
            }
        }
    }
}
