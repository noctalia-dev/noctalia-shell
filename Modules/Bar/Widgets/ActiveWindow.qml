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
  Layout.preferredHeight: isVerticalBar ? -1 : Style.getBarHeightForScreen(screenName)
  Layout.preferredWidth: isVerticalBar ? Style.getBarHeightForScreen(screenName) : -1
  Layout.fillHeight: false
  Layout.fillWidth: false

  property ShellScreen screen

  // Widget properties passed from Bar.qml for per-instance settings
  property string widgetId: ""
  property string section: ""
  property int sectionWidgetIndex: -1
  property int sectionWidgetsCount: 0

  property var widgetMetadata: BarWidgetRegistry.widgetMetadata[widgetId] || {}
  // Explicit screenName property ensures reactive binding when screen changes
  readonly property string screenName: screen ? screen.name : ""
  property var widgetSettings: {
    if (section && sectionWidgetIndex >= 0 && screenName) {
      var widgets = Settings.getBarWidgetsForScreen(screenName)[section];
      if (widgets && sectionWidgetIndex < widgets.length && widgets[sectionWidgetIndex]) {
        return widgets[sectionWidgetIndex];
      }
    }
    return {};
  }

  // Widget settings - matching MediaMini pattern
  readonly property bool showIcon: (widgetSettings.showIcon !== undefined) ? widgetSettings.showIcon : (widgetMetadata.showIcon || false)
  readonly property string hideMode: (widgetSettings.hideMode !== undefined) ? widgetSettings.hideMode : (widgetMetadata.hideMode || "hidden")
  readonly property string scrollingMode: (widgetSettings.scrollingMode !== undefined) ? widgetSettings.scrollingMode : (widgetMetadata.scrollingMode || "hover")

  // Maximum widget width with user settings support
  readonly property real maxWidth: (widgetSettings.maxWidth !== undefined) ? widgetSettings.maxWidth : Math.max(widgetMetadata.maxWidth || 0, screen ? screen.width * 0.06 : 0)
  readonly property bool useFixedWidth: (widgetSettings.useFixedWidth !== undefined) ? widgetSettings.useFixedWidth : (widgetMetadata.useFixedWidth || false)
  readonly property string textColorKey: (widgetSettings.textColor !== undefined) ? widgetSettings.textColor : widgetMetadata.textColor
  readonly property color textColor: Color.resolveColorKey(textColorKey)

  readonly property string barPosition: Settings.getBarPositionForScreen(screenName)
  readonly property bool isVerticalBar: barPosition === "left" || barPosition === "right"
  readonly property real barHeight: Style.getBarHeightForScreen(screenName)
  readonly property real capsuleHeight: Style.getCapsuleHeightForScreen(screenName)
  readonly property real barFontSize: Style.getBarFontSizeForScreen(screenName)
  readonly property bool hasFocusedWindow: CompositorService.getFocusedWindow() !== null
  readonly property string windowTitle: CompositorService.getFocusedWindowTitle() || "No active window"
  readonly property string fallbackIcon: "user-desktop"

  readonly property int iconSize: Style.toOdd(capsuleHeight * 0.75)
  readonly property int verticalSize: Style.toOdd(capsuleHeight * 0.85)

  // For horizontal bars, height is always barHeight (no animation needed)
  // For vertical bars, collapse to 0 when hidden
  implicitHeight: isVerticalBar ? (((!hasFocusedWindow) && hideMode === "hidden") ? 0 : verticalSize) : barHeight
  implicitWidth: isVerticalBar ? (((!hasFocusedWindow) && hideMode === "hidden") ? 0 : verticalSize) : (((!hasFocusedWindow) && hideMode === "hidden") ? 0 : dynamicWidth)

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

  function calculateContentWidth() {
    // Calculate the actual content width based on visible elements
    var contentWidth = 0;
    var margins = Style.margin2S; // Left and right margins

    // Icon width (if visible)
    if (showIcon) {
      contentWidth += iconSize;
      contentWidth += Style.marginS; // Spacing after icon
    }

    // Text width (use the measured width)
    contentWidth += titleContainer.measuredWidth;

    // Additional small margin for text
    contentWidth += Style.margin2XXS;

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

  NPopupContextMenu {
    id: contextMenu

    model: [
      {
        "label": I18n.tr("actions.widget-settings"),
        "action": "widget-settings",
        "icon": "settings"
      },
    ]

    onTriggered: action => {
                   contextMenu.close();
                   PanelService.closeContextMenu(screen);

                   if (action === "widget-settings") {
                     BarService.openWidgetSettings(screen, section, sectionWidgetIndex, widgetId, widgetSettings);
                   }
                 }
  }

  Rectangle {
    id: windowActiveRect
    visible: root.visible
    x: isVerticalBar ? Style.pixelAlignCenter(parent.width, width) : 0
    y: isVerticalBar ? 0 : Style.pixelAlignCenter(parent.height, height)
    width: isVerticalBar ? ((!hasFocusedWindow) && hideMode === "hidden" ? 0 : verticalSize) : ((!hasFocusedWindow) && (hideMode === "hidden") ? 0 : dynamicWidth)
    height: isVerticalBar ? ((!hasFocusedWindow) && hideMode === "hidden" ? 0 : verticalSize) : capsuleHeight
    radius: Style.radiusM
    color: Style.capsuleColor
    border.color: Style.capsuleBorderColor
    border.width: Style.capsuleBorderWidth

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
      anchors.leftMargin: isVerticalBar ? 0 : Style.marginS
      anchors.rightMargin: isVerticalBar ? 0 : Style.marginS

      // Horizontal layout for top/bottom bars
      RowLayout {
        id: rowLayout
        height: iconSize
        y: Style.pixelAlignCenter(parent.height, height)
        spacing: Style.marginS
        visible: !isVerticalBar
        z: 1

        // Window icon
        Item {
          Layout.preferredWidth: iconSize
          Layout.preferredHeight: iconSize
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

        NScrollText {
          id: titleContainer
          text: windowTitle
          Layout.alignment: Qt.AlignVCenter
          maxWidth: {
            // Calculate available width based on other elements
            var iconWidth = (showIcon && windowIcon.visible ? (iconSize + Style.marginS) : 0);
            var totalMargins = Style.margin2XXS;
            var availableWidth = mainContainer.width - iconWidth - totalMargins;
            return Math.max(20, availableWidth);
          }
          scrollMode: {
            if (scrollingMode === "always")
              return NScrollText.ScrollMode.Always;
            if (scrollingMode === "hover")
              return NScrollText.ScrollMode.Hover;
            return NScrollText.ScrollMode.Never;
          }
          forcedHover: mainMouseArea.containsMouse
          gradientColor: Style.capsuleColor
          gradientWidth: Math.round(8 * Style.uiScaleRatio)
          cornerRadius: Style.radiusM

          NText {
            text: windowTitle
            pointSize: barFontSize
            applyUiScale: false
            font.weight: Style.fontWeightMedium
            color: root.textColor
          }
        }
      }

      // Vertical layout for left/right bars - icon only
      Item {
        id: verticalLayout
        width: parent.width - Style.margin2M
        height: parent.height - Style.margin2M
        x: Style.pixelAlignCenter(parent.width, width)
        y: Style.pixelAlignCenter(parent.height, height)
        visible: isVerticalBar
        z: 1

        // Window icon
        Item {
          id: verticalIconContainer
          width: root.iconSize
          height: width
          x: Style.pixelAlignCenter(parent.width, width)
          y: Style.pixelAlignCenter(parent.height, height)
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

      // Mouse area moved to root
    }
  }

  // Mouse area for hover detection
  MouseArea {
    id: mainMouseArea
    anchors.fill: parent

    // Extend click area to screen edge if widget is at the start/end
    anchors.leftMargin: (!isVerticalBar && section === "left" && sectionWidgetIndex === 0) ? -Style.marginS : 0
    anchors.rightMargin: (!isVerticalBar && section === "right" && sectionWidgetIndex === sectionWidgetsCount - 1) ? -Style.marginS : 0
    anchors.topMargin: (isVerticalBar && section === "left" && sectionWidgetIndex === 0) ? -Style.marginM : 0
    anchors.bottomMargin: (isVerticalBar && section === "right" && sectionWidgetIndex === sectionWidgetsCount - 1) ? -Style.marginM : 0

    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    onEntered: {
      if ((windowTitle !== "") && isVerticalBar || (scrollingMode === "never")) {
        TooltipService.show(root, windowTitle, BarService.getTooltipDirection(root.screen?.name));
      }
    }
    onExited: {
      TooltipService.hide();
    }
    onClicked: mouse => {
                 if (mouse.button === Qt.RightButton) {
                   PanelService.showContextMenu(contextMenu, root, screen);
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
