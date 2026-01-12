import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Services.Control
import qs.Services.UI
import qs.Widgets

ColumnLayout {
  id: contentColumn
  spacing: Style.marginL
  width: root.width

  // Enable/Disable Toggle
  NToggle {
    label: I18n.tr("panels.hooks.system-hooks-enable-label")
    description: I18n.tr("panels.hooks.system-hooks-enable-description")
    checked: Settings.data.hooks.enabled
    onToggled: checked => Settings.data.hooks.enabled = checked
  }

  ColumnLayout {
    visible: Settings.data.hooks.enabled
    spacing: Style.marginL
    Layout.fillWidth: true

    NDivider {
      Layout.fillWidth: true
    }

    // Wallpaper Hook Section
    NInputAction {
      id: wallpaperHookInput
      label: I18n.tr("panels.hooks.wallpaper-changed-label")
      description: I18n.tr("panels.hooks.wallpaper-changed-description")
      placeholderText: I18n.tr("panels.hooks.wallpaper-changed-placeholder")
      text: Settings.data.hooks.wallpaperChange
      onEditingFinished: {
        Settings.data.hooks.wallpaperChange = wallpaperHookInput.text;
      }
      onActionClicked: {
        if (wallpaperHookInput.text) {
          HooksService.executeWallpaperHook("test", "test-screen");
        }
      }
      Layout.fillWidth: true
    }

    NDivider {
      Layout.fillWidth: true
    }

    // Dark Mode Hook Section
    NInputAction {
      id: darkModeHookInput
      label: I18n.tr("panels.hooks.theme-changed-label")
      description: I18n.tr("panels.hooks.theme-changed-description")
      placeholderText: I18n.tr("panels.hooks.theme-changed-placeholder")
      text: Settings.data.hooks.darkModeChange
      onEditingFinished: {
        Settings.data.hooks.darkModeChange = darkModeHookInput.text;
      }
      onActionClicked: {
        if (darkModeHookInput.text) {
          HooksService.executeDarkModeHook(Settings.data.colorSchemes.darkMode);
        }
      }
      Layout.fillWidth: true
    }

    NDivider {
      Layout.fillWidth: true
    }

    // Screen Lock Hook Section
    NInputAction {
      id: screenLockHookInput
      label: I18n.tr("panels.hooks.screen-lock-label")
      description: I18n.tr("panels.hooks.screen-lock-description")
      placeholderText: I18n.tr("panels.hooks.screen-lock-placeholder")
      text: Settings.data.hooks.screenLock
      onEditingFinished: {
        Settings.data.hooks.screenLock = screenLockHookInput.text;
      }
      onActionClicked: {
        if (screenLockHookInput.text) {
          HooksService.executeLockHook();
        }
      }
      Layout.fillWidth: true
    }

    NDivider {
      Layout.fillWidth: true
    }

    // Screen Unlock Hook Section
    NInputAction {
      id: screenUnlockHookInput
      label: I18n.tr("panels.hooks.screen-unlock-label")
      description: I18n.tr("panels.hooks.screen-unlock-description")
      placeholderText: I18n.tr("panels.hooks.screen-unlock-placeholder")
      text: Settings.data.hooks.screenUnlock
      onEditingFinished: {
        Settings.data.hooks.screenUnlock = screenUnlockHookInput.text;
      }
      onActionClicked: {
        if (screenUnlockHookInput.text) {
          HooksService.executeUnlockHook();
        }
      }
      Layout.fillWidth: true
    }

    NDivider {
      Layout.fillWidth: true
    }

    // Performance Mode Enabled Hook Section
    NInputAction {
      id: performanceModeEnabledHookInput
      label: I18n.tr("panels.hooks.performance-mode-enabled-label")
      description: I18n.tr("panels.hooks.performance-mode-enabled-description")
      placeholderText: I18n.tr("panels.hooks.performance-mode-enabled-placeholder")
      text: Settings.data.hooks.performanceModeEnabled
      onEditingFinished: {
        Settings.data.hooks.performanceModeEnabled = performanceModeEnabledHookInput.text;
      }
      onActionClicked: {
        if (performanceModeEnabledHookInput.text) {
          HooksService.executePerformanceModeEnabledHook();
        }
      }
      Layout.fillWidth: true
    }

    NDivider {
      Layout.fillWidth: true
    }

    // Performance Mode Disabled Hook Section
    NInputAction {
      id: performanceModeDisabledHookInput
      label: I18n.tr("panels.hooks.performance-mode-disabled-label")
      description: I18n.tr("panels.hooks.performance-mode-disabled-description")
      placeholderText: I18n.tr("panels.hooks.performance-mode-disabled-placeholder")
      text: Settings.data.hooks.performanceModeDisabled
      onEditingFinished: {
        Settings.data.hooks.performanceModeDisabled = performanceModeDisabledHookInput.text;
      }
      onActionClicked: {
        if (performanceModeDisabledHookInput.text) {
          HooksService.executePerformanceModeDisabledHook();
        }
      }
      Layout.fillWidth: true
    }

    NDivider {
      Layout.fillWidth: true
    }

    // Session Hook Section
    NInputAction {
      id: sessionHookInput
      label: I18n.tr("panels.hooks.session-label")
      description: I18n.tr("panels.hooks.session-description")
      placeholderText: I18n.tr("panels.hooks.session-placeholder")
      text: Settings.data.hooks.session
      onEditingFinished: {
        Settings.data.hooks.session = sessionHookInput.text;
      }
      onActionClicked: {
        if (sessionHookInput.text) {
          Quickshell.execDetached(["sh", "-c", sessionHookInput.text + " test"]);
        }
      }
      Layout.fillWidth: true
    }

    NDivider {
      Layout.fillWidth: true
    }

    // Info section
    ColumnLayout {
      spacing: Style.marginM
      Layout.fillWidth: true

      NLabel {
        label: I18n.tr("panels.hooks.info-command-info-label")
        description: I18n.tr("panels.hooks.info-command-info-description")
      }

      NLabel {
        label: I18n.tr("panels.hooks.info-parameters-label")
        description: I18n.tr("panels.hooks.info-parameters-description")
      }
    }
  }

  NDivider {
    Layout.fillWidth: true
  }
}
