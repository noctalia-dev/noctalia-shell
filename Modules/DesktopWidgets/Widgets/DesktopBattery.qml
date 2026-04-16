import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Modules.DesktopWidgets
import qs.Services.Hardware
import qs.Services.UI
import qs.Widgets

DraggableDesktopWidget {
  id: root

  readonly property var widgetMetadata: DesktopWidgetRegistry.widgetMetadata["Battery"]
  readonly property string mode: (widgetData && widgetData.mode !== undefined) ? widgetData.mode : (widgetMetadata.mode !== undefined ? widgetMetadata.mode : "ring")
  readonly property string ringColor: (widgetData && widgetData.ringColor !== undefined) ? widgetData.ringColor : (widgetMetadata.ringColor !== undefined ? widgetMetadata.ringColor : "none")
  readonly property bool showPercentage: (widgetData && widgetData.showPercentage !== undefined) ? widgetData.showPercentage : (widgetMetadata.showPercentage !== undefined ? widgetMetadata.showPercentage : false)
  readonly property bool fullCircle: (widgetData && widgetData.fullCircle !== undefined) ? widgetData.fullCircle : (widgetMetadata.fullCircle !== undefined ? widgetMetadata.fullCircle : true)

  readonly property color activeRingColor: Color.resolveColorKey(ringColor)

  readonly property var allDevices: {
    let devices = BatteryService.laptopBatteries.filter(d => BatteryService.isDeviceReady(d));
    devices = devices.concat(BatteryService.peripheralBatteries);
    return devices;
  }

  function getItemColor(device) {
    if (ringColor !== "none")
      return activeRingColor;

    const charging = BatteryService.isCharging(device);
    const low = BatteryService.isLowBattery(device);
    const critical = BatteryService.isCriticalBattery(device);

    if (critical || low)
      return Color.mError;
    if (charging)
      return Color.mPrimary;
    return Color.mOnSurface;
  }

  function getIcon(device) {
    if (device.isLaptopBattery)
      return "device-laptop";
    return BatteryService.getDeviceIcon(device);
  }

  readonly property real contentPadding: Math.round(Style.marginM * widgetScale)
  implicitWidth: contentLoader.item ? Math.round((contentLoader.item.implicitWidth || contentLoader.item.width || 0) + contentPadding * 2) : 0
  implicitHeight: contentLoader.item ? Math.round((contentLoader.item.implicitHeight || contentLoader.item.height || 0) + contentPadding * 2) : 0
  width: implicitWidth
  height: implicitHeight

  Component {
    id: ringLayoutComponent
    Grid {
      id: ringGrid
      rows: 2
      flow: Grid.TopToBottom
      spacing: Math.round(Style.marginM * widgetScale)

      Repeater {
        // Limit to 4 devices max in ring mode
        model: root.allDevices.slice(0, 4)
        delegate: NCircleStat {
          readonly property color itemColor: root.getItemColor(modelData)
          ratio: BatteryService.getPercentage(modelData) / 100
          icon: root.getIcon(modelData)
          fillColor: itemColor
          contentScale: root.widgetScale
          showText: root.showPercentage
          fullCircle: root.fullCircle
          tooltipText: BatteryService.getDeviceName(modelData) + ": " + Math.round(ratio * 100) + "%"
        }
      }
    }
  }
  Component {
    id: listLayoutComponent
    ColumnLayout {
      id: listColumn
      spacing: Math.round(Style.marginS * widgetScale)

      Repeater {
        model: root.allDevices
        delegate: RowLayout {
          readonly property color itemColor: root.getItemColor(modelData)
          Layout.fillWidth: true
          spacing: Math.round(Style.marginM * widgetScale)

          NIcon {
            icon: root.getIcon(modelData)
            color: itemColor
            pointSize: Style.fontSizeM * root.widgetScale
          }

          NText {
            text: BatteryService.getDeviceName(modelData)
            color: Color.mOnSurface
            pointSize: Style.fontSizeS * root.widgetScale
            font.weight: Style.fontWeightRegular
            Layout.fillWidth: true
            elide: Text.ElideRight
          }

          NText {
            readonly property int percent: BatteryService.getPercentage(modelData)
            text: percent + "%"
            pointSize: Style.fontSizeS * root.widgetScale
            font.weight: Style.fontWeightBold
            font.family: Settings.data.ui.fontFixed
            color: itemColor
          }
        }
      }
    }
  }

  Loader {
    id: contentLoader
    anchors.centerIn: parent
    z: 2
    sourceComponent: mode === "list" ? listLayoutComponent : ringLayoutComponent
  }
}
