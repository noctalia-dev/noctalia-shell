import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

ColumnLayout {
  id: root
  spacing: Style.marginL

  RowLayout {
    Layout.fillWidth: true
    spacing: Style.marginM

    NLabel {
      Layout.fillWidth: true
      label: I18n.tr("panels.lock-screen.grace-period-label")
      description: I18n.tr("panels.lock-screen.grace-period-description")
      showIndicator: (Settings.getDefaultValue("general.lockScreenGracePeriod") > 0) !== (Settings.data.general.lockScreenGracePeriod > 0)
      indicatorTooltip: I18n.tr("panels.indicator.default-value", {
                                  "value": String(Settings.getDefaultValue("general.lockScreenGracePeriod") > 0)
                                })
    }

    TextField {
      visible: Settings.data.general.lockScreenGracePeriod > 0
      implicitWidth: 70 * Style.uiScaleRatio
      Layout.alignment: Qt.AlignVCenter
      text: Settings.data.general.lockScreenGracePeriod.toString()
      placeholderText: "5"
      horizontalAlignment: TextInput.AlignHCenter
      color: Color.mOnSurface
      font.pixelSize: Style.fontSizeM * Style.uiScaleRatio
      font.family: Settings.data.ui.fontDefault
      validator: IntValidator {
        bottom: 1
        top: 3600
      }
      onTextChanged: {
        var val = parseInt(text);
        if (!isNaN(val) && val > 0)
          Settings.data.general.lockScreenGracePeriod = val;
      }

      background: Rectangle {
        radius: Style.iRadiusM
        color: Color.mSurface
        border.color: parent.activeFocus ? Color.mSecondary : Color.mOutline
        border.width: Style.borderS
        implicitHeight: 36 * Style.uiScaleRatio
      }
    }

    NText {
      visible: Settings.data.general.lockScreenGracePeriod > 0
      text: "s"
      pointSize: Style.fontSizeM
      color: Color.mOnSurfaceVariant
      Layout.alignment: Qt.AlignVCenter
    }

    Rectangle {
      id: graceSwitch
      opacity: enabled ? 1.0 : 0.6
      Layout.alignment: Qt.AlignVCenter
      Layout.margins: Style.borderS
      implicitWidth: Math.round(Style.baseWidgetSize * 0.8 * Style.uiScaleRatio * .85) * 2
      implicitHeight: Math.round(Style.baseWidgetSize * 0.8 * Style.uiScaleRatio * .5) * 2
      radius: Math.min(Style.iRadiusL, height / 2)
      color: Settings.data.general.lockScreenGracePeriod > 0 ? Color.mPrimary : Color.mSurface
      border.color: Color.mOutline
      border.width: Style.borderS

      Behavior on color {
        ColorAnimation {
          duration: Style.animationFast
        }
      }

      Behavior on border.color {
        ColorAnimation {
          duration: Style.animationFast
        }
      }

      Rectangle {
        implicitWidth: Math.round(Style.baseWidgetSize * 0.8 * Style.uiScaleRatio * 0.4) * 2
        implicitHeight: Math.round(Style.baseWidgetSize * 0.8 * Style.uiScaleRatio * 0.4) * 2
        radius: Math.min(Style.iRadiusL, height / 2)
        color: Settings.data.general.lockScreenGracePeriod > 0 ? Color.mOnPrimary : Color.mPrimary
        border.color: Settings.data.general.lockScreenGracePeriod > 0 ? Color.mSurface : Color.mSurface
        border.width: Style.borderM
        anchors.verticalCenter: parent.verticalCenter
        x: Settings.data.general.lockScreenGracePeriod > 0 ? graceSwitch.width - width - 3 : 3

        Behavior on x {
          NumberAnimation {
            duration: Style.animationFast
            easing.type: Easing.OutCubic
          }
        }
      }

      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        hoverEnabled: true
        onClicked: {
          var newVal = Settings.data.general.lockScreenGracePeriod > 0 ? 0 : 5;
          Settings.data.general.lockScreenGracePeriod = newVal;
        }
      }
    }
  }

  NToggle {
    label: I18n.tr("panels.lock-screen.lock-on-suspend-label")
    description: I18n.tr("panels.lock-screen.lock-on-suspend-description")
    checked: Settings.data.general.lockOnSuspend
    onToggled: checked => Settings.data.general.lockOnSuspend = checked
    defaultValue: Settings.getDefaultValue("general.lockOnSuspend")
  }

  NToggle {
    label: I18n.tr("panels.lock-screen.auto-start-auth-label")
    description: I18n.tr("panels.lock-screen.auto-start-auth-description")
    checked: Settings.data.general.autoStartAuth
    onToggled: checked => Settings.data.general.autoStartAuth = checked
    defaultValue: Settings.getDefaultValue("general.autoStartAuth")
  }

  NToggle {
    label: I18n.tr("panels.lock-screen.allow-password-with-fprintd-label")
    description: I18n.tr("panels.lock-screen.allow-password-with-fprintd-description")
    checked: Settings.data.general.allowPasswordWithFprintd
    onToggled: checked => Settings.data.general.allowPasswordWithFprintd = checked
    defaultValue: Settings.getDefaultValue("general.allowPasswordWithFprintd")
  }

  NToggle {
    label: I18n.tr("panels.lock-screen.show-session-buttons-label")
    description: I18n.tr("panels.lock-screen.show-session-buttons-description")
    checked: Settings.data.general.showSessionButtonsOnLockScreen
    onToggled: checked => Settings.data.general.showSessionButtonsOnLockScreen = checked
    defaultValue: Settings.getDefaultValue("general.showSessionButtonsOnLockScreen")
  }

  NToggle {
    label: I18n.tr("panels.lock-screen.show-hibernate-label")
    description: I18n.tr("panels.lock-screen.show-hibernate-description")
    checked: Settings.data.general.showHibernateOnLockScreen
    onToggled: checked => Settings.data.general.showHibernateOnLockScreen = checked
    visible: Settings.data.general.showSessionButtonsOnLockScreen
    defaultValue: Settings.getDefaultValue("general.showSessionButtonsOnLockScreen")
  }

  NToggle {
    label: I18n.tr("panels.session-menu.enable-countdown-label")
    description: I18n.tr("panels.session-menu.enable-countdown-description")
    checked: Settings.data.general.enableLockScreenCountdown
    onToggled: checked => Settings.data.general.enableLockScreenCountdown = checked
    visible: Settings.data.general.showSessionButtonsOnLockScreen
    defaultValue: Settings.getDefaultValue("general.enableLockScreenCountdown")
  }

  NValueSlider {
    visible: Settings.data.general.showSessionButtonsOnLockScreen && Settings.data.general.enableLockScreenCountdown
    Layout.fillWidth: true
    label: I18n.tr("panels.session-menu.countdown-duration-label")
    description: I18n.tr("panels.session-menu.countdown-duration-description")
    from: 1000
    to: 30000
    stepSize: 1000
    showReset: true
    value: Settings.data.general.lockScreenCountdownDuration
    onMoved: value => Settings.data.general.lockScreenCountdownDuration = value
    text: Math.round(Settings.data.general.lockScreenCountdownDuration / 1000) + "s"
    defaultValue: Settings.getDefaultValue("general.lockScreenCountdownDuration")
  }
}
