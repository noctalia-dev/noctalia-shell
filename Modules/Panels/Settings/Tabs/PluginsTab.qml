import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Services.Noctalia
import qs.Services.UI
import qs.Widgets

ColumnLayout {
  id: root
  spacing: Style.marginL
  width: parent.width

  // Track which plugins are currently updating
  property var updatingPlugins: ({})

  function stripAuthorEmail(author) {
    if (!author)
      return "";
    var lastBracket = author.lastIndexOf("<");
    if (lastBracket >= 0) {
      return author.substring(0, lastBracket).trim();
    }
    return author;
  }

  // Check for updates when tab becomes visible
  onVisibleChanged: {
    if (visible && PluginService.pluginsFullyLoaded) {
      PluginService.checkForUpdates();
    }
  }

  // ------------------------------
  // Installed Plugins
  // ------------------------------
  NHeader {
    label: I18n.tr("settings.plugins.installed.label")
    description: I18n.tr("settings.plugins.installed.description")
  }

  // Update All button
  NButton {
    property int updateCount: Object.keys(PluginService.pluginUpdates).length
    property bool isUpdating: false

    text: I18n.tr("settings.plugins.update-all", {
                    "count": updateCount
                  })
    icon: "download"
    visible: updateCount >= 2
    enabled: !isUpdating
    backgroundColor: Color.mPrimary
    textColor: Color.mOnPrimary
    Layout.fillWidth: true
    onClicked: {
      isUpdating = true;
      var pluginIds = Object.keys(PluginService.pluginUpdates);
      var currentIndex = 0;

      function updateNext() {
        if (currentIndex >= pluginIds.length) {
          isUpdating = false;
          ToastService.showNotice(I18n.tr("settings.plugins.update-all-success"));
          return;
        }

        var pluginId = pluginIds[currentIndex];
        currentIndex++;

        PluginService.updatePlugin(pluginId, function (success, error) {
          if (!success) {
            Logger.w("PluginsTab", "Failed to update", pluginId + ":", error);
          }
          Qt.callLater(updateNext);
        });
      }

      updateNext();
    }
  }

  ColumnLayout {
    spacing: Style.marginM
    Layout.fillWidth: true

    Repeater {
      id: installedPluginsRepeater

      model: {
        // Make this reactive to PluginRegistry and PluginService changes
        var _ = PluginRegistry.installedPlugins; // Force dependency
        var __ = PluginRegistry.pluginStates;    // Force dependency
        var ___ = PluginService.pluginUpdates;   // Force dependency on updates

        var allIds = PluginRegistry.getAllInstalledPluginIds();
        var plugins = [];
        for (var i = 0; i < allIds.length; i++) {
          var manifest = PluginRegistry.getPluginManifest(allIds[i]);
          if (manifest) {
            plugins.push(manifest);
          }
        }
        return plugins;
      }

      delegate: NBox {
        Layout.fillWidth: true
        implicitHeight: rowLayout.implicitHeight + Style.marginL * 2
        color: Color.mSurface

        RowLayout {
          id: rowLayout
          anchors.fill: parent
          anchors.margins: Style.marginL
          spacing: Style.marginM

          NIcon {
            icon: "plugin"
            pointSize: Style.fontSizeXL
            color: Color.mOnSurface
          }

          ColumnLayout {
            spacing: 2
            Layout.fillWidth: true

            NText {
              text: modelData.name
              font.weight: Font.Medium
              color: Color.mOnSurface
              Layout.fillWidth: true
            }

            NText {
              text: modelData.description
              font.pointSize: Style.fontSizeXS
              color: Color.mOnSurfaceVariant
              wrapMode: Text.WordWrap
              Layout.fillWidth: true
            }

            RowLayout {
              spacing: Style.marginS

              NText {
                property var updateInfo: PluginService.pluginUpdates[modelData.id]

                text: updateInfo ? I18n.tr("settings.plugins.update-version", {
                                             "current": modelData.version,
                                             "new": updateInfo.availableVersion
                                           }) : "v" + modelData.version
                font.pointSize: Style.fontSizeXXS
                color: updateInfo ? Color.mPrimary : Color.mOnSurfaceVariant
                font.weight: updateInfo ? Font.Medium : Font.Normal
              }

              NText {
                text: "•"
                font.pointSize: Style.fontSizeXXS
                color: Color.mOnSurfaceVariant
              }

              NText {
                text: stripAuthorEmail(modelData.author)
                font.pointSize: Style.fontSizeXXS
                color: Color.mOnSurfaceVariant
              }
            }
          }

          NIconButton {
            icon: "settings"
            tooltipText: I18n.tr("settings.plugins.settings.tooltip")
            baseSize: Style.baseWidgetSize * 0.7
            visible: modelData.entryPoints?.settings !== undefined
            onClicked: {
              pluginSettingsDialog.openPluginSettings(modelData);
            }
          }

          NButton {
            id: updateButton
            property string pluginId: modelData.id
            property bool isUpdating: root.updatingPlugins[pluginId] === true

            text: isUpdating ? I18n.tr("settings.plugins.updating", {
                                         "plugin": modelData.name
                                       }) : I18n.tr("settings.plugins.update")
            icon: isUpdating ? "" : "download"
            visible: PluginService.pluginUpdates[pluginId] !== undefined
            enabled: !isUpdating
            backgroundColor: Color.mPrimary
            textColor: Color.mOnPrimary
            onClicked: {
              var pid = pluginId;
              var pname = modelData.name;
              var pversion = PluginService.pluginUpdates[pid]?.availableVersion || "";
              var rootRef = root;
              var updates = Object.assign({}, rootRef.updatingPlugins);
              updates[pid] = true;
              rootRef.updatingPlugins = updates;

              PluginService.updatePlugin(pid, function (success, error) {
                var updates2 = Object.assign({}, rootRef.updatingPlugins);
                updates2[pid] = false;
                rootRef.updatingPlugins = updates2;

                if (success) {
                  ToastService.showNotice(I18n.tr("settings.plugins.update-success", {
                                                    "plugin": pname,
                                                    "version": pversion
                                                  }));
                } else {
                  ToastService.showError(I18n.tr("settings.plugins.update-error", {
                                                   "plugin": pname,
                                                   "error": error || "Unknown error"
                                                 }));
                }
              });
            }
          }

          NToggle {
            checked: PluginRegistry.isPluginEnabled(modelData.id)
            baseSize: Style.baseWidgetSize * 0.7
            onToggled: function (checked) {
              if (checked) {
                PluginService.enablePlugin(modelData.id);
              } else {
                PluginService.disablePlugin(modelData.id);
              }
            }
          }
        }
      }
    }

    NLabel {
      visible: PluginRegistry.getAllInstalledPluginIds().length === 0
      label: I18n.tr("settings.plugins.installed.no-plugins-label")
      description: I18n.tr("settings.plugins.installed.no-plugins-description")
      Layout.fillWidth: true
    }
  }

  NDivider {
    Layout.fillWidth: true
    Layout.topMargin: Style.marginL
    Layout.bottomMargin: Style.marginL
  }

  // ------------------------------
  // Available Plugins (Sources + Filter + List)
  // ------------------------------
  NHeader {
    label: I18n.tr("settings.plugins.available.label")
    description: I18n.tr("settings.plugins.available.description")
  }

  // Sources
  NCollapsible {
    Layout.fillWidth: true
    label: I18n.tr("settings.plugins.sources.label")
    description: I18n.tr("settings.plugins.sources.description")
    expanded: false

    ColumnLayout {
      spacing: Style.marginM
      Layout.fillWidth: true

      // List of plugin sources
      Repeater {
        id: pluginSourcesRepeater
        model: PluginRegistry.pluginSources || []

        delegate: RowLayout {
          spacing: Style.marginM
          Layout.fillWidth: true

          NIcon {
            icon: "brand-github"
            pointSize: Style.fontSizeM
          }

          ColumnLayout {
            spacing: Style.marginS

            NText {
              text: modelData.name
              font.weight: Font.Medium
              color: Color.mOnSurface
            }

            NText {
              text: modelData.url
              font.pointSize: Style.fontSizeS
              color: Color.mOnSurfaceVariant
            }
          }

          Item {
            Layout.fillWidth: true
          }

          // Enable/Disable a source
          NToggle {
            checked: modelData.enabled !== false // Default to true if not set
            baseSize: Style.baseWidgetSize * 0.7
            onToggled: function (checked) {
              PluginRegistry.setSourceEnabled(modelData.url, checked);
              PluginService.refreshAvailablePlugins();
              ToastService.showNotice(I18n.tr("settings.plugins.refresh.refreshing"));
            }
          }

          NIconButton {
            icon: "trash"
            tooltipText: I18n.tr("settings.plugins.sources.remove.tooltip")
            visible: index !== 0 // Cannot remove official source
            baseSize: Style.baseWidgetSize * 0.7
            onClicked: {
              PluginRegistry.removePluginSource(modelData.url);
            }
          }
        }
      }

      NDivider {
        Layout.fillWidth: true
      }

      // Add custom repository
      NButton {
        text: I18n.tr("settings.plugins.sources.add-custom")
        icon: "plus"
        onClicked: {
          addSourceDialog.open();
        }
        Layout.fillWidth: true
      }
    }
  }

  // Filter controls
  RowLayout {
    spacing: Style.marginM
    Layout.fillWidth: true

    NTabBar {
      id: filterTabBar
      Layout.fillWidth: true
      currentIndex: 0
      onCurrentIndexChanged: {
        if (currentIndex === 0)
          pluginFilter = "all";
        else if (currentIndex === 1)
          pluginFilter = "downloaded";
        else if (currentIndex === 2)
          pluginFilter = "notDownloaded";
      }
      spacing: Style.marginXS

      NTabButton {
        text: I18n.tr("settings.plugins.filter.all")
        tabIndex: 0
        checked: pluginFilter === "all"
      }

      NTabButton {
        text: I18n.tr("settings.plugins.filter.downloaded")
        tabIndex: 1
        checked: pluginFilter === "downloaded"
      }

      NTabButton {
        text: I18n.tr("settings.plugins.filter.not-downloaded")
        tabIndex: 2
        checked: pluginFilter === "notDownloaded"
      }
    }

    NIconButton {
      icon: "refresh"
      tooltipText: I18n.tr("settings.plugins.refresh.tooltip")
      baseSize: Style.baseWidgetSize * 0.9
      onClicked: {
        PluginService.refreshAvailablePlugins();
        checkUpdatesTimer.restart();
        ToastService.showNotice(I18n.tr("settings.plugins.refresh.refreshing"));
      }
    }
  }

  // Timer to check for updates after refresh
  Timer {
    id: checkUpdatesTimer
    interval: 100
    onTriggered: {
      PluginService.checkForUpdates();
    }
  }

  property string pluginFilter: "all"

  // Available plugins list
  ColumnLayout {
    spacing: Style.marginM
    Layout.fillWidth: true

    Repeater {
      id: availablePluginsRepeater

      model: {
        var all = PluginService.availablePlugins || [];
        var filtered = [];

        for (var i = 0; i < all.length; i++) {
          var plugin = all[i];
          var downloaded = plugin.downloaded || false;

          if (pluginFilter === "all") {
            filtered.push(plugin);
          } else if (pluginFilter === "downloaded" && downloaded) {
            filtered.push(plugin);
          } else if (pluginFilter === "notDownloaded" && !downloaded) {
            filtered.push(plugin);
          }
        }

        return filtered;
      }

      delegate: NBox {
        Layout.fillWidth: true
        implicitHeight: contentRow.implicitHeight + Style.marginL * 2
        color: Color.mSurface

        RowLayout {
          id: contentRow
          anchors.fill: parent
          anchors.margins: Style.marginL
          spacing: Style.marginM

          NIcon {
            icon: "plugin"
            pointSize: Style.fontSizeXL
            color: Color.mOnSurface
          }

          ColumnLayout {
            spacing: 2
            Layout.fillWidth: true
            Layout.preferredWidth: modelData.downloaded ? parent.width * 0.6 : parent.width * 0.7

            NText {
              text: modelData.name
              font.weight: Font.Medium
              color: Color.mOnSurface
              Layout.fillWidth: true
              elide: Text.ElideRight
              maximumLineCount: 1
            }

            NText {
              text: modelData.description
              font.pointSize: Style.fontSizeXS
              color: Color.mOnSurfaceVariant
              wrapMode: Text.WordWrap
              Layout.fillWidth: true
              elide: Text.ElideRight
              maximumLineCount: 2
            }

            RowLayout {
              spacing: Style.marginS

              NText {
                text: "v" + modelData.version
                font.pointSize: Style.fontSizeXXS
                color: Color.mOnSurfaceVariant
              }

              NText {
                text: "•"
                font.pointSize: Style.fontSizeXXS
                color: Color.mOnSurfaceVariant
              }

              NText {
                text: stripAuthorEmail(modelData.author)
                font.pointSize: Style.fontSizeXXS
                color: Color.mOnSurfaceVariant
              }

              NText {
                text: "•"
                font.pointSize: Style.fontSizeXXS
                color: Color.mOnSurfaceVariant
              }

              NText {
                text: modelData.source?.name || "Unknown"
                font.pointSize: Style.fontSizeXS
                color: Color.mOnSurfaceVariant
              }
            }
          }

          RowLayout {
            spacing: Style.marginXS
            Layout.alignment: Qt.AlignRight | Qt.AlignVCenter

            NIcon {
              icon: "circle-check"
              pointSize: Style.fontSizeM
              color: Color.mPrimary
              visible: modelData.downloaded === true
            }

            NIconButton {
              icon: modelData.downloaded ? "trash" : "download"
              baseSize: Style.baseWidgetSize * 0.8
              tooltipText: modelData.downloaded ? I18n.tr("settings.plugins.uninstall") : I18n.tr("settings.plugins.install")
              onClicked: {
                if (modelData.downloaded) {
                  uninstallDialog.pluginToUninstall = modelData;
                  uninstallDialog.open();
                } else {
                  installPlugin(modelData);
                }
              }
            }
          }
        }
      }
    }

    NLabel {
      visible: availablePluginsRepeater.count === 0
      label: I18n.tr("settings.plugins.available.no-plugins-label")
      description: I18n.tr("settings.plugins.available.no-plugins-description")
      Layout.fillWidth: true
    }
  }

  NDivider {
    Layout.fillWidth: true
    Layout.topMargin: Style.marginL
    Layout.bottomMargin: Style.marginL
  }

  // ------------------------------
  // Dialogs
  // ------------------------------

  // Add source dialog
  Popup {
    id: addSourceDialog
    modal: true
    dim: false
    anchors.centerIn: parent
    width: 500
    padding: Style.marginL

    background: Rectangle {
      color: Color.mSurface
      radius: Style.radiusS
      border.color: Color.mPrimary
      border.width: Style.borderM
    }

    contentItem: ColumnLayout {
      width: parent.width
      spacing: Style.marginL

      NHeader {
        label: I18n.tr("settings.plugins.sources.add-dialog.title")
        description: I18n.tr("settings.plugins.sources.add-dialog.description")
      }

      NTextInput {
        id: sourceNameInput
        label: I18n.tr("settings.plugins.sources.add-dialog.name")
        placeholderText: I18n.tr("settings.plugins.sources.add-dialog.name-placeholder")
        Layout.fillWidth: true
      }

      NTextInput {
        id: sourceUrlInput
        label: I18n.tr("settings.plugins.sources.add-dialog.url")
        placeholderText: "https://github.com/user/repo"
        Layout.fillWidth: true
      }

      RowLayout {
        spacing: Style.marginM
        Layout.fillWidth: true

        Item {
          Layout.fillWidth: true
        }

        NButton {
          text: I18n.tr("common.cancel")
          onClicked: addSourceDialog.close()
        }

        NButton {
          text: I18n.tr("common.add")
          backgroundColor: Color.mPrimary
          textColor: Color.mOnPrimary
          enabled: sourceNameInput.text.length > 0 && sourceUrlInput.text.length > 0
          onClicked: {
            if (PluginRegistry.addPluginSource(sourceNameInput.text, sourceUrlInput.text)) {
              ToastService.showNotice(I18n.tr("settings.plugins.sources.add-dialog.success"));
              PluginService.refreshAvailablePlugins();
              addSourceDialog.close();
              sourceNameInput.text = "";
              sourceUrlInput.text = "";
            } else {
              ToastService.showNotice(I18n.tr("settings.plugins.sources.add-dialog.error"));
            }
          }
        }
      }
    }
  }

  // Uninstall confirmation dialog
  Popup {
    id: uninstallDialog
    modal: true
    dim: false
    anchors.centerIn: parent
    width: 400 * Style.uiScaleRatio
    padding: Style.marginL

    property var pluginToUninstall: null

    background: Rectangle {
      color: Color.mSurface
      radius: Style.radiusS
      border.color: Color.mPrimary
      border.width: Style.borderM
    }

    contentItem: ColumnLayout {
      width: parent.width
      spacing: Style.marginL

      NHeader {
        label: I18n.tr("settings.plugins.uninstall-dialog.title")
        description: I18n.tr("settings.plugins.uninstall-dialog.description", {
                               "plugin": uninstallDialog.pluginToUninstall?.name || ""
                             })
      }

      RowLayout {
        spacing: Style.marginM
        Layout.fillWidth: true

        Item {
          Layout.fillWidth: true
        }

        NButton {
          text: I18n.tr("common.cancel")
          onClicked: uninstallDialog.close()
        }

        NButton {
          text: I18n.tr("settings.plugins.uninstall")
          backgroundColor: Color.mPrimary
          textColor: Color.mOnPrimary
          onClicked: {
            if (uninstallDialog.pluginToUninstall) {
              root.uninstallPlugin(uninstallDialog.pluginToUninstall.id);
              uninstallDialog.close();
            }
          }
        }
      }
    }
  }

  // Plugin settings popup
  NPluginSettingsPopup {
    id: pluginSettingsDialog
    parent: Overlay.overlay
    showToastOnSave: true
  }

  // ------------------------------
  // Functions
  // ------------------------------

  function installPlugin(pluginMetadata) {
    ToastService.showNotice(I18n.tr("settings.plugins.installing", {
                                      "plugin": pluginMetadata.name
                                    }));

    PluginService.installPlugin(pluginMetadata, function (success, error) {
      if (success) {
        ToastService.showNotice(I18n.tr("settings.plugins.install-success", {
                                          "plugin": pluginMetadata.name
                                        }));
        // Auto-enable the plugin after installation
        PluginService.enablePlugin(pluginMetadata.id);
      } else {
        ToastService.showNotice(I18n.tr("settings.plugins.install-error", {
                                          "error": error || "Unknown error"
                                        }));
      }
    });
  }

  function uninstallPlugin(pluginId) {
    var manifest = PluginRegistry.getPluginManifest(pluginId);
    var pluginName = manifest?.name || pluginId;

    ToastService.showNotice(I18n.tr("settings.plugins.uninstalling", {
                                      "plugin": pluginName
                                    }));

    PluginService.uninstallPlugin(pluginId, function (success, error) {
      if (success) {
        ToastService.showNotice(I18n.tr("settings.plugins.uninstall-success", {
                                          "plugin": pluginName
                                        }));
      } else {
        ToastService.showNotice(I18n.tr("settings.plugins.uninstall-error", {
                                          "error": error || "Unknown error"
                                        }));
      }
    });
  }

  // Listen to plugin registry changes
  Connections {
    target: PluginRegistry

    function onPluginsChanged() {
      // Force model refresh for installed plugins
      installedPluginsRepeater.model = undefined;
      Qt.callLater(function () {
        installedPluginsRepeater.model = Qt.binding(function () {
          var allIds = PluginRegistry.getAllInstalledPluginIds();
          var plugins = [];
          for (var i = 0; i < allIds.length; i++) {
            var manifest = PluginRegistry.getPluginManifest(allIds[i]);
            if (manifest) {
              plugins.push(manifest);
            }
          }
          return plugins;
        });
      });

      // Force model refresh for plugin sources
      pluginSourcesRepeater.model = undefined;
      Qt.callLater(function () {
        pluginSourcesRepeater.model = Qt.binding(function () {
          return PluginRegistry.pluginSources || [];
        });
      });
    }
  }

  // Listen to plugin service signals
  Connections {
    target: PluginService

    function onAvailablePluginsUpdated() {
      // Force model refresh
      availablePluginsRepeater.model = undefined;
      Qt.callLater(function () {
        availablePluginsRepeater.model = Qt.binding(function () {
          var all = PluginService.availablePlugins || [];
          var filtered = [];

          for (var i = 0; i < all.length; i++) {
            var plugin = all[i];
            var downloaded = plugin.downloaded || false;

            if (root.pluginFilter === "all") {
              filtered.push(plugin);
            } else if (root.pluginFilter === "downloaded" && downloaded) {
              filtered.push(plugin);
            } else if (root.pluginFilter === "notDownloaded" && !downloaded) {
              filtered.push(plugin);
            }
          }

          return filtered;
        });
      });
    }
  }
}
