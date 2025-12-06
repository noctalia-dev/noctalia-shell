import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import qs.Commons
import qs.Modules.Bar.Extras
import qs.Services.Compositor
import qs.Services.UI
import qs.Widgets

Item {
  id: root

  property ShellScreen screen

  // Widget properties passed from Bar.qml for per-instance settings
  property string widgetId: ""
  property string section: ""
  property int sectionWidgetIndex: -1
  property int sectionWidgetsCount: 0
  property real scaling: 1.0

  property var widgetMetadata: BarWidgetRegistry.widgetMetadata[widgetId]
  property var widgetSettings: {
    if (section && sectionWidgetIndex >= 0) {
      var widgets = Settings.data.bar.widgets[section];
      if (widgets && sectionWidgetIndex < widgets.length) {
        return widgets[sectionWidgetIndex];
      }
    }
    return {};
  }

  // Widget settings - matching MediaMini pattern
  readonly property bool showIcon: (widgetSettings.showIcon !== undefined) ? widgetSettings.showIcon : widgetMetadata.showIcon
  readonly property string hideMode: (widgetSettings.hideMode !== undefined) ? widgetSettings.hideMode : widgetMetadata.hideMode
  readonly property string scrollingMode: (widgetSettings.scrollingMode !== undefined) ? widgetSettings.scrollingMode : (widgetMetadata.scrollingMode !== undefined ? widgetMetadata.scrollingMode : "hover")

  // Maximum widget width with user settings support
  readonly property real maxWidth: (widgetSettings.maxWidth !== undefined) ? widgetSettings.maxWidth : Math.max(widgetMetadata.maxWidth, screen ? screen.width * 0.06 : 0)
  readonly property bool useFixedWidth: (widgetSettings.useFixedWidth !== undefined) ? widgetSettings.useFixedWidth : widgetMetadata.useFixedWidth

  readonly property bool isVerticalBar: (Settings.data.bar.position === "left" || Settings.data.bar.position === "right")
  readonly property bool hasFocusedWindow: CompositorService.getFocusedWindow() !== null
  readonly property string windowTitle: CompositorService.getFocusedWindowTitle() || "No active window"
  readonly property string fallbackIcon: "user-desktop"

  implicitHeight: visible ? (isVerticalBar ? (((!hasFocusedWindow) && hideMode === "hidden") ? 0 : calculatedVerticalDimension()) : Style.capsuleHeight) : 0
  implicitWidth: visible ? (isVerticalBar ? (((!hasFocusedWindow) && hideMode === "hidden") ? 0 : calculatedVerticalDimension()) : (((!hasFocusedWindow) && hideMode === "hidden") ? 0 : dynamicWidth)) : 0

  // "visible": Always Visible, "hidden": Hide When Empty, "transparent": Transparent When Empty
  visible: (hideMode !== "hidden" || hasFocusedWindow) || opacity > 0
  opacity: ((hideMode !== "hidden" || hasFocusedWindow) && (hideMode !== "transparent" || hasFocusedWindow)) ? 1.0 : 0.0
  Behavior on opacity {
    NumberAnimation {
      duration: Style.animationNormal
      easing.type: Easing.OutCubic
    }
  }

  Behavior on implicitWidth {
    NumberAnimation {
      duration: Style.animationNormal
      easing.type: Easing.InOutCubic
    }
  }

  Behavior on implicitHeight {
    NumberAnimation {
      duration: Style.animationNormal
      easing.type: Easing.InOutCubic
    }
  }

  function calculatedVerticalDimension() {
    return Math.round((Style.baseWidgetSize - 5) * scaling);
  }

  function calculateContentWidth() {
    // Calculate the actual content width based on visible elements
    var contentWidth = 0;
    var margins = Style.marginS * scaling * 2; // Left and right margins

    // Icon width (if visible)
    if (showIcon) {
      contentWidth += 18 * scaling;
      contentWidth += Style.marginS * scaling; // Spacing after icon
    }

    // Text width (use the measured width)
    contentWidth += fullTitleMetrics.contentWidth;

    // Additional small margin for text
    contentWidth += Style.marginXXS * 2;

    // Add container margins
    contentWidth += margins;

    return Math.ceil(contentWidth);
  }

  // Dynamic width: adapt to content but respect maximum width setting
  readonly property real dynamicWidth: {
    // If using fixed width mode, always use maxWidth
    if (useFixedWidth) {
      return maxWidth;
    }
    // Otherwise, adapt to content
    if (!hasFocusedWindow) {
      return Math.min(calculateContentWidth(), maxWidth);
    }
    // Use content width but don't exceed user-set maximum width
    return Math.min(calculateContentWidth(), maxWidth);
  }

  function getAppIcon() {
    try {
      // Try CompositorService first
      const focusedWindow = CompositorService.getFocusedWindow();
      if (focusedWindow && focusedWindow.appId) {
        try {
          const idValue = focusedWindow.appId;
          const normalizedId = (typeof idValue === 'string') ? idValue : String(idValue);
          const iconResult = ThemeIcons.iconForAppId(normalizedId.toLowerCase());
          if (iconResult && iconResult !== "") {
            return iconResult;
          }
        } catch (iconError) {
          Logger.w("ActiveWindow", "Error getting icon from CompositorService:", iconError);
        }
      }

      if (CompositorService.isHyprland) {
        // Fallback to ToplevelManager
        if (ToplevelManager && ToplevelManager.activeToplevel) {
          try {
            const activeToplevel = ToplevelManager.activeToplevel;
            if (activeToplevel.appId) {
              const idValue2 = activeToplevel.appId;
              const normalizedId2 = (typeof idValue2 === 'string') ? idValue2 : String(idValue2);
              const iconResult2 = ThemeIcons.iconForAppId(normalizedId2.toLowerCase());
              if (iconResult2 && iconResult2 !== "") {
                return iconResult2;
              }
            }
          } catch (fallbackError) {
            Logger.w("ActiveWindow", "Error getting icon from ToplevelManager:", fallbackError);
          }
        }
      }

      return ThemeIcons.iconFromName(fallbackIcon);
    } catch (e) {
      Logger.w("ActiveWindow", "Error in getAppIcon:", e);
      return ThemeIcons.iconFromName(fallbackIcon);
    }
  }

  // Hidden text element to measure full title width
  NText {
    id: fullTitleMetrics
    visible: false
    text: windowTitle
    pointSize: Style.fontSizeS * scaling
    applyUiScale: false
    font.weight: Style.fontWeightMedium
  }

  NPopupContextMenu {
    id: contextMenu

    model: [
      {
        "label": I18n.tr("context-menu.widget-settings"),
        "action": "widget-settings",
        "icon": "settings"
      },
    ]

    onTriggered: action => {
                   var popupMenuWindow = PanelService.getPopupMenuWindow(screen);
                   if (popupMenuWindow) {
                     popupMenuWindow.close();
                   }

                   if (action === "widget-settings") {
                     BarService.openWidgetSettings(screen, section, sectionWidgetIndex, widgetId, widgetSettings);
                   }
                 }
  }

  Rectangle {
    id: windowActiveRect
    visible: root.visible
    anchors.verticalCenter: parent.verticalCenter
    width: isVerticalBar ? ((!hasFocusedWindow) && hideMode === "hidden" ? 0 : calculatedVerticalDimension()) : ((!hasFocusedWindow) && (hideMode === "hidden") ? 0 : dynamicWidth)
    height: isVerticalBar ? ((!hasFocusedWindow) && hideMode === "hidden" ? 0 : calculatedVerticalDimension()) : Style.capsuleHeight
    radius: Style.radiusM
    color: Style.capsuleColor

    // Smooth width transition
    Behavior on width {
      NumberAnimation {
        duration: Style.animationNormal
        easing.type: Easing.InOutCubic
      }
    }

    Item {
      id: mainContainer
      anchors.fill: parent
      anchors.leftMargin: isVerticalBar ? 0 : Style.marginS * scaling
      anchors.rightMargin: isVerticalBar ? 0 : Style.marginS * scaling

      // Horizontal layout for top/bottom bars
      RowLayout {
        id: rowLayout
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.marginS * scaling
        visible: !isVerticalBar
        z: 1

        // Window icon
        Item {
          Layout.preferredWidth: 18 * scaling
          Layout.preferredHeight: 18 * scaling
          Layout.alignment: Qt.AlignVCenter
          visible: showIcon

          IconImage {
            id: windowIcon
            anchors.fill: parent
            source: getAppIcon()
            asynchronous: true
            smooth: true
            visible: source !== ""

            // Apply dock shader to active window icon (always themed)
            layer.enabled: widgetSettings.colorizeIcons !== false
            layer.effect: ShaderEffect {
              property color targetColor: Settings.data.colorSchemes.darkMode ? Color.mOnSurface : Color.mSurfaceVariant
              property real colorizeMode: 0.0 // Dock mode (grayscale)

              fragmentShader: Qt.resolvedUrl(Quickshell.shellDir + "/Shaders/qsb/appicon_colorize.frag.qsb")
            }
          }
        }

        // Title container with scrolling
        Item {
          id: titleContainer
          Layout.preferredWidth: {
            // Calculate available width based on other elements
            var iconWidth = (showIcon && windowIcon.visible ? (18 + Style.marginS) : 0);
            var totalMargins = Style.marginXXS * 2;
            var availableWidth = mainContainer.width - iconWidth - totalMargins;
            return Math.max(20, availableWidth);
          }
          Layout.maximumWidth: Layout.preferredWidth
          Layout.alignment: Qt.AlignVCenter
          Layout.preferredHeight: titleText.height

          clip: true

          property bool isScrolling: false
          property bool isResetting: false
          property real textWidth: fullTitleMetrics.contentWidth
          property real containerWidth: width
          property bool needsScrolling: textWidth > containerWidth

          // Timer for "always" mode with delay
          Timer {
            id: scrollStartTimer
            interval: 1000
            repeat: false
            onTriggered: {
              if (scrollingMode === "always" && titleContainer.needsScrolling) {
                titleContainer.isScrolling = true;
                titleContainer.isResetting = false;
              }
            }
          }

          // Update scrolling state based on mode
          property var updateScrollingState: function () {
            if (scrollingMode === "never") {
              isScrolling = false;
              isResetting = false;
            } else if (scrollingMode === "always") {
              if (needsScrolling) {
                if (mouseArea.containsMouse) {
                  isScrolling = false;
                  isResetting = true;
                } else {
                  scrollStartTimer.restart();
                }
              } else {
                scrollStartTimer.stop();
                isScrolling = false;
                isResetting = false;
              }
            } else if (scrollingMode === "hover") {
              if (mouseArea.containsMouse && needsScrolling) {
                isScrolling = true;
                isResetting = false;
              } else {
                isScrolling = false;
                if (needsScrolling) {
                  isResetting = true;
                }
              }
            }
          }

          onWidthChanged: updateScrollingState()
          Component.onCompleted: updateScrollingState()

          // React to hover changes
          Connections {
            target: mouseArea
            function onContainsMouseChanged() {
              titleContainer.updateScrollingState();
            }
          }

          // Scrolling content with seamless loop
          Item {
            id: scrollContainer
            height: parent.height
            width: childrenRect.width

            property real scrollX: 0
            x: scrollX

            RowLayout {
              spacing: 50 // Gap between text copies

              NText {
                id: titleText
                text: windowTitle
                pointSize: Style.fontSizeS * scaling
                applyUiScale: false
                font.weight: Style.fontWeightMedium
                verticalAlignment: Text.AlignVCenter
                color: Color.mOnSurface
                onTextChanged: {
                  if (root.scrollingMode === "always") {
                    titleContainer.isScrolling = false;
                    titleContainer.isResetting = false;
                    scrollContainer.scrollX = 0;
                    scrollStartTimer.restart();
                  }
                }
              }

              // Second copy for seamless scrolling
              NText {
                text: windowTitle
                font: titleText.font
                pointSize: Style.fontSizeS * scaling
                applyUiScale: false
                verticalAlignment: Text.AlignVCenter
                color: Color.mOnSurface
                visible: titleContainer.needsScrolling && titleContainer.isScrolling
              }
            }

            // Reset animation
            NumberAnimation on scrollX {
              running: titleContainer.isResetting
              to: 0
              duration: 300
              easing.type: Easing.OutQuad
              onFinished: {
                titleContainer.isResetting = false;
              }
            }

            // Seamless infinite scroll
            NumberAnimation on scrollX {
              id: infiniteScroll
              running: titleContainer.isScrolling && !titleContainer.isResetting
              from: 0
              to: -(titleContainer.textWidth + 50)
              duration: Math.max(4000, windowTitle.length * 100)
              loops: Animation.Infinite
              easing.type: Easing.Linear
            }
          }
        }
      }

      // Vertical layout for left/right bars - icon only
      Item {
        id: verticalLayout
        anchors.centerIn: parent
        width: parent.width - Style.marginM * 2
        height: parent.height - Style.marginM * 2
        visible: isVerticalBar
        z: 1

        // Window icon
        Item {
          width: Style.baseWidgetSize * 0.5 * scaling
          height: width
          anchors.centerIn: parent
          visible: windowTitle !== ""

          IconImage {
            id: windowIconVertical
            anchors.fill: parent
            source: getAppIcon()
            asynchronous: true
            smooth: true
            visible: source !== ""

            // Apply dock shader to active window icon (always themed)
            layer.enabled: widgetSettings.colorizeIcons !== false
            layer.effect: ShaderEffect {
              property color targetColor: Color.mOnSurface
              property real colorizeMode: 0.0 // Dock mode (grayscale)

              fragmentShader: Qt.resolvedUrl(Quickshell.shellDir + "/Shaders/qsb/appicon_colorize.frag.qsb")
            }
          }
        }
      }

      // Mouse area for hover detection
      MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onEntered: {
          if ((windowTitle !== "") && isVerticalBar || (scrollingMode === "never")) {
            TooltipService.show(root, windowTitle, BarService.getTooltipDirection());
          }
        }
        onExited: {
          TooltipService.hide();
        }
        onClicked: mouse => {
                     if (mouse.button === Qt.RightButton) {
                       var popupMenuWindow = PanelService.getPopupMenuWindow(screen);
                       if (popupMenuWindow) {
                         popupMenuWindow.showContextMenu(contextMenu);
                         const pos = BarService.getContextMenuPosition(root, contextMenu.implicitWidth, contextMenu.implicitHeight);
                         contextMenu.openAtItem(root, pos.x, pos.y);
                       }
                     }
                   }
      }
    }
  }

  Connections {
    target: CompositorService
    function onActiveWindowChanged() {
      try {
        windowIcon.source = Qt.binding(getAppIcon);
        windowIconVertical.source = Qt.binding(getAppIcon);
      } catch (e) {
        Logger.w("ActiveWindow", "Error in onActiveWindowChanged:", e);
      }
    }
    function onWindowListChanged() {
      try {
        windowIcon.source = Qt.binding(getAppIcon);
        windowIconVertical.source = Qt.binding(getAppIcon);
      } catch (e) {
        Logger.w("ActiveWindow", "Error in onWindowListChanged:", e);
      }
    }
  }
}
