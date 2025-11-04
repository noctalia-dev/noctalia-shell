import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Modules.Settings
import qs.Services
import qs.Widgets
import "../../Helpers/FuzzySort.js" as FuzzySort

NPanel {
  id: root

  preferredWidth: 800 * Style.uiScaleRatio
  preferredHeight: 600 * Style.uiScaleRatio
  preferredWidthRatio: 0.5
  preferredHeightRatio: 0.45

  // Positioning
  readonly property string panelPosition: {
    if (Settings.data.wallpaper.panelPosition === "follow_bar") {
      if (Settings.data.bar.position === "left" || Settings.data.bar.position === "right") {
        return `center_${Settings.data.bar.position}`
      } else {
        return `${Settings.data.bar.position}_center`
      }
    } else {
      return Settings.data.wallpaper.panelPosition
    }
  }
  panelAnchorHorizontalCenter: panelPosition === "center" || panelPosition.endsWith("_center")
  panelAnchorVerticalCenter: panelPosition === "center"
  panelAnchorLeft: panelPosition !== "center" && panelPosition.endsWith("_left")
  panelAnchorRight: panelPosition !== "center" && panelPosition.endsWith("_right")
  panelAnchorBottom: panelPosition.startsWith("bottom_")
  panelAnchorTop: panelPosition.startsWith("top_")

  // Store direct reference to content for instant access
  property var contentItem: null

  // Override keyboard handlers to enable grid navigation
  function onDownPressed() {
    if (!contentItem)
      return
    let view = contentItem.screenRepeater.itemAt(contentItem.currentScreenIndex)
    if (view?.gridView) {
      if (!view.gridView.activeFocus) {
        view.gridView.forceActiveFocus()
        if (view.gridView.currentIndex < 0) {
          view.gridView.currentIndex = 0
        }
      } else {
        view.gridView.moveCurrentIndexDown()
      }
    }
  }

  function onUpPressed() {
    if (!contentItem)
      return
    let view = contentItem.screenRepeater.itemAt(contentItem.currentScreenIndex)
    if (view?.gridView?.activeFocus) {
      view.gridView.moveCurrentIndexUp()
    }
  }

  function onLeftPressed() {
    if (!contentItem)
      return
    let view = contentItem.screenRepeater.itemAt(contentItem.currentScreenIndex)
    if (view?.gridView?.activeFocus) {
      view.gridView.moveCurrentIndexLeft()
    }
  }

  function onRightPressed() {
    if (!contentItem)
      return
    let view = contentItem.screenRepeater.itemAt(contentItem.currentScreenIndex)
    if (view?.gridView?.activeFocus) {
      view.gridView.moveCurrentIndexRight()
    }
  }

  function onReturnPressed() {
    if (!contentItem)
      return
    let view = contentItem.screenRepeater.itemAt(contentItem.currentScreenIndex)
    if (view?.gridView?.activeFocus) {
      let gridView = view.gridView
      if (gridView.currentIndex >= 0 && gridView.currentIndex < gridView.model.length) {
        let path = gridView.model[gridView.currentIndex]
        if (Settings.data.wallpaper.setWallpaperOnAllMonitors) {
          WallpaperService.changeWallpaper(path, undefined)
        } else {
          WallpaperService.changeWallpaper(path, view.targetScreen.name)
        }
      }
    }
  }

  panelContent: Rectangle {
    id: wallpaperPanel

    property int currentScreenIndex: {
      if (screen !== null) {
        for (var i = 0; i < Quickshell.screens.length; i++) {
          if (Quickshell.screens[i].name == screen.name) {
            return i
          }
        }
      }
      return 0
    }
    property var currentScreen: Quickshell.screens[currentScreenIndex]
    property string filterText: ""
    property alias screenRepeater: screenRepeater

    Component.onCompleted: {
      root.contentItem = wallpaperPanel
    }

    color: Color.transparent

    // Focus management
    Connections {
      target: root
      function onOpened() {
        // Ensure contentItem is set
        if (!root.contentItem) {
          root.contentItem = wallpaperPanel
        }
        // Give initial focus to search input
        Qt.callLater(() => {
                       if (searchInput.inputItem) {
                         searchInput.inputItem.forceActiveFocus()
                       }
                     })
      }
    }

    // Debounce timer for search
    Timer {
      id: searchDebounceTimer
      interval: 150
      onTriggered: {
        wallpaperPanel.filterText = searchInput.text
        // Trigger update on all screen views
        for (var i = 0; i < screenRepeater.count; i++) {
          let item = screenRepeater.itemAt(i)
          if (item && item.updateFiltered) {
            item.updateFiltered()
          }
        }
      }
    }

    ColumnLayout {
      anchors.fill: parent
      anchors.margins: Style.marginL
      spacing: Style.marginM

      // Header
      RowLayout {
        Layout.fillWidth: true
        spacing: Style.marginM

        NIcon {
          icon: "settings-wallpaper-selector"
          pointSize: Style.fontSizeXXL
          color: Color.mPrimary
        }

        NText {
          text: I18n.tr("wallpaper.panel.title")
          pointSize: Style.fontSizeL
          font.weight: Style.fontWeightBold
          color: Color.mOnSurface
          Layout.fillWidth: true
        }

        NIconButton {
          icon: "settings"
          tooltipText: I18n.tr("settings.wallpaper.settings.section.label")
          baseSize: Style.baseWidgetSize * 0.8
          onClicked: {
            var settingsPanel = PanelService.getPanel("settingsPanel", screen)
            settingsPanel.requestedTab = SettingsPanel.Tab.Wallpaper
            settingsPanel.open()
          }
        }

        NIconButton {
          icon: "refresh"
          tooltipText: I18n.tr("tooltips.refresh-wallpaper-list")
          baseSize: Style.baseWidgetSize * 0.8
          onClicked: WallpaperService.refreshWallpapersList()
        }

        NIconButton {
          icon: "close"
          tooltipText: I18n.tr("tooltips.close")
          baseSize: Style.baseWidgetSize * 0.8
          onClicked: root.close()
        }
      }

      NDivider {
        Layout.fillWidth: true
      }

      NToggle {
        label: I18n.tr("wallpaper.panel.apply-all-monitors.label")
        description: I18n.tr("wallpaper.panel.apply-all-monitors.description")
        checked: Settings.data.wallpaper.setWallpaperOnAllMonitors
        onToggled: checked => Settings.data.wallpaper.setWallpaperOnAllMonitors = checked
        Layout.fillWidth: true
      }

      // Monitor tabs
      TabBar {
        id: screenTabBar
        visible: !Settings.data.wallpaper.setWallpaperOnAllMonitors || Settings.data.wallpaper.enableMultiMonitorDirectories
        Layout.fillWidth: true
        currentIndex: currentScreenIndex
        onCurrentIndexChanged: currentScreenIndex = currentIndex
        spacing: Style.marginM

        background: Rectangle {
          color: Color.transparent
        }

        Repeater {
          model: Quickshell.screens
          delegate: TabButton {
            text: modelData.name || `Screen ${index + 1}`
            width: implicitWidth + Style.marginS * 2

            background: Rectangle {
              color: screenTabBar.currentIndex === index ? Color.mSecondary : Color.transparent
              radius: Style.radiusS
              border.width: screenTabBar.currentIndex === index ? 0 : Style.borderS
              border.color: Color.mOutline

              Behavior on color {
                ColorAnimation {
                  duration: Style.animationFast
                }
              }
            }

            contentItem: NText {
              text: parent.text
              pointSize: Style.fontSizeL
              font.weight: screenTabBar.currentIndex === index ? Style.fontWeightBold : Style.fontWeightRegular
              family: Settings.data.ui.fontDefault
              color: screenTabBar.currentIndex === index ? Color.mOnSecondary : Color.mOnSurfaceVariant
              horizontalAlignment: Text.AlignHCenter
              verticalAlignment: Text.AlignVCenter
            }

            // Add hover effect
            HoverHandler {
              id: tabHover
            }

            Rectangle {
              anchors.fill: parent
              color: Color.mOnSurface
              opacity: tabHover.hovered && screenTabBar.currentIndex !== index ? 0.08 : 0
              radius: Style.radiusS

              Behavior on opacity {
                NumberAnimation {
                  duration: Style.animationFast
                }
              }
            }
          }
        }
      }

      // StackLayout for each screen's wallpaper content
      StackLayout {
        id: screenStack
        Layout.fillWidth: true
        Layout.fillHeight: true
        currentIndex: currentScreenIndex

        Repeater {
          id: screenRepeater
          model: Quickshell.screens
          delegate: WallpaperScreenView {
            targetScreen: modelData
          }
        }
      }

      // Filter input
      RowLayout {
        Layout.fillWidth: true
        spacing: Style.marginM

        NText {
          text: I18n.tr("wallpaper.panel.search")
          color: Color.mOnSurface
          pointSize: Style.fontSizeM
          Layout.preferredWidth: implicitWidth
        }

        NTextInput {
          id: searchInput
          placeholderText: I18n.tr("placeholders.search-wallpapers")
          Layout.fillWidth: true

          onTextChanged: {
            searchDebounceTimer.restart()
          }

          Keys.onDownPressed: {
            let currentView = screenRepeater.itemAt(currentScreenIndex)
            if (currentView && currentView.gridView) {
              currentView.gridView.forceActiveFocus()
            }
          }

          Component.onCompleted: {
            if (searchInput.inputItem && searchInput.inputItem.visible) {
              searchInput.inputItem.forceActiveFocus()
            }
          }
        }
      }
    }
  }

  // Component for each screen's wallpaper view
  component WallpaperScreenView: Item {
    property var targetScreen
    property alias gridView: wallpaperGridView

    // Local reactive state for this screen
    property list<string> wallpapersList: []
    property string currentWallpaper: ""
    property list<string> filteredWallpapers: []
    property var wallpapersWithNames: [] // Cached basenames

    // Expose updateFiltered as a proper function property
    function updateFiltered() {
      if (!wallpaperPanel.filterText || wallpaperPanel.filterText.trim().length === 0) {
        filteredWallpapers = wallpapersList
        return
      }

      const results = FuzzySort.go(wallpaperPanel.filterText.trim(), wallpapersWithNames, {
                                     "key": 'name',
                                     "limit": 200
                                   })
      // Map back to path list
      filteredWallpapers = results.map(function (r) {
        return r.obj.path
      })
    }

    Component.onCompleted: {
      refreshWallpaperScreenData()
    }

    Connections {
      target: WallpaperService
      function onWallpaperChanged(screenName, path) {
        if (targetScreen !== null && screenName === targetScreen.name) {
          currentWallpaper = WallpaperService.getWallpaper(targetScreen.name)
        }
      }
      function onWallpaperDirectoryChanged(screenName, directory) {
        if (targetScreen !== null && screenName === targetScreen.name) {
          refreshWallpaperScreenData()
        }
      }
      function onWallpaperListChanged(screenName, count) {
        if (targetScreen !== null && screenName === targetScreen.name) {
          refreshWallpaperScreenData()
        }
      }
    }

    function refreshWallpaperScreenData() {
      if (targetScreen === null) {
        return
      }
      wallpapersList = WallpaperService.getWallpapersList(targetScreen.name)
      Logger.i("WallpaperPanel", "Got", wallpapersList.length, "wallpapers for screen", targetScreen.name)

      // Pre-compute basenames once for better performance
      wallpapersWithNames = wallpapersList.map(function (p) {
        return {
          "path": p,
          "name": p.split('/').pop()
        }
      })

      currentWallpaper = WallpaperService.getWallpaper(targetScreen.name)
      updateFiltered()
    }

    ColumnLayout {
      anchors.fill: parent
      spacing: Style.marginM

      GridView {
        id: wallpaperGridView

        Layout.fillWidth: true
        Layout.fillHeight: true

        visible: !WallpaperService.scanning
        interactive: true
        clip: true
        focus: true
        keyNavigationEnabled: true
        keyNavigationWraps: false

        model: filteredWallpapers

        property int columns: (screen.width > 1920) ? 5 : 4
        property int itemSize: cellWidth

        cellWidth: Math.floor((width - leftMargin - rightMargin) / columns)
        cellHeight: Math.floor(itemSize * 0.7) + Style.marginXS + Style.fontSizeXS + Style.marginM

        leftMargin: Style.marginS
        rightMargin: Style.marginS
        topMargin: Style.marginS
        bottomMargin: Style.marginS

        onCurrentIndexChanged: {
          // Synchronize scroll with current item position
          if (currentIndex >= 0) {
            let row = Math.floor(currentIndex / columns)
            let itemY = row * cellHeight
            let viewportTop = contentY
            let viewportBottom = viewportTop + height

            // If item is out of view, scroll
            if (itemY < viewportTop) {
              contentY = Math.max(0, itemY - cellHeight)
            } else if (itemY + cellHeight > viewportBottom) {
              contentY = itemY + cellHeight - height + cellHeight
            }
          }
        }

        Keys.onPressed: event => {
                          if (event.key === Qt.Key_Return || event.key === Qt.Key_Space) {
                            if (currentIndex >= 0 && currentIndex < filteredWallpapers.length) {
                              let path = filteredWallpapers[currentIndex]
                              if (Settings.data.wallpaper.setWallpaperOnAllMonitors) {
                                WallpaperService.changeWallpaper(path, undefined)
                              } else {
                                WallpaperService.changeWallpaper(path, targetScreen.name)
                              }
                            }
                            event.accepted = true
                          }
                        }

        ScrollBar.vertical: ScrollBar {
          policy: ScrollBar.AsNeeded
        }

        delegate: ColumnLayout {
          id: wallpaperItem

          property string wallpaperPath: modelData
          property bool isSelected: (wallpaperPath === currentWallpaper)
          property string filename: wallpaperPath.split('/').pop()

          width: wallpaperGridView.itemSize
          spacing: Style.marginXS

          Rectangle {
            id: imageContainer
            Layout.fillWidth: true
            Layout.preferredHeight: Math.round(wallpaperGridView.itemSize * 0.67)
            color: Color.transparent

            NImageCached {
              id: img
              maxCacheDimension: 384
              imagePath: wallpaperPath
              cacheFolder: Settings.cacheDirImagesWallpapers
              anchors.fill: parent
            }

            Rectangle {
              anchors.fill: parent
              color: Color.transparent
              border.color: {
                if (isSelected) {
                  return Color.mSecondary
                }
                if (wallpaperGridView.currentIndex === index) {
                  return Color.mHover
                }
                return Color.mSurface
              }
              border.width: Math.max(1, Style.borderL * 1.5)
            }

            Rectangle {
              anchors.top: parent.top
              anchors.right: parent.right
              anchors.margins: Style.marginS
              width: 28
              height: 28
              radius: width / 2
              color: Color.mSecondary
              border.color: Color.mOutline
              border.width: Style.borderS
              visible: isSelected

              NIcon {
                icon: "check"
                pointSize: Style.fontSizeM
                color: Color.mOnSecondary
                anchors.centerIn: parent
              }
            }

            Rectangle {
              anchors.fill: parent
              color: Color.mSurface
              opacity: (hoverHandler.hovered || isSelected || wallpaperGridView.currentIndex === index) ? 0 : 0.3
              radius: parent.radius
              Behavior on opacity {
                NumberAnimation {
                  duration: Style.animationFast
                }
              }
            }

            // More efficient hover handling
            HoverHandler {
              id: hoverHandler
            }

            TapHandler {
              onTapped: {
                wallpaperGridView.currentIndex = index
                if (Settings.data.wallpaper.setWallpaperOnAllMonitors) {
                  WallpaperService.changeWallpaper(wallpaperPath, undefined)
                } else {
                  WallpaperService.changeWallpaper(wallpaperPath, targetScreen.name)
                }
              }
            }
          }

          NText {
            text: filename
            color: (hoverHandler.hovered || isSelected || wallpaperGridView.currentIndex === index) ? Color.mOnSurface : Color.mOnSurfaceVariant
            pointSize: Style.fontSizeXS
            Layout.fillWidth: true
            Layout.leftMargin: Style.marginS
            Layout.rightMargin: Style.marginS
            Layout.alignment: Qt.AlignHCenter
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
          }
        }
      }

      // Empty / scanning state
      Rectangle {
        color: Color.mSurface
        radius: Style.radiusM
        border.color: Color.mOutline
        border.width: Style.borderS
        visible: (filteredWallpapers.length === 0 && !WallpaperService.scanning) || WallpaperService.scanning
        Layout.fillWidth: true
        Layout.preferredHeight: 130

        ColumnLayout {
          anchors.fill: parent
          visible: WallpaperService.scanning
          NBusyIndicator {
            Layout.alignment: Qt.AlignHCenter | Qt.AlignVCenter
          }
        }

        ColumnLayout {
          anchors.fill: parent
          visible: filteredWallpapers.length === 0 && !WallpaperService.scanning
          Item {
            Layout.fillHeight: true
          }
          NIcon {
            icon: "folder-open"
            pointSize: Style.fontSizeXXL
            color: Color.mOnSurface
            Layout.alignment: Qt.AlignHCenter
          }
          NText {
            text: (wallpaperPanel.filterText && wallpaperPanel.filterText.length > 0) ? I18n.tr("wallpaper.no-match") : I18n.tr("wallpaper.no-wallpaper")
            color: Color.mOnSurface
            font.weight: Style.fontWeightBold
            Layout.alignment: Qt.AlignHCenter
          }
          NText {
            text: (wallpaperPanel.filterText && wallpaperPanel.filterText.length > 0) ? I18n.tr("wallpaper.try-different-search") : I18n.tr("wallpaper.configure-directory")
            color: Color.mOnSurfaceVariant
            wrapMode: Text.WordWrap
            Layout.alignment: Qt.AlignHCenter
          }
          Item {
            Layout.fillHeight: true
          }
        }
      }
    }
  }
}
