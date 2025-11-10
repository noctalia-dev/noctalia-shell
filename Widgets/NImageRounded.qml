import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Widgets
import qs.Commons

Rectangle {
  id: root

  property string imagePath: ""
  property color borderColor: Color.transparent
  property real borderWidth: 0
  property real imageRadius: width * 0.5
  property string fallbackIcon: ""
  property real fallbackIconSize: Style.fontSizeXXL

  property real scaledRadius: imageRadius * Settings.data.general.radiusRatio

  signal statusChanged(int status)

  color: Color.transparent
  radius: scaledRadius
  anchors.margins: Style.marginXXS

  Rectangle {
    color: Color.transparent
    anchors.fill: parent

    Image {
      id: img
      anchors.fill: parent
      source: imagePath
      visible: false // Hide since we're using it as shader source
      mipmap: true
      smooth: true
      asynchronous: true
      antialiasing: true
      fillMode: Image.PreserveAspectCrop

      onStatusChanged: root.statusChanged(status)
    }

    ShaderEffect {
      anchors.fill: parent

      property var source: ShaderEffectSource {
        sourceItem: img
        hideSource: true
        live: true
        recursive: false
        format: ShaderEffectSource.RGBA
      }

      // Use custom property names to avoid conflicts with final properties
      property real itemWidth: root.width
      property real itemHeight: root.height
      property real cornerRadius: root.radius
      property real imageOpacity: root.opacity
      fragmentShader: Qt.resolvedUrl(Quickshell.shellDir + "/Shaders/qsb/rounded_image.frag.qsb")

      // Qt6 specific properties - ensure proper blending
      supportsAtlasTextures: false
      blending: true
      // Make sure the background is transparent
      Rectangle {
        id: background
        anchors.fill: parent
        color: Color.transparent
        z: -1
      }
    }

    // Fallback icon
    Loader {
      active: fallbackIcon !== undefined && fallbackIcon !== "" && (imagePath === undefined || imagePath === "")
      anchors.centerIn: parent
      sourceComponent: NIcon {
        anchors.centerIn: parent
        icon: fallbackIcon
        pointSize: fallbackIconSize
        z: 0
      }
    }
  }

  // Border
  Rectangle {
    anchors.fill: parent
    radius: parent.radius
    color: Color.transparent
    border.color: parent.borderColor
    border.width: parent.borderWidth
    antialiasing: true
    z: 10
  }
}
