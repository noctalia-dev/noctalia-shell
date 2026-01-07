import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.UPower
import Quickshell.Wayland
import qs.Commons
import qs.Modules.Bar.Extras
import qs.Modules.Notification
import qs.Services.UI
import qs.Widgets

// Bar Component
Item {
  id: root

  // This property will be set by MainScreen
  property ShellScreen screen: null

  // Filter widgets to only include those that exist in the registry
  // This prevents errors when plugins are missing or widgets are being cleaned up
  function filterValidWidgets(widgets: list<var>): list<var> {
    if (!widgets)
      return [];
    return widgets.filter(function (w) {
      return w && w.id && BarWidgetRegistry.hasWidget(w.id);
    });
  }

  // Expose bar region for click-through mask
  readonly property var barRegion: barContentLoader.item?.children[0] || null

  // Expose the actual bar Item for unified background system
  readonly property var barItem: barRegion

  // Bar positioning properties
  readonly property string barPosition: Settings.data.bar.position || "top"
  readonly property bool barIsVertical: barPosition === "left" || barPosition === "right"
  readonly property bool barFloating: Settings.data.bar.floating || false
  readonly property int barInset: Style.pixelAlignCenter(Style.barHeight, Style.capsuleHeight)

  // Fill the parent (the Loader)
  anchors.fill: parent

  // Register bar when screen becomes available
  onScreenChanged: {
    if (screen && screen.name) {
      Logger.d("Bar", "Bar screen set to:", screen.name);
      Logger.d("Bar", "  Position:", barPosition, "Floating:", barFloating);
      BarService.registerBar(screen.name);
    }
  }

  // Wait for screen to be set before loading bar content
  Loader {
    id: barContentLoader
    anchors.fill: parent
    active: {
      if (root.screen === null || root.screen === undefined) {
        return false;
      }

      var monitors = Settings.data.bar.monitors || [];
      var result = monitors.length === 0 || monitors.includes(root.screen.name);
      return result;
    }

    sourceComponent: Item {
      anchors.fill: parent

      // Bar container - Content
      Item {
        id: bar

        // Position and size the bar content based on orientation
        x: (root.barPosition === "right") ? (parent.width - Style.barHeight) : 0
        y: (root.barPosition === "bottom") ? (parent.height - Style.barHeight) : 0
        width: root.barIsVertical ? Style.barHeight : parent.width
        height: root.barIsVertical ? parent.height : Style.barHeight

        // Corner states for new unified background system
        // State -1: No radius (flat/square corner)
        // State 0: Normal (inner curve)
        // State 1: Horizontal inversion (outer curve on X-axis)
        // State 2: Vertical inversion (outer curve on Y-axis)
        readonly property int topLeftCornerState: {
          // Floating bar: always simple rounded corners
          if (barFloating)
            return 0;
          // Top bar: top corners against screen edge = no radius
          if (barPosition === "top")
            return -1;
          // Left bar: top-left against screen edge = no radius
          if (barPosition === "left")
            return -1;
          // Bottom/Right bar with outerCorners: inverted corner
          if (Settings.data.bar.outerCorners && (barPosition === "bottom" || barPosition === "right")) {
            return barIsVertical ? 1 : 2; // horizontal invert for vertical bars, vertical invert for horizontal
          }
          // No outerCorners = square
          return -1;
        }

        readonly property int topRightCornerState: {
          // Floating bar: always simple rounded corners
          if (barFloating)
            return 0;
          // Top bar: top corners against screen edge = no radius
          if (barPosition === "top")
            return -1;
          // Right bar: top-right against screen edge = no radius
          if (barPosition === "right")
            return -1;
          // Bottom/Left bar with outerCorners: inverted corner
          if (Settings.data.bar.outerCorners && (barPosition === "bottom" || barPosition === "left")) {
            return barIsVertical ? 1 : 2;
          }
          // No outerCorners = square
          return -1;
        }

        readonly property int bottomLeftCornerState: {
          // Floating bar: always simple rounded corners
          if (barFloating)
            return 0;
          // Bottom bar: bottom corners against screen edge = no radius
          if (barPosition === "bottom")
            return -1;
          // Left bar: bottom-left against screen edge = no radius
          if (barPosition === "left")
            return -1;
          // Top/Right bar with outerCorners: inverted corner
          if (Settings.data.bar.outerCorners && (barPosition === "top" || barPosition === "right")) {
            return barIsVertical ? 1 : 2;
          }
          // No outerCorners = square
          return -1;
        }

        readonly property int bottomRightCornerState: {
          // Floating bar: always simple rounded corners
          if (barFloating)
            return 0;
          // Bottom bar: bottom corners against screen edge = no radius
          if (barPosition === "bottom")
            return -1;
          // Right bar: bottom-right against screen edge = no radius
          if (barPosition === "right")
            return -1;
          // Top/Left bar with outerCorners: inverted corner
          if (Settings.data.bar.outerCorners && (barPosition === "top" || barPosition === "left")) {
            return barIsVertical ? 1 : 2;
          }
          // No outerCorners = square
          return -1;
        }

        MouseArea {
          anchors.fill: parent
          acceptedButtons: Qt.RightButton
          hoverEnabled: false
          preventStealing: true
          onClicked: function (mouse) {
            if (mouse.button === Qt.RightButton) {
              // Check if click is over any widget
              var widgets = BarService.getAllWidgetInstances(null, screen.name);
              for (var i = 0; i < widgets.length; i++) {
                var widget = widgets[i];
                if (!widget || !widget.visible || widget.widgetId === "Spacer") {
                  continue;
                }
                // Map click position to widget's coordinate space
                var localPos = mapToItem(widget, mouse.x, mouse.y);

                if (root.barIsVertical) {
                  if (localPos.y >= -Style.marginS && localPos.y <= widget.height + Style.marginS) {
                    return;
                  }
                } else {
                  if (localPos.x >= -Style.marginS && localPos.x <= widget.width + Style.marginS) {
                    return;
                  }
                }
              }
              // Click is on empty bar background - open control center
              var controlCenterPanel = PanelService.getPanel("controlCenterPanel", screen);
              if (Settings.data.controlCenter.position === "close_to_bar_button") {
                // Will attempt to open the panel next to the bar button if any.
                controlCenterPanel?.toggle(null, "ControlCenter");
              } else {
                controlCenterPanel?.toggle();
              }
              mouse.accepted = true;
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
        x: Style.pixelAlignCenter(parent.width, width)
        anchors.top: parent.top
        anchors.topMargin: root.barInset
        spacing: Style.marginS

        Repeater {
          model: root.filterValidWidgets(Settings.data.bar.widgets.left)
          delegate: BarWidgetLoader {
            required property var modelData
            required property int index

            widgetId: modelData.id || ""
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
        x: Style.pixelAlignCenter(parent.width, width)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.marginS

        Repeater {
          model: root.filterValidWidgets(Settings.data.bar.widgets.center)
          delegate: BarWidgetLoader {
            required property var modelData
            required property int index

            widgetId: modelData.id || ""
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
        x: Style.pixelAlignCenter(parent.width, width)
        anchors.bottom: parent.bottom
        anchors.bottomMargin: root.barInset
        spacing: Style.marginS

        Repeater {
          model: root.filterValidWidgets(Settings.data.bar.widgets.right)
          delegate: BarWidgetLoader {
            required property var modelData
            required property int index

            widgetId: modelData.id || ""
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
        anchors.leftMargin: root.barInset
        y: Style.pixelAlignCenter(parent.height, height)
        spacing: root.barInset

        Repeater {
          model: root.filterValidWidgets(Settings.data.bar.widgets.left)
          delegate: BarWidgetLoader {
            required property var modelData
            required property int index

            widgetId: modelData.id || ""
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
        y: Style.pixelAlignCenter(parent.height, height)
        spacing: root.barInset

        Repeater {
          model: root.filterValidWidgets(Settings.data.bar.widgets.center)
          delegate: BarWidgetLoader {
            required property var modelData
            required property int index

            widgetId: modelData.id || ""
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
        anchors.rightMargin: root.barInset
        y: Style.pixelAlignCenter(parent.height, height)
        spacing: root.barInset

        Repeater {
          model: root.filterValidWidgets(Settings.data.bar.widgets.right)
          delegate: BarWidgetLoader {
            required property var modelData
            required property int index

            widgetId: modelData.id || ""
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
