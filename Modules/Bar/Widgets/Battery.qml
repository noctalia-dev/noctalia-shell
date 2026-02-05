import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.UPower
import qs.Commons
import qs.Modules.Bar.Extras
import qs.Services.Hardware
import qs.Services.Networking
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

  property var widgetMetadata: BarWidgetRegistry.widgetMetadata[widgetId]
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

  readonly property string barPosition: Settings.getBarPositionForScreen(screenName)
  readonly property bool isBarVertical: barPosition === "left" || barPosition === "right"
  readonly property real capsuleHeight: Style.getCapsuleHeightForScreen(screenName)

  readonly property string displayMode: widgetSettings.displayMode !== undefined ? widgetSettings.displayMode : widgetMetadata.displayMode
  readonly property bool useGraphicMode: displayMode === "graphic"

  readonly property bool hideIfNotDetected: widgetSettings.hideIfNotDetected !== undefined ? widgetSettings.hideIfNotDetected : widgetMetadata.hideIfNotDetected
  readonly property bool hideIfIdle: widgetSettings.hideIfIdle !== undefined ? widgetSettings.hideIfIdle : widgetMetadata.hideIfIdle

  // Check if selected device is actually present/connected
  readonly property bool isReady: BatteryService.isDeviceReady(selectedDevice)
  readonly property bool isPresent: BatteryService.isDevicePresent(selectedDevice)
  readonly property real percent: isReady ? BatteryService.getPercentage(selectedDevice) : -1
  readonly property bool isCharging: isReady ? BatteryService.isCharging(selectedDevice) : false
  readonly property bool isPluggedIn: isReady ? BatteryService.isPluggedIn(selectedDevice) : false
  readonly property bool isLowBattery: isReady ? BatteryService.isLowBattery(selectedDevice) : false
  readonly property bool isCriticalBattery: isReady ? BatteryService.isCriticalBattery(selectedDevice) : false

  // Visibility: show if hideIfNotDetected is false, or if battery is ready
  readonly property bool shouldShow: !hideIfNotDetected || (isReady && (hideIfIdle ? !isPluggedIn : true))
  readonly property string deviceNativePath: widgetSettings.deviceNativePath !== undefined ? widgetSettings.deviceNativePath : widgetMetadata.deviceNativePath
  readonly property var selectedDevice: BatteryService.isDevicePresent(BatteryService.findDevice(deviceNativePath)) ? BatteryService.findDevice(deviceNativePath) : null

  readonly property string tooltipText: {
    let lines = [];
    if (!isReady || !isPresent) {
      return I18n.tr("battery.no-battery-detected");
    }
    const isInternal = selectedDevice.isLaptopBattery;

    if (isInternal) {
      // Show charge percentage
      lines.push(`${I18n.tr("battery.battery-level")}: ${percent}%`);

      let timeText = BatteryService.getTimeRemainingText(selectedDevice);
      if (timeText) {
        lines.push(timeText);
      }

      let rateText = BatteryService.getRateText(selectedDevice);
      if (rateText) {
        lines.push(rateText);
      }

      // Show battery health if supported (check actual battery, not DisplayDevice)
      let healthDevice = selectedDevice.healthSupported ? selectedDevice : (BatteryService.laptopBatteries.length > 0 ? BatteryService.laptopBatteries[0] : null);
      if (healthDevice && healthDevice.healthSupported) {
        lines.push(`${I18n.tr("battery.battery-health")}: ${Math.round(healthDevice.healthPercentage)}%`);
      }
    } else if (selectedDevice) {
      // External / Peripheral Device (Phone, Keyboard, Mouse, Gamepad, Headphone etc.)
      let name = BatteryService.getDeviceName(selectedDevice);
      lines.push(`${name}: ${percent}%`);
    }

    // If we are showing the main laptop battery, append external devices
    if (isInternal) {
      var external = BatteryService.bluetoothBatteries;
      if (external.length > 0) {
        if (lines.length > 0)
          lines.push(""); // Separator
        for (var j = 0; j < external.length; j++) {
          var dev = external[j];
          var dName = BatteryService.getDeviceName(dev);
          var dPct = BatteryService.getPercentage(dev);
          lines.push(`${dName}: ${dPct}%`);
        }
      }
    }
    return lines.join("\n");
  }

  visible: shouldShow
  opacity: shouldShow ? 1.0 : 0.0

  implicitWidth: useGraphicMode ? capsule.width : pill.width
  implicitHeight: useGraphicMode ? capsule.height : pill.height

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

  // ==================== GRAPHIC MODE ====================

  // Capsule background (graphic mode only)
  Rectangle {
    id: capsule
    visible: root.useGraphicMode
    anchors.centerIn: nBattery
    width: root.isBarVertical ? root.capsuleHeight : nBattery.width + Style.marginS * 2
    height: root.isBarVertical ? nBattery.height + Style.marginS * 2 : root.capsuleHeight
    radius: Math.min(Style.radiusL, width / 2)
    color: graphicMouseArea.containsMouse ? Color.mHover : Style.capsuleColor
    border.color: Style.capsuleBorderColor
    border.width: Style.capsuleBorderWidth

    Behavior on color {
      enabled: !Color.isTransitioning
      ColorAnimation {
        duration: Style.animationFast
        easing.type: Easing.InOutQuad
      }
    }
  }

  NBattery {
    id: nBattery
    visible: root.useGraphicMode
    anchors.centerIn: parent
    baseSize: Style.barFontSize
    showPercentageText: true
    vertical: root.isBarVertical
    percentage: root.percent
    ready: root.isReady
    charging: root.isCharging
    pluggedIn: root.isPluggedIn
    low: root.isLowBattery || root.isCriticalBattery
    baseColor: graphicMouseArea.containsMouse ? Color.mOnHover : Color.mOnSurface
    textColor: graphicMouseArea.containsMouse ? Color.mHover : Color.mSurface
  }

  MouseArea {
    id: graphicMouseArea
    visible: root.useGraphicMode
    anchors.fill: parent
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    onEntered: {
      if (root.tooltipText) {
        TooltipService.show(root, root.tooltipText, BarService.getTooltipDirection(root.screen?.name));
      }
    }
    onExited: {
      TooltipService.hide();
    }
    onClicked: mouse => {
                 if (mouse.button === Qt.RightButton) {
                   PanelService.showContextMenu(contextMenu, nBattery, screen);
                 } else {
                   openBatteryPanel();
                 }
               }
  }

  // ==================== ICON MODE ====================

  BarPill {
    id: pill
    visible: !root.useGraphicMode
    screen: root.screen
    oppositeDirection: BarService.getPillDirection(root)
    icon: BatteryService.getIcon(root.percent, root.isCharging, root.isPluggedIn, root.isReady)
    text: root.isReady ? root.percent : "-"
    suffix: "%"
    autoHide: false
    forceOpen: root.isReady && root.displayMode === "icon-always"
    forceClose: root.displayMode === "icon-only" || !root.isReady
    customBackgroundColor: root.isCharging ? Color.mPrimary : ((root.isLowBattery || root.isCriticalBattery) ? Color.mError : "transparent")
    customTextIconColor: root.isCharging ? Color.mOnPrimary : ((root.isLowBattery || root.isCriticalBattery) ? Color.mOnError : "transparent")
    tooltipText: root.tooltipText

    onClicked: openBatteryPanel()
    onRightClicked: PanelService.showContextMenu(contextMenu, pill, screen)
  }

  // ==================== SHARED ====================

  function openBatteryPanel() {
    var panel = PanelService.getPanel("batteryPanel", screen);
    if (panel) {
      panel.panelID = {
        showPowerProfiles: widgetSettings.showPowerProfiles !== undefined ? widgetSettings.showPowerProfiles : widgetMetadata.showPowerProfiles,
        showNoctaliaPerformance: widgetSettings.showNoctaliaPerformance !== undefined ? widgetSettings.showNoctaliaPerformance : widgetMetadata.showNoctaliaPerformance
      };
      panel.toggle(root);
    }
  }
}
