import QtQuick
import QtQuick.Effects
import Quickshell
import qs.Commons
import qs.Services.Noctalia
import qs.Services.UI
import qs.Widgets

Item {
  id: root

  property ShellScreen screen
  property var widgetData: null
  property int widgetIndex: -1

  property real defaultX: 100
  property real defaultY: 100

  default property alias content: contentContainer.data

  readonly property bool isDragging: internal.isDragging
  readonly property bool isScaling: internal.isScaling

  property bool showBackground: (widgetData && widgetData.showBackground !== undefined) ? widgetData.showBackground : true

  property real widgetScale: (widgetData && widgetData.scale !== undefined) ? widgetData.scale : 1.0
  property real minScale: 0.5
  property real maxScale: 3.0

  readonly property real scaleSensitivity: 0.0015
  readonly property real scaleUpdateThreshold: 0.015
  readonly property real cornerScaleSensitivity: 0.0003  // Much lower sensitivity for corner handles

  // Grid size ensures lines pass through screen center on both axes
  readonly property int gridSize: {
    if (!screen)
      return 30;
    var baseSize = Math.round(screen.width * 0.015);
    baseSize = Math.max(20, Math.min(60, baseSize));

    var centerX = screen.width / 2;
    var centerY = screen.height / 2;
    var bestSize = baseSize;
    var bestDistance = Infinity;

    for (var offset = -10; offset <= 10; offset++) {
      var candidate = baseSize + offset;
      if (candidate < 20 || candidate > 60)
        continue;

      var remainderX = centerX % candidate;
      var remainderY = centerY % candidate;

      if (remainderX === 0 && remainderY === 0) {
        return candidate;
      }

      var distance = Math.abs(remainderX) + Math.abs(remainderY);
      if (distance < bestDistance) {
        bestDistance = distance;
        bestSize = candidate;
      }
    }

    var gcd = function (a, b) {
      while (b !== 0) {
        var temp = b;
        b = a % b;
        a = temp;
      }
      return a;
    };

    var centerGcd = gcd(Math.round(centerX), Math.round(centerY));
    if (centerGcd > 0) {
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

  QtObject {
    id: internal
    property bool isDragging: false
    property bool isScaling: false
    property real dragOffsetX: 0
    property real dragOffsetY: 0
    property real baseX: (root.widgetData && root.widgetData.x !== undefined) ? root.widgetData.x : root.defaultX
    property real baseY: (root.widgetData && root.widgetData.y !== undefined) ? root.widgetData.y : root.defaultY
    property real initialWidth: 0
    property real initialHeight: 0
    property point initialMousePos: Qt.point(0, 0)
    property real initialScale: 1.0
    property real lastScale: 1.0
    // Locks operation type to prevent switching between drag/scale mid-operation
    property string operationType: ""  // "drag" or "scale" or ""
  }

  function snapToGrid(coord) {
    if (!Settings.data.desktopWidgets.gridSnap) {
      return coord;
    }
    return Math.round(coord / root.gridSize) * root.gridSize;
  }

  function updateWidgetData(properties) {
    if (widgetIndex < 0 || !screen || !screen.name) {
      return;
    }

    var monitorWidgets = Settings.data.desktopWidgets.monitorWidgets || [];
    var newMonitorWidgets = monitorWidgets.slice();

    for (var i = 0; i < newMonitorWidgets.length; i++) {
      if (newMonitorWidgets[i].name === screen.name) {
        var widgets = (newMonitorWidgets[i].widgets || []).slice();
        if (widgetIndex < widgets.length) {
          widgets[widgetIndex] = Object.assign({}, widgets[widgetIndex], properties);
          newMonitorWidgets[i] = Object.assign({}, newMonitorWidgets[i], {
                                                 "widgets": widgets
                                               });
          Settings.data.desktopWidgets.monitorWidgets = newMonitorWidgets;
        }
        break;
      }
    }
  }

  function removeWidget() {
    if (widgetIndex < 0 || !screen || !screen.name) {
      return;
    }

    var monitorWidgets = Settings.data.desktopWidgets.monitorWidgets || [];
    var newMonitorWidgets = monitorWidgets.slice();

    for (var i = 0; i < newMonitorWidgets.length; i++) {
      if (newMonitorWidgets[i].name === screen.name) {
        var widgets = (newMonitorWidgets[i].widgets || []).slice();
        if (widgetIndex >= 0 && widgetIndex < widgets.length) {
          widgets.splice(widgetIndex, 1);
          newMonitorWidgets[i] = Object.assign({}, newMonitorWidgets[i], {
                                                 "widgets": widgets
                                               });
          Settings.data.desktopWidgets.monitorWidgets = newMonitorWidgets;
        }
        break;
      }
    }
  }

  function openWidgetSettings() {
    if (!widgetData || !widgetData.id || !screen) {
      return;
    }

    var widgetId = widgetData.id;
    var hasSettings = false;

    // Check if widget has settings
    if (DesktopWidgetRegistry.isPluginWidget(widgetId)) {
      var pluginId = widgetId.replace("plugin:", "");
      var manifest = PluginRegistry.getPluginManifest(pluginId);
      if (manifest && manifest.entryPoints && manifest.entryPoints.settings) {
        hasSettings = true;
      }
    } else {
      hasSettings = DesktopWidgetRegistry.widgetSettingsMap[widgetId] !== undefined;
    }

    if (!hasSettings) {
      Logger.w("DraggableDesktopWidget", "Widget does not have settings:", widgetId);
      return;
    }

    var popupMenuWindow = PanelService.getPopupMenuWindow(screen);
    if (!popupMenuWindow) {
      Logger.e("DraggableDesktopWidget", "No popup menu window found for screen");
      return;
    }

    // Hide the dynamic context menu (popup window stays open for the dialog)
    if (popupMenuWindow.hideDynamicMenu) {
      popupMenuWindow.hideDynamicMenu();
    }

    var component = Qt.createComponent(Quickshell.shellDir + "/Modules/Panels/Settings/DesktopWidgets/DesktopWidgetSettingsDialog.qml");

    function instantiateAndOpen() {
      var dialog = component.createObject(popupMenuWindow.dialogParent, {
                                            "widgetIndex": widgetIndex,
                                            "widgetData": widgetData,
                                            "widgetId": widgetId,
                                            "sectionId": screen.name
                                          });

      if (dialog) {
        dialog.updateWidgetSettings.connect((sec, idx, settings) => {
                                              root.updateWidgetData(settings);
                                            });
        popupMenuWindow.hasDialog = true;
        dialog.closed.connect(() => {
                                popupMenuWindow.hasDialog = false;
                                popupMenuWindow.close();
                                dialog.destroy();
                              });
        dialog.open();
      } else {
        Logger.e("DraggableDesktopWidget", "Failed to create widget settings dialog");
      }
    }

    if (component.status === Component.Ready) {
      instantiateAndOpen();
    } else if (component.status === Component.Error) {
      Logger.e("DraggableDesktopWidget", "Error loading settings dialog component:", component.errorString());
    } else {
      component.statusChanged.connect(() => {
                                        if (component.status === Component.Ready) {
                                          instantiateAndOpen();
                                        } else if (component.status === Component.Error) {
                                          Logger.e("DraggableDesktopWidget", "Error loading settings dialog component:", component.errorString());
                                        }
                                      });
    }
  }

  x: internal.isDragging ? internal.dragOffsetX : internal.baseX
  y: internal.isDragging ? internal.dragOffsetY : internal.baseY

  // Scale from top-left corner to prevent position drift
  scale: widgetScale
  transformOrigin: Item.TopLeft

  onWidgetDataChanged: {
    if (!internal.isDragging) {
      internal.baseX = (widgetData && widgetData.x !== undefined) ? widgetData.x : defaultX;
      internal.baseY = (widgetData && widgetData.y !== undefined) ? widgetData.y : defaultY;
      if (widgetData && widgetData.scale !== undefined) {
        widgetScale = widgetData.scale;
      }
    }
  }

  Rectangle {
    id: decorationRect
    anchors.fill: parent
    anchors.margins: -Style.marginS
    color: DesktopWidgetRegistry.editMode ? Qt.rgba(Color.mPrimary.r, Color.mPrimary.g, Color.mPrimary.b, 0.1) : Color.transparent
    border.color: (DesktopWidgetRegistry.editMode || internal.isDragging) ? (internal.isDragging ? Color.mOutline : Color.mPrimary) : Color.transparent
    border.width: DesktopWidgetRegistry.editMode ? 3 : 0
    radius: Style.radiusL
    z: -1
  }

  Rectangle {
    id: container
    anchors.fill: parent
    radius: Style.radiusL
    color: Color.mSurface
    border {
      width: 1
      color: Qt.alpha(Color.mOutline, 0.12)
    }
    clip: true
    visible: root.showBackground

    layer.enabled: Settings.data.general.enableShadows && !internal.isDragging && root.showBackground
    layer.effect: MultiEffect {
      shadowEnabled: true
      shadowBlur: Style.shadowBlur * 1.5
      shadowOpacity: Style.shadowOpacity * 0.6
      shadowColor: Color.black
      shadowHorizontalOffset: Settings.data.general.shadowOffsetX
      shadowVerticalOffset: Settings.data.general.shadowOffsetY
      blurMax: Style.shadowBlurMax
    }
  }

  Item {
    id: contentContainer
    anchors.fill: parent
    z: 1
  }

  // Context menu model and handler - menu is created dynamically in PopupMenuWindow
  property var contextMenuModel: {
    var hasSettings = false;
    if (widgetData && widgetData.id) {
      var widgetId = widgetData.id;
      if (DesktopWidgetRegistry.isPluginWidget(widgetId)) {
        var pluginId = widgetId.replace("plugin:", "");
        var manifest = PluginRegistry.getPluginManifest(pluginId);
        hasSettings = manifest && manifest.entryPoints && manifest.entryPoints.settings;
      } else {
        hasSettings = DesktopWidgetRegistry.widgetSettingsMap[widgetId] !== undefined;
      }
    }

    var items = [];
    if (hasSettings) {
      items.push({
                   "label": I18n.tr("context-menu.widget-settings"),
                   "action": "widget-settings",
                   "icon": "settings"
                 });
    }
    items.push({
                 "label": I18n.tr("context-menu.delete"),
                 "action": "delete",
                 "icon": "trash"
               });
    return items;
  }

  function handleContextMenuAction(action) {
    if (action === "widget-settings") {
      // Don't close - openWidgetSettings will use the popup window for the dialog
      root.openWidgetSettings();
      return true; // Signal that we're handling close ourselves
    } else if (action === "delete") {
      root.removeWidget();
      return false; // Let caller close the popup
    }
    return false;
  }

  // Drag MouseArea - handles dragging (left-click)
  MouseArea {
    id: dragArea
    anchors.fill: parent
    z: 1000
    visible: DesktopWidgetRegistry.editMode
    cursorShape: internal.isDragging ? Qt.ClosedHandCursor : Qt.OpenHandCursor
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton

    property point pressPos: Qt.point(0, 0)

    onPressed: mouse => {
                 // Prevent starting new operation if one is already in progress
                 if (internal.operationType !== "") {
                   return;
                 }

                 pressPos = Qt.point(mouse.x, mouse.y);
                 internal.operationType = "drag";
                 internal.dragOffsetX = root.x;
                 internal.dragOffsetY = root.y;
                 internal.isDragging = true;
               }

    onPositionChanged: mouse => {
                         if (internal.isDragging && pressed && internal.operationType === "drag") {
                           var globalPressPos = mapToItem(root.parent, pressPos.x, pressPos.y);
                           var globalCurrentPos = mapToItem(root.parent, mouse.x, mouse.y);

                           var deltaX = globalCurrentPos.x - globalPressPos.x;
                           var deltaY = globalCurrentPos.y - globalPressPos.y;

                           var newX = internal.dragOffsetX + deltaX;
                           var newY = internal.dragOffsetY + deltaY;

                           // Boundary clamping - must account for scaled widget size
                           var scaledWidth = root.width * root.widgetScale;
                           var scaledHeight = root.height * root.widgetScale;
                           if (root.parent && scaledWidth > 0 && scaledHeight > 0) {
                             newX = Math.max(0, Math.min(newX, root.parent.width - scaledWidth));
                             newY = Math.max(0, Math.min(newY, root.parent.height - scaledHeight));
                           }

                           if (Settings.data.desktopWidgets.gridSnap) {
                             newX = root.snapToGrid(newX);
                             newY = root.snapToGrid(newY);
                             // Re-clamp after snapping to ensure widget stays within bounds
                             if (root.parent && scaledWidth > 0 && scaledHeight > 0) {
                               newX = Math.max(0, Math.min(newX, root.parent.width - scaledWidth));
                               newY = Math.max(0, Math.min(newY, root.parent.height - scaledHeight));
                             }
                           }

                           internal.dragOffsetX = newX;
                           internal.dragOffsetY = newY;
                         }
                       }

    onReleased: mouse => {
                  if (internal.isDragging && internal.operationType === "drag" && widgetIndex >= 0 && screen && screen.name) {
                    root.updateWidgetData({
                                            "x": internal.dragOffsetX,
                                            "y": internal.dragOffsetY
                                          });

                    internal.baseX = internal.dragOffsetX;
                    internal.baseY = internal.dragOffsetY;
                    internal.isDragging = false;
                    internal.operationType = "";
                  }
                }

    onCanceled: {
      internal.isDragging = false;
      internal.operationType = "";
    }
  }

  // Right-click MouseArea for context menu
  MouseArea {
    id: contextMenuArea
    anchors.fill: parent
    z: 1001
    visible: DesktopWidgetRegistry.editMode
    acceptedButtons: Qt.RightButton
    hoverEnabled: true

    onPressed: mouse => {
                 if (mouse.button === Qt.RightButton) {
                   var popupMenuWindow = PanelService.getPopupMenuWindow(root.screen);
                   if (popupMenuWindow) {
                     // Map click position to screen coordinates
                     var globalPos = root.mapToItem(null, mouse.x, mouse.y);
                     // Use dynamic context menu (created in PopupMenuWindow's Top layer)
                     // This ensures input events work correctly for desktop widgets (Bottom layer)
                     popupMenuWindow.showDynamicContextMenu(root.contextMenuModel, globalPos.x, globalPos.y, root.handleContextMenuAction);
                   }
                 }
               }
  }

  // Corner handles for scaling - using Repeater to avoid code duplication
  readonly property real cornerHandleSize: 8
  readonly property real outlineMargin: Style.marginS
  readonly property color colorHandle: Color.mSecondary

  // Corner handle model: defines position, direction, cursor, and triangle points for each corner
  // xMult/yMult: multipliers for position (0 = left/top edge, 1 = right/bottom edge)
  // xDir/yDir: direction multiplier for scaling (-1 = left/up increases, 1 = right/down increases)
  // cursor: resize cursor type (FDiag for TL-BR diagonal, BDiag for TR-BL diagonal)
  // points: triangle vertices as [x, y] pairs normalized to cornerHandleSize
  readonly property var cornerHandleModel: [
    {
      xMult: 0,
      yMult: 0,
      xDir: -1,
      yDir: -1,
      cursor: Qt.SizeFDiagCursor,
      points: [[0, 0], [1, 0], [0, 1]]
    },
    {
      xMult: 1,
      yMult: 0,
      xDir: 1,
      yDir: -1,
      cursor: Qt.SizeBDiagCursor,
      points: [[1, 0], [1, 1], [0, 0]]
    },
    {
      xMult: 0,
      yMult: 1,
      xDir: -1,
      yDir: 1,
      cursor: Qt.SizeBDiagCursor,
      points: [[0, 1], [0, 0], [1, 1]]
    },
    {
      xMult: 1,
      yMult: 1,
      xDir: 1,
      yDir: 1,
      cursor: Qt.SizeFDiagCursor,
      points: [[1, 1], [1, 0], [0, 1]]
    }
  ]

  Repeater {
    model: root.cornerHandleModel

    delegate: Canvas {
      id: cornerHandle
      required property var modelData
      required property int index

      visible: DesktopWidgetRegistry.editMode && !internal.isDragging
      x: modelData.xMult * (root.width + outlineMargin) - (modelData.xMult === 0 ? outlineMargin : cornerHandleSize)
      y: modelData.yMult * (root.height + outlineMargin) - (modelData.yMult === 0 ? outlineMargin : cornerHandleSize)
      width: cornerHandleSize
      height: cornerHandleSize
      z: 2000

      onPaint: {
        var ctx = getContext("2d");
        ctx.reset();
        ctx.fillStyle = colorHandle;
        ctx.beginPath();
        ctx.moveTo(modelData.points[0][0] * cornerHandleSize, modelData.points[0][1] * cornerHandleSize);
        ctx.lineTo(modelData.points[1][0] * cornerHandleSize, modelData.points[1][1] * cornerHandleSize);
        ctx.lineTo(modelData.points[2][0] * cornerHandleSize, modelData.points[2][1] * cornerHandleSize);
        ctx.closePath();
        ctx.fill();
      }

      Component.onCompleted: requestPaint()
      onVisibleChanged: if (visible)
                          requestPaint()

      Connections {
        target: root
        function onWidthChanged() {
          if (cornerHandle.visible)
            cornerHandle.requestPaint();
        }
        function onHeightChanged() {
          if (cornerHandle.visible)
            cornerHandle.requestPaint();
        }
      }

      MouseArea {
        id: scaleMouseArea
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton
        cursorShape: cornerHandle.modelData.cursor
        property point pressPos: Qt.point(0, 0)

        onPressed: mouse => {
                     if (internal.operationType !== "") {
                       return;
                     }
                     pressPos = mapToItem(root.parent, mouse.x, mouse.y);
                     internal.operationType = "scale";
                     internal.isScaling = true;
                     internal.initialScale = root.widgetScale;
                     internal.lastScale = root.widgetScale;
                   }

        onPositionChanged: mouse => {
                             if (internal.isScaling && pressed && internal.operationType === "scale") {
                               var currentPos = mapToItem(root.parent, mouse.x, mouse.y);
                               var deltaX = currentPos.x - pressPos.x;
                               var deltaY = currentPos.y - pressPos.y;

                               // Project delta onto the diagonal direction for this corner
                               // xDir/yDir indicate which direction increases scale
                               var diagonalDelta = (deltaX * cornerHandle.modelData.xDir + deltaY * cornerHandle.modelData.yDir) / Math.sqrt(2);

                               // Scale sensitivity: pixels of drag per 1.0 scale change
                               var sensitivity = 150;
                               var scaleDelta = diagonalDelta / sensitivity;
                               var newScale = Math.max(root.minScale, Math.min(root.maxScale, internal.initialScale + scaleDelta));

                               if (!isNaN(newScale) && newScale > 0) {
                                 root.widgetScale = newScale;
                                 internal.lastScale = newScale;
                               }
                             }
                           }

        onReleased: mouse => {
                      if (internal.isScaling && internal.operationType === "scale") {
                        root.updateWidgetData({
                                                "scale": root.widgetScale
                                              });
                        internal.isScaling = false;
                        internal.operationType = "";
                        internal.lastScale = root.widgetScale;
                      }
                    }

        onCanceled: {
          internal.isScaling = false;
          internal.operationType = "";
          internal.lastScale = root.widgetScale;
        }
      }
    }
  }
}
