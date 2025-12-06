import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import Quickshell
import Quickshell.Widgets
import qs.Commons
import qs.Modules.Bar.Extras
import qs.Services.System
import qs.Services.UI
import qs.Widgets

NIconButton {
  id: root

  property ShellScreen screen

  // Widget properties passed from Bar.qml for per-instance settings
  property string widgetId: ""
  property string section: ""
  property int sectionWidgetIndex: -1
  property int sectionWidgetsCount: 0

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

  readonly property string customIcon: widgetSettings.icon || widgetMetadata.icon
  readonly property bool useDistroLogo: (widgetSettings.useDistroLogo !== undefined) ? widgetSettings.useDistroLogo : widgetMetadata.useDistroLogo
  readonly property string customIconPath: widgetSettings.customIconPath || ""
  readonly property bool enableColorization: widgetSettings.enableColorization || false

  readonly property string colorizeSystemIcon: {
    if (widgetSettings.colorizeSystemIcon !== undefined)
      return widgetSettings.colorizeSystemIcon;
    return widgetMetadata.colorizeSystemIcon !== undefined ? widgetMetadata.colorizeSystemIcon : "none";
  }

  readonly property bool isColorizing: enableColorization && colorizeSystemIcon !== "none"

  readonly property color iconColor: {
    if (!isColorizing)
      return Color.mOnSurface;
    switch (colorizeSystemIcon) {
    case "primary":
      return Color.mPrimary;
    case "secondary":
      return Color.mSecondary;
    case "tertiary":
      return Color.mTertiary;
    case "error":
      return Color.mError;
    default:
      return Color.mOnSurface;
    }
  }
  readonly property color iconHoverColor: {
    if (!isColorizing)
      return Color.mOnHover;
    switch (colorizeSystemIcon) {
    case "primary":
      return Qt.darker(Color.mPrimary, 1.2);
    case "secondary":
      return Qt.darker(Color.mSecondary, 1.2);
    case "tertiary":
      return Qt.darker(Color.mTertiary, 1.2);
    case "error":
      return Qt.darker(Color.mError, 1.2);
    default:
      return Color.mOnHover;
    }
  }

  // If we have a custom path and not using distro logo, use the theme icon.
  // If using distro logo, don't use theme icon.
  icon: (customIconPath === "" && !useDistroLogo) ? customIcon : ""
  tooltipText: I18n.tr("tooltips.open-control-center")
  tooltipDirection: BarService.getTooltipDirection()
  baseSize: Style.capsuleHeight
  applyUiScale: false
  density: Settings.data.bar.density
  customRadius: Style.radiusL
  colorBg: Style.capsuleColor
  colorFg: iconColor
  colorBgHover: useDistroLogo ? Color.mSurfaceVariant : Color.mHover
  colorFgHover: iconHoverColor
  colorBorder: Color.transparent
  colorBorderHover: useDistroLogo ? Color.mHover : Color.transparent

  NPopupContextMenu {
    id: contextMenu

    model: [
      {
        "label": I18n.tr("context-menu.open-launcher"),
        "action": "open-launcher",
        "icon": "search"
      },
      {
        "label": I18n.tr("context-menu.open-settings"),
        "action": "open-settings",
        "icon": "adjustments"
      },
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

                   if (action === "open-launcher") {
                     PanelService.getPanel("launcherPanel", screen)?.toggle();
                   } else if (action === "open-settings") {
                     PanelService.getPanel("settingsPanel", screen)?.toggle();
                   } else if (action === "widget-settings") {
                     BarService.openWidgetSettings(screen, section, sectionWidgetIndex, widgetId, widgetSettings);
                   }
                 }
  }

  onClicked: {
    var controlCenterPanel = PanelService.getPanel("controlCenterPanel", screen);
    if (Settings.data.controlCenter.position === "close_to_bar_button") {
      // Will open the panel next to the bar button.
      controlCenterPanel?.toggle(this);
    } else {
      controlCenterPanel?.toggle();
    }
  }
  onRightClicked: {
    var popupMenuWindow = PanelService.getPopupMenuWindow(screen);
    if (popupMenuWindow) {
      popupMenuWindow.showContextMenu(contextMenu);
      const pos = BarService.getContextMenuPosition(root, contextMenu.implicitWidth, contextMenu.implicitHeight);
      contextMenu.openAtItem(root, pos.x, pos.y);
    }
  }
  onMiddleClicked: PanelService.getPanel("launcherPanel", screen)?.toggle()

  IconImage {
    id: customOrDistroLogo
    anchors.centerIn: parent
    width: root.width * 0.8
    height: width
    source: {
      if (useDistroLogo)
        return HostService.osLogo;
      if (customIconPath !== "")
        return customIconPath.startsWith("file://") ? customIconPath : "file://" + customIconPath;
      return "";
    }
    visible: source !== ""
    smooth: true
    asynchronous: true
    layer.enabled: isColorizing && (useDistroLogo || customIconPath !== "")
    layer.effect: ShaderEffect {
      property color targetColor: isColorizing ? iconColor : (Settings.data.colorSchemes.darkMode ? Color.mOnSurface : Color.mSurfaceVariant)
      property real colorizeMode: 2.0

      fragmentShader: Qt.resolvedUrl(Quickshell.shellDir + "/Shaders/qsb/appicon_colorize.frag.qsb")
    }
  }
}
