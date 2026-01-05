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
  property real tabHeight: Style.baseWidgetSize
  property bool distributeEvenly: false
  default property alias content: tabRow.children

  onDistributeEvenlyChanged: _applyDistribution()
  Component.onCompleted: _applyDistribution()

  function _applyDistribution() {
    if (!distributeEvenly)
      return;
    for (var i = 0; i < tabRow.children.length; i++) {
      var child = tabRow.children[i];
      child.Layout.fillWidth = true;
      child.Layout.preferredWidth = 1;
    }
  }

  // Styling
  implicitWidth: tabRow.implicitWidth + (margins * 2)
  implicitHeight: tabHeight + (margins * 2)
  color: Color.mSurfaceVariant
  radius: Style.iRadiusS

  RowLayout {
    id: tabRow
    anchors.fill: parent
    anchors.margins: margins
    spacing: root.spacing
  }
}
