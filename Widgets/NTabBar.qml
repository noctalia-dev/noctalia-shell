import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

Rectangle {
  id: root
  objectName: "NTabBar"

  // Public properties
  property int currentIndex: 0
  property real spacing: Style.marginXS
  property real margins: 0
  property real tabHeight: Style.baseWidgetSize
  property bool distributeEvenly: false
  default property alias content: tabRow.children

  onDistributeEvenlyChanged: _applyDistribution()
  Component.onCompleted: _applyDistribution()

  function _updateFirstLast() {
    // Defensive check for QML initialization timing
    if (!tabRow || !tabRow.children) {
      return;
    }
    var kids = tabRow.children;
    var len = kids.length;
    var firstVisible = -1;
    var lastVisible = -1;
    for (var i = 0; i < len; i++) {
      var child = kids[i];
      // Only consider items that have isFirst/isLast (actual tab buttons, not Repeaters)
      if (child.visible && "isFirst" in child) {
        if (firstVisible === -1)
          firstVisible = i;
        lastVisible = i;
      }
    }
    for (var i = 0; i < len; i++) {
      var child = kids[i];
      if ("isFirst" in child)
        child.isFirst = (i === firstVisible);
      if ("isLast" in child)
        child.isLast = (i === lastVisible);
    }
  }

  function _applyDistribution() {
    if (!tabRow || !tabRow.children) {
      return;
    }
    if (!distributeEvenly) {
      for (var i = 0; i < tabRow.children.length; i++) {
        var child = tabRow.children[i];
        child.Layout.fillWidth = true;
      }
      return;
    }

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
  radius: Style.iRadiusM

  RowLayout {
    id: tabRow
    anchors.fill: parent
    anchors.margins: margins
    spacing: root.spacing

    onChildrenChanged: {
      for (var i = 0; i < children.length; i++) {
        var child = children[i];
        child.visibleChanged.connect(root._updateFirstLast);
      }
      root._updateFirstLast();
      root._applyDistribution();
    }
  }
}
