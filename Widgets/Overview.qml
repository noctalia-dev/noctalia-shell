import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import qs.Services
import qs.Settings

ShellRoot {
    property string wallpaperSource: WallpaperManager.currentWallpaper !== "" && !Settings.settings.useSWWW ? WallpaperManager.currentWallpaper : ""

    Variants {
        model: Quickshell.screens

        PanelWindow {
            required property ShellScreen modelData

            visible: wallpaperSource !== ""
            anchors {
                top: true
                bottom: true
                right: true
                left: true
            }
            color: "transparent"
            screen: modelData
            WlrLayershell.layer: WlrLayer.Background
            WlrLayershell.exclusionMode: ExclusionMode.Ignore
            WlrLayershell.namespace: "quickshell-overview"
            Image {
                id: bgImage
                anchors.fill: parent
                fillMode: Image.PreserveAspectCrop
                source: wallpaperSource
                cache: true
                smooth: true
                mipmap: false
                visible: wallpaperSource !== ""
            }
            MultiEffect {
                id: overviewBgBlur
                anchors.fill: parent
                source: bgImage
                blurEnabled: true
                            blur: 0.48
            blurMax: 128
            }
            Rectangle {
                anchors.fill: parent
                color: Qt.rgba(
                    Theme.backgroundPrimary.r,
                    Theme.backgroundPrimary.g,
                    Theme.backgroundPrimary.b, 0.5)
            }
        }
    }
}
