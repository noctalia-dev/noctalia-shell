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
  Layout.fillWidth: true

  property string pluginSearchText: ""
  property string selectedTag: ""
  property int tagsRefreshCounter: 0
  property int availablePluginsRefreshCounter: 0

  // Pseudo tags for filtering
  readonly property var pseudoTags: ["official", "downloaded", "notDownloaded"]

  readonly property var availableTags: {
    // Reference counter to force re-evaluation
    void (root.tagsRefreshCounter);
    var tags = {};
    var plugins = PluginService.availablePlugins || [];
    for (var i = 0; i < plugins.length; i++) {
      var pluginTags = plugins[i].tags || [];
      for (var j = 0; j < pluginTags.length; j++) {
        tags[pluginTags[j]] = true;
      }
    }
    return Object.keys(tags).sort();
  }

  function stripAuthorEmail(author) {
    if (!author)
      return "";
    var lastBracket = author.lastIndexOf("<");
    if (lastBracket >= 0) {
      return author.substring(0, lastBracket).trim();
    }
    return author;
  }

  // Tag filter chips in collapsible
  NTagFilter {
    tags: root.pseudoTags.concat(root.availableTags)
    selectedTag: root.selectedTag
    onSelectedTagChanged: root.selectedTag = selectedTag
    label: I18n.tr("panels.plugins.filter-tags-label")
    description: I18n.tr("panels.plugins.filter-tags-description")
    expanded: true

    formatTag: function (tag) {
      if (tag === "")
        return I18n.tr("launcher.categories.all");
      if (tag === "official")
        return I18n.tr("common.official");
      if (tag === "downloaded")
        return I18n.tr("panels.plugins.filter-downloaded");
      if (tag === "notDownloaded")
        return I18n.tr("panels.plugins.filter-not-downloaded");
      return tag;
    }
  }

  // Search input with refresh button
  RowLayout {
    Layout.fillWidth: true
    spacing: Style.marginM

    NTextInput {
      placeholderText: I18n.tr("placeholders.search")
      inputIconName: "search"
      text: root.pluginSearchText
      onTextChanged: root.pluginSearchText = text
      Layout.fillWidth: true
    }

    NIconButton {
      icon: "refresh"
      tooltipText: I18n.tr("panels.plugins.refresh-tooltip")
      baseSize: Style.baseWidgetSize * 0.9
      onClicked: {
        PluginService.refreshAvailablePlugins();
        checkUpdatesTimer.restart();
        ToastService.showNotice(I18n.tr("panels.plugins.title"), I18n.tr("panels.plugins.refresh-refreshing"));
      }
    }
  }

  // Available plugins list
  ColumnLayout {
    spacing: Style.marginM
    Layout.fillWidth: true

    Repeater {
      id: availablePluginsRepeater

      model: {
        // Reference counter to force re-evaluation when plugins are updated
        void (root.availablePluginsRefreshCounter);

        var all = PluginService.availablePlugins || [];
        var filtered = [];

        // Apply filter based on selectedTag
        for (var i = 0; i < all.length; i++) {
          var plugin = all[i];
          var downloaded = plugin.downloaded || false;
          var pluginTags = plugin.tags || [];

          if (root.selectedTag === "") {
            // "All" - no filter
            filtered.push(plugin);
          } else if (root.selectedTag === "official") {
            // Official (team-maintained) pseudo tag
            if (plugin.official === true)
              filtered.push(plugin);
          } else if (root.selectedTag === "downloaded") {
            // Downloaded pseudo tag
            if (downloaded)
              filtered.push(plugin);
          } else if (root.selectedTag === "notDownloaded") {
            // Not Downloaded pseudo tag
            if (!downloaded)
              filtered.push(plugin);
          } else {
            // Actual category tag
            if (pluginTags.indexOf(root.selectedTag) >= 0) {
              filtered.push(plugin);
            }
          }
        }

        // Then apply fuzzy search if there's search text
        var query = root.pluginSearchText.trim();
        if (query !== "") {
          var results = FuzzySort.go(query, filtered, {
                                       "keys": ["name", "description"],
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

        // Move hello-world plugin to the end
        var helloWorldIndex = -1;
        for (var h = 0; h < filtered.length; h++) {
          if (filtered[h].id === "hello-world") {
            helloWorldIndex = h;
            break;
          }
        }
        if (helloWorldIndex >= 0) {
          var helloWorld = filtered.splice(helloWorldIndex, 1)[0];
          filtered.push(helloWorld);
        }

        return filtered;
      }

      delegate: NBox {
        id: pluginBox

        Layout.fillWidth: true
        Layout.leftMargin: Style.borderS
        Layout.rightMargin: Style.borderS
        implicitHeight: Math.round(contentColumn.implicitHeight + Style.marginL * 2)
        color: Color.mSurface

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
              color: Color.mPrimary
            }

            NText {
              text: modelData.name
              color: Color.mPrimary
              elide: Text.ElideRight
            }

            // Official badge (Noctalia Team maintained)
            Rectangle {
              visible: modelData.official === true
              color: Color.mSecondary
              radius: Style.radiusXS
              implicitWidth: officialBadgeRow.implicitWidth + Style.marginS * 2
              implicitHeight: officialBadgeRow.implicitHeight + Style.marginXS * 2

              RowLayout {
                id: officialBadgeRow
                anchors.centerIn: parent
                spacing: Style.marginXS

                NIcon {
                  icon: "official-plugin"
                  pointSize: Style.fontSizeXXS
                  color: Color.mOnSecondary
                }

                NText {
                  text: I18n.tr("common.official")
                  font.pointSize: Style.fontSizeXXS
                  font.weight: Style.fontWeightMedium
                  color: Color.mOnSecondary
                }
              }
            }

            // Spacer
            Item {
              Layout.fillWidth: true
            }

            // Downloaded indicator
            NIcon {
              icon: "circle-check"
              pointSize: Style.baseWidgetSize * 0.5
              color: Color.mPrimary
              visible: modelData.downloaded === true
            }

            // Open plugin page button
            NIconButton {
              icon: "external-link"
              baseSize: Style.baseWidgetSize * 0.7
              tooltipText: I18n.tr("panels.plugins.open-plugin-page")
              onClicked: Qt.openUrlExternally("https://noctalia.dev/plugins/" + modelData.id + "/")
            }

            // Install/Uninstall button
            NIconButton {
              icon: modelData.downloaded ? "trash" : "download"
              baseSize: Style.baseWidgetSize * 0.7
              tooltipText: modelData.downloaded ? I18n.tr("common.uninstall") : I18n.tr("common.install")
              onClicked: {
                if (modelData.downloaded) {
                  // Construct composite key for available plugins
                  var pluginData = Object.assign({}, modelData);
                  pluginData.compositeKey = PluginRegistry.generateCompositeKey(modelData.id, modelData.source?.url || "");
                  uninstallDialog.pluginToUninstall = pluginData;
                  uninstallDialog.open();
                } else {
                  installPlugin(modelData);
                }
              }
            }
          }

          // Description
          NText {
            visible: modelData.description
            text: modelData.description || ""
            font.pointSize: Style.fontSizeXS
            color: Color.mOnSurface
            wrapMode: Text.WordWrap
            maximumLineCount: 2
            elide: Text.ElideRight
            Layout.fillWidth: true
          }

          // Details row
          RowLayout {
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

            NText {
              visible: !!modelData.lastUpdated
              text: "•"
              font.pointSize: Style.fontSizeXS
              color: Color.mOnSurfaceVariant
            }

            NText {
              visible: !!modelData.lastUpdated
              text: modelData.lastUpdated ? Time.formatRelativeTime(new Date(modelData.lastUpdated)) : ""
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
      label: I18n.tr("panels.plugins.available-no-plugins-label")
      description: I18n.tr("panels.plugins.available-no-plugins-description")
      Layout.fillWidth: true
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
        label: I18n.tr("panels.plugins.uninstall-dialog-title")
        description: I18n.tr("panels.plugins.uninstall-dialog-description", {
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
          text: I18n.tr("common.uninstall")
          backgroundColor: Color.mPrimary
          textColor: Color.mOnPrimary
          onClicked: {
            if (uninstallDialog.pluginToUninstall) {
              uninstallPlugin(uninstallDialog.pluginToUninstall.compositeKey);
              uninstallDialog.close();
            }
          }
        }
      }
    }
  }

  // Timer to check for updates after refresh starts
  Timer {
    id: checkUpdatesTimer
    interval: 100
    onTriggered: {
      PluginService.checkForUpdates();
    }
  }

  function installPlugin(pluginMetadata) {
    ToastService.showNotice(I18n.tr("panels.plugins.title"), I18n.tr("panels.plugins.installing", {
                                                                       "plugin": pluginMetadata.name
                                                                     }));

    PluginService.installPlugin(pluginMetadata, false, function (success, error, registeredKey) {
      if (success) {
        ToastService.showNotice(I18n.tr("panels.plugins.title"), I18n.tr("panels.plugins.install-success", {
                                                                           "plugin": pluginMetadata.name
                                                                         }));
        // Auto-enable the plugin after installation (use registered key which may be composite)
        PluginService.enablePlugin(registeredKey);
      } else {
        ToastService.showError(I18n.tr("panels.plugins.title"), I18n.tr("panels.plugins.install-error", {
                                                                          "error": error || "Unknown error"
                                                                        }));
      }
    });
  }

  function uninstallPlugin(pluginId) {
    var manifest = PluginRegistry.getPluginManifest(pluginId);
    var pluginName = manifest?.name || pluginId;

    ToastService.showNotice(I18n.tr("panels.plugins.title"), I18n.tr("panels.plugins.uninstalling", {
                                                                       "plugin": pluginName
                                                                     }));

    PluginService.uninstallPlugin(pluginId, function (success, error) {
      if (success) {
        ToastService.showNotice(I18n.tr("panels.plugins.title"), I18n.tr("panels.plugins.uninstall-success", {
                                                                           "plugin": pluginName
                                                                         }));
      } else {
        ToastService.showError(I18n.tr("panels.plugins.title"), I18n.tr("panels.plugins.uninstall-error", {
                                                                          "error": error || "Unknown error"
                                                                        }));
      }
    });
  }

  // Listen to plugin service signals
  Connections {
    target: PluginService

    function onAvailablePluginsUpdated() {
      // Force tags and plugins model to re-evaluate
      root.tagsRefreshCounter++;
      root.availablePluginsRefreshCounter++;

      // Manually trigger update check after a small delay to ensure all registries are loaded
      Qt.callLater(function () {
        PluginService.checkForUpdates();
      });
    }
  }
}
