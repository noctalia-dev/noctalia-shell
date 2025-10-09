import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Modules.ControlCenter.Cards
import qs.Commons
import qs.Services
import qs.Widgets

NPanel {
  id: root

  preferredWidth: 480
  preferredHeight: 580
  panelKeyboardFocus: true

  // Positioning
  readonly property string controlCenterPosition: Settings.data.controlCenter.position
  panelAnchorHorizontalCenter: controlCenterPosition !== "close_to_bar_button" && controlCenterPosition.endsWith("_center")
  panelAnchorVerticalCenter: false
  panelAnchorLeft: controlCenterPosition !== "close_to_bar_button" && controlCenterPosition.endsWith("_left")
  panelAnchorRight: controlCenterPosition !== "close_to_bar_button" && controlCenterPosition.endsWith("_right")
  panelAnchorBottom: controlCenterPosition !== "close_to_bar_button" && controlCenterPosition.startsWith("bottom_")
  panelAnchorTop: controlCenterPosition !== "close_to_bar_button" && controlCenterPosition.startsWith("top_")

  panelContent: Item {
    id: content

    property real cardSpacing: Style.marginL * scaling

    // Layout content
    ColumnLayout {
      id: layout
      anchors.fill: parent
      anchors.margins: content.cardSpacing
      spacing: content.cardSpacing

      // Top Card: profile + utilities
      TopCard {
        Layout.fillWidth: true
        Layout.preferredHeight: Math.max(124 * scaling)
      }

      // Weather
      WeatherCard {
        Layout.fillWidth: true
        Layout.preferredHeight: Math.max(196 * scaling)
      }

      // Media + stats column
      RowLayout {
        Layout.fillWidth: true
        Layout.preferredHeight: Math.max(196 * scaling)
        spacing: content.cardSpacing

        // Media card
        MediaCard {
          Layout.preferredWidth: Math.max(270 * scaling)
          Layout.fillHeight: true
        }

        // System monitors combined in one card
        SystemMonitorCard {
          Layout.preferredWidth: Math.max(160 * scaling)
          Layout.preferredHeight: Math.max(196 * scaling)
        }
      }
    }
  }
}
