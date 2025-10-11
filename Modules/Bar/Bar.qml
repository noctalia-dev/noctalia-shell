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

Variants {
  model: Quickshell.screens

  delegate: Loader {
    id: root

    required property ShellScreen modelData
    property real scaling: ScalingService.getScreenScale(modelData)

    // Auto-hide state and timings
    property bool autoHide: Settings.data.bar.autoHide
    property bool hidden: autoHide
    property bool barHovered: false
    property bool peekHovered: false
    // Controls PanelWindow visibility while auto-hide is enabled
    property bool barWindowVisible: !autoHide
    // Respect global animation toggle: no delays when animations are disabled
    readonly property int hideDelay: Settings.data.general.animationDisabled ? 0 : 500
    readonly property int showDelay: Settings.data.general.animationDisabled ? 0 : 120
    readonly property int hideAnimationDuration: Style.animationNormal
    readonly property int showAnimationDuration: Style.animationNormal

    // Ensure internal state updates when the setting toggles
    Connections {
      target: Settings.data.bar
      function onAutoHideChanged() {
        root.autoHide = Settings.data.bar.autoHide
        if (root.autoHide) {
          root.hidden = true
          root.barWindowVisible = false
        } else {
          root.hidden = false
          root.barWindowVisible = true
        }
      }
    }

    // Timers for reveal/hide
    Timer {
      id: showTimer
      interval: root.showDelay
      repeat: false
      onTriggered: {
        root.barWindowVisible = true
        root.hidden = false
      }
    }

    Timer {
      id: hideTimer
      interval: root.hideDelay
      repeat: false
      onTriggered: {
        if (root.autoHide && !root.peekHovered && !root.barHovered) {
          root.hidden = true
          unloadTimer.restart()
        }
      }
    }

    // After hide animation, make the window invisible so it doesn't intercept input
    Timer {
      id: unloadTimer
      interval: root.hideAnimationDuration
      repeat: false
      onTriggered: {
        if (root.autoHide && !root.peekHovered && !root.barHovered) {
          root.barWindowVisible = false
        }
      }
    }

    Connections {
      target: ScalingService
      function onScaleChanged(screenName, scale) {
        if ((modelData !== null) && (screenName === modelData.name)) {
          scaling = scale
        }
      }
    }

    active: BarService.isVisible && modelData && modelData.name ? (Settings.data.bar.monitors.includes(modelData.name) || (Settings.data.bar.monitors.length === 0)) : false

    sourceComponent: PanelWindow {
      screen: modelData || null

      WlrLayershell.namespace: "noctalia-bar"

      WlrLayershell.exclusionMode: root.autoHide ? ExclusionMode.Ignore : ExclusionMode.Auto

      // When auto-hide is enabled, actually toggle window visibility after animations
      visible: root.autoHide ? root.barWindowVisible : true

      implicitHeight: (Settings.data.bar.position === "left" || Settings.data.bar.position === "right") ? screen.height : Math.round(Style.barHeight * scaling)
      implicitWidth: (Settings.data.bar.position === "left" || Settings.data.bar.position === "right") ? Math.round(Style.barHeight * scaling) : screen.width
      color: Color.transparent

      anchors {
        top: Settings.data.bar.position === "top" || Settings.data.bar.position === "left" || Settings.data.bar.position === "right"
        bottom: Settings.data.bar.position === "bottom" || Settings.data.bar.position === "left" || Settings.data.bar.position === "right"
        left: Settings.data.bar.position === "left" || Settings.data.bar.position === "top" || Settings.data.bar.position === "bottom"
        right: Settings.data.bar.position === "right" || Settings.data.bar.position === "top" || Settings.data.bar.position === "bottom"
      }

      // Floating bar margins - only apply when floating is enabled
      // Also don't apply margin on the opposite side ot the bar orientation, ex: if bar is floating on top, margin is only applied on top, not bottom.
      margins {
        top: Settings.data.bar.floating && Settings.data.bar.position !== "bottom" ? Settings.data.bar.marginVertical * Style.marginXL * scaling : 0
        bottom: Settings.data.bar.floating && Settings.data.bar.position !== "top" ? Settings.data.bar.marginVertical * Style.marginXL * scaling : 0
        left: Settings.data.bar.floating && Settings.data.bar.position !== "right" ? Settings.data.bar.marginHorizontal * Style.marginXL * scaling : 0
        right: Settings.data.bar.floating && Settings.data.bar.position !== "left" ? Settings.data.bar.marginHorizontal * Style.marginXL * scaling : 0
      }

      Component.onCompleted: {
        if (modelData && modelData.name) {
          BarService.registerBar(modelData.name)
        }
      }

      // Wrapper for animations when hiding/showing
      Item {
        id: barContainer
        anchors.fill: parent
        clip: true

        opacity: root.hidden ? 0.0 : 1.0

        // Slide distance depends on bar orientation
        readonly property real offX: (function () {
            switch (Settings.data.bar.position) {
            case "left":
              return -barContainer.width
            case "right":
              return barContainer.width
            default:
              return 0
            }
          })()
        readonly property real offY: (function () {
            switch (Settings.data.bar.position) {
            case "top":
              return -barContainer.height
            case "bottom":
              return barContainer.height
            default:
              return 0
            }
          })()

        transform: Translate {
          id: slide
          x: root.hidden ? barContainer.offX : 0
          y: root.hidden ? barContainer.offY : 0
          Behavior on x {
            NumberAnimation {
              duration: root.hidden ? root.hideAnimationDuration : root.showAnimationDuration
              easing.type: Easing.InOutCubic
            }
          }
          Behavior on y {
            NumberAnimation {
              duration: root.hidden ? root.hideAnimationDuration : root.showAnimationDuration
              easing.type: Easing.InOutCubic
            }
          }
        }

        Behavior on opacity {
          NumberAnimation {
            duration: root.hidden ? root.hideAnimationDuration : root.showAnimationDuration
            easing.type: Easing.InOutQuad
          }
        }

        // Mark bar hovered without stealing events from child widgets
        HoverHandler {
          id: barHoverHandler
          onHoveredChanged: {
            root.barHovered = hovered
            if (!root.autoHide)
              return
            if (hovered) {
              showTimer.stop()
              hideTimer.stop()
              root.barWindowVisible = true
              root.hidden = false
            } else if (!root.peekHovered) {
              hideTimer.restart()
            }
          }
        }

        // Background fill with shadow
        Rectangle {
          id: bar

          anchors.fill: parent
          color: Qt.alpha(Color.mSurface, Settings.data.bar.backgroundOpacity)

          // Floating bar rounded corners
          radius: Settings.data.bar.floating ? Style.radiusL : 0
        }

        MouseArea {
          anchors.fill: parent
          acceptedButtons: Qt.RightButton
          hoverEnabled: false
          preventStealing: true
          onClicked: function (mouse) {
            if (mouse.button === Qt.RightButton) {
              // Important to pass the screen here so we get the right widget for the actual bar that was clicked.
              controlCenterPanel.toggle(BarService.lookupWidget("ControlCenter", screen.name))
              mouse.accepted = true
            }
          }
        }

        Loader {
          anchors.fill: parent
          sourceComponent: (Settings.data.bar.position === "left" || Settings.data.bar.position === "right") ? verticalBarComponent : horizontalBarComponent
        }

        // For vertical bars
        Component {
          id: verticalBarComponent
          Item {
            anchors.fill: parent

            // Top section (left widgets)
            ColumnLayout {
              anchors.horizontalCenter: parent.horizontalCenter
              anchors.top: parent.top
              anchors.topMargin: Style.marginM * root.scaling
              spacing: Style.marginS * root.scaling

              Repeater {
                model: Settings.data.bar.widgets.left
                delegate: BarWidgetLoader {
                  widgetId: (modelData.id !== undefined ? modelData.id : "")
                  widgetProps: {
                    "screen": root.modelData || null,
                    "scaling": ScalingService.getScreenScale(screen),
                    "widgetId": modelData.id,
                    "section": "left",
                    "sectionWidgetIndex": index,
                    "sectionWidgetsCount": Settings.data.bar.widgets.left.length
                  }
                  Layout.alignment: Qt.AlignHCenter
                }
              }
            }

            // Center section (center widgets)
            ColumnLayout {
              anchors.horizontalCenter: parent.horizontalCenter
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.marginS * root.scaling

              Repeater {
                model: Settings.data.bar.widgets.center
                delegate: BarWidgetLoader {
                  widgetId: (modelData.id !== undefined ? modelData.id : "")
                  widgetProps: {
                    "screen": root.modelData || null,
                    "scaling": ScalingService.getScreenScale(screen),
                    "widgetId": modelData.id,
                    "section": "center",
                    "sectionWidgetIndex": index,
                    "sectionWidgetsCount": Settings.data.bar.widgets.center.length
                  }
                  Layout.alignment: Qt.AlignHCenter
                }
              }
            }

            // Bottom section (right widgets)
            ColumnLayout {
              anchors.horizontalCenter: parent.horizontalCenter
              anchors.bottom: parent.bottom
              anchors.bottomMargin: Style.marginM * root.scaling
              spacing: Style.marginS * root.scaling

              Repeater {
                model: Settings.data.bar.widgets.right
                delegate: BarWidgetLoader {
                  widgetId: (modelData.id !== undefined ? modelData.id : "")
                  widgetProps: {
                    "screen": root.modelData || null,
                    "scaling": ScalingService.getScreenScale(screen),
                    "widgetId": modelData.id,
                    "section": "right",
                    "sectionWidgetIndex": index,
                    "sectionWidgetsCount": Settings.data.bar.widgets.right.length
                  }
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

            // Left Section
            RowLayout {
              id: leftSection
              objectName: "leftSection"
              anchors.left: parent.left
              anchors.leftMargin: Style.marginS * root.scaling
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.marginS * root.scaling

              Repeater {
                model: Settings.data.bar.widgets.left
                delegate: BarWidgetLoader {
                  widgetId: (modelData.id !== undefined ? modelData.id : "")
                  widgetProps: {
                    "screen": root.modelData || null,
                    "scaling": ScalingService.getScreenScale(screen),
                    "widgetId": modelData.id,
                    "section": "left",
                    "sectionWidgetIndex": index,
                    "sectionWidgetsCount": Settings.data.bar.widgets.left.length
                  }
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
              spacing: Style.marginS * root.scaling

              Repeater {
                model: Settings.data.bar.widgets.center
                delegate: BarWidgetLoader {
                  widgetId: (modelData.id !== undefined ? modelData.id : "")
                  widgetProps: {
                    "screen": root.modelData || null,
                    "scaling": ScalingService.getScreenScale(screen),
                    "widgetId": modelData.id,
                    "section": "center",
                    "sectionWidgetIndex": index,
                    "sectionWidgetsCount": Settings.data.bar.widgets.center.length
                  }
                  Layout.alignment: Qt.AlignVCenter
                }
              }
            }

            // Right Section
            RowLayout {
              id: rightSection
              objectName: "rightSection"
              anchors.right: parent.right
              anchors.rightMargin: Style.marginS * root.scaling
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.marginS * root.scaling

              Repeater {
                model: Settings.data.bar.widgets.right
                delegate: BarWidgetLoader {
                  widgetId: (modelData.id !== undefined ? modelData.id : "")
                  widgetProps: {
                    "screen": root.modelData || null,
                    "scaling": ScalingService.getScreenScale(screen),
                    "widgetId": modelData.id,
                    "section": "right",
                    "sectionWidgetIndex": index,
                    "sectionWidgetsCount": Settings.data.bar.widgets.right.length
                  }
                  Layout.alignment: Qt.AlignVCenter
                }
              }
            }
          }
        }
      }
    }

    // Peek window to reveal the bar when hovering at the screen edge
    Loader {
      id: peekLoader
      active: root.modelData && root.autoHide

      sourceComponent: PanelWindow {
        id: peekWindow
        screen: root.modelData || null
        color: Color.transparent
        focusable: false

        WlrLayershell.namespace: "noctalia-bar-peek"
        // Do not reserve space; keep as pure overlay so work area never changes
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.exclusionMode: ExclusionMode.Ignore
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        anchors {
          top: Settings.data.bar.position === "top"
          bottom: Settings.data.bar.position === "bottom"
          left: Settings.data.bar.position === "left"
          right: Settings.data.bar.position === "right"
        }

        // 1px reveal strip along the relevant edge
        implicitHeight: (Settings.data.bar.position === "left" || Settings.data.bar.position === "right") ? screen.height : 1
        implicitWidth: (Settings.data.bar.position === "top" || Settings.data.bar.position === "bottom") ? screen.width : 1

        MouseArea {
          anchors.fill: parent
          hoverEnabled: true
          onEntered: {
            root.peekHovered = true
            if (root.autoHide && root.hidden) {
              showTimer.restart()
            }
          }
          onExited: {
            root.peekHovered = false
            if (root.autoHide && !root.barHovered) {
              hideTimer.restart()
            }
          }
        }
      }
    }
  }
}
