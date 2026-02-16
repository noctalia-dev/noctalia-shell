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
    Layout.fillWidth: true
    label: I18n.tr("panels.session-menu.large-buttons-style-label")
    description: I18n.tr("panels.session-menu.large-buttons-style-description")
    checked: Settings.data.sessionMenu.largeButtonsStyle
    onToggled: checked => Settings.data.sessionMenu.largeButtonsStyle = checked
  }

  NComboBox {
    visible: Settings.data.sessionMenu.largeButtonsStyle
    Layout.fillWidth: true
    label: I18n.tr("panels.session-menu.large-buttons-layout-label")
    description: I18n.tr("panels.session-menu.large-buttons-layout-description")
    model: [
      {
        "key": "grid",
        "name": I18n.tr("options.session-menu-grid-layout.grid")
      },
      {
        "key": "single-row",
        "name": I18n.tr("options.session-menu-grid-layout.single-row")
      }
    ]
    currentKey: Settings.data.sessionMenu.largeButtonsLayout
    defaultValue: Settings.getDefaultValue("sessionMenu.largeButtonsLayout")
    onSelected: key => Settings.data.sessionMenu.largeButtonsLayout = key
  }

  NComboBox {
    label: I18n.tr("common.position")
    description: I18n.tr("panels.session-menu.position-description")
    Layout.fillWidth: true
    model: [
      {
        "key": "center",
        "name": I18n.tr("positions.center")
      },
      {
        "key": "top_center",
        "name": I18n.tr("positions.top-center")
      },
      {
        "key": "top_left",
        "name": I18n.tr("positions.top-left")
      },
      {
        "key": "top_right",
        "name": I18n.tr("positions.top-right")
      },
      {
        "key": "bottom_center",
        "name": I18n.tr("positions.bottom-center")
      },
      {
        "key": "bottom_left",
        "name": I18n.tr("positions.bottom-left")
      },
      {
        "key": "bottom_right",
        "name": I18n.tr("positions.bottom-right")
      }
    ]
    currentKey: Settings.data.sessionMenu.position
    onSelected: key => Settings.data.sessionMenu.position = key
    visible: !Settings.data.sessionMenu.largeButtonsStyle
    defaultValue: Settings.getDefaultValue("sessionMenu.position")
  }

  NToggle {
    Layout.fillWidth: true
    label: I18n.tr("panels.session-menu.show-header-label")
    description: I18n.tr("panels.session-menu.show-header-description")
    checked: Settings.data.sessionMenu.showHeader
    onToggled: checked => Settings.data.sessionMenu.showHeader = checked
    visible: !Settings.data.sessionMenu.largeButtonsStyle
    defaultValue: Settings.getDefaultValue("sessionMenu.showHeader")
  }

  NToggle {
    Layout.fillWidth: true
    label: I18n.tr("panels.session-menu.show-keybinds-label")
    description: I18n.tr("panels.session-menu.show-keybinds-description")
    checked: Settings.data.sessionMenu.showKeybinds
    onToggled: checked => Settings.data.sessionMenu.showKeybinds = checked
    defaultValue: Settings.getDefaultValue("sessionMenu.showKeybinds")
  }

  NToggle {
    Layout.fillWidth: true
    label: I18n.tr("panels.session-menu.enable-countdown-label")
    description: I18n.tr("panels.session-menu.enable-countdown-description")
    checked: Settings.data.sessionMenu.enableCountdown
    onToggled: checked => Settings.data.sessionMenu.enableCountdown = checked
    defaultValue: Settings.getDefaultValue("sessionMenu.enableCountdown")
  }

  NValueSlider {
    visible: Settings.data.sessionMenu.enableCountdown
    Layout.fillWidth: true
    label: I18n.tr("panels.session-menu.countdown-duration-label")
    description: I18n.tr("panels.session-menu.countdown-duration-description")
    from: 1000
    to: 30000
    stepSize: 1000
    value: Settings.data.sessionMenu.countdownDuration
    onMoved: value => Settings.data.sessionMenu.countdownDuration = value
    text: Math.round(Settings.data.sessionMenu.countdownDuration / 1000) + "s"
    defaultValue: Settings.getDefaultValue("sessionMenu.countdownDuration")
  }

  NToggle {
    Layout.fillWidth: true
    label: I18n.tr("panels.session-menu.show-blur-background-label")
    description: I18n.tr("panels.session-menu.show-blur-background-description")
    checked: Settings.data.sessionMenu.showBlurBackground
    onToggled: checked => Settings.data.sessionMenu.showBlurBackground = checked
  }

  NComboBox {
    label: I18n.tr("panels.session-menu.blur-color-label")
    description: I18n.tr("panels.session-menu.blur-color-description")
    Layout.fillWidth: true
    model: [
      {
        "key": "mPrimary",
        "name": I18n.tr("common.primary")
      },
      {
        "key": "mOnPrimary",
        "name": I18n.tr("common.on-primary")
      },
      {
        "key": "mSecondary",
        "name": I18n.tr("common.secondary")
      },
      {
        "key": "mOnSecondary",
        "name": I18n.tr("common.on-secondary")
      },
      {
        "key": "mTertiary",
        "name": I18n.tr("common.tertiary")
      },
      {
        "key": "mOnTertiary",
        "name": I18n.tr("common.on-tertiary")
      },
      {
        "key": "mError",
        "name": I18n.tr("common.error")
      },
      {
        "key": "mOnError",
        "name": I18n.tr("common.on-error")
      },
      {
        "key": "mSurface",
        "name": I18n.tr("common.surface")
      },
      {
        "key": "mOnSurface",
        "name": I18n.tr("common.on-surface")
      },
      {
        "key": "mSurfaceVariant",
        "name": I18n.tr("common.surface-variant")
      },
      {
        "key": "mOnSurfaceVariant",
        "name": I18n.tr("common.on-surface-variant")
      },
      {
        "key": "mOutline",
        "name": I18n.tr("common.outline")
      },
      {
        "key": "mShadow",
        "name": I18n.tr("common.shadow")
      },
      {
        "key": "mHover",
        "name": I18n.tr("common.hover")
      },
      {
        "key": "mOnHover",
        "name": I18n.tr("common.on-hover")
      }
    ]

    currentKey: Settings.data.sessionMenu.blurColor
    onSelected: key => Settings.data.sessionMenu.blurColor = key
    visible: Settings.data.sessionMenu.showBlurBackground
    defaultValue: Settings.getDefaultValue("sessionMenu.blurColor")
  }
}
