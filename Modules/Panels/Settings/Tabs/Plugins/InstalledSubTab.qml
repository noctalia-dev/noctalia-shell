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

  // Update All button
  NButton {
    property int updateCount: Object.keys(PluginService.pluginUpdates).length
    property bool isUpdating: false

    text: I18n.tr("panels.plugins.update-all", {
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
          ToastService.showNotice(I18n.tr("panels.plugins.title"), I18n.tr("panels.plugins.update-all-success"));
          return;
        }

        var pluginId = pluginIds[currentIndex];
        currentIndex++;

        PluginService.updatePlugin(pluginId, function (success, error) {
          if (!success) {
            Logger.w("InstalledSubTab", "Failed to update", pluginId + ":", error);
          }
          Qt.callLater(updateNext);
        });
      }

      updateNext();
    }
  }

  // Installed plugins list
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
            pluginData.pendingUpdateInfo = PluginService.pluginUpdatesPending[compositeKey];
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
            color: PluginService.hasPluginError(modelData.compositeKey) ? Color.mError : Color.mPrimary
          }

          ColumnLayout {
            spacing: 2
            Layout.fillWidth: true

            NText {
              text: modelData.name
              color: Color.mPrimary
              elide: Text.ElideRight
              Layout.fillWidth: true
            }

            NText {
              text: modelData.description
              font.pointSize: Style.fontSizeXS
              color: Color.mOnSurface
              wrapMode: Text.WordWrap
              maximumLineCount: 2
              elide: Text.ElideRight
              Layout.fillWidth: true
            }

            RowLayout {
              spacing: Style.marginS

              NText {
                text: {
                  if (modelData.updateInfo) {
                    return I18n.tr("panels.plugins.update-version", {
                                     "current": modelData.version,
                                     "new": modelData.updateInfo.availableVersion
                                   });
                  } else if (modelData.pendingUpdateInfo) {
                    return I18n.tr("panels.plugins.update-pending", {
                                     "current": modelData.version,
                                     "new": modelData.pendingUpdateInfo.availableVersion,
                                     "required": modelData.pendingUpdateInfo.minNoctaliaVersion
                                   });
                  }
                  return "v" + modelData.version;
                }
                font.pointSize: Style.fontSizeXXS
                color: modelData.updateInfo ? Color.mPrimary : (modelData.pendingUpdateInfo ? Color.mTertiary : Color.mOnSurfaceVariant)
                font.weight: (modelData.updateInfo || modelData.pendingUpdateInfo) ? Style.fontWeightMedium : Style.fontWeightRegular
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
                text: modelData.sourceName || I18n.tr("panels.plugins.source-custom")
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
            tooltipText: I18n.tr("panels.plugins.settings-tooltip")
            baseSize: Style.baseWidgetSize * 0.7
            visible: modelData.entryPoints?.settings !== undefined
            onClicked: {
              pluginSettingsDialog.openPluginSettings(modelData);
            }
          }

          NIconButton {
            icon: "external-link"
            tooltipText: I18n.tr("panels.plugins.open-plugin-page")
            baseSize: Style.baseWidgetSize * 0.7
            visible: modelData.isOfficial
            onClicked: Qt.openUrlExternally("https://noctalia.dev/plugins/" + modelData.id)
          }

          NIconButton {
            icon: "trash"
            tooltipText: I18n.tr("common.uninstall")
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

            text: isUpdating ? I18n.tr("panels.plugins.updating") : I18n.tr("common.update")
            icon: isUpdating ? "" : "download"
            visible: modelData.updateInfo !== undefined
            enabled: !isUpdating
            backgroundColor: Color.mPrimary
            textColor: Color.mOnPrimary
            fontSize: Style.fontSizeXXS
            fontWeight: Style.fontWeightMedium
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
                  ToastService.showNotice(I18n.tr("panels.plugins.title"), I18n.tr("panels.plugins.update-success", {
                                                                                     "plugin": pname,
                                                                                     "version": pversion
                                                                                   }));
                } else {
                  ToastService.showError(I18n.tr("panels.plugins.title"), I18n.tr("panels.plugins.update-error", {
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
      label: I18n.tr("panels.plugins.installed-no-plugins-label")
      description: I18n.tr("panels.plugins.installed-no-plugins-description")
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

  // Listen to plugin registry changes
  Connections {
    target: PluginRegistry

    function onPluginsChanged() {
      root.installedPluginsRefreshCounter++;
    }
  }

  // Listen to plugin service signals
  Connections {
    target: PluginService

    function onPluginUpdatesChanged() {
      root.installedPluginsRefreshCounter++;
    }
  }
}
