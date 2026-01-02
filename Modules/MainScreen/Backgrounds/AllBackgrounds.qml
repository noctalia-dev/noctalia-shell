import QtQuick
import QtQuick.Shapes
import qs.Commons
import qs.Services.UI
import qs.Widgets

/**
* AllBackgrounds - Unified Shape container for all bar and panel backgrounds
*
* Unified shadow system. This component contains a single Shape
* with multiple ShapePath children (one for bar, one for each panel type).
*
* Benefits:
* - Single GPU-accelerated rendering pass for all backgrounds
* - Unified shadow system (one MultiEffect for everything)
*/
Item {
  id: root

  // Reference Bar
  required property var bar

  // Reference to MainScreen (for panel access)
  required property var windowRoot

  readonly property color panelBackgroundColor: Color.mSurface

  anchors.fill: parent

  // Unified background container
  Item {
    anchors.fill: parent

    // When not using separate bar opacity, use unified approach (original behavior)
    Item {
      anchors.fill: parent
      visible: !Settings.data.bar.useSeparateOpacity

      // Enable layer caching to prevent continuous re-rendering
      layer.enabled: true
      opacity: Settings.data.ui.panelBackgroundOpacity

      Shape {
        id: unifiedBackgroundsShape
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        enabled: false

        Component.onCompleted: {
          Logger.d("AllBackgrounds", "AllBackgrounds initialized");
        }

        /**
        *  Bar
        */
        BarBackground {
          bar: root.bar
          shapeContainer: unifiedBackgroundsShape
          windowRoot: root.windowRoot
          backgroundColor: panelBackgroundColor
        }

        /**
        *  Panel Background Slots
        *  Only 2 slots needed: one for currently open/opening panel, one for closing panel
        */

        // Slot 0: Currently open/opening panel
        PanelBackground {
          assignedPanel: {
            var p = PanelService.backgroundSlotAssignments[0];
            // Only render if this panel belongs to this screen
            return (p && p.screen === root.windowRoot.screen) ? p : null;
          }
          shapeContainer: unifiedBackgroundsShape
          defaultBackgroundColor: panelBackgroundColor
        }

        // Slot 1: Closing panel (during transitions)
        PanelBackground {
          assignedPanel: {
            var p = PanelService.backgroundSlotAssignments[1];
            // Only render if this panel belongs to this screen
            return (p && p.screen === root.windowRoot.screen) ? p : null;
          }
          shapeContainer: unifiedBackgroundsShape
          defaultBackgroundColor: panelBackgroundColor
        }
      }

      // Apply shadow to the unified backgrounds
      NDropShadow {
        anchors.fill: parent
        source: unifiedBackgroundsShape
      }
    }

    // When using separate bar opacity, separate the rendering
    Item {
      anchors.fill: parent
      visible: Settings.data.bar.useSeparateOpacity

      // Panel backgrounds with panel opacity
      Item {
        anchors.fill: parent

        layer.enabled: true
        opacity: Settings.data.ui.panelBackgroundOpacity

        Shape {
          id: panelBackgroundsShape
          anchors.fill: parent
          preferredRendererType: Shape.CurveRenderer
          enabled: false

          /**
          *  Panel Background Slots
          *  Only 2 slots needed: one for currently open/opening panel, one for closing panel
          */

          // Slot 0: Currently open/opening panel
          PanelBackground {
            assignedPanel: {
              var p = PanelService.backgroundSlotAssignments[0];
              // Only render if this panel belongs to this screen
              return (p && p.screen === root.windowRoot.screen) ? p : null;
            }
            shapeContainer: panelBackgroundsShape
            defaultBackgroundColor: panelBackgroundColor
          }

          // Slot 1: Closing panel (during transitions)
          PanelBackground {
            assignedPanel: {
              var p = PanelService.backgroundSlotAssignments[1];
              // Only render if this panel belongs to this screen
              return (p && p.screen === root.windowRoot.screen) ? p : null;
            }
            shapeContainer: panelBackgroundsShape
            defaultBackgroundColor: panelBackgroundColor
          }
        }

        // Apply shadow to the panel backgrounds
        NDropShadow {
          anchors.fill: parent
          source: panelBackgroundsShape
        }
      }

      // Bar background with separate opacity
      Item {
        anchors.fill: parent

        layer.enabled: true
        opacity: Settings.data.bar.backgroundOpacity

        Shape {
          id: barBackgroundShape
          anchors.fill: parent
          preferredRendererType: Shape.CurveRenderer
          enabled: false

          BarBackground {
            bar: root.bar
            shapeContainer: barBackgroundShape
            windowRoot: root.windowRoot
            backgroundColor: panelBackgroundColor
          }
        }

        NDropShadow {
          anchors.fill: parent
          source: barBackgroundShape
        }
      }
    }
  }
}
