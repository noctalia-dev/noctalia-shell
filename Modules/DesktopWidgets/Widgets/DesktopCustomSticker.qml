import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Modules.DesktopWidgets
import qs.Services.UI
import qs.Widgets

DraggableDesktopWidget {
  id: root

  readonly property var widgetMetadata: DesktopWidgetRegistry.widgetMetadata["CustomSticker"]

  readonly property string widgetImage: widgetData.image !== undefined ? widgetData.image : ""
  readonly property real widgetOpacity: widgetData.opacity !== undefined ? widgetData.opacity : 1.0

  implicitWidth: (widgetImage == "" ? 50 : sticker.sourceSize.width) * widgetScale
  implicitHeight: (widgetImage == "" ? 50 : sticker.sourceSize.height) * widgetScale
  width: implicitWidth
  height: implicitHeight
  minScale: 0.1

  Image {
    id: sticker

    anchors.fill: parent
    opacity: root.widgetOpacity
    source: Qt.resolvedUrl(root.widgetImage)
  }
}
