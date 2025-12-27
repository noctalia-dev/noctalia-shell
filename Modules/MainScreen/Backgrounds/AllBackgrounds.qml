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

  // Wrapper with layer caching for better shadow performance
  Item {
    anchors.fill: parent

    // Enable layer caching to prevent continuous re-rendering
    // This caches the Shape to a GPU texture, reducing GPU tessellation overhead
    layer.enabled: true

    // Apply opacity to all backgrounds
    opacity: Settings.data.ui.panelBackgroundOpacity

    // The unified Shape container
    Shape {
      id: backgroundsShape
      anchors.fill: parent

      // Use curve renderer for smooth corners (GPU-accelerated)
      preferredRendererType: Shape.CurveRenderer

      enabled: false // Disable mouse input on the Shape itself

      Component.onCompleted: {
        Logger.d("AllBackgrounds", "AllBackgrounds initialized");
      }

      /**
      *  Bar
      */
      BarBackground {
        bar: root.bar
        shapeContainer: backgroundsShape
        windowRoot: root.windowRoot
        backgroundColor: Settings.data.bar.transparent ? Color.transparent : panelBackgroundColor
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
        shapeContainer: backgroundsShape
        defaultBackgroundColor: panelBackgroundColor
      }

      // Slot 1: Closing panel (during transitions)
      PanelBackground {
        assignedPanel: {
          var p = PanelService.backgroundSlotAssignments[1];
          // Only render if this panel belongs to this screen
          return (p && p.screen === root.windowRoot.screen) ? p : null;
        }
        shapeContainer: backgroundsShape
        defaultBackgroundColor: panelBackgroundColor
      }
    }

    // Apply shadow to the cached layer
    NDropShadow {
      anchors.fill: parent
      source: backgroundsShape
    }
  }
}
