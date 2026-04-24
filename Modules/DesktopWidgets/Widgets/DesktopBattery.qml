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
  readonly property bool showPercentage: (widgetData && widgetData.showPercentage !== undefined) ? widgetData.showPercentage : (widgetMetadata.showPercentage !== undefined ? widgetMetadata.showPercentage : false)
  readonly property bool fullCircle: (widgetData && widgetData.fullCircle !== undefined) ? widgetData.fullCircle : (widgetMetadata.fullCircle !== undefined ? widgetMetadata.fullCircle : true)

  readonly property var all_batteries: {
    const pd = BatteryService.primaryDevice;
    const pb = BatteryService.peripheralBatteries;
    const batteries = BatteryService.isDeviceReady(pd) ? [pd] : [];
    return batteries.concat(pb);
  }

  function getItemColor(device) {
    const charging = BatteryService.isCharging(device);
    const low = BatteryService.isLowBattery(device);
    const critical = BatteryService.isCriticalBattery(device);

    if (critical || low) {
      return Color.mError;
    }
    if (charging) {
      return Color.mPrimary;
    }
    return Color.mOnSurface;
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
        model: root.all_batteries.slice(0, 4)
        delegate: NCircleStat {
          ratio: BatteryService.getPercentage(modelData) / 100
          icon: BatteryService.getDeviceIcon(modelData)
          fillColor: root.getItemColor(modelData)
          contentScale: root.widgetScale
          showText: root.showPercentage
          fullCircle: root.fullCircle
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
        model: root.all_batteries
        delegate: RowLayout {
          Layout.fillWidth: true
          spacing: Math.round(Style.marginM * widgetScale)

          NIcon {
            icon: BatteryService.getDeviceIcon(modelData)
            color: root.getItemColor(modelData)
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
            text: BatteryService.getPercentage(modelData) + "%"
            pointSize: Style.fontSizeS * root.widgetScale
            font.weight: Style.fontWeightBold
            font.family: Settings.data.ui.fontFixed
            color: root.getItemColor(modelData)
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
