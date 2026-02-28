import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Services.Noctalia
import qs.Services.UI
import qs.Widgets

NPopup {
  id: root
  modal: true
  dim: false
  anchors.centerIn: parent
  property var screen: null
  readonly property real maxHeight: (screen ? screen.height : (parent ? parent.height : 800)) * 0.8

  width: Math.max(settingsContent.implicitWidth + padding * 2, 600 * Style.uiScaleRatio)
  height: Math.min(settingsContent.implicitHeight + padding * 2, maxHeight)
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
          text: I18n.tr("panels.plugins.plugin-settings-title", {
                          "plugin": root.currentPlugin?.name || ""
                        })
          pointSize: Style.fontSizeL
          font.weight: Style.fontWeightBold
          color: Color.mPrimary
          Layout.fillWidth: true
        }

        NIconButton {
          icon: "close"
          tooltipText: I18n.tr("common.close")
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
      NScrollView {
        id: settingsScrollView
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.minimumHeight: 100
        horizontalPolicy: ScrollBar.AlwaysOff
        gradientColor: Color.mSurface

        Loader {
          id: settingsLoader
          width: settingsScrollView.availableWidth
        }
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
          text: I18n.tr("common.close")
          outlined: true
          onClicked: root.close()
        }

        NButton {
          text: I18n.tr("common.apply")
          icon: "check"
          onClicked: {
            if (settingsLoader.item && settingsLoader.item.saveSettings) {
              settingsLoader.item.saveSettings();
              if (root.showToastOnSave) {
                ToastService.showNotice(I18n.tr("panels.plugins.title"), I18n.tr("panels.plugins.settings-saved"));
              }
            }
          }
        }
      }
    }
  }

  onClosed: {
    // Clear both source and sourceComponent to ensure full cleanup
    settingsLoader.sourceComponent = null;
    settingsLoader.source = "";
    currentPlugin = null;
    currentPluginApi = null;
  }

  function openPluginSettings(pluginManifest) {
    currentPlugin = pluginManifest;

    // Use composite key if available (for custom plugins), otherwise use manifest ID (for official plugins)
    var pluginId = pluginManifest.compositeKey || pluginManifest.id;

    currentPluginApi = PluginService.getPluginAPI(pluginId);
    if (!currentPluginApi) {
      Logger.e("NPluginSettingsPopup", "Cannot open settings: plugin not loaded:", pluginId);
      if (showToastOnSave) {
        ToastService.showError(I18n.tr("panels.plugins.title"), I18n.tr("panels.plugins.settings-error-not-loaded"));
      }
      return;
    }

    // Get plugin directory
    var pluginDir = PluginRegistry.getPluginDir(pluginId);
    var settingsPath = pluginDir + "/" + pluginManifest.entryPoints.settings;

    settingsLoader.setSource("file://" + settingsPath, {
                               "pluginApi": currentPluginApi
                             });

    open();
  }
}
