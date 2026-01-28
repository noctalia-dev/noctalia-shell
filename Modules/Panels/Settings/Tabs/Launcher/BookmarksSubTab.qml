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
    label: I18n.tr("panels.launcher.settings-enable-bookmarks-label")
    description: I18n.tr("panels.launcher.settings-enable-bookmarks-description")
    checked: Settings.data.appLauncher.enableBookmarks
    onToggled: checked => Settings.data.appLauncher.enableBookmarks = checked
    defaultValue: Settings.getDefaultValue("appLauncher.enableBookmarks")
  }

  NDivider {
    Layout.fillWidth: true
  }

  NLabel {
    label: I18n.tr("panels.launcher.settings-bookmarks-browsers-label")
    description: I18n.tr("panels.launcher.settings-bookmarks-browsers-description")
    Layout.fillWidth: true
  }

  ColumnLayout {
    spacing: Style.marginS
    Layout.fillWidth: true
    Layout.leftMargin: Style.marginL
    enabled: Settings.data.appLauncher.enableBookmarks

    NCheckbox {
      label: "Google Chrome"
      checked: (Settings.data.appLauncher.bookmarksBrowsers || []).includes("chrome")
      onToggled: function(checked) { toggleBrowser("chrome", checked) }
    }

    NCheckbox {
      label: "Chromium"
      checked: (Settings.data.appLauncher.bookmarksBrowsers || []).includes("chromium")
      onToggled: function(checked) { toggleBrowser("chromium", checked) }
    }

    NCheckbox {
      label: "Brave"
      checked: (Settings.data.appLauncher.bookmarksBrowsers || []).includes("brave")
      onToggled: function(checked) { toggleBrowser("brave", checked) }
    }

    NCheckbox {
      label: "Microsoft Edge"
      checked: (Settings.data.appLauncher.bookmarksBrowsers || []).includes("edge")
      onToggled: function(checked) { toggleBrowser("edge", checked) }
    }

    NCheckbox {
      label: "Vivaldi"
      checked: (Settings.data.appLauncher.bookmarksBrowsers || []).includes("vivaldi")
      onToggled: function(checked) { toggleBrowser("vivaldi", checked) }
    }

    NCheckbox {
      label: "Opera"
      checked: (Settings.data.appLauncher.bookmarksBrowsers || []).includes("opera")
      onToggled: function(checked) { toggleBrowser("opera", checked) }
    }

    NCheckbox {
      label: "Firefox"
      checked: (Settings.data.appLauncher.bookmarksBrowsers || []).includes("firefox")
      onToggled: function(checked) { toggleBrowser("firefox", checked) }
    }

    NCheckbox {
      label: "Firefox Developer Edition"
      checked: (Settings.data.appLauncher.bookmarksBrowsers || []).includes("firefox-dev")
      onToggled: function(checked) { toggleBrowser("firefox-dev", checked) }
    }

    NCheckbox {
      label: "LibreWolf"
      checked: (Settings.data.appLauncher.bookmarksBrowsers || []).includes("librewolf")
      onToggled: function(checked) { toggleBrowser("librewolf", checked) }
    }

    NCheckbox {
      label: "Zen Browser"
      checked: (Settings.data.appLauncher.bookmarksBrowsers || []).includes("zen")
      onToggled: function(checked) { toggleBrowser("zen", checked) }
    }
  }

  function toggleBrowser(browserId, enabled) {
    let browsers = (Settings.data.appLauncher.bookmarksBrowsers || []).slice();
    if (enabled && !browsers.includes(browserId)) {
      browsers.push(browserId);
    } else if (!enabled) {
      browsers = browsers.filter(b => b !== browserId);
    }
    Settings.data.appLauncher.bookmarksBrowsers = browsers;
  }

  Item {
    Layout.fillHeight: true
  }

  NLabel {
    label: I18n.tr("panels.launcher.settings-bookmarks-hint")
    opacity: 0.7
    Layout.fillWidth: true
  }
}
