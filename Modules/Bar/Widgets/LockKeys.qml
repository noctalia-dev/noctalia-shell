import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Modules.Settings
import qs.Services
import qs.Widgets

//import qs.Modules.Bar.Extras
Rectangle {
  id: root

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

  readonly property string barPosition: Settings.data.bar.position
  readonly property bool isVertical: barPosition === "left" || barPosition === "right"

  readonly property string iconStyle: (widgetSettings.indicatorStyle !== undefined) ? widgetSettings.indicatorStyle : widgetMetadata.indicatorStyle
  readonly property bool showCaps: (widgetSettings.showCapsLock !== undefined) ? widgetSettings.showCapsLock : widgetMetadata.showCapsLock
  readonly property bool showNum: (widgetSettings.showNumLock !== undefined) ? widgetSettings.showNumLock : widgetMetadata.showNumLock
  readonly property bool showScroll: (widgetSettings.showScrollLock !== undefined) ? widgetSettings.showScrollLock : widgetMetadata.showScrollLock

  implicitWidth: isVertical ? Style.capsuleHeight : Math.round(layout.implicitWidth + Style.marginM * 2)
  implicitHeight: isVertical ? Math.round(layout.implicitHeight + Style.marginM * 2) : Style.capsuleHeight

  Layout.alignment: Qt.AlignVCenter

  radius: Style.radiusM
  color: Settings.data.bar.showCapsule ? Color.mSurfaceVariant : Color.transparent

  Item {
    id: layout
    anchors.verticalCenter: parent.verticalCenter
    anchors.horizontalCenter: parent.horizontalCenter

    implicitWidth: rowLayout.visible ? rowLayout.implicitWidth : colLayout.implicitWidth
    implicitHeight: rowLayout.visible ? rowLayout.implicitHeight : colLayout.implicitHeight

    readonly property var indicatorStyle: root.getIndicatorStyle(root.iconStyle)

    RowLayout {
      id: rowLayout
      visible: !root.isVertical
      spacing: 0

      NIcon {
        visible: root.showCaps
        icon: layout.indicatorStyle[0]
        color: LockKeysService.capsLockOn ? Color.mTertiary : Qt.alpha(Color.mOnSurfaceVariant, 0.3)
      }
      NIcon {
        visible: root.showNum
        icon: layout.indicatorStyle[1]
        color: LockKeysService.numLockOn ? Color.mTertiary : Qt.alpha(Color.mOnSurfaceVariant, 0.3)
      }
      NIcon {
        visible: root.showScroll
        icon: layout.indicatorStyle[2]
        color: LockKeysService.scrollLockOn ? Color.mTertiary : Qt.alpha(Color.mOnSurfaceVariant, 0.3)
      }
    }

    ColumnLayout {
      id: colLayout
      visible: root.isVertical
      spacing: 0

      NIcon {
        visible: root.showCaps
        icon: layout.indicatorStyle[0]
        color: LockKeysService.capsLockOn ? Color.mTertiary : Qt.alpha(Color.mOnSurfaceVariant, 0.3)
      }
      NIcon {
        visible: root.showNum
        icon: layout.indicatorStyle[1]
        color: LockKeysService.numLockOn ? Color.mTertiary : Qt.alpha(Color.mOnSurfaceVariant, 0.3)
      }
      NIcon {
        visible: root.showScroll
        icon: layout.indicatorStyle[2]
        color: LockKeysService.scrollLockOn ? Color.mTertiary : Qt.alpha(Color.mOnSurfaceVariant, 0.3)
      }
    }
  }

  function getIndicatorStyle(styleName) {
    switch (styleName) {
    case "large":
      return ["letter-c", "letter-n", "letter-s"]
    case "small":
      return ["letter-c-small", "letter-n-small", "letter-s-small"]
    case "square":
      return ["square-letter-c", "square-letter-n", "square-letter-s"]
    case "square-round":
      return ["square-rounded-letter-c", "square-rounded-letter-n", "square-rounded-letter-s"]
    case "circle":
      return ["circle-letter-c", "circle-letter-n", "circle-letter-s"]
    case "circle-dash":
      return ["circle-dashed-letter-c", "circle-dashed-letter-n", "circle-dashed-letter-s"]
    case "circle-dot":
      return ["circle-dotted-letter-c", "circle-dotted-letter-n", "circle-dotted-letter-s"]
    case "hex":
      return ["hexagon-letter-c", "hexagon-letter-n", "hexagon-letter-s"]
    default:
      return ["letter-c", "letter-n", "letter-s"]
    }
  }
}
