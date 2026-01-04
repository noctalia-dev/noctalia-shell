import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import QtQuick.Layouts
import qs.Commons
import qs.Services.Noctalia
import qs.Widgets

NBox {
  id: root

  property string sectionName: ""
  property string sectionSubtitle: ""
  property string sectionId: ""
  property var widgetModel: []
  property var availableWidgets: []
  property var availableSections: ["left", "center", "right"]
  property var sectionLabels: ({}) // Map of sectionId -> display label
  property var sectionIcons: ({}) // Map of sectionId -> icon name
  property int maxWidgets: -1 // -1 means unlimited
  property bool draggable: true // Enable/disable drag reordering

  // Get display label for a section
  function getSectionLabel(sectionId) {
    if (sectionLabels && sectionLabels[sectionId]) {
      return sectionLabels[sectionId];
    }
    return sectionId; // Fallback to section ID
  }

  // Get icon for a section
  function getSectionIcon(sectionId) {
    if (sectionIcons && sectionIcons[sectionId]) {
      return sectionIcons[sectionId];
    }
    return "arrow-right"; // Default fallback icon
  }

  property var widgetRegistry: null
  property string settingsDialogComponent: "BarWidgetSettingsDialog.qml"

  readonly property int gridColumns: 3
  readonly property real miniButtonSize: Style.baseWidgetSize * 0.65
  readonly property bool isAtMaxCapacity: maxWidgets >= 0 && widgetModel.length >= maxWidgets
  readonly property real widgetItemHeight: Style.baseWidgetSize * 1.3 * Style.uiScaleRatio

  signal addWidget(string widgetId, string section)
  signal removeWidget(string section, int index)
  signal reorderWidget(string section, int fromIndex, int toIndex)
  signal updateWidgetSettings(string section, int index, var settings)
  signal moveWidget(string fromSection, int index, string toSection)
  signal dragPotentialStarted
  signal dragPotentialEnded
  signal openPluginSettingsRequested(var pluginManifest)

  color: Color.mSurface
  Layout.fillWidth: true

  // Calculate width to fit gridColumns widgets with spacing
  function calculateWidgetWidth(gridWidth) {
    var columnSpacing = (root.gridColumns - 1) * Style.marginM;
    var widgetWidth = (gridWidth - columnSpacing) / root.gridColumns;
    return Math.floor(widgetWidth);
  }

  Layout.minimumHeight: {
    // header + minimal content area
    var absoluteMin = (Style.marginL * 2) + (Style.fontSizeL * 2) + Style.marginM + (65 * Style.uiScaleRatio);

    var widgetCount = widgetModel.length;
    if (widgetCount === 0) {
      return absoluteMin;
    }

    // Calculate rows based on grid layout
    // Use actual parent width if available, otherwise estimate
    var availableWidth = (parent && parent.width > 0) ? (parent.width - (Style.marginL * 2)) : 400;
    var rows = Math.ceil(widgetCount / root.gridColumns);

    // Calculate widget width for height calculation
    var containerWidth = availableWidth;
    var widgetWidth = calculateWidgetWidth(containerWidth);

    // Header height + spacing + (rows * widget height) + (spacing between rows) + margins
    var headerHeight = Style.fontSizeL * 2;
    // Account for grid margins
    var gridTopMargin = Style.marginS;
    var gridBottomMargin = Style.marginL;
    var widgetAreaHeight = gridTopMargin + (rows * widgetItemHeight) + ((rows - 1) * Style.marginL) + gridBottomMargin;

    return Math.max(absoluteMin, (Style.marginL * 2) + headerHeight + Style.marginM + widgetAreaHeight);
  }

  // Generate widget color from name checksum
  function getWidgetColor(widget) {
    if (widget.id.startsWith('plugin:')) {
      return [Color.mSecondary, Color.mOnSecondary];
    }
    return [Color.mPrimary, Color.mOnPrimary];
  }

  // Check if widget has settings (either core widget with allowUserSettings or plugin with settings entry point)
  function widgetHasSettings(widgetId) {
    // Check if it's a core widget with user settings
    if (root.widgetRegistry && root.widgetRegistry.widgetHasUserSettings(widgetId)) {
      return true;
    }

    // Check if it's a plugin with settings
    if (root.widgetRegistry && root.widgetRegistry.isPluginWidget(widgetId)) {
      var pluginId = widgetId.replace("plugin:", "");
      var manifest = PluginRegistry.getPluginManifest(pluginId);
      return manifest?.entryPoints?.settings !== undefined;
    }

    return false;
  }

  ColumnLayout {
    anchors.fill: parent
    anchors.margins: Style.marginL
    spacing: Style.marginM

    RowLayout {
      Layout.fillWidth: true
      Layout.rightMargin: Style.marginS

      ColumnLayout {
        spacing: Style.marginXXS
        Layout.alignment: Qt.AlignVCenter
        Layout.fillWidth: false
        Layout.leftMargin: Style.marginS
        Layout.maximumWidth: {
          // Reserve space for other elements: count indicator, combo box (~200), button (~50), and margins
          // Use a reasonable maximum that leaves room for controls on the right
          // On smaller screens, use a smaller percentage to ensure controls fit
          var rowLayout = parent;
          if (rowLayout && rowLayout.width > 0) {
            // Use smaller percentage on smaller screens, but ensure minimum space for text
            var minWidth = 150 * Style.uiScaleRatio;
            var maxWidth = rowLayout.width < 600 ? rowLayout.width * 0.35 : rowLayout.width * 0.4;
            return Math.max(minWidth, maxWidth);
          }
          return 250 * Style.uiScaleRatio;
        }

        NText {
          text: sectionName
          pointSize: Style.fontSizeL
          font.weight: Style.fontWeightBold
          color: Color.mOnSurface
          elide: Text.ElideRight
          Layout.fillWidth: true
        }

        NText {
          visible: sectionSubtitle !== ""
          text: sectionSubtitle
          pointSize: Style.fontSizeS
          color: Color.mOnSurfaceVariant
          elide: Text.ElideRight
          Layout.fillWidth: true
        }
      }

      // Widget count indicator (when max is set)
      NText {
        visible: root.maxWidgets >= 0
        text: root.maxWidgets === 0 ? "(LOCKED)" : "(" + widgetModel.length + "/" + root.maxWidgets + ")"
        pointSize: Style.fontSizeS
        color: root.isAtMaxCapacity ? Color.mError : Color.mOnSurfaceVariant
        Layout.alignment: Qt.AlignVCenter
        Layout.leftMargin: Style.marginXS
      }

      Item {
        Layout.fillWidth: true
      }

      NSearchableComboBox {
        id: comboBox
        model: availableWidgets ?? null
        label: ""
        description: ""
        placeholder: I18n.tr("bar.widget-settings.section-editor.placeholder")
        searchPlaceholder: I18n.tr("bar.widget-settings.section-editor.search-placeholder")
        onSelected: key => comboBox.currentKey = key
        popupHeight: 300 * Style.uiScaleRatio
        minimumWidth: 200 * Style.uiScaleRatio
        enabled: !root.isAtMaxCapacity

        Layout.alignment: Qt.AlignVCenter

        // Re-filter when the model count changes (when widgets are loaded)
        Connections {
          target: availableWidgets ?? null
          ignoreUnknownSignals: true
          function onCountChanged() {
            // Trigger a re-filter by clearing and re-setting the search text
            var currentSearch = comboBox.searchText;
            comboBox.searchText = "";
            comboBox.searchText = currentSearch;
          }
        }
      }

      NIconButton {
        icon: "add"
        colorBg: Color.mPrimary
        colorFg: Color.mOnPrimary
        colorBgHover: Color.mSecondary
        colorFgHover: Color.mOnSecondary
        enabled: comboBox.currentKey !== "" && !root.isAtMaxCapacity
        tooltipText: root.isAtMaxCapacity ? I18n.tr("tooltips.max-widgets-reached") : I18n.tr("tooltips.add-widget")
        Layout.alignment: Qt.AlignVCenter
        Layout.leftMargin: Style.marginS
        onClicked: {
          if (comboBox.currentKey !== "" && !root.isAtMaxCapacity) {
            addWidget(comboBox.currentKey, sectionId);
            comboBox.currentKey = "";
          }
        }
      }
    }

    // Drag and Drop Widget Area
    Item {
      id: gridContainer
      Layout.fillWidth: true
      Layout.preferredHeight: {
        if (widgetModel.length === 0) {
          return 65 * Style.uiScaleRatio;
        }
        // Use actual width, fallback to a reasonable default if not yet available
        var containerWidth = width > 0 ? width : (parent ? parent.width : 400);
        var rows = Math.ceil(widgetModel.length / root.gridColumns);
        // Calculate height: (rows * item height) + (row spacing between items) + grid margins
        var gridTopMargin = Style.marginS;
        var gridBottomMargin = Style.marginS;
        var calculatedHeight = gridTopMargin + (rows * root.widgetItemHeight) + ((rows - 1) * Style.marginS) + gridBottomMargin;
        return Math.max(65 * Style.uiScaleRatio, calculatedHeight);
      }
      Layout.minimumHeight: 65 * Style.uiScaleRatio
      clip: true // Clip to prevent overflow

      Grid {
        id: widgetGrid
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.leftMargin: Style.marginS
        anchors.rightMargin: Style.marginS
        anchors.topMargin: Style.marginS
        anchors.bottomMargin: Style.marginS
        columns: root.gridColumns
        rowSpacing: Style.marginS
        columnSpacing: Style.marginM

        Repeater {
          id: widgetRepeater
          model: widgetModel

          delegate: Rectangle {
            id: widgetItem
            required property int index
            required property var modelData

            width: root.calculateWidgetWidth(parent.width)
            height: root.widgetItemHeight
            radius: Style.iRadiusL
            color: root.getWidgetColor(modelData)[0]
            border.color: Color.mOutline
            border.width: Style.borderS

            // Store the widget index for drag operations
            property int widgetIndex: index
            readonly property int buttonsWidth: Math.round(20)
            readonly property int buttonsCount: root.widgetHasSettings(modelData.id) ? 1 : 0

            // Visual feedback during drag
            opacity: flowDragArea.draggedIndex === index ? 0.5 : 1.0
            scale: flowDragArea.draggedIndex === index ? 0.95 : 1.0
            z: flowDragArea.draggedIndex === index ? 1000 : 0

            Behavior on opacity {
              NumberAnimation {
                duration: Style.animationFast
              }
            }
            Behavior on scale {
              NumberAnimation {
                duration: Style.animationFast
              }
            }

            // Context menu for moving widget to other sections
            NContextMenu {
              id: contextMenu
              parent: Overlay.overlay
              width: 240 * Style.uiScaleRatio
              model: {
                var items = [];
                // Add move options for each available section (except current)
                for (var i = 0; i < root.availableSections.length; i++) {
                  var section = root.availableSections[i];
                  if (section !== root.sectionId) {
                    var label = root.getSectionLabel(section);
                    // Capitalize first letter
                    var capitalizedLabel = label.charAt(0).toUpperCase() + label.slice(1);
                    items.push({
                                 "label": I18n.tr("tooltips.move-to-section", {
                                                    "section": capitalizedLabel
                                                  }),
                                 "action": section,
                                 "icon": root.getSectionIcon(section),
                                 "visible": true
                               });
                  }
                }
                // Add remove option
                items.push({
                             "label": I18n.tr("tooltips.remove-widget"),
                             "action": "remove",
                             "icon": "trash",
                             "visible": true
                           });
                return items;
              }

              onTriggered: action => {
                             if (action === "remove") {
                               root.removeWidget(root.sectionId, widgetItem.index);
                             } else {
                               root.moveWidget(root.sectionId, widgetItem.index, action);
                             }
                           }
            }

            // MouseArea for the context menu - only active when not dragging
            MouseArea {
              id: contextMouseArea
              anchors.fill: parent
              acceptedButtons: Qt.RightButton
              cursorShape: Qt.PointingHandCursor
              z: -1 // Below the buttons but above background
              enabled: !flowDragArea.dragStarted && !flowDragArea.potentialDrag

              onPressed: mouse => {
                           mouse.accepted = true;
                           // Check if click is not on the settings button area (if visible)
                           const localX = mouse.x;
                           const buttonsStartX = parent.width - (parent.buttonsCount * parent.buttonsWidth);
                           if (localX < buttonsStartX || parent.buttonsCount === 0) {
                             contextMenu.openAtItem(widgetItem, mouse.x, mouse.y);
                           }
                         }
            }

            RowLayout {
              id: widgetContent
              anchors.fill: parent
              anchors.margins: Style.marginXS
              anchors.rightMargin: Style.marginS
              spacing: Style.marginXXS

              NText {
                text: {
                  // For plugin widgets, get the actual plugin name from manifest
                  if (root.widgetRegistry && root.widgetRegistry.isPluginWidget(modelData.id)) {
                    const pluginId = modelData.id.replace("plugin:", "");
                    const manifest = PluginRegistry.getPluginManifest(pluginId);
                    if (manifest && manifest.name) {
                      return manifest.name;
                    }
                    // Fallback: just strip the prefix
                    return pluginId;
                  }
                  return modelData.id;
                }
                pointSize: Style.fontSizeXS
                color: root.getWidgetColor(modelData)[1]
                horizontalAlignment: Text.AlignLeft
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideRight
                leftPadding: Style.marginS
                rightPadding: Style.marginS
                Layout.fillWidth: true
                Layout.fillHeight: true
              }

              // Plugin indicator icon
              NIcon {
                visible: root.widgetRegistry && root.widgetRegistry.isPluginWidget(modelData.id)
                icon: "plugin"
                pointSize: Style.fontSizeXXS
                color: root.getWidgetColor(modelData)[1]
                Layout.preferredWidth: visible ? Style.baseWidgetSize * 0.5 : 0
                Layout.preferredHeight: Style.baseWidgetSize * 0.5
              }

              RowLayout {
                spacing: 0
                Layout.preferredWidth: buttonsCount * buttonsWidth * Style.uiScaleRatio
                Layout.preferredHeight: parent.height

                Loader {
                  active: root.widgetHasSettings(modelData.id)
                  sourceComponent: NIconButton {
                    icon: "settings"
                    tooltipText: I18n.tr("tooltips.widget-settings")
                    baseSize: miniButtonSize
                    colorBorder: Qt.alpha(Color.mOutline, Style.opacityLight)
                    colorBg: Color.mOnSurface
                    colorFg: Color.mOnPrimary
                    colorBgHover: Qt.alpha(Color.mOnPrimary, Style.opacityLight)
                    colorFgHover: Color.mOnPrimary
                    onClicked: {
                      // Check if this is a plugin widget
                      var isPlugin = root.widgetRegistry && root.widgetRegistry.isPluginWidget(modelData.id);

                      if (isPlugin) {
                        // Handle plugin settings - emit signal for parent to handle
                        var pluginId = modelData.id.replace("plugin:", "");
                        var manifest = PluginRegistry.getPluginManifest(pluginId);

                        if (!manifest || !manifest.entryPoints?.settings) {
                          Logger.e("NSectionEditor", "Plugin settings not found for:", pluginId);
                          return;
                        }

                        // Emit signal to request opening plugin settings
                        root.openPluginSettingsRequested(manifest);
                      } else {
                        // Handle core widget settings
                        var component = Qt.createComponent(Qt.resolvedUrl(root.settingsDialogComponent));
                        function instantiateAndOpen() {
                          var dialog = component.createObject(Overlay.overlay, {
                                                                "widgetIndex": index,
                                                                "widgetData": modelData,
                                                                "widgetId": modelData.id,
                                                                "sectionId": root.sectionId
                                                              });
                          if (dialog) {
                            dialog.updateWidgetSettings.connect(root.updateWidgetSettings);
                            dialog.open();
                          } else {
                            Logger.e("NSectionEditor", "Failed to create settings dialog instance");
                          }
                        }
                        if (component.status === Component.Ready) {
                          instantiateAndOpen();
                        } else if (component.status === Component.Error) {
                          Logger.e("NSectionEditor", component.errorString());
                        } else {
                          component.statusChanged.connect(function () {
                            if (component.status === Component.Ready) {
                              instantiateAndOpen();
                            } else if (component.status === Component.Error) {
                              Logger.e("NSectionEditor", component.errorString());
                            }
                          });
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }

      // Ghost/Clone widget for dragging
      Rectangle {
        id: dragGhost
        width: 0
        height: Style.baseWidgetSize * 1.15
        radius: Style.iRadiusL
        color: Color.transparent
        border.color: Color.mOutline
        border.width: Style.borderS
        opacity: 0.7
        visible: flowDragArea.dragStarted
        z: 2000
        clip: false // Ensure ghost isn't clipped

        NText {
          id: ghostText
          anchors.centerIn: parent
          pointSize: Style.fontSizeS
          color: Color.mOnPrimary
        }
      }

      // Drop indicator - visual feedback for where the widget will be inserted
      Rectangle {
        id: dropIndicator
        width: 3
        height: Style.baseWidgetSize * 1.15
        radius: Style.iRadiusXXS
        color: Color.mSecondary
        opacity: 0
        visible: opacity > 0
        z: 1999

        SequentialAnimation on opacity {
          id: pulseAnimation
          running: false
          loops: Animation.Infinite
          NumberAnimation {
            to: 1
            duration: 400
            easing.type: Easing.InOutQuad
          }
          NumberAnimation {
            to: 0.6
            duration: 400
            easing.type: Easing.InOutQuad
          }
        }

        Behavior on x {
          NumberAnimation {
            duration: 100
            easing.type: Easing.OutCubic
          }
        }
        Behavior on y {
          NumberAnimation {
            duration: 100
            easing.type: Easing.OutCubic
          }
        }
      }

      // MouseArea for drag and drop
      MouseArea {
        id: flowDragArea
        anchors.fill: parent
        z: 100 // Above widgets to ensure it captures events first
        enabled: root.draggable

        acceptedButtons: Qt.LeftButton
        preventStealing: true // Always prevent stealing to ensure we get all events
        propagateComposedEvents: true // Allow events to propagate when not handled
        hoverEnabled: potentialDrag || dragStarted // Only track hover during drag operations
        cursorShape: dragStarted ? Qt.ClosedHandCursor : Qt.ArrowCursor

        property point startPos: Qt.point(0, 0)
        property bool dragStarted: false
        property bool potentialDrag: false // Track if we're in a potential drag interaction
        property int draggedIndex: -1
        property real dragThreshold: 8 // Reduced threshold for more responsive drag
        property Item draggedWidget: null
        property int dropTargetIndex: -1
        property var draggedModelData: null
        property bool isOverButtonArea: false

        // Drop position calculation
        // Map widget coordinates from grid-local to gridContainer coordinates
        function mapWidgetCoords(widget) {
          return {
            x: widget.x + widgetGrid.x,
            y: widget.y + widgetGrid.y,
            width: widget.width,
            height: widget.height
          };
        }

        function updateDropIndicator(mouseX, mouseY) {
          if (!dragStarted || draggedIndex === -1) {
            dropIndicator.opacity = 0;
            pulseAnimation.running = false;
            return;
          }

          let bestIndex = -1;
          let bestPosition = null;
          let minDistance = Infinity;

          // Check position relative to each widget
          for (var i = 0; i < widgetModel.length; i++) {
            if (i === draggedIndex)
              continue;
            const widget = widgetRepeater.itemAt(i);
            if (!widget || widget.widgetIndex === undefined)
              continue;

            const mapped = mapWidgetCoords(widget);

            // Check distance to left edge (insert before)
            const leftDist = Math.sqrt(Math.pow(mouseX - mapped.x, 2) + Math.pow(mouseY - (mapped.y + mapped.height / 2), 2));

            // Check distance to right edge (insert after)
            const rightDist = Math.sqrt(Math.pow(mouseX - (mapped.x + mapped.width), 2) + Math.pow(mouseY - (mapped.y + mapped.height / 2), 2));

            if (leftDist < minDistance) {
              minDistance = leftDist;
              bestIndex = i;
              bestPosition = Qt.point(mapped.x - dropIndicator.width / 2 - Style.marginXS, mapped.y);
            }

            if (rightDist < minDistance) {
              minDistance = rightDist;
              bestIndex = i + 1;
              bestPosition = Qt.point(mapped.x + mapped.width + Style.marginXS - dropIndicator.width / 2, mapped.y);
            }
          }

          // Check if we should insert at position 0 (very beginning)
          if (widgetModel.length > 0 && draggedIndex !== 0) {
            const firstWidget = widgetRepeater.itemAt(0);
            if (firstWidget) {
              const mapped = mapWidgetCoords(firstWidget);
              const dist = Math.sqrt(Math.pow(mouseX - mapped.x, 2) + Math.pow(mouseY - mapped.y, 2));
              if (dist < minDistance && mouseX < mapped.x + mapped.width / 2) {
                minDistance = dist;
                bestIndex = 0;
                // Position indicator to the left of the first widget
                bestPosition = Qt.point(mapped.x - dropIndicator.width / 2 - Style.marginXS, mapped.y);
              }
            }
          }

          // Only show indicator if we're close enough and it's a different position
          if (minDistance < 80 && bestIndex !== -1) {
            // Adjust index if we're moving forward
            let adjustedIndex = bestIndex;
            if (bestIndex > draggedIndex) {
              adjustedIndex = bestIndex - 1;
            }

            // Don't show if it's the same position
            if (adjustedIndex === draggedIndex) {
              dropIndicator.opacity = 0;
              pulseAnimation.running = false;
              dropTargetIndex = -1;
              return;
            }

            dropTargetIndex = adjustedIndex;
            if (bestPosition) {
              dropIndicator.x = bestPosition.x;
              dropIndicator.y = bestPosition.y;
              dropIndicator.opacity = 1;
              if (!pulseAnimation.running) {
                pulseAnimation.running = true;
              }
            }
          } else {
            dropIndicator.opacity = 0;
            pulseAnimation.running = false;
            dropTargetIndex = -1;
          }
        }

        function resetDragState() {
          dragStarted = false;
          potentialDrag = false;
          draggedIndex = -1;
          draggedWidget = null;
          dropTargetIndex = -1;
          draggedModelData = null;
          isOverButtonArea = false;
          dropIndicator.opacity = 0;
          pulseAnimation.running = false;
          dragGhost.width = 0;
        }

        onPressed: mouse => {
                     // Reset state
                     startPos = Qt.point(mouse.x, mouse.y);
                     dragStarted = false;
                     potentialDrag = false;
                     draggedIndex = -1;
                     draggedWidget = null;
                     dropTargetIndex = -1;
                     draggedModelData = null;
                     isOverButtonArea = false;

                     // Find which widget was clicked
                     for (var i = 0; i < widgetModel.length; i++) {
                       const widget = widgetRepeater.itemAt(i);
                       if (widget && widget.widgetIndex !== undefined) {
                         if (mouse.x >= widget.x && mouse.x <= widget.x + widget.width && mouse.y >= widget.y && mouse.y <= widget.y + widget.height) {
                           const localX = mouse.x - widget.x;
                           const buttonsStartX = widget.width - (widget.buttonsCount * widget.buttonsWidth * Style.uiScaleRatio);

                           if (localX >= buttonsStartX && widget.buttonsCount > 0) {
                             // Click is on button area - don't start drag, propagate event
                             isOverButtonArea = true;
                             mouse.accepted = false;
                             return;
                           } else {
                             // This is a draggable area
                             draggedIndex = widget.widgetIndex;
                             draggedWidget = widget;
                             draggedModelData = widget.modelData;
                             potentialDrag = true;
                             mouse.accepted = true;

                             // Signal that interaction started (prevents panel close)
                             root.dragPotentialStarted();
                             return;
                           }
                         }
                       }
                     }

                     // Click was not on any widget
                     mouse.accepted = false;
                   }

        onPositionChanged: mouse => {
                             if (potentialDrag && draggedIndex !== -1) {
                               const deltaX = mouse.x - startPos.x;
                               const deltaY = mouse.y - startPos.y;
                               const distance = Math.sqrt(deltaX * deltaX + deltaY * deltaY);

                               // Start drag if threshold exceeded
                               if (!dragStarted && distance > dragThreshold) {
                                 dragStarted = true;

                                 // Setup ghost widget
                                 if (draggedWidget) {
                                   dragGhost.width = draggedWidget.width;
                                   dragGhost.color = root.getWidgetColor(draggedModelData)[0];
                                   ghostText.text = draggedModelData.id;
                                 }
                               }

                               if (dragStarted) {
                                 // Move ghost widget
                                 dragGhost.x = mouse.x - dragGhost.width / 2;
                                 dragGhost.y = mouse.y - dragGhost.height / 2;

                                 // Update drop indicator
                                 updateDropIndicator(mouse.x, mouse.y);
                               }
                             }
                           }

        onReleased: mouse => {
                      if (dragStarted && dropTargetIndex !== -1 && dropTargetIndex !== draggedIndex) {
                        // Perform the reorder
                        reorderWidget(sectionId, draggedIndex, dropTargetIndex);
                      }

                      // Always signal end of interaction if we started one
                      if (potentialDrag) {
                        root.dragPotentialEnded();
                      }

                      // Reset everything
                      resetDragState();
                      mouse.accepted = true;
                    }

        onCanceled: {
          // Handle cancel (e.g., ESC key pressed during drag)
          if (potentialDrag) {
            root.dragPotentialEnded();
          }

          resetDragState();
        }
      }
    }
  }
}
