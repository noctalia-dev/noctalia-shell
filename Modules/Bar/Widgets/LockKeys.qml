import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Modules.Bar.Extras
import qs.Modules.Panels.Settings
import qs.Services.Keyboard
import qs.Services.UI
import qs.Widgets

Item {
  id: root

  property ShellScreen screen

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
  readonly property bool isVertical: barPosition === "left" || barPosition === "right"
  readonly property real capsuleHeight: Style.getCapsuleHeightForScreen(screenName)

  readonly property bool showCaps: (widgetSettings.showCapsLock !== undefined) ? widgetSettings.showCapsLock : widgetMetadata.showCapsLock
  readonly property bool showNum: (widgetSettings.showNumLock !== undefined) ? widgetSettings.showNumLock : widgetMetadata.showNumLock
  readonly property bool showScroll: (widgetSettings.showScrollLock !== undefined) ? widgetSettings.showScrollLock : widgetMetadata.showScrollLock

  readonly property string capsIcon: widgetSettings.capsLockIcon !== undefined ? widgetSettings.capsLockIcon : widgetMetadata.capsLockIcon
  readonly property string numIcon: widgetSettings.numLockIcon !== undefined ? widgetSettings.numLockIcon : widgetMetadata.numLockIcon
  readonly property string scrollIcon: widgetSettings.scrollLockIcon !== undefined ? widgetSettings.scrollLockIcon : widgetMetadata.scrollLockIcon

  readonly property bool hideWhenOff: (widgetSettings.hideWhenOff !== undefined) ? widgetSettings.hideWhenOff : (widgetMetadata.hideWhenOff !== undefined ? widgetMetadata.hideWhenOff : false)

  // Content dimensions for implicit sizing
  readonly property real contentWidth: isVertical ? capsuleHeight : Math.round(layout.implicitWidth + Style.marginXL)
  readonly property real contentHeight: isVertical ? Math.round(layout.implicitHeight + Style.marginXL) : capsuleHeight

  visible: !root.hideWhenOff || (root.showCaps && LockKeysService.capsLockOn) || (root.showNum && LockKeysService.numLockOn) || (root.showScroll && LockKeysService.scrollLockOn)

  implicitWidth: contentWidth
  implicitHeight: contentHeight

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

  // Visual capsule centered in parent
  Rectangle {
    id: visualCapsule
    width: root.contentWidth
    height: root.contentHeight
    anchors.centerIn: parent
    radius: Style.radiusM
    color: Style.capsuleColor
    border.color: Style.capsuleBorderColor
    border.width: Style.capsuleBorderWidth

    Item {
      id: layout
      anchors.verticalCenter: parent.verticalCenter
      anchors.horizontalCenter: parent.horizontalCenter

      implicitWidth: rowLayout.visible ? rowLayout.implicitWidth : colLayout.implicitWidth
      implicitHeight: rowLayout.visible ? rowLayout.implicitHeight : colLayout.implicitHeight

      RowLayout {
        id: rowLayout
        visible: !root.isVertical
        spacing: 0

        NIcon {
          visible: root.showCaps && (!root.hideWhenOff || LockKeysService.capsLockOn)
          icon: root.capsIcon
          color: LockKeysService.capsLockOn ? Color.mTertiary : Qt.alpha(Color.mOnSurfaceVariant, 0.3)
        }
        NIcon {
          visible: root.showNum && (!root.hideWhenOff || LockKeysService.numLockOn)
          icon: root.numIcon
          color: LockKeysService.numLockOn ? Color.mTertiary : Qt.alpha(Color.mOnSurfaceVariant, 0.3)
        }
        NIcon {
          visible: root.showScroll && (!root.hideWhenOff || LockKeysService.scrollLockOn)
          icon: root.scrollIcon
          color: LockKeysService.scrollLockOn ? Color.mTertiary : Qt.alpha(Color.mOnSurfaceVariant, 0.3)
        }
      }

      ColumnLayout {
        id: colLayout
        visible: root.isVertical
        spacing: 0

        NIcon {
          visible: root.showCaps && (!root.hideWhenOff || LockKeysService.capsLockOn)
          icon: root.capsIcon
          color: LockKeysService.capsLockOn ? Color.mTertiary : Qt.alpha(Color.mOnSurfaceVariant, 0.3)
        }
        NIcon {
          visible: root.showNum && (!root.hideWhenOff || LockKeysService.numLockOn)
          icon: root.numIcon
          color: LockKeysService.numLockOn ? Color.mTertiary : Qt.alpha(Color.mOnSurfaceVariant, 0.3)
        }
        NIcon {
          visible: root.showScroll && (!root.hideWhenOff || LockKeysService.scrollLockOn)
          icon: root.scrollIcon
          color: LockKeysService.scrollLockOn ? Color.mTertiary : Qt.alpha(Color.mOnSurfaceVariant, 0.3)
        }
      }
    }
  }

  // MouseArea at root level for extended click area
  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.RightButton
    onClicked: mouse => {
                 if (mouse.button === Qt.RightButton) {
                   PanelService.showContextMenu(contextMenu, root, screen);
                 }
               }
  }
}
