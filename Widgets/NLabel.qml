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
  property real labelSize: Style.fontSizeL

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
      id: labelText
      Layout.fillWidth: true
      text: root.label
      pointSize: root.labelSize
      font.weight: Style.fontWeightSemiBold
      color: labelColor
      wrapMode: Text.WordWrap

      // Settings indicator dot positioned right after the text content
      Loader {
        active: root.showIndicator
        x: labelText.contentWidth + Style.marginXS
        anchors.verticalCenter: parent.verticalCenter
        sourceComponent: NSettingsIndicator {
          show: true
          tooltipText: root.indicatorTooltip || ""
        }
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
