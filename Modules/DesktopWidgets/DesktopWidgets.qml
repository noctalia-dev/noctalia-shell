import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Modules.Panels.Settings
import qs.Services.Compositor
import qs.Services.Noctalia
import qs.Services.Power
import qs.Services.UI
import qs.Widgets

Variants {
  id: root
  model: Quickshell.screens

  // Direct binding to registry's widgets property for reactivity
  readonly property var registeredWidgets: DesktopWidgetRegistry.widgets

  // Force reload counter - incremented when plugin widget registry changes
  property int pluginReloadCounter: 0

  Connections {
    target: DesktopWidgetRegistry

    function onPluginWidgetRegistryUpdated() {
      root.pluginReloadCounter++;
      Logger.d("DesktopWidgets", "Plugin widget registry updated, reload counter:", root.pluginReloadCounter);
    }
  }

  delegate: Loader {
    id: screenLoader
    required property ShellScreen modelData

    // Reactive property for widgets on this specific screen
    // Returns a fresh array whenever Settings changes
    property var screenWidgets: {
      if (!modelData || !modelData.name) {
        return [];
      }
      var monitorWidgets = Settings.data.desktopWidgets.monitorWidgets || [];
      for (var i = 0; i < monitorWidgets.length; i++) {
        if (monitorWidgets[i].name === modelData.name) {
          return monitorWidgets[i].widgets || [];
        }
      }
      return [];
    }

    // Only create PanelWindow if enabled AND (screen has widgets OR in edit mode)
    active: modelData && Settings.data.desktopWidgets.enabled && (screenWidgets.length > 0 || DesktopWidgetRegistry.editMode) && !PowerProfileService.noctaliaPerformanceMode && !PanelService.lockScreen?.active

    sourceComponent: PanelWindow {
      id: window
      color: "transparent"
      screen: screenLoader.modelData

      WlrLayershell.layer: WlrLayer.Bottom
      WlrLayershell.exclusionMode: ExclusionMode.Ignore
      WlrLayershell.namespace: "noctalia-desktop-widgets-" + (screen?.name || "unknown")

      anchors {
        top: true
        bottom: true
        right: true
        left: true
      }

      Component.onCompleted: {
        Logger.d("DesktopWidgets", "Created panel window for", screen?.name);
      }

      // Add a new widget to the current screen
      function addWidgetToCurrentScreen(widgetId) {
        var monitorName = window.screen.name;
        var newWidget = {
          "id": widgetId
        };

        // Load default metadata if available
        var metadata = DesktopWidgetRegistry.widgetMetadata[widgetId];
        if (metadata) {
          Object.keys(metadata).forEach(function (key) {
            newWidget[key] = metadata[key];
          });
        }

        // Place at screen center
        newWidget.x = (window.screen.width / 2) - 100;
        newWidget.y = (window.screen.height / 2) - 100;
        newWidget.scale = 1.0;

        // Get current widgets and add new one
        var monitorWidgets = Settings.data.desktopWidgets.monitorWidgets || [];
        var newMonitorWidgets = monitorWidgets.slice();
        var found = false;

        for (var i = 0; i < newMonitorWidgets.length; i++) {
          if (newMonitorWidgets[i].name === monitorName) {
            var widgets = (newMonitorWidgets[i].widgets || []).slice();
            widgets.push(newWidget);
            newMonitorWidgets[i] = {
              "name": monitorName,
              "widgets": widgets
            };
            found = true;
            break;
          }
        }

        if (!found) {
          newMonitorWidgets.push({
                                   "name": monitorName,
                                   "widgets": [newWidget]
                                 });
        }

        Settings.data.desktopWidgets.monitorWidgets = newMonitorWidgets;
        Logger.i("DesktopWidgets", "Added widget", widgetId, "to", monitorName);
      }

      Item {
        id: widgetsContainer
        anchors.fill: parent

        // Visual grid overlay - shown when grid snap is enabled in edit mode
        // Using Loader to properly unload Canvas when not needed
        Loader {
          id: gridOverlayLoader
          active: DesktopWidgetRegistry.editMode && Settings.data.desktopWidgets.enabled && Settings.data.desktopWidgets.gridSnap
          anchors.fill: parent
          z: -1  // Behind widgets but above background
          asynchronous: false

          sourceComponent: Canvas {
            id: gridOverlay
            anchors.fill: parent
            opacity: 0.3

            // Grid size calculated based on screen resolution - matches DraggableDesktopWidget
            // Ensures grid lines pass through the screen center on both axes
            readonly property int gridSize: {
              if (!window.screen)
                return 30; // Fallback
              var baseSize = Math.round(window.screen.width * 0.015);
              baseSize = Math.max(20, Math.min(60, baseSize));

              // Calculate center coordinates
              var centerX = window.screen.width / 2;
              var centerY = window.screen.height / 2;

              // Find a grid size that divides evenly into both center coordinates
              // This ensures a grid line crosses through the center on both axes
              var bestSize = baseSize;
              var bestDistance = Infinity;

              // Try values around baseSize to find one that divides evenly into both centers
              for (var offset = -10; offset <= 10; offset++) {
                var candidate = baseSize + offset;
                if (candidate < 20 || candidate > 60)
                  continue;

                // Check if this size divides evenly into both center coordinates
                var remainderX = centerX % candidate;
                var remainderY = centerY % candidate;

                // If both remainders are 0, this is perfect - center is on grid lines
                if (remainderX === 0 && remainderY === 0) {
                  return candidate; // Perfect match, use it immediately
                }

                // Otherwise, find the closest to perfect alignment
                var distance = Math.abs(remainderX) + Math.abs(remainderY);
                if (distance < bestDistance) {
                  bestDistance = distance;
                  bestSize = candidate;
                }
              }

              // If we found a perfect match, it would have returned already
              // Otherwise, try to find a divisor of both centerX and centerY
              // that's close to our best size
              var gcd = function (a, b) {
                while (b !== 0) {
                  var temp = b;
                  b = a % b;
                  a = temp;
                }
                return a;
              };

              // Find common divisors of centerX and centerY
              var centerGcd = gcd(Math.round(centerX), Math.round(centerY));
              if (centerGcd > 0) {
                // Find a divisor of centerGcd that's close to bestSize
                for (var divisor = Math.floor(centerGcd / 60); divisor <= Math.ceil(centerGcd / 20); divisor++) {
                  if (centerGcd % divisor !== 0)
                    continue;
                  var candidate = centerGcd / divisor;
                  if (candidate >= 20 && candidate <= 60) {
                    if (Math.abs(candidate - baseSize) < Math.abs(bestSize - baseSize)) {
                      bestSize = candidate;
                    }
                  }
                }
              }

              return bestSize;
            }

            onPaint: {
              const ctx = getContext("2d");
              ctx.reset();
              ctx.strokeStyle = Color.mPrimary;
              ctx.lineWidth = 1;

              // Draw vertical lines
              for (let x = 0; x <= width; x += gridSize) {
                ctx.beginPath();
                ctx.moveTo(x, 0);
                ctx.lineTo(x, height);
                ctx.stroke();
              }

              // Draw horizontal lines
              for (let y = 0; y <= height; y += gridSize) {
                ctx.beginPath();
                ctx.moveTo(0, y);
                ctx.lineTo(width, y);
                ctx.stroke();
              }
            }

            // Repaint when size changes
            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()

            Component.onCompleted: {
              requestPaint();
            }

            Connections {
              target: Settings.data.desktopWidgets
              function onGridSnapChanged() {
                if (gridOverlayLoader.active) {
                  gridOverlay.requestPaint();
                }
              }
            }

            Connections {
              target: DesktopWidgetRegistry
              function onEditModeChanged() {
                if (gridOverlayLoader.active) {
                  gridOverlay.requestPaint();
                }
              }
            }
          }
        }

        // Load widgets dynamically from per-monitor array
        Repeater {
          model: screenLoader.screenWidgets

          delegate: Loader {
            id: widgetLoader
            // Bind to registeredWidgets and pluginReloadCounter to re-evaluate when plugins register/unregister
            active: (modelData.id in root.registeredWidgets) && (root.pluginReloadCounter >= 0)

            required property var modelData
            required property int index

            sourceComponent: {
              // Access registeredWidgets and pluginReloadCounter to create reactive binding
              var _ = root.pluginReloadCounter;
              var widgets = root.registeredWidgets;
              return widgets[modelData.id] || null;
            }

            onLoaded: {
              if (item) {
                item.screen = window.screen;
                item.parent = widgetsContainer;
                item.widgetData = modelData;
                item.widgetIndex = index;

                // Inject plugin API for plugin widgets
                if (DesktopWidgetRegistry.isPluginWidget(modelData.id)) {
                  var pluginId = modelData.id.replace("plugin:", "");
                  var api = PluginService.getPluginAPI(pluginId);
                  if (api && item.hasOwnProperty("pluginApi")) {
                    item.pluginApi = api;
                  }
                }
              }
            }
          }
        }

        // Edit mode controls panel
        Rectangle {
          id: editModeControlsPanel
          visible: DesktopWidgetRegistry.editMode && Settings.data.desktopWidgets.enabled

          readonly property string barPos: Settings.getBarPositionForScreen(window.screen?.name)
          readonly property bool barFloating: Settings.data.bar.floating || false
          readonly property real barHeight: Style.getBarHeightForScreen(window.screen?.name)

          readonly property int barOffsetTop: {
            if (barPos !== "top")
              return Style.marginM;
            const floatMarginV = barFloating ? Math.ceil(Settings.data.bar.marginVertical) : 0;
            return barHeight + floatMarginV + Style.marginM;
          }
          readonly property int barOffsetRight: {
            if (barPos !== "right")
              return Style.marginM;
            const floatMarginH = barFloating ? Math.ceil(Settings.data.bar.marginHorizontal) : 0;
            return barHeight + floatMarginH + Style.marginM;
          }

          // Internal state for drag tracking (session-only, resets on restart)
          QtObject {
            id: panelInternal
            property bool isDragging: false
            property real dragOffsetX: 0
            property real dragOffsetY: 0
            // Default position: top-right corner accounting for bar
            property real baseX: widgetsContainer.width - editModeControlsPanel.width - editModeControlsPanel.barOffsetRight
            property real baseY: editModeControlsPanel.barOffsetTop
          }

          // Reset position when bar position changes
          Connections {
            target: Settings.data.bar
            function onPositionChanged() {
              panelInternal.baseX = widgetsContainer.width - editModeControlsPanel.width - editModeControlsPanel.barOffsetRight;
              panelInternal.baseY = editModeControlsPanel.barOffsetTop;
            }
          }

          x: panelInternal.isDragging ? panelInternal.dragOffsetX : panelInternal.baseX
          y: panelInternal.isDragging ? panelInternal.dragOffsetY : panelInternal.baseY

          width: controlsLayout.implicitWidth + Style.margin2XL
          height: controlsLayout.implicitHeight + Style.margin2XL

          color: Qt.rgba(Color.mSurface.r, Color.mSurface.g, Color.mSurface.b, 0.85)
          radius: Style.radiusL
          border {
            width: Style.borderS
            color: Color.mOutline
          }
          z: 9999

          // Drag area for relocating the panel
          MouseArea {
            id: dragArea
            anchors.fill: parent
            cursorShape: panelInternal.isDragging ? Qt.ClosedHandCursor : Qt.OpenHandCursor

            property point pressPos: Qt.point(0, 0)

            onPressed: mouse => {
                         pressPos = mapToItem(widgetsContainer, mouse.x, mouse.y);
                         panelInternal.dragOffsetX = editModeControlsPanel.x;
                         panelInternal.dragOffsetY = editModeControlsPanel.y;
                         panelInternal.isDragging = true;
                       }

            onPositionChanged: mouse => {
                                 if (panelInternal.isDragging && pressed) {
                                   var currentPos = mapToItem(widgetsContainer, mouse.x, mouse.y);
                                   var deltaX = currentPos.x - pressPos.x;
                                   var deltaY = currentPos.y - pressPos.y;

                                   var newX = panelInternal.baseX + deltaX;
                                   var newY = panelInternal.baseY + deltaY;

                                   // Boundary clamping
                                   newX = Math.max(0, Math.min(newX, widgetsContainer.width - editModeControlsPanel.width));
                                   newY = Math.max(0, Math.min(newY, widgetsContainer.height - editModeControlsPanel.height));

                                   panelInternal.dragOffsetX = newX;
                                   panelInternal.dragOffsetY = newY;
                                 }
                               }

            onReleased: {
              if (panelInternal.isDragging) {
                panelInternal.baseX = panelInternal.dragOffsetX;
                panelInternal.baseY = panelInternal.dragOffsetY;
                panelInternal.isDragging = false;
              }
            }

            onCanceled: {
              panelInternal.isDragging = false;
            }
          }

          ColumnLayout {
            id: controlsLayout
            anchors {
              fill: parent
              margins: Style.marginXL
            }
            spacing: Style.marginL

            RowLayout {
              Layout.alignment: Qt.AlignRight
              spacing: Style.marginS

              NIconButton {
                id: addWidgetButton
                icon: "layout-grid-add"
                tooltipText: I18n.tr("tooltips.add-widget")
                onClicked: {
                  var popupMenuWindow = PanelService.getPopupMenuWindow(window.screen);
                  if (popupMenuWindow) {
                    // Build menu items from registry
                    var items = [];
                    var widgets = DesktopWidgetRegistry.widgets;
                    for (var id in widgets) {
                      items.push({
                                   action: id,
                                   text: DesktopWidgetRegistry.getWidgetDisplayName(id),
                                   icon: "layout-grid-add"
                                 });
                    }
                    var globalPos = addWidgetButton.mapToItem(null, 0, addWidgetButton.height + Style.marginS);
                    popupMenuWindow.showDynamicContextMenu(items, globalPos.x, globalPos.y, function (widgetId) {
                      addWidgetToCurrentScreen(widgetId);
                      return false;
                    });
                  }
                }
              }

              NIconButton {
                icon: "grid-4x4"
                tooltipText: I18n.tr("panels.desktop-widgets.edit-mode-grid-snap-label")
                colorBg: Settings.data.desktopWidgets.gridSnap ? Color.mPrimary : Color.mSurfaceVariant
                colorFg: Settings.data.desktopWidgets.gridSnap ? Color.mOnPrimary : Color.mPrimary
                onClicked: Settings.data.desktopWidgets.gridSnap = !Settings.data.desktopWidgets.gridSnap
              }

              NIconButton {
                icon: "settings"
                tooltipText: I18n.tr("actions.open-settings")
                onClicked: {
                  SettingsPanelService.toggle(SettingsPanel.Tab.DesktopWidgets, -1, screenLoader.modelData);
                }
              }

              NButton {
                text: I18n.tr("panels.desktop-widgets.edit-mode-exit-button")
                icon: "logout"
                outlined: false
                fontSize: Style.fontSizeS
                iconSize: Style.fontSizeM
                onClicked: DesktopWidgetRegistry.editMode = false
              }
            }

            NText {
              Layout.alignment: Qt.AlignRight
              Layout.maximumWidth: 300 * Style.uiScaleRatio
              text: I18n.tr("panels.desktop-widgets.edit-mode-controls-explanation")
              pointSize: Style.fontSizeS
              color: Color.mOnSurfaceVariant
              horizontalAlignment: Text.AlignRight
              wrapMode: Text.WordWrap
            }
          }
        }
      }
    }
  }
}
