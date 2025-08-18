import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Widgets
import qs.Commons
import qs.Services

Rectangle {
  id: root

  property string imagePath: ""
  property string fallbackIcon: ""
  property color borderColor: Color.transparent
  property real borderWidth: 0
  property real imageRadius: width * 0.5

  property real scaledRadius: imageRadius * Settings.data.general.radiusRatio

  color: Color.transparent
  radius: scaledRadius
  anchors.margins: Style.marginTiniest * scaling

  // Border
  Rectangle {
    anchors.fill: parent
    radius: parent.radius
    color: Color.transparent
    border.color: parent.borderColor
    border.width: parent.borderWidth
    z: 10
  }

  Image {
    id: img
    anchors.fill: parent
    source: imagePath
    visible: false
    mipmap: true
    smooth: true
    asynchronous: true
    fillMode: Image.PreserveAspectCrop
  }

  MultiEffect {
    anchors.fill: parent
    source: img
    maskEnabled: true
    maskSource: mask
    visible: imagePath !== ""
  }

  Item {
    id: mask
    anchors.fill: parent
    layer.enabled: true
    visible: false
    Rectangle {
      anchors.fill: parent
      radius: scaledRadius
    }
  }

  // Fallback icon
  NIcon {
    anchors.centerIn: parent
    text: fallbackIcon
    font.pointSize: Style.fontSizeXL * scaling
    visible: fallbackIcon !== undefined && fallbackIcon !== "" && (imagePath === undefined || imagePath === "")
    z: 0
  }
}
