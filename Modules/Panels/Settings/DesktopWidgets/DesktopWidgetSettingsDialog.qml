import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Services.Noctalia
import qs.Services.UI
import qs.Widgets

Popup {
  id: root

  property int widgetIndex: -1
  property var widgetData: null
  property string widgetId: ""
  property string sectionId: "" // Not used for desktop widgets, but required by NSectionEditor
  property var screen: null
  property var settingsCache: ({})

  readonly property real maxHeight: (screen ? screen.height : (parent ? parent.height : 800)) * 0.8

  signal updateWidgetSettings(string section, int index, var settings)

  width: Math.max(content.implicitWidth + padding * 2, 500)
  height: Math.min(content.implicitHeight + padding * 2, maxHeight)
  padding: Style.marginXL
  modal: true
  dim: false

  // Center in parent
  x: Math.round((parent.width - width) / 2)
  y: Math.round((parent.height - height) / 2)

  onOpened: {
    if (widgetData && widgetId) {
      loadWidgetSettings();
    }
    forceActiveFocus();
  }

  background: Rectangle {
    id: bgRect
    color: Color.mSurface
    radius: Style.radiusL
    border.color: Color.mPrimary
    border.width: Style.borderM
  }

  contentItem: FocusScope {
    id: focusScope
    focus: true

    ColumnLayout {
      id: content
      anchors.fill: parent
      spacing: Style.marginM

      RowLayout {
        id: titleRow
        Layout.fillWidth: true
        Layout.preferredHeight: implicitHeight

        NText {
          text: I18n.tr("system.widget-settings-title", {
                          "widget": root.widgetId
                        })
          pointSize: Style.fontSizeL
          font.weight: Style.fontWeightBold
          color: Color.mPrimary
          Layout.fillWidth: true
        }

        NIconButton {
          icon: "close"
          tooltipText: I18n.tr("common.close")
          onClicked: saveAndClose()
        }
      }

      Rectangle {
        id: separator
        Layout.fillWidth: true
        Layout.preferredHeight: 1
        color: Color.mOutline
      }

      // Scrollable settings area
      NScrollView {
        id: scrollView
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.minimumHeight: 100
        gradientColor: Color.mSurface

        ColumnLayout {
          width: scrollView.availableWidth
          spacing: Style.marginM

          Loader {
            id: settingsLoader
            Layout.fillWidth: true
            onLoaded: {
              if (item) {
                Qt.callLater(() => {
                               var firstInput = findFirstFocusable(item);
                               if (firstInput) {
                                 firstInput.forceActiveFocus();
                               } else {
                                 focusScope.forceActiveFocus();
                               }
                             });
              }
            }

            function findFirstFocusable(item) {
              if (!item)
                return null;
              if (item.focus !== undefined && item.focus === true)
                return item;
              if (item.children) {
                for (var i = 0; i < item.children.length; i++) {
                  var child = item.children[i];
                  if (child && child.focus !== undefined && child.focus === true)
                    return child;
                  var found = findFirstFocusable(child);
                  if (found)
                    return found;
                }
              }
              return null;
            }
          }
        }
      }
    }
  }

  Timer {
    id: saveTimer
    running: false
    interval: 150
    onTriggered: {
      root.updateWidgetSettings(root.sectionId, root.widgetIndex, root.settingsCache);
    }
  }

  Connections {
    target: settingsLoader.item
    ignoreUnknownSignals: true
    function onSettingsChanged(newSettings) {
      if (newSettings) {
        root.settingsCache = newSettings;
        saveTimer.start();
      }
    }
  }

  function saveAndClose() {
    if (settingsLoader.item && typeof settingsLoader.item.saveSettings === 'function') {
      var newSettings = settingsLoader.item.saveSettings();
      if (newSettings) {
        root.updateWidgetSettings(root.sectionId, root.widgetIndex, newSettings);
      }
    }
    root.close();
  }

  function loadWidgetSettings() {
    // Handle plugin widgets
    if (DesktopWidgetRegistry.isPluginWidget(widgetId)) {
      var pluginId = widgetId.replace("plugin:", "");
      var manifest = PluginRegistry.getPluginManifest(pluginId);

      if (!manifest || !manifest.entryPoints || !manifest.entryPoints.settings) {
        Logger.w("DesktopWidgetSettingsDialog", "Plugin does not have settings:", pluginId);
        return;
      }

      var pluginDir = PluginRegistry.getPluginDir(pluginId);
      var settingsPath = "file://" + pluginDir + "/" + manifest.entryPoints.settings;
      var loadVersion = PluginRegistry.pluginLoadVersions[pluginId] || 0;
      var api = PluginService.getPluginAPI(pluginId);

      settingsLoader.setSource(settingsPath + "?v=" + loadVersion, {
                                 "pluginApi": api
                               });
      return;
    }

    // Handle core widgets
    const source = DesktopWidgetRegistry.widgetSettingsMap[widgetId];
    if (source) {
      var currentWidgetData = widgetData;
      var monitorWidgets = Settings.data.desktopWidgets.monitorWidgets || [];
      for (var i = 0; i < monitorWidgets.length; i++) {
        if (monitorWidgets[i].name === sectionId) {
          var widgets = monitorWidgets[i].widgets || [];
          if (widgetIndex >= 0 && widgetIndex < widgets.length) {
            currentWidgetData = widgets[widgetIndex];
          }
          break;
        }
      }
      var fullPath = Qt.resolvedUrl(Quickshell.shellDir + "/Modules/Panels/Settings/DesktopWidgets/" + source);
      settingsLoader.setSource(fullPath, {
                                 "widgetData": currentWidgetData,
                                 "widgetMetadata": DesktopWidgetRegistry.widgetMetadata[widgetId]
                               });
    }
  }
}
