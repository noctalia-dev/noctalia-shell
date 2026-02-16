import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

ColumnLayout {
  id: root

  property string label: ""
  property string description: ""
  property string icon: ""
  property color labelColor: Color.mOnSurface
  property color descriptionColor: Color.mOnSurfaceVariant
  property color iconColor: Color.mOnSurface
  property bool showIndicator: false
  property string indicatorTooltip: ""

  opacity: enabled ? 1.0 : 0.6
  spacing: Style.marginXXS
  visible: root.label != "" || root.description != ""

  Layout.fillWidth: true

  RowLayout {
    spacing: Style.marginXS
    Layout.fillWidth: true
    visible: root.label !== ""

    NIcon {
      visible: root.icon !== ""
      icon: root.icon
      pointSize: Style.fontSizeXXL
      color: root.iconColor
      Layout.rightMargin: Style.marginS
    }

    NText {
      Layout.fillWidth: !root.showIndicator
      text: root.label
      pointSize: Style.fontSizeL
      font.weight: Style.fontWeightSemiBold
      color: labelColor
      wrapMode: Text.WordWrap
    }

    // Settings indicator
    Loader {
      active: root.showIndicator
      sourceComponent: NSettingsIndicator {
        show: true
        tooltipText: root.indicatorTooltip || ""
        Layout.alignment: Qt.AlignVCenter
      }
    }
  }

  NText {
    visible: root.description !== ""
    Layout.fillWidth: true
    text: root.description
    pointSize: Style.fontSizeS
    color: root.descriptionColor
    wrapMode: Text.WordWrap
    textFormat: Text.StyledText
  }
}
