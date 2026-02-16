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

  // Hot corner: trigger click on first widget in a section
  function triggerFirstWidgetInSection(sectionName: string) {
    var widgets = BarService.getWidgetsBySection(sectionName, screen?.name);
    for (var i = 0; i < widgets.length; i++) {
      var widget = widgets[i];
      if (widget && widget.visible && widget.widgetId !== "Spacer") {
        if (typeof widget.clicked === "function") {
          widget.clicked();
        }
        return;
      }
    }
  }

  // Hot corner: trigger click on last widget in a section
  function triggerLastWidgetInSection(sectionName: string) {
    var widgets = BarService.getWidgetsBySection(sectionName, screen?.name);
    for (var i = widgets.length - 1; i >= 0; i--) {
      var widget = widgets[i];
      if (widget && widget.visible && widget.widgetId !== "Spacer") {
        if (typeof widget.clicked === "function") {
          widget.clicked();
        }
        return;
      }
    }
  }

  // Expose bar region for click-through mask
  readonly property var barRegion: barContentLoader.item?.children[0] || null

  // Expose the actual bar Item for unified background system
  readonly property var barItem: barRegion

  // Bar positioning properties (per-screen)
  readonly property string barPosition: Settings.getBarPositionForScreen(screen?.name)
  readonly property bool barIsVertical: barPosition === "left" || barPosition === "right"
  readonly property bool barFloating: Settings.data.bar.floating || false
  readonly property bool barIsland: Settings.data.bar.island || false

  // Bar density (per-screen)
  readonly property string barDensity: Settings.getBarDensityForScreen(screen?.name)

  // Bar sizing based on per-screen density
  readonly property real barHeight: Style.getBarHeightForDensity(barDensity, barIsVertical)
  readonly property real capsuleHeight: Style.getCapsuleHeightForDensity(barDensity, barHeight)
  readonly property real barFontSize: Style.getBarFontSizeForDensity(barHeight, capsuleHeight, barIsVertical)

  // Bar widgets (per-screen) - initial configuration
  // Note: Updates are handled via Connections to BarService.widgetsRevisionChanged
  readonly property var barWidgets: Settings.getBarWidgetsForScreen(screen?.name)

  // Stable ListModels for each section - prevents Repeater recreation on settings changes
  property ListModel leftWidgetsModel: ListModel {}
  property ListModel centerWidgetsModel: ListModel {}
  property ListModel rightWidgetsModel: ListModel {}

  // Sync a ListModel with widget data, preserving delegates when only settings change
  function syncWidgetModel(model, newWidgets) {
    var validWidgets = filterValidWidgets(newWidgets);

    // Build list of current IDs in model
    var currentIds = [];
    for (var i = 0; i < model.count; i++) {
      currentIds.push(model.get(i).id);
    }

    // Build list of new IDs
    var newIds = validWidgets.map(w => w.id);

    // Check if structure changed (different IDs or order)
    var structureChanged = currentIds.length !== newIds.length;
    if (!structureChanged) {
      for (var i = 0; i < currentIds.length; i++) {
        if (currentIds[i] !== newIds[i]) {
          structureChanged = true;
          break;
        }
      }
    }

    Logger.d("Bar", "syncWidgetModel:", currentIds.join("|"), "→", newIds.join("|"), "changed:", structureChanged);

    if (structureChanged) {
      // Rebuild model - IDs changed
      model.clear();
      for (var i = 0; i < validWidgets.length; i++) {
        model.append(validWidgets[i]);
      }
    }
    // If structure didn't change, delegates are preserved and will read fresh settings
  }

  // Sync models when widget revision changes
  // Note: We use Connections instead of onBarWidgetsChanged because getBarWidgetsForScreen
  // returns the same object reference (Settings.data.bar.widgets) even when content changes,
  // so QML won't detect the change via property binding.
  Connections {
    target: BarService
    function onWidgetsRevisionChanged() {
      Logger.d("Bar", "onWidgetsRevisionChanged, revision:", BarService.widgetsRevision, "screen:", root.screen?.name);
      var widgets = Settings.getBarWidgetsForScreen(root.screen?.name);
      if (widgets) {
        root.syncWidgetModel(root.leftWidgetsModel, widgets.left);
        root.syncWidgetModel(root.centerWidgetsModel, widgets.center);
        root.syncWidgetModel(root.rightWidgetsModel, widgets.right);
      }
    }
  }

  // Initialize models
  Component.onCompleted: {
    Logger.d("Bar", "Bar Component.onCompleted for screen:", screen?.name);
    var widgets = Settings.getBarWidgetsForScreen(screen?.name);
    if (widgets) {
      syncWidgetModel(leftWidgetsModel, widgets.left);
      syncWidgetModel(centerWidgetsModel, widgets.center);
      syncWidgetModel(rightWidgetsModel, widgets.right);
    }
  }

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
        x: (root.barPosition === "right") ? (parent.width - root.barHeight) : 0
        y: (root.barPosition === "bottom") ? (parent.height - root.barHeight) : 0
        width: root.barIsVertical ? root.barHeight : parent.width
        height: root.barIsVertical ? parent.height : root.barHeight

        // Corner states for new unified background system
        // State -1: No radius (flat/square corner)
        // State 0: Normal (inner curve)
        // State 1: Horizontal inversion (outer curve on X-axis)
        // State 2: Vertical inversion (outer curve on Y-axis)
        readonly property int topLeftCornerState: {
          // Floating bar: always simple rounded corners
          if (barFloating)
            return 0;
          // Island mode: edge corners flat, opposite corners rounded
          if (barIsland) {
            // Top/Left bar: top-left against screen edge = no radius
            if (barPosition === "top" || barPosition === "left")
              return -1;
            // Bottom/Right bar: top-left is away from edge = rounded
            return 0;
          }
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
          // Island mode: edge corners flat, opposite corners rounded
          if (barIsland) {
            // Top/Right bar: top-right against screen edge = no radius
            if (barPosition === "top" || barPosition === "right")
              return -1;
            // Bottom/Left bar: top-right is away from edge = rounded
            return 0;
          }
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
          // Island mode: edge corners flat, opposite corners rounded
          if (barIsland) {
            // Bottom/Left bar: bottom-left against screen edge = no radius
            if (barPosition === "bottom" || barPosition === "left")
              return -1;
            // Top/Right bar: bottom-left is away from edge = rounded
            return 0;
          }
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
          // Island mode: edge corners flat, opposite corners rounded
          if (barIsland) {
            // Bottom/Right bar: bottom-right against screen edge = no radius
            if (barPosition === "bottom" || barPosition === "right")
              return -1;
            // Top/Left bar: bottom-right is away from edge = rounded
            return 0;
          }
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
          onClicked: mouse => {
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
          sourceComponent: root.barIsVertical ? verticalBarComponent : horizontalBarComponent
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

      // Top edge hot corner - triggers first widget in left (top) section
      MouseArea {
        width: parent.width
        height: Style.marginS
        x: 0
        y: 0
        onClicked: root.triggerFirstWidgetInSection("left")
      }

      // Bottom edge hot corner - triggers last widget in right (bottom) section
      MouseArea {
        width: parent.width
        height: Style.marginS
        x: 0
        anchors.bottom: parent.bottom
        onClicked: root.triggerLastWidgetInSection("right")
      }

      // Calculate margin to center widgets vertically within the bar height
      readonly property real verticalBarMargin: Math.round((root.barHeight - root.capsuleHeight) / 2)

      // Top section (left widgets)
      ColumnLayout {
        x: Style.pixelAlignCenter(parent.width, width)
        anchors.top: parent.top
        anchors.topMargin: verticalBarMargin
        spacing: Style.marginS

        Repeater {
          model: root.leftWidgetsModel
          delegate: BarWidgetLoader {
            required property var model
            required property int index

            widgetId: model.id || ""
            widgetScreen: root.screen
            widgetProps: ({
                            "widgetId": model.id,
                            "section": "left",
                            "sectionWidgetIndex": index,
                            "sectionWidgetsCount": root.leftWidgetsModel.count
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
          model: root.centerWidgetsModel
          delegate: BarWidgetLoader {
            required property var model
            required property int index

            widgetId: model.id || ""
            widgetScreen: root.screen
            widgetProps: ({
                            "widgetId": model.id,
                            "section": "center",
                            "sectionWidgetIndex": index,
                            "sectionWidgetsCount": root.centerWidgetsModel.count
                          })
            Layout.alignment: Qt.AlignHCenter
          }
        }
      }

      // Bottom section (right widgets)
      ColumnLayout {
        x: Style.pixelAlignCenter(parent.width, width)
        anchors.bottom: parent.bottom
        anchors.bottomMargin: verticalBarMargin
        spacing: Style.marginS

        Repeater {
          model: root.rightWidgetsModel
          delegate: BarWidgetLoader {
            required property var model
            required property int index

            widgetId: model.id || ""
            widgetScreen: root.screen
            widgetProps: ({
                            "widgetId": model.id,
                            "section": "right",
                            "sectionWidgetIndex": index,
                            "sectionWidgetsCount": root.rightWidgetsModel.count
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

      // Left edge hot corner - triggers first widget in left section
      MouseArea {
        width: Style.marginS
        height: parent.height
        x: 0
        y: 0
        onClicked: root.triggerFirstWidgetInSection("left")
      }

      // Right edge hot corner - triggers last widget in right section
      MouseArea {
        width: Style.marginS
        height: parent.height
        anchors.right: parent.right
        y: 0
        onClicked: root.triggerLastWidgetInSection("right")
      }

      // Calculate margin to center widgets horizontally within the bar height
      readonly property real horizontalBarMargin: Math.round((root.barHeight - root.capsuleHeight) / 2)

      // Left Section
      RowLayout {
        id: leftSection
        objectName: "leftSection"
        anchors.left: parent.left
        anchors.leftMargin: horizontalBarMargin
        y: Style.pixelAlignCenter(parent.height, height)
        spacing: Style.marginS

        Repeater {
          model: root.leftWidgetsModel
          delegate: BarWidgetLoader {
            required property var model
            required property int index

            widgetId: model.id || ""
            widgetScreen: root.screen
            widgetProps: ({
                            "widgetId": model.id,
                            "section": "left",
                            "sectionWidgetIndex": index,
                            "sectionWidgetsCount": root.leftWidgetsModel.count
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
        spacing: Style.marginS

        Repeater {
          model: root.centerWidgetsModel
          delegate: BarWidgetLoader {
            required property var model
            required property int index

            widgetId: model.id || ""
            widgetScreen: root.screen
            widgetProps: ({
                            "widgetId": model.id,
                            "section": "center",
                            "sectionWidgetIndex": index,
                            "sectionWidgetsCount": root.centerWidgetsModel.count
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
        anchors.rightMargin: horizontalBarMargin
        y: Style.pixelAlignCenter(parent.height, height)
        spacing: Style.marginS

        Repeater {
          model: root.rightWidgetsModel
          delegate: BarWidgetLoader {
            required property var model
            required property int index

            widgetId: model.id || ""
            widgetScreen: root.screen
            widgetProps: ({
                            "widgetId": model.id,
                            "section": "right",
                            "sectionWidgetIndex": index,
                            "sectionWidgetsCount": root.rightWidgetsModel.count
                          })
            Layout.alignment: Qt.AlignVCenter
          }
        }
      }
    }
  }
}
