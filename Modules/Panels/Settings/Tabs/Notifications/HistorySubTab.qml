import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

ColumnLayout {
  id: root
  spacing: Style.marginL
  Layout.fillWidth: true

  NHeader {
    label: I18n.tr("settings.notifications.duration.section.label")
    description: I18n.tr("settings.notifications.duration.section.description")
  }

  NToggle {
    label: I18n.tr("settings.notifications.duration.respect-expire.label")
    description: I18n.tr("settings.notifications.duration.respect-expire.description")
    checked: Settings.data.notifications.respectExpireTimeout
    onToggled: checked => Settings.data.notifications.respectExpireTimeout = checked
    isSettings: true
    defaultValue: Settings.getDefaultValue("notifications.respectExpireTimeout")
  }

  RowLayout {
    spacing: Style.marginL
    Layout.fillWidth: true

    NValueSlider {
      Layout.fillWidth: true
      label: I18n.tr("settings.notifications.duration.low-urgency.label")
      description: I18n.tr("settings.notifications.duration.low-urgency.description")
      from: 1
      to: 30
      stepSize: 1
      value: Settings.data.notifications.lowUrgencyDuration
      onMoved: value => Settings.data.notifications.lowUrgencyDuration = value
      text: Settings.data.notifications.lowUrgencyDuration + "s"
      isSettings: true
      defaultValue: Settings.getDefaultValue("notifications.lowUrgencyDuration")
    }

    Item {
      Layout.preferredWidth: 30 * Style.uiScaleRatio
      Layout.preferredHeight: 30 * Style.uiScaleRatio

      NIconButton {
        icon: "restore"
        baseSize: Style.baseWidgetSize * 0.8
        tooltipText: I18n.tr("settings.notifications.duration.reset")
        onClicked: Settings.data.notifications.lowUrgencyDuration = 3
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
      }
    }
  }

  RowLayout {
    spacing: Style.marginL
    Layout.fillWidth: true

    NValueSlider {
      Layout.fillWidth: true
      label: I18n.tr("settings.notifications.duration.normal-urgency.label")
      description: I18n.tr("settings.notifications.duration.normal-urgency.description")
      from: 1
      to: 30
      stepSize: 1
      value: Settings.data.notifications.normalUrgencyDuration
      onMoved: value => Settings.data.notifications.normalUrgencyDuration = value
      text: Settings.data.notifications.normalUrgencyDuration + "s"
      isSettings: true
      defaultValue: Settings.getDefaultValue("notifications.normalUrgencyDuration")
    }

    Item {
      Layout.preferredWidth: 30 * Style.uiScaleRatio
      Layout.preferredHeight: 30 * Style.uiScaleRatio

      NIconButton {
        icon: "restore"
        baseSize: Style.baseWidgetSize * 0.8
        tooltipText: I18n.tr("settings.notifications.duration.reset")
        onClicked: Settings.data.notifications.normalUrgencyDuration = 8
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
      }
    }
  }

  RowLayout {
    spacing: Style.marginL
    Layout.fillWidth: true

    NValueSlider {
      Layout.fillWidth: true
      label: I18n.tr("settings.notifications.duration.critical-urgency.label")
      description: I18n.tr("settings.notifications.duration.critical-urgency.description")
      from: 1
      to: 30
      stepSize: 1
      value: Settings.data.notifications.criticalUrgencyDuration
      onMoved: value => Settings.data.notifications.criticalUrgencyDuration = value
      text: Settings.data.notifications.criticalUrgencyDuration + "s"
      isSettings: true
      defaultValue: Settings.getDefaultValue("notifications.criticalUrgencyDuration")
    }

    Item {
      Layout.preferredWidth: 30 * Style.uiScaleRatio
      Layout.preferredHeight: 30 * Style.uiScaleRatio

      NIconButton {
        icon: "restore"
        baseSize: Style.baseWidgetSize * 0.8
        tooltipText: I18n.tr("settings.notifications.duration.reset")
        onClicked: Settings.data.notifications.criticalUrgencyDuration = 15
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
      }
    }
  }

  NDivider {
    Layout.fillWidth: true
    Layout.topMargin: Style.marginL
    Layout.bottomMargin: Style.marginL
  }

  NHeader {
    label: I18n.tr("settings.notifications.history.section.label")
    description: I18n.tr("settings.notifications.history.section.description")
  }

  NToggle {
    label: I18n.tr("settings.notifications.history.low-urgency.label")
    description: I18n.tr("settings.notifications.history.low-urgency.description")
    checked: Settings.data.notifications?.saveToHistory?.low !== false
    onToggled: checked => Settings.data.notifications.saveToHistory.low = checked
    isSettings: true
    defaultValue: Settings.getDefaultValue("notifications.saveToHistory.low")
  }

  NToggle {
    label: I18n.tr("settings.notifications.history.normal-urgency.label")
    description: I18n.tr("settings.notifications.history.normal-urgency.description")
    checked: Settings.data.notifications?.saveToHistory?.normal !== false
    onToggled: checked => Settings.data.notifications.saveToHistory.normal = checked
    isSettings: true
    defaultValue: Settings.getDefaultValue("notifications.saveToHistory.normal")
  }

  NToggle {
    label: I18n.tr("settings.notifications.history.critical-urgency.label")
    description: I18n.tr("settings.notifications.history.critical-urgency.description")
    checked: Settings.data.notifications?.saveToHistory?.critical !== false
    onToggled: checked => Settings.data.notifications.saveToHistory.critical = checked
    isSettings: true
    defaultValue: Settings.getDefaultValue("notifications.saveToHistory.critical")
  }
}
