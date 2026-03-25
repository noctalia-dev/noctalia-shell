import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Widgets
import qs.Commons

Item {
  id: root

  property real radius: 0
  property string imagePath: ""
  property string fallbackIcon: ""
  property real fallbackIconSize: Style.fontSizeXXL
  property real borderWidth: 0
  property color borderColor: "transparent"
  property int imageFillMode: Image.PreserveAspectCrop

  readonly property bool _isAnimated: imagePath.toLowerCase().endsWith(".gif")
  readonly property Item imageSource: imageSourceLoader.item
  readonly property bool showFallback: fallbackIcon !== "" && (imagePath === "" || (imageSource && imageSource.status === Image.Error))
  readonly property int status: imageSource ? imageSource.status : Image.Null

  Rectangle {
    anchors.fill: parent
    radius: root.radius
    color: "transparent"
    border.width: root.borderWidth
    border.color: root.borderColor

    Loader {
      id: imageSourceLoader
      anchors.fill: parent
      anchors.margins: root.borderWidth
      active: root.imagePath !== ""
      sourceComponent: root._isAnimated ? animatedComponent : staticComponent
    }

    Component {
      id: staticComponent
      Image {
        visible: false
        source: root.imagePath
        mipmap: true
        smooth: true
        asynchronous: true
        antialiasing: true
        fillMode: root.imageFillMode
      }
    }

    Component {
      id: animatedComponent
      AnimatedImage {
        visible: false
        source: root.imagePath
        mipmap: true
        smooth: true
        asynchronous: true
        antialiasing: true
        fillMode: root.imageFillMode
        playing: true
      }
    }

    // Fallback texture provider to avoid null source warnings
    ShaderEffectSource {
      id: _safeFallback
      sourceItem: Rectangle {
        width: 1
        height: 1
        color: "transparent"
      }
      visible: false
      live: false
    }

    ShaderEffect {
      anchors.fill: parent
      anchors.margins: root.borderWidth
      visible: !root.showFallback && root.imageSource !== null && root.status === Image.Ready
      property var source: root.imageSource ?? _safeFallback
      property real itemWidth: width
      property real itemHeight: height
      property real sourceWidth: root.imageSource?.sourceSize.width ?? 0
      property real sourceHeight: root.imageSource?.sourceSize.height ?? 0
      property real cornerRadius: Math.max(0, root.radius - root.borderWidth)
      property real imageOpacity: 1.0
      property int fillMode: root.imageFillMode

      fragmentShader: Qt.resolvedUrl(Quickshell.shellDir + "/Shaders/qsb/rounded_image.frag.qsb")
      supportsAtlasTextures: false
      blending: true
    }

    NIcon {
      anchors.fill: parent
      anchors.margins: root.borderWidth
      visible: root.showFallback
      icon: root.fallbackIcon
      pointSize: root.fallbackIconSize
    }
  }
}
