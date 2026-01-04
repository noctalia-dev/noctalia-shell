import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../../../Helpers/FuzzySort.js" as Fuzzysort
import qs.Commons
import qs.Services.Noctalia
import qs.Services.UI
import qs.Widgets

ColumnLayout {
  id: root

  // Track which plugins are currently updating
  property var updatingPlugins: ({})
  property int installedPluginsRefreshCounter: 0

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
          ToastService.showNotice(I18n.tr("settings.plugins.title"), I18n.tr("settings.plugins.update-all-success"));
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

  // ------------------------------
  // Installed plugins
  // ------------------------------
  ColumnLayout {
    spacing: Style.marginM
    Layout.fillWidth: true

    Repeater {
      id: installedPluginsRepeater

      model: {
        // Force refresh when counter changes
        var _ = root.installedPluginsRefreshCounter;

        var allIds = PluginRegistry.getAllInstalledPluginIds();
        var plugins = [];
        for (var i = 0; i < allIds.length; i++) {
          var compositeKey = allIds[i];
          var manifest = PluginRegistry.getPluginManifest(compositeKey);
          if (manifest) {
            // Create a copy of manifest and include update info, enabled state, and source info
            var pluginData = JSON.parse(JSON.stringify(manifest));
            pluginData.compositeKey = compositeKey;
            pluginData.updateInfo = PluginService.pluginUpdates[compositeKey];
            pluginData.enabled = PluginRegistry.isPluginEnabled(compositeKey);

            // Add source info
            var parsed = PluginRegistry.parseCompositeKey(compositeKey);
            pluginData.isOfficial = parsed.isOfficial;
            if (!parsed.isOfficial) {
              pluginData.sourceName = PluginRegistry.getSourceNameByHash(parsed.sourceHash);
            }

            plugins.push(pluginData);
          }
        }
        return plugins;
      }

      delegate: NBox {
        Layout.fillWidth: true
        Layout.leftMargin: Style.borderS
        Layout.rightMargin: Style.borderS
        implicitHeight: Math.round(rowLayout.implicitHeight) + Style.marginL * 2
        color: Color.mSurface

        RowLayout {
          id: rowLayout
          anchors.fill: parent
          anchors.margins: Style.marginL
          spacing: Style.marginM

          NIcon {
            icon: "plugin"
            pointSize: Style.fontSizeXL
            color: PluginService.hasPluginError(modelData.compositeKey) ? Color.mError : Color.mOnSurface
          }

          ColumnLayout {
            spacing: 2
            Layout.fillWidth: true

            NText {
              text: modelData.name
              color: Color.mOnSurface
              elide: Text.ElideRight
              Layout.fillWidth: true
            }

            NText {
              text: modelData.description
              font.pointSize: Style.fontSizeXS
              color: Color.mOnSurfaceVariant
              wrapMode: Text.WordWrap
              maximumLineCount: 2
              elide: Text.ElideRight
              Layout.fillWidth: true
            }

            RowLayout {
              spacing: Style.marginS

              NText {
                text: modelData.updateInfo ? I18n.tr("settings.plugins.update-version", {
                                                       "current": modelData.version,
                                                       "new": modelData.updateInfo.availableVersion
                                                     }) : "v" + modelData.version
                font.pointSize: Style.fontSizeXXS
                color: modelData.updateInfo ? Color.mPrimary : Color.mOnSurfaceVariant
                font.weight: modelData.updateInfo ? Style.fontWeightMedium : Style.fontWeightRegular
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

              // Source indicator for non-official plugins
              NText {
                visible: !modelData.isOfficial
                text: "•"
                font.pointSize: Style.fontSizeXXS
                color: Color.mOnSurfaceVariant
              }

              NText {
                visible: !modelData.isOfficial
                text: modelData.sourceName || I18n.tr("settings.plugins.source.custom")
                font.pointSize: Style.fontSizeXXS
                color: Color.mTertiary
              }
            }

            // Error indicator
            RowLayout {
              spacing: Style.marginS
              visible: PluginService.hasPluginError(modelData.compositeKey)

              NIcon {
                icon: "alert-triangle"
                pointSize: Style.fontSizeS
                color: Color.mError
              }

              NText {
                property var errorInfo: PluginService.getPluginError(modelData.compositeKey)
                text: errorInfo ? errorInfo.error : ""
                font.pointSize: Style.fontSizeXXS
                color: Color.mError
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
                elide: Text.ElideRight
                maximumLineCount: 3
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

          NIconButton {
            icon: "trash"
            tooltipText: I18n.tr("settings.plugins.uninstall")
            baseSize: Style.baseWidgetSize * 0.7
            onClicked: {
              uninstallDialog.pluginToUninstall = modelData;
              uninstallDialog.open();
            }
          }

          NButton {
            id: updateButton
            property string pluginId: modelData.compositeKey
            property bool isUpdating: root.updatingPlugins[pluginId] === true

            text: isUpdating ? I18n.tr("settings.plugins.updating") : I18n.tr("settings.plugins.update")
            icon: isUpdating ? "" : "download"
            visible: modelData.updateInfo !== undefined
            enabled: !isUpdating
            backgroundColor: Color.mPrimary
            textColor: Color.mOnPrimary
            onClicked: {
              var pid = pluginId;
              var pname = modelData.name;
              var pversion = modelData.updateInfo?.availableVersion || "";
              var rootRef = root;
              var updates = Object.assign({}, rootRef.updatingPlugins);
              updates[pid] = true;
              rootRef.updatingPlugins = updates;

              PluginService.updatePlugin(pid, function (success, error) {
                var updates2 = Object.assign({}, rootRef.updatingPlugins);
                updates2[pid] = false;
                rootRef.updatingPlugins = updates2;

                if (success) {
                  ToastService.showNotice(I18n.tr("settings.plugins.title"), I18n.tr("settings.plugins.update-success", {
                                                                                       "plugin": pname,
                                                                                       "version": pversion
                                                                                     }));
                } else {
                  ToastService.showError(I18n.tr("settings.plugins.title"), I18n.tr("settings.plugins.update-error", {
                                                                                      "plugin": pname,
                                                                                      "error": error || "Unknown error"
                                                                                    }));
                }
              });
            }
          }

          NToggle {
            checked: modelData.enabled
            baseSize: Style.baseWidgetSize * 0.7
            onToggled: checked => {
                         if (checked) {
                           PluginService.enablePlugin(modelData.compositeKey);
                         } else {
                           PluginService.disablePlugin(modelData.compositeKey);
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
            Layout.fillWidth: true

            NText {
              text: modelData.name
              color: Color.mOnSurface
              Layout.fillWidth: true
            }

            NText {
              text: modelData.url
              font.pointSize: Style.fontSizeS
              color: Color.mOnSurfaceVariant
              Layout.fillWidth: true
            }
          }

          Item {
            Layout.fillWidth: true
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

          // Enable/Disable a source
          NToggle {
            checked: modelData.enabled !== false // Default to true if not set
            baseSize: Style.baseWidgetSize * 0.7
            onToggled: checked => {
                         PluginRegistry.setSourceEnabled(modelData.url, checked);
                         PluginService.refreshAvailablePlugins();
                         ToastService.showNotice(I18n.tr("settings.plugins.title"), I18n.tr("settings.plugins.refresh.refreshing"));
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
    Layout.topMargin: Style.marginM
    Layout.bottomMargin: Style.marginM

    NTabBar {
      id: filterTabBar
      Layout.fillWidth: true
      spacing: Style.marginM
      currentIndex: 0
      onCurrentIndexChanged: {
        if (currentIndex === 0)
          pluginFilter = "all";
        else if (currentIndex === 1)
          pluginFilter = "downloaded";
        else if (currentIndex === 2)
          pluginFilter = "notDownloaded";
      }

      NTabButton {
        Layout.fillWidth: true
        text: I18n.tr("settings.plugins.filter.all")
        tabIndex: 0
        checked: pluginFilter === "all"
      }

      NTabButton {
        Layout.fillWidth: true
        text: I18n.tr("settings.plugins.filter.downloaded")
        tabIndex: 1
        checked: pluginFilter === "downloaded"
      }

      NTabButton {
        Layout.fillWidth: true
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
        ToastService.showNotice(I18n.tr("settings.plugins.title"), I18n.tr("settings.plugins.refresh.refreshing"));
      }
    }
  }

  property string pluginFilter: "all"
  property string pluginSearchText: ""

  // Search input
  NTextInput {
    placeholderText: I18n.tr("placeholders.search")
    inputIconName: "search"
    text: root.pluginSearchText
    onTextChanged: root.pluginSearchText = text
    Layout.fillWidth: true
    Layout.bottomMargin: Style.marginL
  }

  // Available plugins list
  ColumnLayout {
    spacing: Style.marginM
    Layout.fillWidth: true

    Repeater {
      id: availablePluginsRepeater

      model: {
        var all = PluginService.availablePlugins || [];
        var filtered = [];

        // First apply download filter
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

        // Then apply fuzzy search if there's search text
        var query = root.pluginSearchText.trim();
        if (query !== "") {
          var results = Fuzzysort.go(query, filtered, {
                                       "keys": ["name", "description"],
                                       "threshold": 0.35,
                                       "limit": 50
                                     });
          filtered = [];
          for (var j = 0; j < results.length; j++) {
            filtered.push(results[j].obj);
          }
        } else {
          // Sort by lastUpdated (most recent first) when not searching
          filtered.sort(function (a, b) {
            var dateA = a.lastUpdated ? new Date(a.lastUpdated).getTime() : 0;
            var dateB = b.lastUpdated ? new Date(b.lastUpdated).getTime() : 0;
            return dateB - dateA;
          });
        }

        return filtered;
      }

      delegate: NBox {
        id: pluginBox
        property bool isHovered: hoverHandler.hovered

        Layout.fillWidth: true
        Layout.leftMargin: Style.borderS
        Layout.rightMargin: Style.borderS
        implicitHeight: Math.round(contentColumn.implicitHeight + Style.marginL * 2)
        color: Color.mSurface

        Behavior on implicitHeight {
          NumberAnimation {
            duration: 150
            easing.type: Easing.OutCubic
          }
        }

        HoverHandler {
          id: hoverHandler
        }

        ColumnLayout {
          id: contentColumn
          anchors.fill: parent
          anchors.margins: Style.marginL
          spacing: Style.marginS

          RowLayout {
            spacing: Style.marginM
            Layout.fillWidth: true

            NIcon {
              icon: "plugin"
              pointSize: Style.fontSizeL
              color: Color.mOnSurface
            }

            NText {
              text: modelData.name
              color: Color.mOnSurface
              elide: Text.ElideRight
            }

            // Description excerpt - visible when not hovered
            NText {
              visible: !pluginBox.isHovered && modelData.description
              text: modelData.description || ""
              font.pointSize: Style.fontSizeXS
              color: Color.mOnSurfaceVariant
              elide: Text.ElideRight
              Layout.fillWidth: true
            }

            // Spacer when hovered or no description
            Item {
              visible: pluginBox.isHovered || !modelData.description
              Layout.fillWidth: true
            }

            // Downloaded indicator
            NIcon {
              icon: "circle-check"
              pointSize: Style.fontSizeL
              color: Color.mPrimary
              visible: modelData.downloaded === true
            }

            // Install/Uninstall button
            NIconButton {
              icon: modelData.downloaded ? "trash" : "download"
              baseSize: Style.baseWidgetSize * 0.7
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

          // Description - visible on hover
          NText {
            visible: pluginBox.isHovered && modelData.description
            text: modelData.description || ""
            font.pointSize: Style.fontSizeXS
            color: Color.mOnSurface
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
          }

          // Details row - visible on hover
          RowLayout {
            visible: pluginBox.isHovered
            spacing: Style.marginS
            Layout.fillWidth: true

            NText {
              text: "v" + modelData.version
              font.pointSize: Style.fontSizeXS
              color: Color.mOnSurfaceVariant
            }

            NText {
              text: "•"
              font.pointSize: Style.fontSizeXS
              color: Color.mOnSurfaceVariant
            }

            NText {
              text: stripAuthorEmail(modelData.author)
              font.pointSize: Style.fontSizeXS
              color: Color.mOnSurfaceVariant
            }

            NText {
              text: "•"
              font.pointSize: Style.fontSizeXS
              color: Color.mOnSurfaceVariant
            }

            NText {
              text: modelData.source ? modelData.source.name : ""
              font.pointSize: Style.fontSizeXS
              color: Color.mOnSurfaceVariant
            }

            Item {
              Layout.fillWidth: true
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
    parent: Overlay.overlay
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
              ToastService.showNotice(I18n.tr("settings.plugins.title"), I18n.tr("settings.plugins.sources.add-dialog.success"));
              PluginService.refreshAvailablePlugins();
              addSourceDialog.close();
              sourceNameInput.text = "";
              sourceUrlInput.text = "";
            } else {
              ToastService.showError(I18n.tr("settings.plugins.title"), I18n.tr("settings.plugins.sources.add-dialog.error"));
            }
          }
        }
      }
    }
  }

  // Uninstall confirmation dialog
  Popup {
    id: uninstallDialog
    parent: Overlay.overlay
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
              root.uninstallPlugin(uninstallDialog.pluginToUninstall.compositeKey);
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

  // Timer to check for updates after refresh starts
  Timer {
    id: checkUpdatesTimer
    interval: 100
    onTriggered: {
      PluginService.checkForUpdates();
    }
  }

  // Timer to recheck updates after available plugins are updated
  Timer {
    id: recheckUpdatesTimer
    interval: 50
    onTriggered: {
      PluginService.checkForUpdates();
    }
  }
  // ------------------------------
  // Functions
  // ------------------------------

  function installPlugin(pluginMetadata) {
    ToastService.showNotice(I18n.tr("settings.plugins.title"), I18n.tr("settings.plugins.installing", {
                                                                         "plugin": pluginMetadata.name
                                                                       }));

    PluginService.installPlugin(pluginMetadata, false, function (success, error, registeredKey) {
      if (success) {
        ToastService.showNotice(I18n.tr("settings.plugins.title"), I18n.tr("settings.plugins.install-success", {
                                                                             "plugin": pluginMetadata.name
                                                                           }));
        // Auto-enable the plugin after installation (use registered key which may be composite)
        PluginService.enablePlugin(registeredKey);
      } else {
        ToastService.showError(I18n.tr("settings.plugins.title"), I18n.tr("settings.plugins.install-error", {
                                                                            "error": error || "Unknown error"
                                                                          }));
      }
    });
  }

  function uninstallPlugin(pluginId) {
    var manifest = PluginRegistry.getPluginManifest(pluginId);
    var pluginName = manifest?.name || pluginId;

    ToastService.showNotice(I18n.tr("settings.plugins.title"), I18n.tr("settings.plugins.uninstalling", {
                                                                         "plugin": pluginName
                                                                       }));

    PluginService.uninstallPlugin(pluginId, function (success, error) {
      if (success) {
        ToastService.showNotice(I18n.tr("settings.plugins.title"), I18n.tr("settings.plugins.uninstall-success", {
                                                                             "plugin": pluginName
                                                                           }));
      } else {
        ToastService.showError(I18n.tr("settings.plugins.title"), I18n.tr("settings.plugins.uninstall-error", {
                                                                            "error": error || "Unknown error"
                                                                          }));
      }
    });
  }

  // Listen to plugin registry changes
  Connections {
    target: PluginRegistry

    function onPluginsChanged() {
      // Force model refresh for installed plugins by incrementing counter
      root.installedPluginsRefreshCounter++;

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
      // Force model refresh for available plugins
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

      // Manually trigger update check after a small delay to ensure all registries are loaded
      Qt.callLater(function () {
        PluginService.checkForUpdates();
      });
    }

    function onPluginUpdatesChanged() {
      // Increment counter to force installed plugins model refresh
      root.installedPluginsRefreshCounter++;
    }
  }
}
