import QtQuick
import Quickshell
import Quickshell.Widgets
import QtQuick.Effects
import qs.Commons
import qs.Widgets
import qs.Services.UI

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
      var widgets = Settings.data.bar.widgets[section]
      if (widgets && sectionWidgetIndex < widgets.length) {
        return widgets[sectionWidgetIndex]
      }
    }
    return {}
  }

  readonly property string customIcon: widgetSettings.icon || widgetMetadata.icon
  readonly property bool useDistroLogo: (widgetSettings.useDistroLogo !== undefined) ? widgetSettings.useDistroLogo : widgetMetadata.useDistroLogo
  readonly property string customIconPath: widgetSettings.customIconPath || ""

  // If we have a custom path or distro logo, don't use the theme icon.
  icon: (customIconPath === "" && !useDistroLogo) ? customIcon : ""
  tooltipText: I18n.tr("tooltips.open-control-center")
  tooltipDirection: BarService.getTooltipDirection()
  baseSize: Style.capsuleHeight
  applyUiScale: false
  density: Settings.data.bar.density
  colorBg: (Settings.data.bar.showCapsule ? Color.mSurfaceVariant : Color.transparent)
  colorFg: Color.mOnSurface
  colorBgHover: useDistroLogo ? Color.mSurfaceVariant : Color.mHover
  colorBorder: Color.transparent
  colorBorderHover: useDistroLogo ? Color.mHover : Color.transparent
  onClicked: {
    var controlCenterPanel = PanelService.getPanel("controlCenterPanel", screen)
    if (Settings.data.controlCenter.position === "close_to_bar_button") {
      // Willopen the panel next to the bar button.
      controlCenterPanel?.toggle(this)
    } else {
      controlCenterPanel?.toggle()
    }
  }
  onRightClicked: PanelService.getPanel("settingsPanel", screen)?.toggle()
  onMiddleClicked: PanelService.getPanel("launcherPanel", screen)?.toggle()

  IconImage {
    id: customOrDistroLogo
    anchors.centerIn: parent
    width: root.width * 0.8
    height: width
    source: {
      if (customIconPath !== "")
        return customIconPath.startsWith("file://") ? customIconPath : "file://" + customIconPath
      if (useDistroLogo)
        return DistroService.osLogo
      return ""
    }
    visible: source !== ""
    smooth: true
    asynchronous: true
  }
}
