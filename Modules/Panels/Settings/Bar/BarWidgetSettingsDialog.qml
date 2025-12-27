import QtQuick
import QtQuick.Controls
import QtQuick.Effects
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

  width: Math.max(content.implicitWidth + padding * 2, 500)
  height: Math.min(content.implicitHeight + padding * 2, maxHeight)
  padding: Style.marginXL
  modal: true
  dim: false
  anchors.centerIn: parent

  onOpened: {
    // Load settings when popup opens with data
    if (widgetData && widgetId) {
      loadWidgetSettings();
    }
    // Request focus to ensure keyboard input works
    forceActiveFocus();
  }

  background: Rectangle {
    id: bgRect

    color: Color.mSurface
    radius: Style.radiusL
    border.color: Color.mPrimary
    border.width: Style.borderM
  }

  contentItem: FocusScope {
    id: focusScope
    focus: true

    ColumnLayout {
      id: content
      anchors.fill: parent
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
          tooltipText: I18n.tr("tooltips.close")
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

          // Settings based on widget type
          // Will be triggered via settingsLoader.setSource()
          Loader {
            id: settingsLoader
            Layout.fillWidth: true
            onLoaded: {
              // Try to focus the first focusable item in the loaded settings
              if (item) {
                Qt.callLater(() => {
                               var firstInput = findFirstFocusable(item);
                               if (firstInput) {
                                 firstInput.forceActiveFocus();
                               } else {
                                 focusScope.forceActiveFocus();
                               }
                             });
              }
            }

            function findFirstFocusable(item) {
              if (!item)
                return null;
              // Check if this item can accept focus
              if (item.focus !== undefined && item.focus === true)
                return item;
              // Check children
              if (item.children) {
                for (var i = 0; i < item.children.length; i++) {
                  var child = item.children[i];
                  if (child && child.focus !== undefined && child.focus === true)
                    return child;
                  var found = findFirstFocusable(child);
                  if (found)
                    return found;
                }
              }
              return null;
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
          text: I18n.tr("bar.widget-settings.dialog.cancel")
          outlined: true
          onClicked: root.close()
        }

        NButton {
          text: I18n.tr("bar.widget-settings.dialog.apply")
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
  }

  function loadWidgetSettings() {
    const source = BarWidgetRegistry.widgetSettingsMap[widgetId];
    if (source) {
      var currentWidgetData = widgetData;
      if (sectionId && widgetIndex >= 0) {
        var widgets = Settings.data.bar.widgets[sectionId];
        if (widgets && widgetIndex < widgets.length) {
          currentWidgetData = widgets[widgetIndex];
        }
      }
      settingsLoader.setSource(source, {
                                 "widgetData": currentWidgetData,
                                 "widgetMetadata": BarWidgetRegistry.widgetMetadata[widgetId]
                               });
    }
  }
}
