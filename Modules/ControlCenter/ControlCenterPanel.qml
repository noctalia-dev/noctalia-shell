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

  preferredWidth: Math.round(460 * Style.uiScaleRatio)
  preferredHeight: {
    var height = 0
    var count = 0
    for (var i = 0; i < Settings.data.controlCenter.cards.length; i++) {
      const card = Settings.data.controlCenter.cards[i]
      if (!card.enabled)
        continue

      const contributes = (card.id !== "weather-card" || Settings.data.location.weatherEnabled)
      if (!contributes)
        continue

      count++
      switch (card.id) {
      case "profile-card":
        height += profileHeight
        break
      case "shortcuts-card":
        height += shortcutsHeight
        break
      case "audio-card":
        height += audioHeight
        break
      case "weather-card":
        height += weatherHeight
        break
      case "media-sysmon-card":
        height += mediaSysMonHeight
        break
      default:
        break
      }
    }
    return height + (count + 1) * Style.marginL
  }

  // Positioning
  readonly property string controlCenterPosition: Settings.data.controlCenter.position

  // Check if there's a bar on this screen
  readonly property bool hasBarOnScreen: {
    var monitors = Settings.data.bar.monitors || []
    return monitors.length === 0 || monitors.includes(screen?.name)
  }

  // When position is "close_to_bar_button" but there's no bar, fall back to center
  readonly property bool shouldCenter: controlCenterPosition === "close_to_bar_button" && !hasBarOnScreen

  panelAnchorHorizontalCenter: shouldCenter || (controlCenterPosition !== "close_to_bar_button" && (controlCenterPosition.endsWith("_center") || controlCenterPosition === "center"))
  panelAnchorVerticalCenter: shouldCenter || controlCenterPosition === "center"
  panelAnchorLeft: !shouldCenter && controlCenterPosition !== "close_to_bar_button" && controlCenterPosition.endsWith("_left")
  panelAnchorRight: !shouldCenter && controlCenterPosition !== "close_to_bar_button" && controlCenterPosition.endsWith("_right")
  panelAnchorBottom: !shouldCenter && controlCenterPosition !== "close_to_bar_button" && controlCenterPosition.startsWith("bottom_")
  panelAnchorTop: !shouldCenter && controlCenterPosition !== "close_to_bar_button" && controlCenterPosition.startsWith("top_")

  readonly property int profileHeight: Math.round(64 * Style.uiScaleRatio)
  readonly property int shortcutsHeight: Math.round(52 * Style.uiScaleRatio)
  readonly property int audioHeight: Math.round(60 * Style.uiScaleRatio)
  readonly property int weatherHeight: Math.round(190 * Style.uiScaleRatio)
  readonly property int mediaSysMonHeight: Math.round(260 * Style.uiScaleRatio)

  onOpened: {
    MediaService.autoSwitchingPaused = true
  }

  onClosed: {
    MediaService.autoSwitchingPaused = false
  }

  panelContent: Item {
    id: content

    ColumnLayout {
      id: layout
      x: Style.marginL
      y: Style.marginL
      width: parent.width - (Style.marginL * 2)
      spacing: Style.marginL

      Repeater {
        model: Settings.data.controlCenter.cards
        Loader {
          active: modelData.enabled && (modelData.id !== "weather-card" || Settings.data.location.weatherEnabled)
          visible: active
          Layout.fillWidth: true
          Layout.preferredHeight: {
            switch (modelData.id) {
            case "profile-card":
              return profileHeight
            case "shortcuts-card":
              return shortcutsHeight
            case "audio-card":
              return audioHeight
            case "weather-card":
              return weatherHeight
            case "media-sysmon-card":
              return mediaSysMonHeight
            default:
              return 0
            }
          }
          sourceComponent: {
            switch (modelData.id) {
            case "profile-card":
              return profileCard
            case "shortcuts-card":
              return shortcutsCard
            case "audio-card":
              return audioCard
            case "weather-card":
              return weatherCard
            case "media-sysmon-card":
              return mediaSysMonCard
            }
          }
        }
      }
    }

    Component {
      id: profileCard
      ProfileCard {}
    }

    Component {
      id: shortcutsCard
      ShortcutsCard {}
    }

    Component {
      id: audioCard
      AudioCard {}
    }

    Component {
      id: weatherCard
      WeatherCard {}
    }

    Component {
      id: mediaSysMonCard
      RowLayout {
        spacing: Style.marginL

        // Media card
        MediaCard {
          Layout.fillWidth: true
          Layout.fillHeight: true
        }

        // System monitors combined in one card
        SystemMonitorCard {
          Layout.preferredWidth: Math.round(Style.baseWidgetSize * 2.625)
          Layout.fillHeight: true
        }
      }
    }
  }
}
