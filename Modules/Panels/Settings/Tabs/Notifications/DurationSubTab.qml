import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

ColumnLayout {
  id: root
  spacing: Style.marginL
  Layout.fillWidth: true

  NToggle {
    label: I18n.tr("panels.notifications.duration-respect-expire-label")
    description: I18n.tr("panels.notifications.duration-respect-expire-description")
    checked: Settings.data.notifications.respectExpireTimeout
    onToggled: checked => Settings.data.notifications.respectExpireTimeout = checked
    defaultValue: Settings.getDefaultValue("notifications.respectExpireTimeout")
  }

  RowLayout {
    spacing: Style.marginL
    Layout.fillWidth: true

    NValueSlider {
      Layout.fillWidth: true
      label: I18n.tr("panels.notifications.duration-low-urgency-label")
      description: I18n.tr("panels.notifications.duration-low-urgency-description")
      from: 1
      to: 30
      stepSize: 1
      value: Settings.data.notifications.lowUrgencyDuration
      onMoved: value => Settings.data.notifications.lowUrgencyDuration = value
      text: Settings.data.notifications.lowUrgencyDuration + "s"
      defaultValue: Settings.getDefaultValue("notifications.lowUrgencyDuration")
    }

    Item {
      Layout.preferredWidth: 30 * Style.uiScaleRatio
      Layout.preferredHeight: 30 * Style.uiScaleRatio

      NIconButton {
        icon: "restore"
        baseSize: Style.baseWidgetSize * 0.8
        tooltipText: I18n.tr("panels.notifications.duration-reset")
        onClicked: Settings.data.notifications.lowUrgencyDuration = Settings.getDefaultValue("notifications.lowUrgencyDuration")
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
      label: I18n.tr("panels.notifications.duration-normal-urgency-label")
      description: I18n.tr("panels.notifications.duration-normal-urgency-description")
      from: 1
      to: 30
      stepSize: 1
      value: Settings.data.notifications.normalUrgencyDuration
      onMoved: value => Settings.data.notifications.normalUrgencyDuration = value
      text: Settings.data.notifications.normalUrgencyDuration + "s"
      defaultValue: Settings.getDefaultValue("notifications.normalUrgencyDuration")
    }

    Item {
      Layout.preferredWidth: 30 * Style.uiScaleRatio
      Layout.preferredHeight: 30 * Style.uiScaleRatio

      NIconButton {
        icon: "restore"
        baseSize: Style.baseWidgetSize * 0.8
        tooltipText: I18n.tr("panels.notifications.duration-reset")
        onClicked: Settings.data.notifications.normalUrgencyDuration = Settings.getDefaultValue("notifications.normalUrgencyDuration")
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
      label: I18n.tr("panels.notifications.duration-critical-urgency-label")
      description: I18n.tr("panels.notifications.duration-critical-urgency-description")
      from: 1
      to: 30
      stepSize: 1
      value: Settings.data.notifications.criticalUrgencyDuration
      onMoved: value => Settings.data.notifications.criticalUrgencyDuration = value
      text: Settings.data.notifications.criticalUrgencyDuration + "s"
      defaultValue: Settings.getDefaultValue("notifications.criticalUrgencyDuration")
    }

    Item {
      Layout.preferredWidth: 30 * Style.uiScaleRatio
      Layout.preferredHeight: 30 * Style.uiScaleRatio

      NIconButton {
        icon: "restore"
        baseSize: Style.baseWidgetSize * 0.8
        tooltipText: I18n.tr("panels.notifications.duration-reset")
        onClicked: Settings.data.notifications.criticalUrgencyDuration = Settings.getDefaultValue("notifications.criticalUrgencyDuration")
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
      }
    }
  }
}
