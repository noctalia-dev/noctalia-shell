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

  // List of plugin sources
  ColumnLayout {
    spacing: Style.marginM
    Layout.fillWidth: true

    Repeater {
      id: pluginSourcesRepeater
      model: PluginRegistry.pluginSources || []

      delegate: NBox {
        Layout.fillWidth: true
        implicitHeight: sourceRow.implicitHeight + Style.margin2L
        color: Color.mSurface

        RowLayout {
          id: sourceRow
          anchors.fill: parent
          anchors.margins: Style.marginL
          spacing: Style.marginM

          NIcon {
            icon: "brand-github"
            pointSize: Style.fontSizeL
          }

          ColumnLayout {
            spacing: 2
            Layout.fillWidth: true

            NText {
              text: modelData.name
              color: Color.mOnSurface
              Layout.fillWidth: true
            }

            NText {
              text: modelData.url
              font.pointSize: Style.fontSizeXS
              color: Color.mOnSurfaceVariant
              Layout.fillWidth: true
              elide: Text.ElideRight
            }
          }

          NIconButton {
            icon: "trash"
            tooltipText: I18n.tr("panels.plugins.sources-remove-tooltip")
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
                         ToastService.showNotice(I18n.tr("panels.plugins.title"), I18n.tr("panels.plugins.refresh-refreshing"));
                       }
          }
        }
      }
    }
  }

  // Add custom repository
  NButton {
    text: I18n.tr("panels.plugins.sources-add-custom")
    icon: "plus"
    onClicked: {
      addSourceDialog.open();
    }
    Layout.fillWidth: true
  }

  // Add source dialog
  NPopup {
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
        label: I18n.tr("panels.plugins.sources-add-dialog-title")
        description: I18n.tr("panels.plugins.sources-add-dialog-description")
      }

      NTextInput {
        id: sourceNameInput
        label: I18n.tr("panels.plugins.sources-add-dialog-name")
        placeholderText: I18n.tr("panels.plugins.sources-add-dialog-name-placeholder")
        Layout.fillWidth: true
      }

      NTextInput {
        id: sourceUrlInput
        label: I18n.tr("panels.plugins.sources-add-dialog-url")
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
              ToastService.showNotice(I18n.tr("panels.plugins.title"), I18n.tr("panels.plugins.sources-add-dialog-success"));
              PluginService.refreshAvailablePlugins();
              addSourceDialog.close();
              sourceNameInput.text = "";
              sourceUrlInput.text = "";
            } else {
              ToastService.showError(I18n.tr("panels.plugins.title"), I18n.tr("panels.plugins.sources-add-dialog-error"));
            }
          }
        }
      }
    }
  }

  // Listen to plugin registry changes
  Connections {
    target: PluginRegistry

    function onPluginsChanged() {
      // Force model refresh for plugin sources
      pluginSourcesRepeater.model = undefined;
      Qt.callLater(function () {
        pluginSourcesRepeater.model = Qt.binding(function () {
          return PluginRegistry.pluginSources || [];
        });
      });
    }
  }
}
