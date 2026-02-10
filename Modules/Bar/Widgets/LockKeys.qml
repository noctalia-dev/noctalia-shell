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

//test
Item {
  id: root

  property ShellScreen screen
  property string widgetId: ""
  property string section: ""
  property int sectionWidgetIndex: -1
  property int sectionWidgetsCount: 0

  // Settings
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

  // Content dimensions for implicit sizing
  readonly property real contentWidth: isVertical ? capsuleHeight : Math.round(layout.implicitWidth + Style.marginXL)
  readonly property real contentHeight: isVertical ? Math.round(layout.implicitHeight + Style.marginXL) : capsuleHeight

  readonly property bool hideWhenOff: (widgetSettings.hideWhenOff !== undefined) ? widgetSettings.hideWhenOff : (widgetMetadata.hideWhenOff !== undefined ? widgetMetadata.hideWhenOff : false)

  readonly property string capsIcon: widgetSettings.capsLockIcon !== undefined ? widgetSettings.capsLockIcon : widgetMetadata.capsLockIcon
  readonly property string numIcon: widgetSettings.numLockIcon !== undefined ? widgetSettings.numLockIcon : widgetMetadata.numLockIcon
  readonly property string scrollIcon: widgetSettings.scrollLockIcon !== undefined ? widgetSettings.scrollLockIcon : widgetMetadata.scrollLockIcon
  readonly property bool showCaps: (widgetSettings.showCapsLock !== undefined) ? widgetSettings.showCapsLock : widgetMetadata.showCapsLock
  readonly property bool showNum: (widgetSettings.showNumLock !== undefined) ? widgetSettings.showNumLock : widgetMetadata.showNumLock
  readonly property bool showScroll: (widgetSettings.showScrollLock !== undefined) ? widgetSettings.showScrollLock : widgetMetadata.showScrollLock

  implicitHeight: contentHeight
  implicitWidth: contentWidth

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

    visible: !root.hideWhenOff || (root.showCaps && LockKeysService.capsLockOn) || (root.showNum && LockKeysService.numLockOn) || (root.showScroll && LockKeysService.scrollLockOn)
    anchors.centerIn: parent
    color: Style.capsuleColor
    width: root.contentWidth
    height: root.contentHeight
    radius: Style.radiusM
    border.color: Style.capsuleBorderColor
    border.width: Style.capsuleBorderWidth

    Item {
      id: layout

      anchors.horizontalCenter: parent.horizontalCenter
      anchors.verticalCenter: parent.verticalCenter
      implicitHeight: rowLayout.visible ? rowLayout.implicitHeight : colLayout.implicitHeight
      implicitWidth: rowLayout.visible ? rowLayout.implicitWidth : colLayout.implicitWidth

      RowLayout {
        id: rowLayout

        spacing: 0
        visible: !root.isVertical

        NIcon {
          color: LockKeysService.capsLockOn ? Color.mTertiary : Qt.alpha(Color.mOnSurfaceVariant, 0.3)
          icon: root.capsIcon
          visible: root.showCaps && (!root.hideWhenOff || LockKeysService.capsLockOn)
        }

        NIcon {
          color: LockKeysService.numLockOn ? Color.mTertiary : Qt.alpha(Color.mOnSurfaceVariant, 0.3)
          icon: root.numIcon
          visible: root.showNum && (!root.hideWhenOff || LockKeysService.numLockOn)
        }

        NIcon {
          color: LockKeysService.scrollLockOn ? Color.mTertiary : Qt.alpha(Color.mOnSurfaceVariant, 0.3)
          icon: root.scrollIcon
          visible: root.showScroll && (!root.hideWhenOff || LockKeysService.scrollLockOn)
        }
      }

      ColumnLayout {
        id: colLayout

        spacing: 0
        visible: root.isVertical

        NIcon {
          color: LockKeysService.capsLockOn ? Color.mTertiary : Qt.alpha(Color.mOnSurfaceVariant, 0.3)
          icon: root.capsIcon
          visible: root.showCaps && (!root.hideWhenOff || LockKeysService.capsLockOn)
        }

        NIcon {
          color: LockKeysService.numLockOn ? Color.mTertiary : Qt.alpha(Color.mOnSurfaceVariant, 0.3)
          icon: root.numIcon
          visible: root.showNum && (!root.hideWhenOff || LockKeysService.numLockOn)
        }

        NIcon {
          color: LockKeysService.scrollLockOn ? Color.mTertiary : Qt.alpha(Color.mOnSurfaceVariant, 0.3)
          icon: root.scrollIcon
          visible: root.showScroll && (!root.hideWhenOff || LockKeysService.scrollLockOn)
        }
      }
    }
  }

  // MouseArea at root level for extended click area
  MouseArea {
    acceptedButtons: Qt.RightButton
    anchors.fill: parent

    onClicked: mouse => {
                 if (mouse.button === Qt.RightButton) {
                   PanelService.showContextMenu(contextMenu, root, screen);
                 }
               }
  }
}
