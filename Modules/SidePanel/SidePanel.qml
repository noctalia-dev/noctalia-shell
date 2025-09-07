import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Modules.SidePanel.Cards
import qs.Commons
import qs.Services
import qs.Widgets

NPanel {
  id: root

  panelWidth: 460 * scaling
  panelHeight: 712 * scaling

  panelContent: Item {
    id: content

    property real cardSpacing: Style.marginL * scaling

    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.margins: content.cardSpacing
    implicitHeight: layout.implicitHeight

    // Layout content (not vertically anchored so implicitHeight is valid)
    ColumnLayout {
      id: layout
      // Use the same spacing value horizontally and vertically
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      spacing: content.cardSpacing

      // Cards (consistent inter-card spacing via ColumnLayout spacing)
      ProfileCard {// Layout.topMargin: 0
        // Layout.bottomMargin: 0
      }
      WeatherCard {// Layout.topMargin: 0
        // Layout.bottomMargin: 0
      }

      // Middle section: media + stats column
      RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: 0
        Layout.bottomMargin: 0
        spacing: content.cardSpacing

        // Media card
        MediaCard {
          id: mediaCard
          Layout.fillWidth: true
          implicitHeight: statsCard.implicitHeight
        }

        // System monitors combined in one card
        SystemMonitorCard {
          id: statsCard
        }
      }

      // Bottom actions (two grouped rows of round buttons)
      RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: 0
        Layout.bottomMargin: 0
        spacing: content.cardSpacing

        // Power Profiles switcher
        PowerProfilesCard {
          spacing: content.cardSpacing
        }

        // Utilities buttons
        UtilitiesCard {
          spacing: content.cardSpacing
        }
      }
    }
  }
}
