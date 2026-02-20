import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Modules.Bar.Extras
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
  readonly property real barFontSize: Style.getBarFontSizeForScreen(screenName)
  readonly property var now: Time.now

  // Resolve settings: try user settings or defaults from BarWidgetRegistry
  readonly property string clockColor: widgetSettings.clockColor !== undefined ? widgetSettings.clockColor : widgetMetadata.clockColor
  readonly property bool useCustomFont: widgetSettings.useCustomFont !== undefined ? widgetSettings.useCustomFont : widgetMetadata.useCustomFont
  readonly property string customFont: widgetSettings.customFont !== undefined ? widgetSettings.customFont : widgetMetadata.customFont
  readonly property string formatHorizontal: widgetSettings.formatHorizontal !== undefined ? widgetSettings.formatHorizontal : widgetMetadata.formatHorizontal
  readonly property string formatVertical: widgetSettings.formatVertical !== undefined ? widgetSettings.formatVertical : widgetMetadata.formatVertical
  readonly property string tooltipFormat: widgetSettings.tooltipFormat !== undefined ? widgetSettings.tooltipFormat : widgetMetadata.tooltipFormat

  readonly property color textColor: Color.resolveColorKey(clockColor)

  // Content dimensions for implicit sizing
  readonly property real contentWidth: isBarVertical ? capsuleHeight : Math.round((isBarVertical ? verticalLoader.implicitWidth : horizontalLoader.implicitWidth) + Style.marginXL)
  readonly property real contentHeight: isBarVertical ? Math.round(verticalLoader.implicitHeight + Style.marginS * 2) : capsuleHeight

  // Size: use implicit width/height
  // BarWidgetLoader sets explicit width/height to extend click area
  implicitWidth: contentWidth
  implicitHeight: contentHeight

  // Visual clock capsule - stays at content size, centered in parent
  Rectangle {
    id: visualClock
    width: root.contentWidth
    height: root.contentHeight
    anchors.centerIn: parent

    radius: Style.radiusL
    color: Style.capsuleColor
    border.color: Style.capsuleBorderColor
    border.width: Style.capsuleBorderWidth

    Item {
      id: clockContainer
      anchors.centerIn: parent

      // Horizontal
      Loader {
        id: horizontalLoader
        active: !isBarVertical
        anchors.centerIn: parent
        sourceComponent: ColumnLayout {
          anchors.centerIn: parent
          spacing: Settings.data.bar.showCapsule ? -5 : -3
          Repeater {
            id: repeater
            model: I18n.locale.toString(now, formatHorizontal.trim()).split("\\n")
            NText {
              visible: text !== ""
              text: modelData
              family: useCustomFont && customFont ? customFont : Settings.data.ui.fontDefault
              Binding on pointSize {
                value: {
                  if (repeater.model.length == 1) {
                    // Single line: Full size
                    return barFontSize;
                  } else if (repeater.model.length == 2) {
                    // Two lines: First line is bigger than the second
                    return (index == 0) ? Math.round(barFontSize * 0.9) : Math.round(barFontSize * 0.75);
                  } else {
                    // More than two lines: Make it small!
                    return Math.round(barFontSize * 0.75);
                  }
                }
              }
              applyUiScale: false
              color: textColor
              wrapMode: Text.WordWrap
              Layout.alignment: Qt.AlignHCenter | Qt.AlignVCenter
            }
          }
        }
      }

      // Vertical
      Loader {
        id: verticalLoader
        active: isBarVertical
        anchors.centerIn: parent // Now this works without layout conflicts
        sourceComponent: ColumnLayout {
          anchors.centerIn: parent
          spacing: -2
          Repeater {
            model: I18n.locale.toString(now, formatVertical.trim()).split(" ")
            delegate: NText {
              visible: text !== ""
              text: modelData
              family: useCustomFont && customFont ? customFont : Settings.data.ui.fontDefault
              pointSize: barFontSize
              applyUiScale: false
              color: textColor
              wrapMode: Text.WordWrap
              Layout.alignment: Qt.AlignHCenter | Qt.AlignVCenter
            }
          }
        }
      }
    }
  }

  NPopupContextMenu {
    id: contextMenu

    model: [
      {
        "label": I18n.tr("actions.open-calendar"),
        "action": "open-calendar",
        "icon": "calendar"
      },
      {
        "label": I18n.tr("actions.widget-settings"),
        "action": "widget-settings",
        "icon": "settings"
      },
    ]

    onTriggered: action => {
                   // Close the context menu
                   contextMenu.close();
                   PanelService.closeContextMenu(screen);

                   if (action === "open-calendar") {
                     PanelService.getPanel("clockPanel", screen)?.toggle(root);
                   } else if (action === "widget-settings") {
                     BarService.openWidgetSettings(screen, section, sectionWidgetIndex, widgetId, widgetSettings);
                   }
                 }
  }

  // Build tooltip text with formatted time/date
  function buildTooltipText() {
    if (tooltipFormat && tooltipFormat.trim() !== "") {
      return I18n.locale.toString(now, tooltipFormat.trim());
    }
    // Fallback to default if no format is set
    return I18n.tr("common.calendar"); // Defaults to "Calendar"
  }

  MouseArea {
    id: clockMouseArea
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    onEntered: {
      if (!PanelService.getPanel("clockPanel", screen)?.isPanelOpen) {
        TooltipService.show(root, buildTooltipText(), BarService.getTooltipDirection(root.screen?.name));
        tooltipRefreshTimer.start();
      }
    }
    onExited: {
      tooltipRefreshTimer.stop();
      TooltipService.hide();
    }
    onClicked: mouse => {
                 TooltipService.hide();
                 if (mouse.button === Qt.RightButton) {
                   PanelService.showContextMenu(contextMenu, root, screen);
                 } else {
                   PanelService.getPanel("clockPanel", screen)?.toggle(this);
                 }
               }
  }

  Timer {
    id: tooltipRefreshTimer
    interval: 1000
    repeat: true
    onTriggered: {
      if (clockMouseArea.containsMouse && !PanelService.getPanel("clockPanel", screen)?.isPanelOpen) {
        TooltipService.updateText(buildTooltipText());
      }
    }
  }
}
