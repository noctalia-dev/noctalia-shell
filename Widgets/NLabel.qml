import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

ColumnLayout {
  id: root

  property string label: ""
  property string description: ""
  property color labelColor: Color.mOnSurface
  property color descriptionColor: Color.mOnSurfaceVariant
  property bool showIndicator: false
  property string indicatorTooltip: ""

  spacing: Style.marginXXS
  Layout.fillWidth: true

  RowLayout {
    spacing: Style.marginXS
    Layout.fillWidth: true
    visible: label !== ""

    NText {
      text: label
      pointSize: Style.fontSizeL
      font.weight: Style.fontWeightSemiBold
      color: labelColor
    }

    // Settings indicator
    Loader {
      active: showIndicator
      sourceComponent: indicatorComponent
    }
  }

  Component {
    id: indicatorComponent
    NSettingsIndicator {
      show: true
      tooltipText: root.indicatorTooltip || ""
      Layout.alignment: Qt.AlignVCenter
    }
  }

  NText {
    text: description
    pointSize: Style.fontSizeS
    color: descriptionColor
    wrapMode: Text.WordWrap
    visible: description !== ""
    Layout.fillWidth: true
    // allow HTML like <i>...</i> in labels/descriptions
    textFormat: Text.StyledText
  }
}
