import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.Commons
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

    // Only create PanelWindow if enabled AND screen has widgets
    active: modelData && Settings.data.desktopWidgets.enabled && screenWidgets.length > 0 && !PowerProfileService.noctaliaPerformanceMode

    sourceComponent: PanelWindow {
      id: window
      color: Color.transparent
      screen: screenLoader.modelData

      WlrLayershell.layer: WlrLayer.Bottom
      WlrLayershell.exclusionMode: ExclusionMode.Ignore
      WlrLayershell.namespace: "noctalia-desktop-widgets-" + (screen?.name || "unknown")
      WlrLayershell.keyboardFocus: needsKeyboardFocus() ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

      function needsKeyboardFocus() {
          for (var i = 0; i < screenLoader.screenWidgets.length; i++) {
              var widget = screenLoader.screenWidgets[i];
              // The countdown widget is the only one requiring focus for now
              if (widget.id === 'Countdown') {
                  // A countdown widget requires focus when it's configured and running
                  if (widget.targetDate && widget.targetDate !== "" &&
                      (widget.isRunning || widget.isPaused)) {
                      return true; // Found a configured and active countdown widget
                  }
              }
          }
          return false;
      }

      anchors {
        top: true
        bottom: true
        right: true
        left: true
      }

      Component.onCompleted: {
        Logger.d("DesktopWidgets", "Created panel window for", screen?.name);
      }

      Item {
        id: widgetsContainer
        anchors.fill: parent

        // Visual grid overlay - shown when grid snap is enabled in edit mode
        // Using Loader to properly unload Canvas when not needed
        Loader {
          id: gridOverlayLoader
          active: Settings.data.desktopWidgets.editMode && Settings.data.desktopWidgets.enabled && Settings.data.desktopWidgets.gridSnap
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

            property var widgetData: modelData
            property int widgetIndex: index

            Connections {
                target: widgetLoader
                function onWidgetDataChanged() {
                    if (widgetLoader.item) {
                        widgetLoader.item.widgetData = widgetLoader.widgetData;
                    }
                }
            }

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
                item.widgetData = widgetData;
                item.widgetIndex = widgetIndex;

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

        // Background for edit mode controls
        Rectangle {
          id: editModeControlsBackground
          visible: Settings.data.desktopWidgets.editMode && Settings.data.desktopWidgets.enabled

          readonly property string barPos: Settings.data.bar.position || "top"
          readonly property bool barFloating: Settings.data.bar.floating || false
          // Calculate offset from bar based on position and floating state
          readonly property int barOffsetTop: {
            if (barPos !== "top")
              return Style.marginXL * Style.uiScaleRatio;
            const floatMarginV = barFloating ? Math.ceil(Settings.data.bar.marginVertical * Style.marginXL) : 0;
            return Style.barHeight + floatMarginV + Style.marginM + (Style.marginXL * Style.uiScaleRatio);
          }
          readonly property int barOffsetRight: {
            if (barPos !== "right")
              return Style.marginXL * Style.uiScaleRatio;
            const floatMarginH = barFloating ? Math.ceil(Settings.data.bar.marginHorizontal * Style.marginXL) : 0;
            return Style.barHeight + floatMarginH + Style.marginM + (Style.marginXL * Style.uiScaleRatio);
          }

          anchors {
            top: parent.top
            right: parent.right
            topMargin: barOffsetTop
            rightMargin: barOffsetRight
          }

          // Calculate width to accommodate all controls
          width: {
            var buttonWidth = editModeButton.visible ? editModeButton.implicitWidth : 0;
            var explanationWidth = controlsExplanation.visible ? controlsExplanation.width : 0;
            var checkboxWidth = gridSnapCheckbox.visible ? gridSnapCheckbox.implicitWidth : 0;
            return Math.max(buttonWidth, explanationWidth, checkboxWidth, 200) + (Style.marginXL * 2);
          }

          // Calculate height to cover all controls with spacing
          height: {
            var buttonHeight = editModeButton.visible ? editModeButton.height : 0;
            var explanationHeight = controlsExplanation.visible ? controlsExplanation.height : 0;
            var checkboxHeight = gridSnapCheckbox.visible ? gridSnapCheckbox.height : 0;
            return buttonHeight + Style.marginXL + explanationHeight + Style.marginXL + checkboxHeight + (Style.marginXL * 2);
          }

          color: Qt.rgba(Color.mSurface.r, Color.mSurface.g, Color.mSurface.b, 0.85)
          radius: Style.radiusL
          border {
            width: 1
            color: Qt.alpha(Color.mOutline, 0.2)
          }
          z: 9999
        }

        // Exit edit mode button
        NButton {
          id: editModeButton
          visible: Settings.data.desktopWidgets.editMode && Settings.data.desktopWidgets.enabled

          readonly property string barPos: Settings.data.bar.position || "top"
          readonly property bool barFloating: Settings.data.bar.floating || false
          // Calculate offset from bar based on position and floating state
          readonly property int barOffsetTop: {
            if (barPos !== "top")
              return Style.marginXL * Style.uiScaleRatio;
            const floatMarginV = barFloating ? Math.ceil(Settings.data.bar.marginVertical * Style.marginXL) : 0;
            return Style.barHeight + floatMarginV + Style.marginM + (Style.marginXL * Style.uiScaleRatio);
          }
          readonly property int barOffsetRight: {
            if (barPos !== "right")
              return Style.marginXL * Style.uiScaleRatio;
            const floatMarginH = barFloating ? Math.ceil(Settings.data.bar.marginHorizontal * Style.marginXL) : 0;
            return Style.barHeight + floatMarginH + Style.marginM + (Style.marginXL * Style.uiScaleRatio);
          }

          anchors {
            top: editModeControlsBackground.top
            right: editModeControlsBackground.right
            topMargin: Style.marginXL
            rightMargin: Style.marginXL
          }
          text: I18n.tr("settings.desktop-widgets.edit-mode.exit-button")
          icon: "logout"
          //backgroundColor: Color.mSurface
          //textColor: Color.mOnSurface
          //hoverColor: Color.mSurfaceVariant
          outlined: false
          fontSize: Style.fontSizeM * 1.1
          iconSize: Style.fontSizeL * 1.1
          z: 10000
          onClicked: Settings.data.desktopWidgets.editMode = false
        }

        // Controls explanation text
        NText {
          id: controlsExplanation
          visible: Settings.data.desktopWidgets.editMode && Settings.data.desktopWidgets.enabled
          anchors {
            top: editModeButton.bottom
            right: editModeControlsBackground.right
            topMargin: Style.marginXL
            rightMargin: Style.marginXL
          }
          text: I18n.tr("settings.desktop-widgets.edit-mode.controls-explanation")
          pointSize: Style.fontSizeS
          color: Color.mOnSurfaceVariant
          horizontalAlignment: Text.AlignRight
          wrapMode: Text.WordWrap
          width: Math.min(implicitWidth, 300 * Style.uiScaleRatio)
          z: 10000
        }

        // Grid snap checkbox
        RowLayout {
          id: gridSnapCheckbox
          visible: Settings.data.desktopWidgets.editMode && Settings.data.desktopWidgets.enabled
          anchors {
            top: controlsExplanation.bottom
            right: editModeControlsBackground.right
            topMargin: Style.marginXL
            rightMargin: Style.marginXL
          }
          spacing: Style.marginS
          z: 10000

          NText {
            text: I18n.tr("settings.desktop-widgets.edit-mode.grid-snap.label")
            pointSize: Style.fontSizeS
            color: Color.mOnSurfaceVariant
            horizontalAlignment: Text.AlignRight
          }

          NCheckbox {
            checked: Settings.data.desktopWidgets.gridSnap
            onToggled: checked => Settings.data.desktopWidgets.gridSnap = checked
          }
        }
      }
    }
  }
}
