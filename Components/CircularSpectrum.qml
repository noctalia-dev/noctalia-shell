import QtQuick
import qs.Components
import qs.Settings

Item {
    id: root
    property int innerRadius: 34 * Theme.scale(Screen)
    property int outerRadius: 48 * Theme.scale(Screen)
    property color fillColor: "#fff"
    property color strokeColor: "#fff"
    property int strokeWidth: 0 * Theme.scale(Screen)
    property var values: []
    property int usableOuter: 48

    width: usableOuter * 2
    height: usableOuter * 2

    onOuterRadiusChanged: () => {
        usableOuter = Settings.settings.visualizerType === "fire" ? outerRadius * 0.85 : outerRadius;
    }

    Repeater {
        model: root.values.length
        Rectangle {
            property real value: root.values[index]
            property real angle: (index / root.values.length) * 360
            width: Math.max(2 * Theme.scale(Screen), (root.innerRadius * 2 * Math.PI) / root.values.length - 4 * Theme.scale(Screen))
            height: Settings.settings.visualizerType === "diamond" ? value * 2 * (usableOuter - root.innerRadius) : value * (usableOuter - root.innerRadius)
            radius: width / 2
            color: root.fillColor
            border.color: root.strokeColor
            border.width: root.strokeWidth
            antialiasing: true

            x: Settings.settings.visualizerType === "radial" ? root.width / 2 - width / 2 : root.width / 2 + root.innerRadius * Math.cos(Math.PI / 2 + 2 * Math.PI * index / root.values.length) - width / 2

            y: Settings.settings.visualizerType === "radial" ? root.height / 2 - height : Settings.settings.visualizerType === "diamond" ? root.height / 2 - root.innerRadius * Math.sin(Math.PI / 2 + 2 * Math.PI * index / root.values.length) - height / 2 : root.height / 2 - root.innerRadius * Math.sin(Math.PI / 2 + 2 * Math.PI * index / root.values.length) - height
            transform: [
                Rotation {
                    origin.x: width / 2
                    origin.y: Settings.settings.visualizerType === "diamond" ? height / 2 : height
                    angle: Settings.settings.visualizerType === "radial" ? (index / root.values.length) * 360 : Settings.settings.visualizerType === "fire" ? 0 : (index / root.values.length) * 360 - 90
                },
                Translate {
                    x: Settings.settings.visualizerType === "radial" ? root.innerRadius * Math.cos(2 * Math.PI * index / root.values.length) : 0
                    y: Settings.settings.visualizerType === "radial" ? root.innerRadius * Math.sin(2 * Math.PI * index / root.values.length) : 0
                }
            ]

            Behavior on height {
                SmoothedAnimation {
                    duration: 120
                }
            }
        }
    }
}
