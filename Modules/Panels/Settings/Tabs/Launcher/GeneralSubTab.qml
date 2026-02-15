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
    label: I18n.tr("panels.launcher.settings-overlay-layer-label")
    description: I18n.tr("panels.launcher.settings-overlay-layer-description")
    checked: Settings.data.appLauncher.overviewLayer
    onToggled: checked => Settings.data.appLauncher.overviewLayer = checked
    defaultValue: Settings.getDefaultValue("appLauncher.overviewLayer")
  }

  NComboBox {
    label: I18n.tr("panels.launcher.settings-view-mode-label")
    description: I18n.tr("panels.launcher.settings-view-mode-description")
    Layout.fillWidth: true
    model: [
      {
        "key": "list",
        "name": I18n.tr("options.launcher-view-mode.list")
      },
      {
        "key": "grid",
        "name": I18n.tr("options.launcher-view-mode.grid")
      }
    ]
    currentKey: Settings.data.appLauncher.viewMode
    onSelected: function (key) {
      Settings.data.appLauncher.viewMode = key;
    }
    defaultValue: Settings.getDefaultValue("appLauncher.viewMode")
  }

  NComboBox {
    label: I18n.tr("panels.launcher.settings-density-label")
    description: I18n.tr("panels.launcher.settings-density-description")
    Layout.fillWidth: true
    model: [
      {
        "key": "compact",
        "name": I18n.tr("options.launcher-density.compact")
      },
      {
        "key": "default",
        "name": I18n.tr("options.launcher-density.default")
      },
      {
        "key": "comfortable",
        "name": I18n.tr("options.launcher-density.comfortable")
      }
    ]
    currentKey: Settings.data.appLauncher.density || "compact"
    onSelected: function (key) {
      Settings.data.appLauncher.density = key;
    }
    defaultValue: Settings.getDefaultValue("appLauncher.density")
  }

  NToggle {
    label: I18n.tr("panels.launcher.settings-show-categories-label")
    description: I18n.tr("panels.launcher.settings-show-categories-description")
    checked: Settings.data.appLauncher.showCategories
    onToggled: checked => Settings.data.appLauncher.showCategories = checked
    defaultValue: Settings.getDefaultValue("appLauncher.showCategories")
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

  NDivider {
    Layout.fillWidth: true
  }

  NToggle {
    label: I18n.tr("panels.launcher.settings-sort-by-usage-label")
    description: I18n.tr("panels.launcher.settings-sort-by-usage-description")
    checked: Settings.data.appLauncher.sortByMostUsed
    onToggled: checked => Settings.data.appLauncher.sortByMostUsed = checked
    defaultValue: Settings.getDefaultValue("appLauncher.sortByMostUsed")
  }

  NToggle {
    label: I18n.tr("panels.launcher.settings-enable-settings-search-label")
    description: I18n.tr("panels.launcher.settings-enable-settings-search-description")
    checked: Settings.data.appLauncher.enableSettingsSearch
    onToggled: checked => Settings.data.appLauncher.enableSettingsSearch = checked
    defaultValue: Settings.getDefaultValue("appLauncher.enableSettingsSearch")
  }

  NToggle {
    label: I18n.tr("panels.launcher.settings-enable-windows-search-label")
    description: I18n.tr("panels.launcher.settings-enable-windows-search-description")
    checked: Settings.data.appLauncher.enableWindowsSearch
    onToggled: checked => Settings.data.appLauncher.enableWindowsSearch = checked
    defaultValue: Settings.getDefaultValue("appLauncher.enableWindowsSearch")
  }

  NToggle {
    label: I18n.tr("panels.launcher.settings-enable-session-search-label")
    description: I18n.tr("panels.launcher.settings-enable-session-search-description")
    checked: Settings.data.appLauncher.enableSessionSearch
    onToggled: checked => Settings.data.appLauncher.enableSessionSearch = checked
    defaultValue: Settings.getDefaultValue("appLauncher.enableSessionSearch")
  }

  NToggle {
    label: I18n.tr("panels.launcher.settings-ignore-mouse-input-label")
    description: I18n.tr("panels.launcher.settings-ignore-mouse-input-description")
    checked: Settings.data.appLauncher.ignoreMouseInput
    onToggled: checked => Settings.data.appLauncher.ignoreMouseInput = checked
    defaultValue: Settings.getDefaultValue("appLauncher.ignoreMouseInput")
  }
}
