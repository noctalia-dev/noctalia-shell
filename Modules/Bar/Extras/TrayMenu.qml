import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Services.UI
import qs.Widgets

PopupWindow {
  id: root

  property ShellScreen screen

  property var trayItem: null
  property var anchorItem: null
  property real anchorX
  property real anchorY
  property bool isSubMenu: false
  property bool isHovered: rootMouseArea.containsMouse
  property string widgetSection: ""
  property int widgetIndex: -1

  // Track if we should try to load menu items
  property int menuLoadTrigger: 0
  property var menuItems: []

  // Menu can be set directly (for submenus) or derived from trayItem
  property var menu: null

  // Compute if current tray item is pinned
  readonly property bool isPinned: {
    if (!trayItem || widgetSection === "" || widgetIndex < 0)
      return false
    var widgets = Settings.data.bar.widgets[widgetSection]
    if (!widgets || widgetIndex >= widgets.length)
      return false
    var widgetSettings = widgets[widgetIndex]
    if (!widgetSettings || widgetSettings.id !== "Tray")
      return false
    var pinnedList = widgetSettings.pinned || []
    const itemName = trayItem.tooltipTitle || trayItem.name || trayItem.id || ""
    for (var i = 0; i < pinnedList.length; i++) {
      if (pinnedList[i] === itemName)
        return true
    }
    return false
  }

  readonly property int menuWidth: 220

  implicitWidth: menuWidth

  // Use the content height of the Flickable for implicit height
  implicitHeight: Math.min(screen?.height * 0.9, flickable.contentHeight + (Style.marginS * 2))
  visible: false
  color: Color.transparent
  anchor.item: anchorItem
  anchor.rect.x: anchorX
  anchor.rect.y: {
    if (isSubMenu) {
      const offsetY = Settings.data.bar.position === "bottom" ? -10 : 10
      return anchorY + offsetY
    }
    return anchorY + Settings.data.bar.position === "bottom" ? -implicitHeight : Style.barHeight
  }

  // Only try to load menu items when explicitly requested
  onMenuLoadTriggerChanged: {
    loadMenuItemsSafely()
  }

  function loadMenuItemsSafely() {
    // Use a timer to defer the access
    loadTimer.start()
  }

  Timer {
    id: loadTimer
    interval: 50
    repeat: false
    onTriggered: {
      try {
        if (opener && opener.children && opener.children.values) {
          const values = opener.children.values
          if (values && values.length > 0) {
            root.menuItems = [...values]
            Logger.i("TrayMenu", "Loaded " + root.menuItems.length + " menu items")
          } else {
            Logger.warn("TrayMenu", "opener.children.values is empty")
          }
        } else {
          Logger.warn("TrayMenu", "opener.children not available")
        }
      } catch (e) {
        Logger.w("TrayMenu", "Failed to load menu items: " + e)
      }
    }
  }

  function showAt(item, x, y) {
    if (!item) {
      Logger.warn("TrayMenu", "anchorItem is undefined, won't show menu.")
      return
    }

    if (!isSubMenu && trayItem && trayItem.menu) {
      menu = trayItem.menu
    }

    anchorItem = item
    anchorX = x
    anchorY = y

    // Reset menu items to force reload with new menu
    menuItems = []

    // Increment trigger to reload menu (always triggers even if already loaded)
    menuLoadTrigger++

    visible = true
    forceActiveFocus()

    // Force update after showing.
    Qt.callLater(() => {
                   root.anchor.updateAnchor()
                 })
  }

  function hideMenu() {
    visible = false

    // Clean up all submenus recursively
    for (var i = 0; i < columnLayout.children.length; i++) {
      const child = columnLayout.children[i]
      if (child?.subMenu) {
        child.subMenu.hideMenu()
        child.subMenu.destroy()
        child.subMenu = null
      }
    }
  }

  // Full-sized, transparent MouseArea to track the mouse.
  MouseArea {
    id: rootMouseArea
    anchors.fill: parent
    hoverEnabled: true
  }

  QsMenuOpener {
    id: opener
    menu: root.menu
  }

  Rectangle {
    anchors.fill: parent
    color: Color.mSurface
    border.color: Color.mOutline
    border.width: Math.max(1, Style.borderS)
    radius: Style.radiusM

    // Fade-in animation
    opacity: root.visible ? 1.0 : 0.0

    Behavior on opacity {
      NumberAnimation {
        duration: Style.animationNormal
        easing.type: Easing.OutQuad
      }
    }
  }

  Flickable {
    id: flickable
    anchors.fill: parent
    anchors.margins: Style.marginS
    contentHeight: columnLayout.implicitHeight
    interactive: true

    // Fade-in animation
    opacity: root.visible ? 1.0 : 0.0

    Behavior on opacity {
      NumberAnimation {
        duration: Style.animationNormal
        easing.type: Easing.OutQuad
      }
    }

    // Use a ColumnLayout to handle menu item arrangement
    ColumnLayout {
      id: columnLayout
      width: flickable.width
      spacing: 0

      Repeater {
        model: root.menuItems

        delegate: Rectangle {
          id: entry
          required property var modelData

          Layout.preferredWidth: parent.width
          Layout.preferredHeight: {
            if (modelData?.isSeparator) {
              return 8
            } else {
              // Calculate based on text content
              const textHeight = text.contentHeight || (Style.fontSizeS * 1.2)
              return Math.max(28, textHeight + (Style.marginS * 2))
            }
          }

          color: Color.transparent
          property var subMenu: null

          NDivider {
            anchors.centerIn: parent
            width: parent.width - (Style.marginM * 2)
            visible: modelData?.isSeparator ?? false
          }

          Rectangle {
            id: innerRect
            anchors.fill: parent
            color: mouseArea.containsMouse ? Color.mTertiary : Color.transparent
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
                color: (modelData?.enabled ?? true) ? (mouseArea.containsMouse ? Color.mOnTertiary : Color.mOnSurface) : Color.mOnSurfaceVariant
                text: modelData?.text !== "" ? modelData?.text.replace(/[\n\r]+/g, ' ') : "..."
                pointSize: Style.fontSizeS
                verticalAlignment: Text.AlignVCenter
                wrapMode: Text.WordWrap
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
                color: (mouseArea.containsMouse ? Color.mOnTertiary : Color.mOnSurface)
              }
            }

            MouseArea {
              id: mouseArea
              anchors.fill: parent
              hoverEnabled: true
              enabled: (modelData?.enabled ?? true) && !(modelData?.isSeparator ?? false) && root.visible
              acceptedButtons: Qt.LeftButton | Qt.RightButton

              onClicked: mouse => {
                           if (modelData && !modelData.isSeparator) {
                             if (modelData.hasChildren) {
                               // Click on items with children toggles submenu
                               if (entry.subMenu) {
                                 // Close existing submenu
                                 entry.subMenu.hideMenu()
                                 entry.subMenu.destroy()
                                 entry.subMenu = null
                               } else {
                                 // Close any other open submenus first
                                 for (var i = 0; i < columnLayout.children.length; i++) {
                                   const sibling = columnLayout.children[i]
                                   if (sibling !== entry && sibling.subMenu) {
                                     sibling.subMenu.hideMenu()
                                     sibling.subMenu.destroy()
                                     sibling.subMenu = null
                                   }
                                 }

                                 // Determine submenu opening direction
                                 let openLeft = false
                                 const barPosition = Settings.data.bar.position
                                 const globalPos = entry.mapToItem(null, 0, 0)

                                 if (barPosition === "right") {
                                   openLeft = true
                                 } else if (barPosition === "left") {
                                   openLeft = false
                                 } else {
                                   openLeft = (root.widgetSection === "right")
                                 }

                                 // Open new submenu
                                 entry.subMenu = Qt.createComponent("TrayMenu.qml").createObject(root, {
                                                                                                   "menu": modelData,
                                                                                                   "isSubMenu": true,
                                                                                                   "screen": root.screen
                                                                                                 })

                                 if (entry.subMenu) {
                                   const overlap = 60
                                   entry.subMenu.anchorItem = entry
                                   entry.subMenu.anchorX = openLeft ? -overlap : overlap
                                   entry.subMenu.anchorY = 0
                                   entry.subMenu.menuLoadTrigger++
                                   entry.subMenu.visible = true
                                   // Force anchor update with new position
                                   Qt.callLater(() => {
                                                  entry.subMenu.anchor.updateAnchor()
                                                })
                                 }
                               }
                             } else {
                               // Click on regular items triggers them
                               modelData.triggered()
                               root.hideMenu()

                               // Close the drawer if it's open
                               if (root.screen) {
                                 const panel = PanelService.getPanel("trayDrawerPanel", root.screen)
                                 if (panel && panel.visible) {
                                   panel.close()
                                 }
                               }
                             }
                           }
                         }
            }
          }

          Component.onDestruction: {
            if (subMenu) {
              subMenu.destroy()
              subMenu = null
            }
          }
        }
      }

      // PIN / UNPIN
      Rectangle {
        Layout.preferredWidth: parent.width
        Layout.preferredHeight: 28
        color: pinUnpinMouseArea.containsMouse ? Qt.alpha(Color.mPrimary, 0.2) : Qt.alpha(Color.mPrimary, 0.08)
        radius: Style.radiusS
        border.color: Qt.alpha(Color.mPrimary, pinUnpinMouseArea.containsMouse ? 0.4 : 0.2)
        border.width: Style.borderS

        RowLayout {
          anchors.fill: parent
          anchors.leftMargin: Style.marginM
          anchors.rightMargin: Style.marginM
          spacing: Style.marginS

          NIcon {
            icon: root.isPinned ? "unpin" : "pin"
            pointSize: Style.fontSizeS
            applyUiScale: false
            verticalAlignment: Text.AlignVCenter
            color: Color.mPrimary
          }

          NText {
            Layout.fillWidth: true
            color: Color.mPrimary
            text: root.isPinned ? I18n.tr("settings.bar.tray.unpin-application") : I18n.tr("settings.bar.tray.pin-application")
            pointSize: Style.fontSizeS
            font.weight: Font.Medium
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
          }
        }

        MouseArea {
          id: pinUnpinMouseArea
          anchors.fill: parent
          hoverEnabled: true

          onClicked: {
            if (root.isPinned) {
              root.removeFromPinned()
            } else {
              root.addToPinned()
            }
          }
        }
      }
    }
  }

  function addToPinned() {
    if (!trayItem || widgetSection === "" || widgetIndex < 0) {
      Logger.w("TrayMenu", "Cannot pin: missing tray item or widget info")
      return
    }
    const itemName = trayItem.tooltipTitle || trayItem.name || trayItem.id || ""
    if (!itemName) {
      Logger.w("TrayMenu", "Cannot pin: tray item has no name")
      return
    }
    var widgets = Settings.data.bar.widgets[widgetSection]
    if (!widgets || widgetIndex >= widgets.length) {
      Logger.w("TrayMenu", "Cannot pin: invalid widget index")
      return
    }
    var widgetSettings = widgets[widgetIndex]
    if (!widgetSettings || widgetSettings.id !== "Tray") {
      Logger.w("TrayMenu", "Cannot pin: widget is not a Tray widget")
      return
    }
    var pinnedList = widgetSettings.pinned || []
    var newPinned = pinnedList.slice()
    newPinned.push(itemName)
    var newSettings = Object.assign({}, widgetSettings)
    newSettings.pinned = newPinned
    widgets[widgetIndex] = newSettings
    Settings.data.bar.widgets[widgetSection] = widgets
    Settings.saveImmediate()

    // Close drawer when pinning (drawer needs to resize)
    if (screen) {
      const panel = PanelService.getPanel("trayDrawerPanel", screen)
      if (panel)
        panel.close()
    }
  }

  function removeFromPinned() {
    if (!trayItem || widgetSection === "" || widgetIndex < 0) {
      Logger.w("TrayMenu", "Cannot unpin: missing tray item or widget info")
      return
    }
    const itemName = trayItem.tooltipTitle || trayItem.name || trayItem.id || ""
    if (!itemName) {
      Logger.w("TrayMenu", "Cannot unpin: tray item has no name")
      return
    }
    var widgets = Settings.data.bar.widgets[widgetSection]
    if (!widgets || widgetIndex >= widgets.length) {
      Logger.w("TrayMenu", "Cannot unpin: invalid widget index")
      return
    }
    var widgetSettings = widgets[widgetIndex]
    if (!widgetSettings || widgetSettings.id !== "Tray") {
      Logger.w("TrayMenu", "Cannot unpin: widget is not a Tray widget")
      return
    }
    var pinnedList = widgetSettings.pinned || []
    var newPinned = []
    for (var i = 0; i < pinnedList.length; i++) {
      if (pinnedList[i] !== itemName) {
        newPinned.push(pinnedList[i])
      }
    }
    var newSettings = Object.assign({}, widgetSettings)
    newSettings.pinned = newPinned
    widgets[widgetIndex] = newSettings
    Settings.data.bar.widgets[widgetSection] = widgets
    Settings.saveImmediate()
  }
}
