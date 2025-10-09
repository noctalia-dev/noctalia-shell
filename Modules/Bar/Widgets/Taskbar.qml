import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Quickshell.Wayland
import qs.Commons
import qs.Services
import qs.Widgets

Rectangle {
  id: root

  property ShellScreen screen
  property real scaling: 1.0

  // Widget properties passed from Bar.qml for per-instance settings
  property string widgetId: ""
  property string section: ""
  property int sectionWidgetIndex: -1
  property int sectionWidgetsCount: 0

  readonly property bool isVerticalBar: Settings.data.bar.position === "left" || Settings.data.bar.position === "right"
  readonly property bool compact: (Settings.data.bar.density === "compact")
  readonly property real itemSize: compact ? Style.capsuleHeight * 0.9 * scaling : Style.capsuleHeight * 0.8 * scaling

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

  // Always visible when there are toplevels
  implicitWidth: isVerticalBar ? Math.round(Style.capsuleHeight * scaling) : taskbarLayout.implicitWidth + Style.marginM * scaling * 2
  implicitHeight: isVerticalBar ? taskbarLayout.implicitHeight + Style.marginM * scaling * 2 : Math.round(Style.capsuleHeight * scaling)
  radius: Math.round(Style.radiusM * scaling)
  color: Settings.data.bar.showCapsule ? Color.mSurfaceVariant : Color.transparent

  GridLayout {
    id: taskbarLayout
    anchors.fill: parent
    anchors {
      leftMargin: isVerticalBar ? undefined : Style.marginM * scaling
      rightMargin: isVerticalBar ? undefined : Style.marginM * scaling
      topMargin: compact ? 0 : isVerticalBar ? Style.marginM * scaling : undefined
      bottomMargin: compact ? 0 : isVerticalBar ? Style.marginM * scaling : undefined
    }

    // Configure GridLayout to behave like RowLayout or ColumnLayout
    rows: isVerticalBar ? -1 : 1 // -1 means unlimited
    columns: isVerticalBar ? 1 : -1 // -1 means unlimited

    rowSpacing: isVerticalBar ? Style.marginXXS * root.scaling : 0
    columnSpacing: isVerticalBar ? 0 : Style.marginXXS * root.scaling

    Repeater {
      model: CompositorService.windows
      delegate: Item {
        id: taskbarItem
        required property var modelData
        property ShellScreen screen: root.screen

        visible: (!widgetSettings.onlySameOutput || modelData.output == screen.name) && (!widgetSettings.onlyActiveWorkspaces || CompositorService.getActiveWorkspaces().map(ws => ws.id).includes(modelData.workspaceId))

        Layout.preferredWidth: root.itemSize
        Layout.preferredHeight: root.itemSize
        Layout.alignment: Qt.AlignCenter

        IconImage {

          id: appIcon
          width: parent.width
          height: parent.height
          source: ThemeIcons.iconForAppId(taskbarItem.modelData.appId)
          smooth: true
          asynchronous: true
          opacity: modelData.isFocused ? Style.opacityFull : 0.6

          Rectangle {
            anchors.bottomMargin: -2 * scaling
            anchors.bottom: parent.bottom
            anchors.horizontalCenter: parent.horizontalCenter
            id: iconBackground
            width: 4 * scaling
            height: 4 * scaling
            color: modelData.isFocused ? Color.mPrimary : Color.transparent
            radius: width * 0.5
          }
        }

        MouseArea {
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          acceptedButtons: Qt.LeftButton | Qt.RightButton

          onPressed: function (mouse) {
            if (!taskbarItem.modelData)
              return

            if (mouse.button === Qt.LeftButton) {
              try {
                CompositorService.focusWindow(taskbarItem.modelData)
              } catch (error) {
                Logger.error("Taskbar", "Failed to activate toplevel: " + error)
              }
            } else if (mouse.button === Qt.RightButton) {
              try {
                CompositorService.closeWindow(taskbarItem.modelData)
              } catch (error) {
                Logger.error("Taskbar", "Failed to close toplevel: " + error)
              }
            }
          }
          onEntered: TooltipService.show(Screen, taskbarItem, taskbarItem.modelData.title || taskbarItem.modelData.appId || "Unknown app.", BarService.getTooltipDirection())
          onExited: TooltipService.hide()
        }
      }
    }
  }
}
