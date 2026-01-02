import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Services.UI
import qs.Widgets

ColumnLayout {
  id: root

  spacing: Style.marginL

  property list<var> entriesModel: []
  property list<var> entriesDefault: [
    {
      "id": "lock",
      "text": I18n.tr("session-menu.lock"),
      "enabled": true,
      "required": false
    },
    {
      "id": "suspend",
      "text": I18n.tr("session-menu.suspend"),
      "enabled": true,
      "required": false
    },
    {
      "id": "hibernate",
      "text": I18n.tr("session-menu.hibernate"),
      "enabled": true,
      "required": false
    },
    {
      "id": "reboot",
      "text": I18n.tr("session-menu.reboot"),
      "enabled": true,
      "required": false
    },
    {
      "id": "logout",
      "text": I18n.tr("session-menu.logout"),
      "enabled": true,
      "required": false
    },
    {
      "id": "shutdown",
      "text": I18n.tr("session-menu.shutdown"),
      "enabled": true,
      "required": false
    }
  ]

  function saveEntries() {
    var toSave = [];
    for (var i = 0; i < entriesModel.length; i++) {
      toSave.push({
                    "action": entriesModel[i].id,
                    "enabled": entriesModel[i].enabled,
                    "countdownEnabled": entriesModel[i].countdownEnabled !== undefined ? entriesModel[i].countdownEnabled : true,
                    "command": entriesModel[i].command || ""
                  });
    }
    Settings.data.sessionMenu.powerOptions = toSave;
  }

  function updateEntry(idx, properties) {
    var newModel = entriesModel.slice();
    newModel[idx] = Object.assign({}, newModel[idx], properties);
    entriesModel = newModel;
    saveEntries();
  }

  function reorderEntries(fromIndex, toIndex) {
    var newModel = entriesModel.slice();
    var item = newModel.splice(fromIndex, 1)[0];
    newModel.splice(toIndex, 0, item);
    entriesModel = newModel;
    saveEntries();
  }

  function openEntrySettingsDialog(index) {
    if (index < 0 || index >= entriesModel.length) {
      return;
    }

    var entry = entriesModel[index];
    var component = Qt.createComponent(Quickshell.shellDir + "/Modules/Panels/Settings/Tabs/SessionMenu/SessionMenuEntrySettingsDialog.qml");

    function instantiateAndOpen() {
      var dialog = component.createObject(Overlay.overlay, {
                                            "entryIndex": index,
                                            "entryData": entry,
                                            "entryId": entry.id,
                                            "entryText": entry.text
                                          });

      if (dialog) {
        dialog.updateEntryCommand.connect((idx, command) => {
                                            root.updateEntry(idx, {
                                                               "command": command
                                                             });
                                          });
        dialog.open();
      } else {
        Logger.e("SessionMenuTab", "Failed to create entry settings dialog");
      }
    }

    if (component.status === Component.Ready) {
      instantiateAndOpen();
    } else if (component.status === Component.Error) {
      Logger.e("SessionMenuTab", "Error loading entry settings dialog:", component.errorString());
    } else {
      component.statusChanged.connect(function () {
        if (component.status === Component.Ready) {
          instantiateAndOpen();
        } else if (component.status === Component.Error) {
          Logger.e("SessionMenuTab", "Error loading entry settings dialog:", component.errorString());
        }
      });
    }
  }

  Component.onCompleted: {
    entriesModel = [];

    // Add the entries available in settings
    for (var i = 0; i < Settings.data.sessionMenu.powerOptions.length; i++) {
      const settingEntry = Settings.data.sessionMenu.powerOptions[i];

      for (var j = 0; j < entriesDefault.length; j++) {
        if (settingEntry.action === entriesDefault[j].id) {
          var entry = entriesDefault[j];
          entry.enabled = settingEntry.enabled;
          // Default countdownEnabled to true for backward compatibility
          entry.countdownEnabled = settingEntry.countdownEnabled !== undefined ? settingEntry.countdownEnabled : true;
          // Load custom command if defined
          entry.command = settingEntry.command || "";
          entriesModel.push(entry);
        }
      }
    }

    // Add any missing entries from default
    for (var i = 0; i < entriesDefault.length; i++) {
      var found = false;
      for (var j = 0; j < entriesModel.length; j++) {
        if (entriesModel[j].id === entriesDefault[i].id) {
          found = true;
          break;
        }
      }

      if (!found) {
        var entry = entriesDefault[i];
        // Default countdownEnabled to true for new entries
        entry.countdownEnabled = true;
        // Default command to empty string for new entries
        entry.command = "";
        entriesModel.push(entry);
      }
    }

    saveEntries();
  }

  NHeader {
    label: I18n.tr("settings.session-menu.general.section.label")
    description: I18n.tr("settings.session-menu.general.section.description")
  }

  NToggle {
    Layout.fillWidth: true
    label: I18n.tr("settings.session-menu.large-buttons-style.label")
    description: I18n.tr("settings.session-menu.large-buttons-style.description")
    checked: Settings.data.sessionMenu.largeButtonsStyle
    onToggled: checked => Settings.data.sessionMenu.largeButtonsStyle = checked
  }

  NComboBox {
    visible: Settings.data.sessionMenu.largeButtonsStyle
    Layout.fillWidth: true
    label: I18n.tr("settings.session-menu.large-buttons-layout.label")
    description: I18n.tr("settings.session-menu.large-buttons-layout.description")
    model: [
      {
        "key": "grid",
        "name": I18n.tr("options.session-menu-grid-layout.grid")
      },
      {
        "key": "single-row",
        "name": I18n.tr("options.session-menu-grid-layout.single-row")
      }
    ]
    currentKey: Settings.data.sessionMenu.largeButtonsLayout
    isSettings: true
    defaultValue: Settings.getDefaultValue("sessionMenu.largeButtonsLayout")
    onSelected: key => Settings.data.sessionMenu.largeButtonsLayout = key
  }

  NToggle {
    Layout.fillWidth: true
    label: I18n.tr("settings.session-menu.show-number-labels.label")
    description: I18n.tr("settings.session-menu.show-number-labels.description")
    checked: Settings.data.sessionMenu.showNumberLabels !== false
    isSettings: true
    defaultValue: Settings.getDefaultValue("sessionMenu.showNumberLabels") ?? true
    onToggled: checked => Settings.data.sessionMenu.showNumberLabels = checked
  }

  NComboBox {
    label: I18n.tr("settings.session-menu.position.label")
    description: I18n.tr("settings.session-menu.position.description")
    Layout.fillWidth: true
    model: [
      {
        "key": "center",
        "name": I18n.tr("options.control-center.position.center")
      },
      {
        "key": "top_center",
        "name": I18n.tr("options.control-center.position.top_center")
      },
      {
        "key": "top_left",
        "name": I18n.tr("options.control-center.position.top_left")
      },
      {
        "key": "top_right",
        "name": I18n.tr("options.control-center.position.top_right")
      },
      {
        "key": "bottom_center",
        "name": I18n.tr("options.control-center.position.bottom_center")
      },
      {
        "key": "bottom_left",
        "name": I18n.tr("options.control-center.position.bottom_left")
      },
      {
        "key": "bottom_right",
        "name": I18n.tr("options.control-center.position.bottom_right")
      }
    ]
    currentKey: Settings.data.sessionMenu.position
    onSelected: key => Settings.data.sessionMenu.position = key
    visible: !Settings.data.sessionMenu.largeButtonsStyle
    isSettings: true
    defaultValue: Settings.getDefaultValue("sessionMenu.position")
  }

  NToggle {
    Layout.fillWidth: true
    label: I18n.tr("settings.session-menu.show-header.label")
    description: I18n.tr("settings.session-menu.show-header.description")
    checked: Settings.data.sessionMenu.showHeader
    onToggled: checked => Settings.data.sessionMenu.showHeader = checked
    visible: !Settings.data.sessionMenu.largeButtonsStyle
    isSettings: true
    defaultValue: Settings.getDefaultValue("sessionMenu.showHeader")
  }

  NToggle {
    Layout.fillWidth: true
    label: I18n.tr("settings.session-menu.enable-countdown.label")
    description: I18n.tr("settings.session-menu.enable-countdown.description")
    checked: Settings.data.sessionMenu.enableCountdown
    onToggled: checked => Settings.data.sessionMenu.enableCountdown = checked
    isSettings: true
    defaultValue: Settings.getDefaultValue("sessionMenu.enableCountdown")
  }

  ColumnLayout {
    visible: Settings.data.sessionMenu.enableCountdown
    spacing: Style.marginXXS
    Layout.fillWidth: true

    NLabel {
      label: I18n.tr("settings.session-menu.countdown-duration.label")
      description: I18n.tr("settings.session-menu.countdown-duration.description")
    }

    NValueSlider {
      Layout.fillWidth: true
      from: 1000
      to: 30000
      stepSize: 1000
      value: Settings.data.sessionMenu.countdownDuration
      onMoved: value => Settings.data.sessionMenu.countdownDuration = value
      text: Math.round(Settings.data.sessionMenu.countdownDuration / 1000) + "s"
      isSettings: true
      defaultValue: Settings.getDefaultValue("sessionMenu.countdownDuration")
    }
  }

  NDivider {
    Layout.fillWidth: true
    Layout.topMargin: Style.marginL
    Layout.bottomMargin: Style.marginL
  }

  // Entries Management Section
  ColumnLayout {
    spacing: Style.marginM
    Layout.fillWidth: true

    NHeader {
      label: I18n.tr("settings.session-menu.entries.section.label")
      description: I18n.tr("settings.session-menu.entries.section.description")
    }

    // List of items
    Item {
      Layout.fillWidth: true
      implicitHeight: listView.contentHeight

      ListView {
        id: listView
        anchors.fill: parent
        spacing: Style.marginS
        interactive: false
        clip: true
        model: entriesModel

        delegate: Item {
          id: delegateItem
          width: listView.width
          height: contentRow.height

          required property int index
          required property var modelData

          property bool dragging: false
          property int dragStartY: 0
          property int dragStartIndex: -1
          property int dragTargetIndex: -1

          Rectangle {
            anchors.fill: parent
            radius: Style.radiusM
            color: delegateItem.dragging ? Color.mSurfaceVariant : Color.transparent
            border.color: delegateItem.dragging ? Color.mOutline : Color.transparent
            border.width: Style.borderS

            Behavior on color {
              ColorAnimation {
                duration: Style.animationFast
              }
            }
          }

          RowLayout {
            id: contentRow
            width: parent.width
            spacing: Style.marginS

            // Drag handle
            Rectangle {
              Layout.preferredWidth: Style.baseWidgetSize * 0.7
              Layout.preferredHeight: Style.baseWidgetSize * 0.7
              Layout.alignment: Qt.AlignVCenter
              radius: Style.radiusXS
              color: dragHandleMouseArea.containsMouse ? Color.mSurfaceVariant : Color.transparent

              Behavior on color {
                ColorAnimation {
                  duration: Style.animationFast
                }
              }

              ColumnLayout {
                anchors.centerIn: parent
                spacing: 2

                Repeater {
                  model: 3
                  Rectangle {
                    Layout.preferredWidth: Style.baseWidgetSize * 0.28
                    Layout.preferredHeight: 2
                    radius: 1
                    color: Color.mOutline
                  }
                }
              }

              MouseArea {
                id: dragHandleMouseArea
                anchors.fill: parent
                cursorShape: Qt.SizeVerCursor
                hoverEnabled: true
                preventStealing: false
                z: 1000

                onPressed: mouse => {
                             delegateItem.dragStartIndex = delegateItem.index;
                             delegateItem.dragTargetIndex = delegateItem.index;
                             delegateItem.dragStartY = delegateItem.y;
                             delegateItem.dragging = true;
                             delegateItem.z = 999;
                             preventStealing = true;
                           }

                onPositionChanged: mouse => {
                                     if (delegateItem.dragging) {
                                       var dy = mouse.y - height / 2;
                                       var newY = delegateItem.y + dy;
                                       newY = Math.max(0, Math.min(newY, listView.contentHeight - delegateItem.height));
                                       delegateItem.y = newY;
                                       var targetIndex = Math.floor((newY + delegateItem.height / 2) / (delegateItem.height + Style.marginS));
                                       targetIndex = Math.max(0, Math.min(targetIndex, listView.count - 1));
                                       delegateItem.dragTargetIndex = targetIndex;
                                     }
                                   }

                onReleased: {
                  preventStealing = false;
                  if (delegateItem.dragStartIndex !== -1 && delegateItem.dragTargetIndex !== -1 && delegateItem.dragStartIndex !== delegateItem.dragTargetIndex) {
                    root.reorderEntries(delegateItem.dragStartIndex, delegateItem.dragTargetIndex);
                  }
                  delegateItem.dragging = false;
                  delegateItem.dragStartIndex = -1;
                  delegateItem.dragTargetIndex = -1;
                  delegateItem.z = 0;
                }

                onCanceled: {
                  preventStealing = false;
                  delegateItem.dragging = false;
                  delegateItem.dragStartIndex = -1;
                  delegateItem.dragTargetIndex = -1;
                  delegateItem.z = 0;
                }
              }
            }

            // Enable checkbox
            Rectangle {
              Layout.preferredWidth: Style.baseWidgetSize * 0.7
              Layout.preferredHeight: Style.baseWidgetSize * 0.7
              Layout.alignment: Qt.AlignVCenter
              radius: Style.radiusXS
              color: modelData.enabled ? Color.mPrimary : Color.mSurface
              border.color: Color.mOutline
              border.width: Style.borderS

              Behavior on color {
                ColorAnimation {
                  duration: Style.animationFast
                }
              }

              NIcon {
                visible: modelData.enabled
                anchors.centerIn: parent
                anchors.horizontalCenterOffset: -1
                icon: "check"
                color: Color.mOnPrimary
                pointSize: Math.max(Style.fontSizeXS, Style.baseWidgetSize * 0.35)
              }

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  root.updateEntry(index, {
                                     "enabled": !modelData.enabled
                                   });
                }
              }
            }

            // Label
            NText {
              Layout.fillWidth: true
              text: modelData.text
              color: Color.mOnSurface
              verticalAlignment: Text.AlignVCenter
              elide: Text.ElideRight
            }

            // Countdown toggle with icon (only shown when global countdown is enabled)
            RowLayout {
              visible: Settings.data.sessionMenu.enableCountdown
              spacing: Style.marginXS
              Layout.alignment: Qt.AlignVCenter

              NIcon {
                icon: "clock"
                color: Color.mOnSurfaceVariant
                pointSize: Style.fontSizeS
              }

              NToggle {
                checked: modelData.countdownEnabled !== undefined ? modelData.countdownEnabled : true
                onToggled: checked => root.updateEntry(delegateItem.index, {
                                                         "countdownEnabled": checked
                                                       })
              }
            }

            // Settings button (cogwheel)
            NIconButton {
              icon: "settings"
              tooltipText: I18n.tr("settings.session-menu.entry-settings.tooltip")
              baseSize: Style.baseWidgetSize * 0.7
              Layout.alignment: Qt.AlignVCenter
              onClicked: {
                openEntrySettingsDialog(delegateItem.index);
              }
            }
          }

          // Position binding for non-dragging state
          y: {
            if (delegateItem.dragging) {
              return delegateItem.y;
            }

            var draggedIndex = -1;
            var targetIndex = -1;
            for (var i = 0; i < listView.count; i++) {
              var item = listView.itemAtIndex(i);
              if (item && item.dragging) {
                draggedIndex = item.dragStartIndex;
                targetIndex = item.dragTargetIndex;
                break;
              }
            }

            if (draggedIndex !== -1 && targetIndex !== -1 && draggedIndex !== targetIndex) {
              var currentIndex = delegateItem.index;
              if (draggedIndex < targetIndex) {
                if (currentIndex > draggedIndex && currentIndex <= targetIndex) {
                  return (currentIndex - 1) * (delegateItem.height + Style.marginS);
                }
              } else {
                if (currentIndex >= targetIndex && currentIndex < draggedIndex) {
                  return (currentIndex + 1) * (delegateItem.height + Style.marginS);
                }
              }
            }

            return delegateItem.index * (delegateItem.height + Style.marginS);
          }

          Behavior on y {
            enabled: !delegateItem.dragging
            NumberAnimation {
              duration: Style.animationNormal
              easing.type: Easing.OutQuad
            }
          }
        }
      }
    }
  }

  NDivider {
    Layout.fillWidth: true
    Layout.topMargin: Style.marginL
    Layout.bottomMargin: Style.marginL
  }
}
