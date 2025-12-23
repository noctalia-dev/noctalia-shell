import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Services.Noctalia
import qs.Services.UI
import qs.Widgets

Popup {
  id: root
  modal: true
  dim: false
  anchors.centerIn: parent
  width: Math.max(settingsContent.implicitWidth + padding * 2, 500 * Style.uiScaleRatio)
  height: settingsContent.implicitHeight + padding * 2
  padding: Style.marginXL

  property var currentPlugin: null
  property var currentPluginApi: null
  property bool showToastOnSave: false

  background: Rectangle {
    color: Color.mSurface
    radius: Style.radiusL
    border.color: Color.mPrimary
    border.width: Style.borderM
  }

  contentItem: FocusScope {
    focus: true

    ColumnLayout {
      id: settingsContent
      anchors.fill: parent
      spacing: Style.marginM

      // Header
      RowLayout {
        Layout.fillWidth: true

        NText {
          text: I18n.tr("settings.plugins.plugin-settings-title", {
                          "plugin": root.currentPlugin?.name || ""
                        })
          pointSize: Style.fontSizeL
          font.weight: Style.fontWeightBold
          color: Color.mPrimary
          Layout.fillWidth: true
        }

        NIconButton {
          icon: "close"
          tooltipText: I18n.tr("tooltips.close")
          onClicked: root.close()
        }
      }

      // Separator
      Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 1
        color: Color.mOutline
      }

      // Settings loader - pluginApi is passed via setSource() in openPluginSettings()
      Loader {
        id: settingsLoader
        Layout.fillWidth: true
      }

      // Action buttons
      RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: Style.marginM
        spacing: Style.marginM

        Item {
          Layout.fillWidth: true
        }

        NButton {
          text: I18n.tr("common.cancel")
          outlined: true
          onClicked: root.close()
        }

        NButton {
          text: I18n.tr("common.apply")
          icon: "check"
          onClicked: {
            if (settingsLoader.item && settingsLoader.item.saveSettings) {
              settingsLoader.item.saveSettings();
              root.close();
              if (root.showToastOnSave) {
                ToastService.showNotice(I18n.tr("settings.plugins.settings-saved"));
              }
            }
          }
        }
      }
    }
  }

  onClosed: {
    settingsLoader.source = "";
    currentPlugin = null;
    currentPluginApi = null;
  }

  function openPluginSettings(pluginManifest) {
    currentPlugin = pluginManifest;

    // Get plugin API
    currentPluginApi = PluginService.getPluginAPI(pluginManifest.id);
    if (!currentPluginApi) {
      Logger.e("NPluginSettingsPopup", "Cannot open settings: plugin not loaded:", pluginManifest.id);
      if (showToastOnSave) {
        ToastService.showNotice(I18n.tr("settings.plugins.settings-error-not-loaded"));
      }
      return;
    }

    // Get plugin directory
    var pluginDir = PluginRegistry.getPluginDir(pluginManifest.id);
    var settingsPath = pluginDir + "/" + pluginManifest.entryPoints.settings;

    // Load settings component
    settingsLoader.setSource("file://" + settingsPath, {
                               "pluginApi": currentPluginApi
                             });

    open();
  }
}
