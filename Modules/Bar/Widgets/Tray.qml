import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Services.SystemTray
import Quickshell.Widgets
import qs.Commons
import qs.Modules.Bar.Extras
import qs.Services
import qs.Widgets

Rectangle {
  id: root

  property ShellScreen screen
  property real scaling: ScalingService.scale(screen)
  readonly property real itemSize: 24 * scaling

  visible: SystemTray.items.values.length > 0
  implicitWidth: tray.width + Style.marginM * scaling * 2
  implicitHeight: Math.round(Style.capsuleHeight * scaling)
  radius: Math.round(Style.radiusM * scaling)
  color: Color.mSurfaceVariant

  Layout.alignment: Qt.AlignVCenter

  Row {
    id: tray

    anchors.verticalCenter: parent.verticalCenter
    anchors.horizontalCenter: parent.horizontalCenter
    spacing: Style.marginS * scaling

    Repeater {
      id: repeater
      model: SystemTray.items
      delegate: Item {
        width: itemSize
        height: itemSize
        visible: modelData

        IconImage {
          id: trayIcon
          anchors.centerIn: parent
          width: Style.marginL * scaling
          height: Style.marginL * scaling
          smooth: false
          asynchronous: true
          backer.fillMode: Image.PreserveAspectFit
          source: {
            let icon = modelData?.icon || ""
            if (!icon) {
              return ""
            }

            // Process icon path
            if (icon.includes("?path=")) {
              // Seems qmlfmt does not support the following ES6 syntax: const[name, path] = icon.split
              const chunks = icon.split("?path=")
              const name = chunks[0]
              const path = chunks[1]
              const fileName = name.substring(name.lastIndexOf("/") + 1)
              return `file://${path}/${fileName}`
            }
            return icon
          }
          opacity: status === Image.Ready ? 1 : 0
        }

        MouseArea {
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
          onClicked: mouse => {
                       if (!modelData) {
                         return
                       }

                       if (mouse.button === Qt.LeftButton) {
                         // Close any open menu first
                         trayPanel.close()

                         if (!modelData.onlyMenu) {
                           modelData.activate()
                         }
                       } else if (mouse.button === Qt.MiddleButton) {
                         // Close any open menu first
                         trayPanel.close()

                         modelData.secondaryActivate && modelData.secondaryActivate()
                       } else if (mouse.button === Qt.RightButton) {
                         trayTooltip.hide()

                         // Close the menu if it was visible
                         if (trayPanel && trayPanel.visible) {
                           trayPanel.close()
                           return
                         }

                         if (modelData.hasMenu && modelData.menu && trayMenu.item) {
                           trayPanel.open()

                           // Anchor the menu to the tray icon item (parent) and position it below the icon
                           const menuX = (width / 2) - (trayMenu.item.width / 2)
                           const menuY = (Style.barHeight * scaling)
                           trayMenu.item.menu = modelData.menu
                           trayMenu.item.showAt(parent, menuX, menuY)
                         } else {
                           Logger.log("Tray", "No menu available for", modelData.id, "or trayMenu not set")
                         }
                       }
                     }
          onEntered: trayTooltip.show()
          onExited: trayTooltip.hide()
        }

        NTooltip {
          id: trayTooltip
          target: trayIcon
          text: modelData.tooltipTitle || modelData.name || modelData.id || "Tray Item"
          positionAbove: Settings.data.bar.position === "bottom"
        }
      }
    }
  }

  PanelWindow {
    id: trayPanel
    anchors.top: true
    anchors.left: true
    anchors.right: true
    anchors.bottom: true
    visible: false
    color: Color.transparent
    screen: screen

    function open() {
      visible = true

      PanelService.willOpenPanel(trayPanel)
    }

    function close() {
      visible = false
      trayMenu.item.hideMenu()
    }

    // Clicking outside of the rectangle to close
    MouseArea {
      anchors.fill: parent
      onClicked: trayPanel.close()
    }

    Loader {
      id: trayMenu
      source: "../Extras/TrayMenu.qml"
    }
  }
}
