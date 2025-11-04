import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.UPower
import qs.Commons
import qs.Services
import qs.Widgets
import qs.Modules.Notification
import qs.Modules.Bar.Extras

// Bar Component
Item {
  id: root

  // This property will be set by NFullScreenWindow
  property ShellScreen screen: null

  // Expose bar region for click-through mask
  readonly property var barRegion: barContentLoader.item?.children[0] || null

  // Bar positioning properties
  readonly property string barPosition: Settings.data.bar.position || "top"
  readonly property bool barIsVertical: barPosition === "left" || barPosition === "right"
  readonly property bool barFloating: Settings.data.bar.floating || false
  readonly property real barMarginH: barFloating ? Settings.data.bar.marginHorizontal * Style.marginXL : 0
  readonly property real barMarginV: barFloating ? Settings.data.bar.marginVertical * Style.marginXL : 0

  // Attachment overlap to fix hairline gap with fractional scaling
  readonly property real attachmentOverlap: 1

  // Fill the parent (the Loader)
  anchors.fill: parent

  // Register bar when screen becomes available
  onScreenChanged: {
    if (screen && screen.name) {
      Logger.d("Bar", "Bar screen set to:", screen.name)
      Logger.d("Bar", "  Position:", barPosition, "Floating:", barFloating)
      Logger.d("Bar", "  Margins - H:", barMarginH, "V:", barMarginV)
      BarService.registerBar(screen.name)
    }
  }

  // Wait for screen to be set before loading bar content
  Loader {
    id: barContentLoader
    anchors.fill: parent
    active: {
      if (root.screen === null || root.screen === undefined) {
        return false
      }

      var monitors = Settings.data.bar.monitors || []
      var result = monitors.length === 0 || monitors.includes(root.screen.name)

      return result
    }

    sourceComponent: Item {
      anchors.fill: parent

      // Background fill
      NShapedRectangle {
        id: bar

        // Position and size the bar based on orientation and floating margins
        // Extend the bar by attachmentOverlap to eliminate hairline gap
        x: {
          var baseX = (root.barPosition === "right") ? (parent.width - Style.barHeight - root.barMarginH) : root.barMarginH
          if (root.barPosition === "right")
            return baseX - root.attachmentOverlap // Extend left towards panels
          return baseX
        }
        y: {
          var baseY = (root.barPosition === "bottom") ? (parent.height - Style.barHeight - root.barMarginV) : root.barMarginV
          if (root.barPosition === "bottom")
            return baseY - root.attachmentOverlap // Extend up towards panels
          return baseY
        }
        width: {
          var baseWidth = root.barIsVertical ? Style.barHeight : (parent.width - root.barMarginH * 2)
          if (!root.barIsVertical)
            return baseWidth // Horizontal bars extend via height, not width
          return baseWidth + root.attachmentOverlap + 1
        }
        height: {
          var baseHeight = root.barIsVertical ? (parent.height - root.barMarginV * 2) : Style.barHeight
          if (!root.barIsVertical)
            return baseHeight + root.attachmentOverlap
          return baseHeight // Vertical bars extend via width, not height
        }

        backgroundColor: Qt.alpha(Color.mSurface, Settings.data.bar.backgroundOpacity)

        // Floating bar rounded corners
        topLeftRadius: Settings.data.bar.floating || topLeftInverted ? Style.radiusL : 0
        topRightRadius: Settings.data.bar.floating || topRightInverted ? Style.radiusL : 0
        bottomLeftRadius: Settings.data.bar.floating || bottomLeftInverted ? Style.radiusL : 0
        bottomRightRadius: Settings.data.bar.floating || bottomRightInverted ? Style.radiusL : 0

        topLeftInverted: Settings.data.bar.outerCorners && (barPosition === "bottom" || barPosition === "right")
        topLeftInvertedDirection: barIsVertical ? "horizontal" : "vertical"
        topRightInverted: Settings.data.bar.outerCorners && (barPosition === "bottom" || barPosition === "left")
        topRightInvertedDirection: barIsVertical ? "horizontal" : "vertical"

        bottomLeftInverted: Settings.data.bar.outerCorners && (barPosition === "top" || barPosition === "right")
        bottomLeftInvertedDirection: barIsVertical ? "horizontal" : "vertical"
        bottomRightInverted: Settings.data.bar.outerCorners && (barPosition === "top" || barPosition === "left")
        bottomRightInvertedDirection: barIsVertical ? "horizontal" : "vertical"

        // No border on the bar
        borderWidth: 0

        MouseArea {
          anchors.fill: parent
          acceptedButtons: Qt.RightButton
          hoverEnabled: false
          preventStealing: true
          onClicked: function (mouse) {
            if (mouse.button === Qt.RightButton) {
              // Look up for any ControlCenter button on this bar
              var widget = BarService.lookupWidget("ControlCenter", root.screen.name)

              // Open the panel near the button if any
              PanelService.getPanel("controlCenterPanel", root.screen)?.toggle(widget)
              mouse.accepted = true
            }
          }
        }

        Loader {
          anchors.fill: parent
          sourceComponent: (Settings.data.bar.position === "left" || Settings.data.bar.position === "right") ? verticalBarComponent : horizontalBarComponent
        }
      }
    }
  }

  // For vertical bars
  Component {
    id: verticalBarComponent
    Item {
      anchors.fill: parent
      clip: true

      // Top section (left widgets)
      ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: Style.marginM
        spacing: Style.marginS

        Repeater {
          model: Settings.data.bar.widgets.left
          delegate: BarWidgetLoader {
            required property var modelData
            required property int index

            widgetId: modelData.id || ""
            barDensity: Settings.data.bar.density
            widgetScreen: root.screen
            widgetProps: ({
                            "widgetId": modelData.id,
                            "section": "left",
                            "sectionWidgetIndex": index,
                            "sectionWidgetsCount": Settings.data.bar.widgets.left.length
                          })
            Layout.alignment: Qt.AlignHCenter
          }
        }
      }

      // Center section (center widgets)
      ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.marginS

        Repeater {
          model: Settings.data.bar.widgets.center
          delegate: BarWidgetLoader {
            required property var modelData
            required property int index

            widgetId: modelData.id || ""
            barDensity: Settings.data.bar.density
            widgetScreen: root.screen
            widgetProps: ({
                            "widgetId": modelData.id,
                            "section": "center",
                            "sectionWidgetIndex": index,
                            "sectionWidgetsCount": Settings.data.bar.widgets.center.length
                          })
            Layout.alignment: Qt.AlignHCenter
          }
        }
      }

      // Bottom section (right widgets)
      ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Style.marginM
        spacing: Style.marginS

        Repeater {
          model: Settings.data.bar.widgets.right
          delegate: BarWidgetLoader {
            required property var modelData
            required property int index

            widgetId: modelData.id || ""
            barDensity: Settings.data.bar.density
            widgetScreen: root.screen
            widgetProps: ({
                            "widgetId": modelData.id,
                            "section": "right",
                            "sectionWidgetIndex": index,
                            "sectionWidgetsCount": Settings.data.bar.widgets.right.length
                          })
            Layout.alignment: Qt.AlignHCenter
          }
        }
      }
    }
  }

  // For horizontal bars
  Component {
    id: horizontalBarComponent
    Item {
      anchors.fill: parent
      clip: true

      // Left Section
      RowLayout {
        id: leftSection
        objectName: "leftSection"
        anchors.left: parent.left
        anchors.leftMargin: Style.marginS
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.marginS

        Repeater {
          model: Settings.data.bar.widgets.left
          delegate: BarWidgetLoader {
            required property var modelData
            required property int index

            widgetId: modelData.id || ""
            barDensity: Settings.data.bar.density
            widgetScreen: root.screen
            widgetProps: ({
                            "widgetId": modelData.id,
                            "section": "left",
                            "sectionWidgetIndex": index,
                            "sectionWidgetsCount": Settings.data.bar.widgets.left.length
                          })
            Layout.alignment: Qt.AlignVCenter
          }
        }
      }

      // Center Section
      RowLayout {
        id: centerSection
        objectName: "centerSection"
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.marginS

        Repeater {
          model: Settings.data.bar.widgets.center
          delegate: BarWidgetLoader {
            required property var modelData
            required property int index

            widgetId: modelData.id || ""
            barDensity: Settings.data.bar.density
            widgetScreen: root.screen
            widgetProps: ({
                            "widgetId": modelData.id,
                            "section": "center",
                            "sectionWidgetIndex": index,
                            "sectionWidgetsCount": Settings.data.bar.widgets.center.length
                          })
            Layout.alignment: Qt.AlignVCenter
          }
        }
      }

      // Right Section
      RowLayout {
        id: rightSection
        objectName: "rightSection"
        anchors.right: parent.right
        anchors.rightMargin: Style.marginS
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.marginS

        Repeater {
          model: Settings.data.bar.widgets.right
          delegate: BarWidgetLoader {
            required property var modelData
            required property int index

            widgetId: modelData.id || ""
            barDensity: Settings.data.bar.density
            widgetScreen: root.screen
            widgetProps: ({
                            "widgetId": modelData.id,
                            "section": "right",
                            "sectionWidgetIndex": index,
                            "sectionWidgetsCount": Settings.data.bar.widgets.right.length
                          })
            Layout.alignment: Qt.AlignVCenter
          }
        }
      }
    }
  }
}
