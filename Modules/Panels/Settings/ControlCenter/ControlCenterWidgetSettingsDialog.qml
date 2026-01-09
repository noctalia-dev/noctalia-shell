import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Services.UI
import qs.Widgets

// Widget Settings Dialog Component
Popup {
  id: root

  property int widgetIndex: -1
  property var widgetData: null
  property string widgetId: ""
  property string sectionId: ""

  signal updateWidgetSettings(string section, int index, var settings)

  // Helper function to find screen from parent chain
  function findScreen() {
    var item = parent;
    while (item) {
      if (item.screen !== undefined) {
        return item.screen;
      }
      item = item.parent;
    }
    return null;
  }

  readonly property var screen: findScreen()
  readonly property real maxHeight: screen ? screen.height * 0.9 : (parent ? parent.height * 0.9 : 800)
  readonly property real defaultContentWidth: Math.round(600 * Style.uiScaleRatio)
  readonly property real settingsContentWidth: {
    if (settingsLoader.item && settingsLoader.item.implicitWidth > 0) {
      return settingsLoader.item.implicitWidth;
    }
    return defaultContentWidth;
  }

  readonly property real dialogPadding: Style.marginXL
  width: Math.max(settingsContentWidth + dialogPadding * 2, 500)
  height: Math.min(content.implicitHeight + dialogPadding * 2, maxHeight)
  padding: 0
  modal: true
  anchors.centerIn: parent

  onOpened: {
    if (widgetData && widgetId) {
      loadWidgetSettings();
    }
  }

  background: Rectangle {
    color: Color.mSurface
    radius: Style.radiusL
    border.color: Color.mPrimary
    border.width: Style.borderM
  }

  contentItem: ColumnLayout {
    id: content
    anchors.fill: parent
    anchors.margins: dialogPadding
    spacing: Style.marginM

    // Title
    RowLayout {
      id: titleRow
      Layout.fillWidth: true
      Layout.preferredHeight: implicitHeight

      NText {
        text: I18n.tr("system.widget-settings-title", {
                        "widget": root.widgetId
                      })
        pointSize: Style.fontSizeL
        font.weight: Style.fontWeightBold
        color: Color.mPrimary
        Layout.fillWidth: true
      }

      NIconButton {
        icon: "close"
        tooltipText: I18n.tr("common.close")
        onClicked: root.close()
      }
    }

    // Separator
    Rectangle {
      id: separator
      Layout.fillWidth: true
      Layout.preferredHeight: 1
      color: Color.mOutline
    }

    // Scrollable settings area
    NScrollView {
      id: scrollView
      Layout.fillWidth: true
      Layout.fillHeight: true
      Layout.minimumHeight: 100

      ColumnLayout {
        width: scrollView.width
        spacing: Style.marginM

        Loader {
          id: settingsLoader
          Layout.fillWidth: true
          onItemChanged: {
            if (item) {
              // Force width recalculation when content loads
              Qt.callLater(() => {
                             root.width = Math.max(root.settingsContentWidth + root.dialogPadding * 2, 500);
                           });
            }
          }
        }
      }
    }

    // Action buttons
    RowLayout {
      id: buttonRow
      Layout.fillWidth: true
      Layout.topMargin: Style.marginM
      Layout.preferredHeight: implicitHeight
      spacing: Style.marginM

      Item {
        Layout.fillWidth: true
      }

      NButton {
        text: I18n.tr("common.cancel", "Cancel")
        outlined: true
        onClicked: root.close()
      }

      NButton {
        text: I18n.tr("common.apply", "Apply")
        icon: "check"
        onClicked: {
          if (settingsLoader.item && settingsLoader.item.saveSettings) {
            var newSettings = settingsLoader.item.saveSettings();
            root.updateWidgetSettings(root.sectionId, root.widgetIndex, newSettings);
            root.close();
          }
        }
      }
    }
  }

  function loadWidgetSettings() {
    const widgetSettingsMap = {
      "CustomButton": "WidgetSettings/CustomButtonSettings.qml"
    };

    const source = widgetSettingsMap[widgetId];
    if (source) {
      settingsLoader.setSource(source, {
                                 "widgetData": widgetData,
                                 "widgetMetadata": ControlCenterWidgetRegistry.widgetMetadata[widgetId]
                               });
    }
  }
}
