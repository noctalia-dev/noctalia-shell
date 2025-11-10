import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Widgets
import qs.Modules.MainScreen

SmartPanel {
  id: root

  // Inputs
  property QsMenuHandle menu
  property var trayItem: null
  property string widgetSection: ""
  property int widgetIndex: -1

  // Internal
  property int menuWidth: 280
  readonly property int minMenuWidth: 280
  readonly property int maxMenuWidth: 600
  preferredWidth: menuWidth
  // Height is content-driven via panelContent

  // Open positioned relative to button
  function openAt(buttonItem) {
    open(buttonItem)
  }

  panelContent: Item {
    id: content

    // Track currently open submenu
    property var activeSubMenu: null
    property var activeSubMenuEntry: null
    // Only show submenu in place (replace main menu)
    property bool inPlaceSubmenu: true

    // Let Panel size to our content
    readonly property real contentPreferredWidth: root.menuWidth
    readonly property real contentPreferredHeight: {
      // If showing submenu in-place, size to the submenu's flickable content height
      if (activeSubMenu && inPlaceSubmenu) {
        const subFlickable = inPlaceSubMenuLoader.item?.children[1] // Flickable is the second child (after MouseArea)
        const subHeight = subFlickable?.contentHeight || 0
        return Math.min(root.screen ? root.screen.height * 0.9 : Screen.height * 0.9, subHeight + (Style.marginS * 2))
      }

      const mainHeight = mainFlickable.contentHeight
      return Math.min(root.screen ? root.screen.height * 0.9 : Screen.height * 0.9, mainHeight + (Style.marginS * 2))
    }

    QsMenuOpener {
      id: opener
      menu: root.menu
      onChildrenChanged: Qt.callLater(() => calculateMenuWidth(opener))
    }

    // Text metrics for measuring text widths
    TextMetrics {
      id: textMetrics
      font.pointSize: Style.fontSizeS
    }

    // Watch for submenu changes
    onActiveSubMenuChanged: {
      if (activeSubMenu && inPlaceSubmenu) {
        Qt.callLater(() => {
                       // Find the subMenuOpener in the loaded component
                       if (inPlaceSubMenuLoader.item) {
                         const flickable = inPlaceSubMenuLoader.item.children[1] // Flickable
                         if (flickable && flickable.children.length > 0) {
                           const columnLayout = flickable.children[0]
                           if (columnLayout && columnLayout.children.length > 0) {
                             const subOpener = columnLayout.children[0]
                             if (subOpener) {
                               calculateMenuWidth(subOpener)
                             }
                           }
                         }
                       }
                     })
      } else if (!activeSubMenu) {
        // Reset to main menu width when submenu closes
        Qt.callLater(() => calculateMenuWidth(opener))
      }
    }

    // Calculate required menu width based on menu entries
    function calculateMenuWidth(menuOpener) {
      let maxWidth = root.minMenuWidth

      // For submenus, also measure the "Back" button
      if (menuOpener !== opener && content.inPlaceSubmenu) {
        textMetrics.text = I18n.tr("settings.bar.tray.back")
        const backWidth = (Style.marginM * 4) + Style.fontSizeS + Style.marginS + textMetrics.width
        maxWidth = Math.max(maxWidth, backWidth)
      }

      // Check all menu entries
      if (menuOpener && menuOpener.children) {
        try {
          const entries = menuOpener.children.values ? [...menuOpener.children.values] : []

          for (var i = 0; i < entries.length; i++) {
            const entry = entries[i]
            if (!entry || entry.isSeparator)
              continue

            const text = entry.text || ""
            if (text === "")
              continue

            // Measure the text
            textMetrics.text = text.replace(/[\n\r]+/g, ' ')
            const textWidth = textMetrics.width

            // Calculate total width:
            // - Outer inset: Style.marginM * 2 (parent width reduction)
            // - RowLayout margins: Style.marginM * 2 (left + right)
            // - Text width
            // - Spacing: Style.marginS
            // - Icon: Style.marginL (if present)
            // - Submenu arrow: ~20px (if present)
            let requiredWidth = (Style.marginM * 4) + textWidth

            if (entry.icon && entry.icon !== "") {
              requiredWidth += Style.marginS + Style.marginL
            }

            if (entry.hasChildren) {
              requiredWidth += Style.marginS + 20
            }

            maxWidth = Math.max(maxWidth, requiredWidth)
          }
        } catch (e) {

          // Silently ignore errors during width calculation
        }
      }

      // Check pin/unpin button (only for main menu)
      if (menuOpener === opener && root.trayItem !== null && root.widgetSection !== "" && root.widgetIndex >= 0) {
        textMetrics.text = I18n.tr("settings.bar.tray.pin-application")
        let pinWidth = (Style.marginM * 4) + textMetrics.width + Style.marginS + 20
        maxWidth = Math.max(maxWidth, pinWidth)

        textMetrics.text = I18n.tr("settings.bar.tray.unpin-application")
        let unpinWidth = (Style.marginM * 4) + textMetrics.width + Style.marginS + 20
        maxWidth = Math.max(maxWidth, unpinWidth)
      }

      // Clamp to min/max and apply
      const finalWidth = Math.min(root.maxMenuWidth, Math.max(root.minMenuWidth, Math.ceil(maxWidth)))
      root.menuWidth = finalWidth
    }

    Component.onCompleted: Qt.callLater(() => calculateMenuWidth(opener))

    Component {
      id: subMenuComponent

      Item {
        id: subMenuContainer

        // MouseArea to track hover for submenu (covers entire submenu area)
        MouseArea {
          id: subMenuMouseArea
          anchors.fill: parent
          hoverEnabled: true
          enabled: content.activeSubMenu !== null && !content.inPlaceSubmenu
          visible: !content.inPlaceSubmenu
          z: 1
          acceptedButtons: Qt.NoButton // Don't intercept clicks, just track hover
          onExited: {
            if (content.inPlaceSubmenu)
              return
            Qt.callLater(() => {
                           if (!subMenuMouseArea.containsMouse && content.activeSubMenuEntry) {
                             // Find the mouseArea in the entry (it's in the second Rectangle's MouseArea)
                             let entryMouseArea = null
                             for (var i = 0; i < content.activeSubMenuEntry.children.length; i++) {
                               const child = content.activeSubMenuEntry.children[i]
                               if (child && child.children && child.children.length > 0) {
                                 for (var j = 0; j < child.children.length; j++) {
                                   const grandchild = child.children[j]
                                   if (grandchild && grandchild.hoverEnabled !== undefined) {
                                     entryMouseArea = grandchild
                                     break
                                   }
                                 }
                               }
                               if (entryMouseArea)
                               break
                             }
                             if (!entryMouseArea || !entryMouseArea.containsMouse) {
                               content.activeSubMenu = null
                               content.activeSubMenuEntry = null
                             }
                           }
                         })
          }
        }

        Flickable {
          id: subMenuFlickable
          anchors.fill: parent
          contentHeight: subMenuColumnLayout.implicitHeight
          interactive: false
          z: 0

          ColumnLayout {
            id: subMenuColumnLayout
            width: subMenuFlickable.width
            spacing: 0

            QsMenuOpener {
              id: subMenuOpener
              menu: content.activeSubMenu
              onChildrenChanged: Qt.callLater(() => content.calculateMenuWidth(subMenuOpener))
            }

            // Back button (only shown when submenu is in-place)
            Rectangle {
              id: backEntry
              visible: content.inPlaceSubmenu
              Layout.preferredWidth: parent.width
              Layout.preferredHeight: visible ? 28 : 0
              color: Color.transparent

              Rectangle {
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.topMargin: 0
                anchors.bottomMargin: 0
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width - (Style.marginM * 2)
                color: backMouseArea.containsMouse ? Color.mHover : Color.transparent
                radius: Style.radiusS

                RowLayout {
                  anchors.fill: parent
                  anchors.leftMargin: Style.marginM
                  anchors.rightMargin: Style.marginM
                  spacing: Style.marginS

                  NIcon {
                    icon: "arrow-left"
                    pointSize: Style.fontSizeS
                    applyUiScale: false
                    verticalAlignment: Text.AlignVCenter
                    color: backMouseArea.containsMouse ? Color.mOnHover : Color.mOnSurface
                  }

                  NText {
                    Layout.fillWidth: true
                    color: backMouseArea.containsMouse ? Color.mOnHover : Color.mOnSurface
                    text: I18n.tr("settings.bar.tray.back")
                    pointSize: Style.fontSizeS
                    verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideRight
                  }
                }

                MouseArea {
                  id: backMouseArea
                  anchors.fill: parent
                  hoverEnabled: true

                  onClicked: {
                    content.activeSubMenu = null
                    content.activeSubMenuEntry = null
                  }
                }
              }
            }

            Rectangle {
              visible: content.inPlaceSubmenu
              Layout.preferredWidth: parent.width
              Layout.preferredHeight: visible ? 8 : 0
              color: Color.transparent

              NDivider {
                anchors.centerIn: parent
                width: parent.width - (Style.marginM * 2)
                visible: parent.visible
              }
            }

            Repeater {
              model: subMenuOpener.children ? [...subMenuOpener.children.values] : []

              delegate: Rectangle {
                id: subEntry
                required property var modelData

                Layout.preferredWidth: parent.width
                Layout.preferredHeight: {
                  if (modelData?.isSeparator) {
                    return 8
                  } else {
                    return 28
                  }
                }

                color: Color.transparent

                NDivider {
                  anchors.centerIn: parent
                  width: parent.width - (Style.marginM * 2)
                  visible: modelData?.isSeparator ?? false
                }

                Rectangle {
                  anchors.top: parent.top
                  anchors.bottom: parent.bottom
                  anchors.topMargin: 0
                  anchors.bottomMargin: 0
                  anchors.horizontalCenter: parent.horizontalCenter
                  width: parent.width - (Style.marginM * 2)
                  color: subMouseArea.containsMouse ? Color.mHover : Color.transparent
                  radius: Style.radiusS
                  visible: !(modelData?.isSeparator ?? false)

                  RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Style.marginM
                    anchors.rightMargin: Style.marginM
                    spacing: Style.marginS

                    NText {
                      Layout.fillWidth: true
                      color: (modelData?.enabled ?? true) ? (subMouseArea.containsMouse ? Color.mOnHover : Color.mOnSurface) : Color.mOnSurfaceVariant
                      text: modelData?.text !== "" ? modelData?.text.replace(/[\n\r]+/g, ' ') : "..."
                      pointSize: Style.fontSizeS
                      verticalAlignment: Text.AlignVCenter
                      elide: Text.ElideRight
                    }

                    Image {
                      Layout.preferredWidth: Style.marginL
                      Layout.preferredHeight: Style.marginL
                      source: modelData?.icon ?? ""
                      visible: (modelData?.icon ?? "") !== ""
                      fillMode: Image.PreserveAspectFit
                    }

                    NIcon {
                      icon: modelData?.hasChildren ? "menu" : ""
                      pointSize: Style.fontSizeS
                      applyUiScale: false
                      verticalAlignment: Text.AlignVCenter
                      visible: modelData?.hasChildren ?? false
                      Layout.rightMargin: Style.marginL
                      color: (subMouseArea.containsMouse ? Color.mOnHover : Color.mOnSurface)
                    }
                  }

                  MouseArea {
                    id: subMouseArea
                    anchors.fill: parent
                    hoverEnabled: true
                    enabled: (modelData?.enabled ?? true) && !(modelData?.isSeparator ?? false)

                    onClicked: {
                      if (!modelData || modelData.isSeparator)
                        return

                      if (modelData.hasChildren) {
                        // Toggle nested submenu on click
                        if (content.activeSubMenu === modelData) {
                          // If already open, close it on second click
                          content.activeSubMenu = null
                          content.activeSubMenuEntry = null
                          return
                        }

                        // Open nested submenu in place
                        content.activeSubMenu = modelData
                        content.activeSubMenuEntry = null // No entry for nested submenus
                        content.inPlaceSubmenu = true
                      } else {
                        modelData.triggered()
                        root.close()
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }

    // Main menu and in-place submenu
    RowLayout {
      id: rowLayout
      anchors.fill: parent
      anchors.topMargin: Style.marginS
      spacing: 0

      // Submenu replacing main menu (in-place)
      Loader {
        id: inPlaceSubMenuLoader
        Layout.preferredWidth: (content.activeSubMenu && content.inPlaceSubmenu) ? root.menuWidth : 0
        Layout.fillHeight: true
        visible: content.activeSubMenu !== null && content.inPlaceSubmenu
        sourceComponent: subMenuComponent
      }

      // Main menu
      Flickable {
        id: mainFlickable
        Layout.preferredWidth: root.menuWidth
        Layout.fillHeight: true
        contentHeight: mainColumnLayout.implicitHeight
        interactive: false
        visible: !(content.activeSubMenu !== null && content.inPlaceSubmenu)

        ColumnLayout {
          id: mainColumnLayout
          width: mainFlickable.width
          spacing: 0

          Repeater {
            model: opener.children ? [...opener.children.values] : []

            delegate: Rectangle {
              id: entry
              required property var modelData

              Layout.preferredWidth: parent.width
              Layout.preferredHeight: {
                if (modelData?.isSeparator) {
                  return 8
                } else {
                  return 28
                }
              }

              color: Color.transparent

              NDivider {
                anchors.centerIn: parent
                width: parent.width - Style.marginL
                visible: modelData?.isSeparator ?? false
              }

              Rectangle {
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.topMargin: 0
                anchors.bottomMargin: 0
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width - (Style.marginM * 2)
                color: mouseArea.containsMouse ? Color.mHover : Color.transparent
                radius: Style.radiusS
                visible: !(modelData?.isSeparator ?? false)

                RowLayout {
                  anchors.fill: parent
                  anchors.leftMargin: Style.marginM
                  anchors.rightMargin: Style.marginM
                  spacing: Style.marginS

                  NText {
                    id: text
                    Layout.fillWidth: true
                    color: (modelData?.enabled ?? true) ? (mouseArea.containsMouse ? Color.mOnHover : Color.mOnSurface) : Color.mOnSurfaceVariant
                    text: modelData?.text !== "" ? modelData?.text.replace(/[\n\r]+/g, ' ') : "..."
                    pointSize: Style.fontSizeS
                    verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideRight
                  }

                  Image {
                    Layout.preferredWidth: Style.marginL
                    Layout.preferredHeight: Style.marginL
                    source: modelData?.icon ?? ""
                    visible: (modelData?.icon ?? "") !== ""
                    fillMode: Image.PreserveAspectFit
                  }

                  NIcon {
                    icon: modelData?.hasChildren ? "menu" : ""
                    pointSize: Style.fontSizeS
                    applyUiScale: false
                    verticalAlignment: Text.AlignVCenter
                    visible: modelData?.hasChildren ?? false
                    Layout.rightMargin: Style.marginS
                    color: (mouseArea.containsMouse ? Color.mOnHover : Color.mOnSurface)
                  }
                }

                MouseArea {
                  id: mouseArea
                  anchors.fill: parent
                  hoverEnabled: true
                  enabled: (modelData?.enabled ?? true) && !(modelData?.isSeparator ?? false)

                  onClicked: {
                    if (!modelData || modelData.isSeparator)
                      return

                    if (modelData.hasChildren) {
                      // Toggle submenu on click
                      if (content.activeSubMenuEntry === entry && content.inPlaceSubmenu) {
                        // If already open in-place, close it on second click
                        content.activeSubMenu = null
                        content.activeSubMenuEntry = null
                        return
                      }

                      // Close any other open submenu
                      if (content.activeSubMenuEntry && content.activeSubMenuEntry !== entry) {
                        content.activeSubMenu = null
                        content.activeSubMenuEntry = null
                      }

                      // Open submenu in place (replace main menu)
                      content.activeSubMenu = modelData
                      content.activeSubMenuEntry = entry
                      content.inPlaceSubmenu = true
                    } else {
                      modelData.triggered()
                      root.close()
                    }
                  }

                  onExited: {

                  }
                }
              }
            }
          }

          Rectangle {
            visible: root.trayItem !== null && root.widgetSection !== "" && root.widgetIndex >= 0
            Layout.preferredWidth: parent.width
            Layout.preferredHeight: visible ? 8 : 0
            color: Color.transparent

            NDivider {
              anchors.centerIn: parent
              width: parent.width - Style.marginL
              visible: parent.visible
            }
          }

          Rectangle {
            id: addToFavoriteEntry
            visible: root.trayItem !== null && root.widgetSection !== "" && root.widgetIndex >= 0
            Layout.preferredWidth: parent.width
            Layout.preferredHeight: visible ? 28 : 0
            color: Color.transparent

            readonly property bool isFavorite: {
              if (!root.trayItem || root.widgetSection === "" || root.widgetIndex < 0)
                return false
              const itemName = root.trayItem.tooltipTitle || root.trayItem.name || root.trayItem.id || ""
              if (!itemName)
                return false
              var widgets = Settings.data.bar.widgets[root.widgetSection]
              if (!widgets || root.widgetIndex >= widgets.length)
                return false
              var widgetSettings = widgets[root.widgetIndex]
              if (!widgetSettings || widgetSettings.id !== "Tray")
                return false
              var favorites = widgetSettings.favorites || []
              for (var i = 0; i < favorites.length; i++) {
                if (favorites[i] === itemName)
                  return true
              }
              return false
            }

            Rectangle {
              anchors.top: parent.top
              anchors.bottom: parent.bottom
              anchors.topMargin: 0
              anchors.bottomMargin: 0
              anchors.horizontalCenter: parent.horizontalCenter
              width: parent.width - (Style.marginM * 2)
              color: addToFavoriteMouseArea.containsMouse ? Qt.alpha(Color.mPrimary, 0.2) : Qt.alpha(Color.mPrimary, 0.08)
              radius: Style.radiusS
              border.color: Qt.alpha(Color.mPrimary, addToFavoriteMouseArea.containsMouse ? 0.4 : 0.2)
              border.width: Style.borderS

              RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Style.marginM
                anchors.rightMargin: Style.marginM
                spacing: Style.marginS

                NIcon {
                  icon: addToFavoriteEntry.isFavorite ? "unpin" : "pin"
                  pointSize: Style.fontSizeS
                  applyUiScale: false
                  verticalAlignment: Text.AlignVCenter
                  color: Color.mPrimary
                }

                NText {
                  Layout.fillWidth: true
                  color: Color.mPrimary
                  text: addToFavoriteEntry.isFavorite ? I18n.tr("settings.bar.tray.unpin-application") : I18n.tr("settings.bar.tray.pin-application")
                  pointSize: Style.fontSizeS
                  font.weight: Font.Medium
                  verticalAlignment: Text.AlignVCenter
                  elide: Text.ElideRight
                }
              }

              MouseArea {
                id: addToFavoriteMouseArea
                anchors.fill: parent
                hoverEnabled: true

                onClicked: {
                  if (addToFavoriteEntry.isFavorite) {
                    root.removeFromFavorites()
                  } else {
                    root.addToFavorites()
                  }
                  root.close()
                }
              }
            }
          }
        }
      }
    }

    Keys.onEscapePressed: root.close()
  }

  function addToFavorites() {
    if (!trayItem || widgetSection === "" || widgetIndex < 0) {
      Logger.w("TrayMenu", "Cannot add as favorite: missing tray item or widget info")
      return
    }
    const itemName = trayItem.tooltipTitle || trayItem.name || trayItem.id || ""
    if (!itemName) {
      Logger.w("TrayMenu", "Cannot add as favorite: tray item has no name")
      return
    }
    var widgets = Settings.data.bar.widgets[widgetSection]
    if (!widgets || widgetIndex >= widgets.length) {
      Logger.w("TrayMenu", "Cannot add as favorite: invalid widget index")
      return
    }
    var widgetSettings = widgets[widgetIndex]
    if (!widgetSettings || widgetSettings.id !== "Tray") {
      Logger.w("TrayMenu", "Cannot add as favorite: widget is not a Tray widget")
      return
    }
    var favorites = widgetSettings.favorites || []
    var newFavorites = favorites.slice()
    newFavorites.push(itemName)
    var newSettings = Object.assign({}, widgetSettings)
    newSettings.favorites = newFavorites
    widgets[widgetIndex] = newSettings
    Settings.data.bar.widgets[widgetSection] = widgets
    Settings.saveImmediate()
    if (root.screen) {
      const panel = PanelService.getPanel("trayDrawerPanel", root.screen)
      if (panel)
        panel.close()
    }
  }

  function removeFromFavorites() {
    if (!trayItem || widgetSection === "" || widgetIndex < 0) {
      Logger.w("TrayMenu", "Cannot remove from favorites: missing tray item or widget info")
      return
    }
    const itemName = trayItem.tooltipTitle || trayItem.name || trayItem.id || ""
    if (!itemName) {
      Logger.w("TrayMenu", "Cannot remove from favorites: tray item has no name")
      return
    }
    var widgets = Settings.data.bar.widgets[widgetSection]
    if (!widgets || widgetIndex >= widgets.length) {
      Logger.w("TrayMenu", "Cannot remove from favorites: invalid widget index")
      return
    }
    var widgetSettings = widgets[widgetIndex]
    if (!widgetSettings || widgetSettings.id !== "Tray") {
      Logger.w("TrayMenu", "Cannot remove from favorites: widget is not a Tray widget")
      return
    }
    var favorites = widgetSettings.favorites || []
    var newFavorites = []
    for (var i = 0; i < favorites.length; i++) {
      if (favorites[i] !== itemName) {
        newFavorites.push(favorites[i])
      }
    }
    var newSettings = Object.assign({}, widgetSettings)
    newSettings.favorites = newFavorites
    widgets[widgetIndex] = newSettings
    Settings.data.bar.widgets[widgetSection] = widgets
    Settings.saveImmediate()
  }
}
