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
  property string fallbackIcon: ""
  property real fallbackIconSize: Style.fontSizeXXL

  color: Color.transparent
  radius: parent.width * 0.5
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

      property real imageOpacity: root.opacity
      fragmentShader: Qt.resolvedUrl(Quickshell.shellDir + "/Shaders/qsb/circled_image.frag.qsb")
      supportsAtlasTextures: false
      blending: true
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
