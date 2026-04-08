import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Services.Noctalia
import qs.Widgets

RowLayout {
  id: root
  spacing: 0

  property string selectedPluginId: ""
  property string _selectedPluginFallbackUrl: ""

  function _buildReadmeFallbackUrl(pluginId, sourceUrl) {
    if (!sourceUrl || sourceUrl === "") return ""
    if (sourceUrl.indexOf("https://github.com/") !== 0) return ""
    if (!(/^[a-zA-Z0-9_-]+$/).test(pluginId)) return ""
    var raw = sourceUrl.replace("https://github.com/", "https://raw.githubusercontent.com/")
    if (sourceUrl.indexOf("noctalia-dev/noctalia-plugins") !== -1)
      return raw + "/main/" + pluginId + "/README.md"
    return raw + "/main/README.md"
  }

  // Left column
  Item {
    Layout.preferredWidth: Math.round(360 * Style.uiScaleRatio)
    Layout.maximumWidth: Math.round(360 * Style.uiScaleRatio)
    Layout.fillHeight: true

    ColumnLayout {
      anchors.fill: parent
      spacing: 0

      NTabBar {
        id: subTabBar
        Layout.fillWidth: true
        Layout.bottomMargin: Style.marginM
        distributeEvenly: true
        currentIndex: 0

        NTabButton {
          text: I18n.tr("common.installed")
          tabIndex: 0
          checked: subTabBar.currentIndex === 0
        }
        NTabButton {
          text: I18n.tr("common.available")
          tabIndex: 1
          checked: subTabBar.currentIndex === 1
        }
        NTabButton {
          text: I18n.tr("common.sources")
          tabIndex: 2
          checked: subTabBar.currentIndex === 2
        }
      }

      StackLayout {
        Layout.fillWidth: true
        Layout.fillHeight: true
        currentIndex: subTabBar.currentIndex

        NScrollView {
          id: installedScrollView
          horizontalPolicy: ScrollBar.AlwaysOff
          gradientColor: Color.mSurface

          Item {
            width: installedScrollView.availableWidth
            implicitWidth: installedScrollView.availableWidth
            implicitHeight: installedContent.implicitHeight

            InstalledSubTab {
              id: installedContent
              width: parent.width
              selectedPluginId: root.selectedPluginId
              onPluginSelected: id => {
                root._selectedPluginFallbackUrl = ""
                root.selectedPluginId = id
              }
            }
          }
        }

        NScrollView {
          id: availableScrollView
          horizontalPolicy: ScrollBar.AlwaysOff
          gradientColor: Color.mSurface

          Item {
            width: availableScrollView.availableWidth
            implicitWidth: availableScrollView.availableWidth
            implicitHeight: availableContent.implicitHeight

            AvailableSubTab {
              id: availableContent
              width: parent.width
              selectedPluginId: root.selectedPluginId
              onPluginSelected: (id, srcUrl) => {
                root._selectedPluginFallbackUrl = root._buildReadmeFallbackUrl(id, srcUrl)
                root.selectedPluginId = id
              }
            }
          }
        }

        NScrollView {
          id: sourcesScrollView
          horizontalPolicy: ScrollBar.AlwaysOff
          gradientColor: Color.mSurface

          Item {
            width: sourcesScrollView.availableWidth
            implicitWidth: sourcesScrollView.availableWidth
            implicitHeight: sourcesContent.implicitHeight

            SourcesSubTab {
              id: sourcesContent
              width: parent.width
            }
          }
        }
      }
    }
  }

  // Vertical divider
  NDivider {
    vertical: true
    Layout.fillHeight: true
    Layout.leftMargin: Style.marginM
    Layout.rightMargin: Style.marginM
  }

  // Right column — README
  PluginsReadmeView {
    Layout.fillWidth: true
    Layout.fillHeight: true
    selectedPluginId: root.selectedPluginId
    fallbackReadmeUrl: root._selectedPluginFallbackUrl
  }
}
