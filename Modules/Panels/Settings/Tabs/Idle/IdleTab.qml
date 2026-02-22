import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Services.Power
import qs.Widgets

ColumnLayout {
  id: root
  spacing: Style.marginL

  // Master enable
  NToggle {
    Layout.fillWidth: true
    label: I18n.tr("panels.idle.enable-label")
    description: I18n.tr("panels.idle.enable-description")
    checked: Settings.data.idle.enabled
    defaultValue: Settings.getDefaultValue("idle.enabled")
    onToggled: checked => Settings.data.idle.enabled = checked
  }

  // Live idle status
  RowLayout {
    Layout.fillWidth: true
    visible: IdleService.nativeIdleMonitorAvailable

    NLabel {
      label: I18n.tr("panels.idle.status-label")
      description: I18n.tr("panels.idle.status-description")
    }

    Item {
      Layout.fillWidth: true
    }

    NText {
      Layout.alignment: Qt.AlignBottom | Qt.AlignRight
      text: IdleService.idleSeconds > 0 ? I18n.trp("common.second", IdleService.idleSeconds) : I18n.tr("common.active")
      family: Settings.data.ui.fontFixed
      pointSize: Style.fontSizeM
      color: IdleService.idleSeconds > 0 ? Color.mPrimary : Color.mOnSurfaceVariant
    }
  }

  NLabel {
    visible: !IdleService.nativeIdleMonitorAvailable
    description: I18n.tr("panels.idle.unavailable")
  }

  NDivider {
    Layout.fillWidth: true
  }

  // Timeout spinboxes (disabled when idle is off)
  ColumnLayout {
    Layout.fillWidth: true
    spacing: Style.marginL
    enabled: Settings.data.idle.enabled

    NLabel {
      label: I18n.tr("panels.idle.timeouts-label")
      description: I18n.tr("panels.idle.timeouts-description")
    }

    NSpinBox {
      label: I18n.tr("panels.idle.screen-off-label")
      description: I18n.tr("panels.idle.screen-off-description")
      from: 0
      to: 999
      value: Settings.data.idle.screenOffTimeout
      defaultValue: 0
      onValueChanged: Settings.data.idle.screenOffTimeout = value
    }

    NSpinBox {
      label: I18n.tr("panels.idle.lock-label")
      description: I18n.tr("panels.idle.lock-description")
      from: 0
      to: 999
      value: Settings.data.idle.lockTimeout
      defaultValue: 0
      onValueChanged: Settings.data.idle.lockTimeout = value
    }

    NSpinBox {
      label: I18n.tr("panels.idle.suspend-label")
      description: I18n.tr("panels.idle.suspend-description")
      from: 0
      to: 999
      value: Settings.data.idle.suspendTimeout
      defaultValue: 0
      onValueChanged: Settings.data.idle.suspendTimeout = value
    }
  }
}
