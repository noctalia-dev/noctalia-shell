import QtQuick
import Quickshell
import Quickshell.Widgets
import qs.Commons
import qs.Modules.Panels.Settings
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

  property var widgetMetadata: BarWidgetRegistry.widgetMetadata[widgetId] ?? {}
  // Explicit screenName property ensures reactive binding when screen changes
  readonly property string screenName: screen ? screen.name : ""
  property var widgetSettings: {
    if (section && sectionWidgetIndex >= 0 && screenName) {
      var widgets = Settings.getBarWidgetsForScreen(screenName)[section];
      if (widgets && sectionWidgetIndex < widgets.length) {
        return widgets[sectionWidgetIndex];
      }
    }
    return {};
  }

  readonly property string customIcon: widgetSettings.icon || (widgetMetadata ? widgetMetadata.icon : "rocket")
  readonly property bool useDistroLogo: widgetSettings.useDistroLogo !== undefined ? widgetSettings.useDistroLogo : widgetMetadata.useDistroLogo
  readonly property string customIconPath: widgetSettings.customIconPath !== undefined ? widgetSettings.customIconPath : widgetMetadata.customIconPath
  readonly property bool enableColorization: widgetSettings.enableColorization !== undefined ? widgetSettings.enableColorization : widgetMetadata.enableColorization
  readonly property string colorizeSystemIcon: widgetSettings.colorizeSystemIcon !== undefined ? widgetSettings.colorizeSystemIcon : widgetMetadata.colorizeSystemIcon

  readonly property color iconColor: {
    if (!enableColorization)
      return Color.mOnSurface;
    return Color.resolveColorKey(colorizeSystemIcon);
  }

  // If we have a custom path or are using distro logo, don't show the theme icon.
  icon: (customIconPath === "" && !useDistroLogo) ? customIcon : ""
  tooltipText: I18n.tr("actions.open-launcher")
  tooltipDirection: BarService.getTooltipDirection(screenName)
  baseSize: Style.getCapsuleHeightForScreen(screenName)
  applyUiScale: false
  customRadius: Style.radiusL
  colorBg: Style.capsuleColor
  colorFg: iconColor
  colorBgHover: Color.mHover
  colorFgHover: Color.mOnHover
  colorBorder: Style.capsuleBorderColor
  colorBorderHover: Style.capsuleBorderColor

  NPopupContextMenu {
    id: contextMenu

    model: [
      {
        "label": I18n.tr("actions.launcher-settings"),
        "action": "launcher-settings",
        "icon": "adjustments"
      },
      {
        "label": I18n.tr("actions.widget-settings"),
        "action": "widget-settings",
        "icon": "settings"
      }
    ]

    onTriggered: action => {
                   contextMenu.close();
                   PanelService.closeContextMenu(screen);

                   if (action === "launcher-settings") {
                     var panel = PanelService.getPanel("settingsPanel", screen);
                     panel.requestedTab = SettingsPanel.Tab.Launcher;
                     panel.toggle();
                   } else if (action === "widget-settings") {
                     BarService.openWidgetSettings(screen, section, sectionWidgetIndex, widgetId, widgetSettings);
                   }
                 }
  }

  onClicked: PanelService.toggleLauncher(screen)
  onMiddleClicked: PanelService.toggleLauncher(screen)
  onRightClicked: {
    PanelService.showContextMenu(contextMenu, root, screen);
  }

  IconImage {
    id: customOrDistroLogo
    anchors.centerIn: parent
    width: root.buttonSize * 0.8
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
    layer.enabled: (enableColorization) && (useDistroLogo || customIconPath !== "")
    layer.effect: ShaderEffect {
      property color targetColor: !hovering ? iconColor : Color.mOnHover
      property real colorizeMode: 2.0

      fragmentShader: Qt.resolvedUrl(Quickshell.shellDir + "/Shaders/qsb/appicon_colorize.frag.qsb")
    }
  }
}
