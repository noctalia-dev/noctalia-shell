import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

ColumnLayout {
  id: root
  spacing: Style.marginL
  Layout.fillWidth: true

  NComboBox {
    label: I18n.tr("common.position")
    description: I18n.tr("panels.launcher.settings-position-description")
    Layout.fillWidth: true
    model: [
      {
        "key": "follow_bar",
        "name": I18n.tr("positions.follow-bar")
      },
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
        "key": "bottom_left",
        "name": I18n.tr("positions.bottom-left")
      },
      {
        "key": "bottom_right",
        "name": I18n.tr("positions.bottom-right")
      },
      {
        "key": "bottom_center",
        "name": I18n.tr("positions.bottom-center")
      }
    ]
    currentKey: Settings.data.appLauncher.position
    onSelected: function (key) {
      Settings.data.appLauncher.position = key;
    }

    defaultValue: Settings.getDefaultValue("appLauncher.position")
  }

  NToggle {
    label: I18n.tr("tooltips.grid-view")
    description: I18n.tr("panels.launcher.settings-grid-view-description")
    checked: Settings.data.appLauncher.viewMode === "grid"
    onToggled: checked => Settings.data.appLauncher.viewMode = checked ? "grid" : "list"
    defaultValue: Settings.getDefaultValue("appLauncher.viewMode")
  }

  NToggle {
    label: I18n.tr("panels.launcher.settings-show-categories-label")
    description: I18n.tr("panels.launcher.settings-show-categories-description")
    checked: Settings.data.appLauncher.showCategories
    onToggled: checked => Settings.data.appLauncher.showCategories = checked
    defaultValue: Settings.getDefaultValue("appLauncher.showCategories")
  }

  NToggle {
    label: I18n.tr("panels.launcher.settings-sort-by-usage-label")
    description: I18n.tr("panels.launcher.settings-sort-by-usage-description")
    checked: Settings.data.appLauncher.sortByMostUsed
    onToggled: checked => Settings.data.appLauncher.sortByMostUsed = checked
    defaultValue: Settings.getDefaultValue("appLauncher.sortByMostUsed")
  }

  NToggle {
    label: I18n.tr("panels.launcher.settings-icon-mode-label")
    description: I18n.tr("panels.launcher.settings-icon-mode-description")
    checked: Settings.data.appLauncher.iconMode === "native"
    onToggled: checked => Settings.data.appLauncher.iconMode = checked ? "native" : "tabler"
    defaultValue: Settings.getDefaultValue("appLauncher.iconMode")
  }

  NToggle {
    label: I18n.tr("panels.launcher.settings-show-icon-background-label")
    description: I18n.tr("panels.launcher.settings-show-icon-background-description")
    checked: Settings.data.appLauncher.showIconBackground
    onToggled: checked => Settings.data.appLauncher.showIconBackground = checked
    defaultValue: Settings.getDefaultValue("appLauncher.showIconBackground")
  }

  NToggle {
    label: I18n.tr("panels.launcher.settings-ignore-mouse-input-label")
    description: I18n.tr("panels.launcher.settings-ignore-mouse-input-description")
    checked: Settings.data.appLauncher.ignoreMouseInput
    onToggled: checked => Settings.data.appLauncher.ignoreMouseInput = checked
    defaultValue: Settings.getDefaultValue("appLauncher.ignoreMouseInput")
  }
}
