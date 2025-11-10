import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

Rectangle {
  id: root

  // Public properties
  property int currentIndex: 0
  property int spacing: Style.marginS
  default property alias content: tabRow.children

  // Styling
  Layout.fillWidth: true
  implicitHeight: Style.baseWidgetSize + Style.marginXS * 2
  color: Color.mSurfaceVariant
  radius: Style.radiusS

  RowLayout {
    id: tabRow
    anchors.fill: parent
    anchors.margins: Style.marginXS
    spacing: root.spacing
  }
}
