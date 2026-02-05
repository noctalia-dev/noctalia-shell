import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

ColumnLayout {
  id: root
  spacing: Style.marginL
  Layout.fillWidth: true

  NCheckbox {
    Layout.fillWidth: true
    label: I18n.tr("panels.notifications.toast-media-label")
    description: I18n.tr("panels.notifications.toast-media-description")
    checked: Settings.data.notifications.enableMediaToast
    onToggled: checked => Settings.data.notifications.enableMediaToast = checked
  }

  NCheckbox {
    Layout.fillWidth: true
    label: I18n.tr("panels.notifications.toast-keyboard-label")
    description: I18n.tr("panels.notifications.toast-keyboard-description")
    checked: Settings.data.notifications.enableKeyboardLayoutToast
    onToggled: checked => Settings.data.notifications.enableKeyboardLayoutToast = checked
  }

  NDivider {
    Layout.fillWidth: true
  }

  RowLayout {

    NLabel {
      label: I18n.tr("panels.notifications.toast-battery-label")
      description: I18n.tr("panels.notifications.toast-battery-description")
    }

    Item {
      Layout.fillWidth: true
    }

    GridLayout {
      Layout.fillWidth: true
      columns: 2
      columnSpacing: Style.marginM
      rowSpacing: Style.marginM

      NText {
        Layout.alignment: Qt.AlignHCenter
        horizontalAlignment: Text.AlignHCenter
        text: I18n.tr("panels.system-monitor.threshold-warning")
        pointSize: Style.fontSizeS
        color: Color.mOnSurfaceVariant
      }

      NText {
        Layout.alignment: Qt.AlignHCenter
        horizontalAlignment: Text.AlignHCenter
        text: I18n.tr("panels.system-monitor.threshold-critical")
        pointSize: Style.fontSizeS
        color: Color.mOnSurfaceVariant
      }

      NSpinBox {
        Layout.alignment: Qt.AlignHCenter
        from: 0
        to: 100
        stepSize: 5
        value: Settings.data.notifications.batteryWarningThreshold
        defaultValue: Settings.getDefaultValue("notifications.batteryWarningThreshold")
        suffix: "%"
        onValueChanged: {
          Settings.data.notifications.batteryWarningThreshold = value;
          if (Settings.data.notifications.batteryCriticalThreshold > value) {
            Settings.data.notifications.batteryCriticalThreshold = value;
          }
        }
      }

      NSpinBox {
        Layout.alignment: Qt.AlignHCenter
        from: 0
        to: Settings.data.notifications.batteryWarningThreshold
        stepSize: 5
        value: Settings.data.notifications.batteryCriticalThreshold
        defaultValue: Settings.getDefaultValue("notifications.batteryCriticalThreshold")
        suffix: "%"
        onValueChanged: Settings.data.notifications.batteryCriticalThreshold = value
      }
    }
  }
}
