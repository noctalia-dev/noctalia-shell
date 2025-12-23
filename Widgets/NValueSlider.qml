import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

ColumnLayout {
  id: root

  property real from: 0
  property real to: 1
  property real value: 0
  property real stepSize: 0.01
  property var cutoutColor: Color.mSurface
  property bool snapAlways: true
  property real heightRatio: 0.7
  property string text: ""
  property real textSize: Style.fontSizeM
  property real customHeight: -1
  property real customHeightRatio: -1
  property string label: ""
  property string description: ""
  property bool isSettings: false
  property var defaultValue: 0

  // Signals
  signal moved(real value)
  signal pressedChanged(bool pressed, real value)

  spacing: Style.marginS
  Layout.fillWidth: true

  readonly property bool isValueChanged: isSettings && (value !== defaultValue)
  readonly property string indicatorTooltip: {
    if (!isSettings)
      return "";
    var defaultVal = defaultValue;
    if (typeof defaultVal === "number") {
      // If it's a decimal between 0 and 1, format as percentage
      if (defaultVal > 0 && defaultVal <= 1 && from >= 0 && from < 1) {
        return I18n.tr("settings.indicator.default-value", {
                         "value": Math.floor(defaultVal * 100) + "%"
                       });
      }
      return I18n.tr("settings.indicator.default-value", {
                       "value": String(defaultVal)
                     });
    }
    return I18n.tr("settings.indicator.default-value", {
                     "value": String(defaultVal)
                   });
  }

  NLabel {
    label: root.label
    description: root.description
    visible: root.label !== "" || root.description !== ""
    showIndicator: root.isSettings && root.isValueChanged
    indicatorTooltip: root.indicatorTooltip
    Layout.fillWidth: true
  }

  RowLayout {
    spacing: Style.marginL
    Layout.fillWidth: true

    NSlider {
      id: slider
      Layout.fillWidth: true
      from: root.from
      to: root.to
      value: root.value
      stepSize: root.stepSize
      cutoutColor: root.cutoutColor
      snapAlways: root.snapAlways
      heightRatio: root.customHeightRatio > 0 ? root.customHeightRatio : root.heightRatio
      onMoved: root.moved(value)
      onPressedChanged: root.pressedChanged(pressed, value)
    }

    NText {
      visible: root.text !== ""
      text: root.text
      pointSize: root.textSize
      family: Settings.data.ui.fontFixed
      Layout.alignment: Qt.AlignVCenter
      Layout.preferredWidth: 45 * Style.uiScaleRatio
      horizontalAlignment: Text.AlignRight
    }
  }
}
