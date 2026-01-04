import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Modules.Panels.Settings
import qs.Services.System
import qs.Services.UI
import qs.Widgets

NIconButton {
  id: root

  property ShellScreen screen

  baseSize: Style.capsuleHeight
  applyUiScale: false
  customRadius: Style.radiusL
  colorBg: Settings.data.nightLight.forced ? Color.mPrimary : Style.capsuleColor
  colorFg: Settings.data.nightLight.forced ? Color.mOnPrimary : Color.mOnSurface
  colorBorder: Color.transparent
  colorBorderHover: Color.transparent
  border.color: Style.capsuleBorderColor
  border.width: Style.capsuleBorderWidth

  icon: Settings.data.nightLight.enabled ? (Settings.data.nightLight.forced ? "nightlight-forced" : "nightlight-on") : "nightlight-off"
  tooltipText: Settings.data.nightLight.enabled ? (Settings.data.nightLight.forced ? I18n.tr("tooltips.night-light-forced") : I18n.tr("tooltips.night-light-enabled")) : I18n.tr("tooltips.night-light-disabled")
  tooltipDirection: BarService.getTooltipDirection()
  onClicked: {
    // Check if wlsunset is available before enabling night light
    if (!ProgramCheckerService.wlsunsetAvailable) {
      ToastService.showWarning(I18n.tr("settings.display.night-light.section.label"), I18n.tr("toast.night-light.not-installed"));
      return;
    }

    if (!Settings.data.nightLight.enabled) {
      Settings.data.nightLight.enabled = true;
      Settings.data.nightLight.forced = false;
    } else if (Settings.data.nightLight.enabled && !Settings.data.nightLight.forced) {
      Settings.data.nightLight.forced = true;
    } else {
      Settings.data.nightLight.enabled = false;
      Settings.data.nightLight.forced = false;
    }
  }

  onRightClicked: {
    var settingsPanel = PanelService.getPanel("settingsPanel", screen);
    settingsPanel.requestedTab = SettingsPanel.Tab.Display;
    settingsPanel.open();
  }
}
