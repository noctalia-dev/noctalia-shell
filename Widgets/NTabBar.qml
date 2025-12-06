import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

Rectangle {
  id: root

  // Public properties
  property int currentIndex: 0
  property real spacing: Style.marginS
  property real margins: Style.marginXS
  default property alias content: tabRow.children

  // Styling
  Layout.fillWidth: true
  implicitHeight: Style.baseWidgetSize + (margins * 2)
  color: Color.mSurfaceVariant
  radius: Style.iRadiusS

  RowLayout {
    id: tabRow
    anchors.fill: parent
    anchors.margins: margins
    spacing: root.spacing
  }
}
