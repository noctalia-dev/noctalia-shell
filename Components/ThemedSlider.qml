import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import qs.Settings

Slider {
    id: slider

    property var screen
    property bool snapAlways: true

    readonly property real trackHeight: 12 * Theme.scale(screen)
    readonly property real knobDiameter: 28 * Theme.scale(screen)
    // Optional color to cut the track beneath the knob (should match surrounding background)
    property var cutoutColor
    readonly property real cutoutExtra: 8 * Theme.scale(screen)

    snapMode: snapAlways ? Slider.SnapAlways : Slider.SnapOnRelease

    implicitHeight: Math.max(trackHeight, knobDiameter)

    background: Rectangle {
        x: slider.leftPadding
        y: slider.topPadding + slider.availableHeight / 2 - height / 2
        implicitWidth: 200
        implicitHeight: trackHeight
        width: slider.availableWidth
        height: implicitHeight
        radius: height / 2
        color: Theme.surfaceVariant

        Rectangle {
            id: activeTrack
            width: slider.visualPosition * parent.width
            height: parent.height
            color: Theme.accentPrimary
            radius: parent.radius

            Behavior on width {
                NumberAnimation { duration: 120; easing.type: Easing.OutQuad }
            }
        }

        // Circular cutout
        Rectangle {
            id: knobCutout
            width: knobDiameter + cutoutExtra
            height: knobDiameter + cutoutExtra
            radius: width / 2
            color: slider.cutoutColor !== undefined ? slider.cutoutColor : Theme.backgroundPrimary
            x: Math.max(0, Math.min(parent.width - width, slider.visualPosition * (parent.width - slider.knobDiameter) - cutoutExtra / 2))
            y: (parent.height - height) / 2
        }
    }

    handle: Item {
        id: handleRoot
        width: knob.implicitWidth
        height: knob.implicitHeight
        x: slider.leftPadding + slider.visualPosition * (slider.availableWidth - width)
        y: slider.topPadding + slider.availableHeight / 2 - height / 2

        // Subtle shadow for a more polished look (keeps theme colors)
        MultiEffect {
            anchors.fill: knob
            source: knob
            shadowEnabled: true
            shadowColor: Theme.shadow
            shadowOpacity: 0.25
            shadowHorizontalOffset: 0
            shadowVerticalOffset: 1
            shadowBlur: 8
        }

        Rectangle {
            id: knob
            implicitWidth: knobDiameter
            implicitHeight: knobDiameter
            radius: width / 2
            color: slider.pressed ? Theme.surfaceVariant : Theme.surface
            border.color: Theme.accentPrimary
            border.width: 2 * Theme.scale(screen)

            // Press feedback halo (using accent color, low opacity)
            Rectangle {
                anchors.centerIn: parent
                width: parent.width + 10 * Theme.scale(screen)
                height: parent.height + 10 * Theme.scale(screen)
                radius: width / 2
                color: Theme.accentPrimary
                opacity: slider.pressed ? 0.16 : 0.0
            }
        }
    }
}

