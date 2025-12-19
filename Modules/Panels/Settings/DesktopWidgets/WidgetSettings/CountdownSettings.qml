import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

ColumnLayout {
  id: root
  spacing: Style.marginM

  property var widgetData: null
  property var widgetMetadata: null

  property var countdownPlans: Settings.data.desktopWidgets.countdownPlans || []
  property int editIndex: -1
  property bool valueShowBackground: widgetData.showBackground !== undefined ? widgetData.showBackground : widgetMetadata.showBackground

  function saveSettings() {
    var settings = Object.assign({}, widgetData || {});
    Settings.data.desktopWidgets.countdownPlans = countdownPlans;
    settings.showBackground = valueShowBackground;
    return settings;
  }

  Component.onCompleted: {
    if (!Settings.data.desktopWidgets.countdownPlans)
      Settings.data.desktopWidgets.countdownPlans = [];
  }

  NHeader {
    label: I18n.tr("settings.desktop-widgets.countdown.settings.title.label")
    description: I18n.tr("settings.desktop-widgets.countdown.settings.title.description")
  }

  NToggle {
    Layout.fillWidth: true
    label: I18n.tr("settings.desktop-widgets.countdown.settings.show-background.label")
    description: I18n.tr("settings.desktop-widgets.countdown.settings.show-background.description")
    checked: valueShowBackground
    onToggled: checked => valueShowBackground = checked
  }

  NCollapsible {
    label: I18n.tr("settings.desktop-widgets.countdown.settings.presets.label")
    description: I18n.tr("settings.desktop-widgets.countdown.settings.presets.description")
    defaultExpanded: true

    ColumnLayout {
      spacing: Style.marginM

      NScrollView {
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.preferredHeight: 200

        ListView {
          id: listView
          model: countdownPlans
          spacing: Style.marginS
          clip: true

          delegate: Item {
            width: listView.width
            height: row.implicitHeight + Style.marginS

            Row {
              id: row
              spacing: Style.marginM
              anchors.verticalCenter: parent.verticalCenter

              NText {
                Layout.fillWidth: true
                text: modelData.name
                elide: Text.ElideRight
                font.weight: Style.fontWeightBold
              }

              NText {
                text: modelData.mode === "duration"
                      ? modelData.durationMinutes + " min"
                      : new Date(modelData.targetDate).toLocaleDateString()
                color: Color.mOnSurfaceVariant
              }

              NIconButton {
                icon: "edit"
                tooltipText: I18n.tr("settings.desktop-widgets.countdown.settings.edit-plan.tooltip")
                onClicked: {
                  root.editIndex = index;
                  root.openEditDialog(countdownPlans[index]);
                }
              }

              NIconButton {
                icon: "trash"
                tooltipText: I18n.tr("settings.desktop-widgets.countdown.settings.remove-plan.tooltip")
                onClicked: {
                  countdownPlans.splice(index, 1);
                  root.saveSettings();
                }
              }
            }
          }
        }
      }

      NButton {
        text: I18n.tr("settings.desktop-widgets.countdown.settings.add-new-preset.text")
        icon: "plus"
        Layout.fillWidth: true
        onClicked: {
          root.editIndex = -1;
          root.openEditDialog(null);
        }
      }
    }
  }




  Component {
    id: editDialogComponent

    Item {
      id: dialogRoot
      anchors.fill: parent


      property var planData: null
      property int editIndex: -1
      property string currentMode: "duration"  // 默认模式


      function updateUiForMode(mode) {
        currentMode = mode;  // 更新当前模式
        durationInput.visible = mode === "duration";
        datetimeInputs.visible = mode === "datetime";
      }

      Component.onCompleted: {
        if (planData) {

          planNameInput.text = planData.name;
          modeInput.currentKey = planData.mode;
          durationInput.value = planData.durationMinutes || 10;

          if (planData.mode === "datetime" && planData.targetDate) {
            var d = new Date(planData.targetDate);
            if (!isNaN(d.getTime())) {
              var dateStr = d.toISOString().substring(0, 10);
              var timeStr = Qt.formatTime(d, "hh:mm");
              dateInput.text = dateStr;
              timeInput.text = timeStr;
            } else {
              var nd = new Date();
              nd.setHours(nd.getHours() + 1);
              var dateStr = nd.toISOString().substring(0, 10);
              var timeStr = Qt.formatTime(nd, "hh:mm");
              dateInput.text = dateStr;
              timeInput.text = timeStr;
            }
          } else {
            var nd = new Date();
            nd.setHours(nd.getHours() + 1);
            var dateStr = nd.toISOString().substring(0, 10);
            var timeStr = Qt.formatTime(nd, "hh:mm");
            dateInput.text = dateStr;
            timeInput.text = timeStr;
          }

          updateUiForMode(planData.mode);
        } else {

          planNameInput.text = "";
          modeInput.currentKey = "duration";
          durationInput.value = 10;
          var nd = new Date();
          nd.setHours(nd.getHours() + 1);
          var dateStr = nd.toISOString().substring(0, 10);
          var timeStr = Qt.formatTime(nd, "hh:mm");
          dateInput.text = dateStr;
          timeInput.text = timeStr;

          updateUiForMode("duration");
        }
      }

      Rectangle {
        id: dialogOverlay
        anchors.fill: parent
        color: "#66000000"

        MouseArea {
          anchors.fill: parent
          onClicked: dialogRoot.destroy();
        }

        Item {
          width: 500 * Style.uiScaleRatio
          height: 400
          anchors.centerIn: parent

          Rectangle {
            anchors.fill: parent
            radius: Style.radiusL
            color: Color.mSurface
            border.color: Color.mOutline
            focus: true
            Keys.onEscapePressed: dialogRoot.destroy()

            ColumnLayout {
              anchors.fill: parent
              anchors.margins: Style.marginL
              spacing: Style.marginS

              NText {
                text: I18n.tr(editIndex > -1
                      ? "settings.desktop-widgets.countdown.settings.dialog.edit-title"
                      : "settings.desktop-widgets.countdown.settings.dialog.add-title")
                pointSize: Style.fontSizeL
                font.weight: Style.fontWeightBold
                Layout.alignment: Qt.AlignHCenter
              }

              NTextInput {
                id: planNameInput
                Layout.fillWidth: true
                label: I18n.tr("settings.desktop-widgets.countdown.settings.dialog.preset-name.label")
              }

              NComboBox {
                id: modeInput
                Layout.fillWidth: true
                label: I18n.tr("settings.desktop-widgets.countdown.settings.dialog.mode.label")
                model: [
                  { name: I18n.tr("settings.desktop-widgets.countdown.settings.modeDuration"), key: "duration" },
                  { name: I18n.tr("settings.desktop-widgets.countdown.settings.modeDatetime"), key: "datetime" }
                ]
              }

              Connections {
                target: modeInput
                function onSelected(key) {
                  updateUiForMode(key);
                }
              }

              NSpinBox {
                id: durationInput
                Layout.fillWidth: true
                label: I18n.tr("settings.desktop-widgets.countdown.settings.durationLabel")
                from: 1
                to: 525600
                visible: false  // 由函数控制
              }

              ColumnLayout {
                id: datetimeInputs
                Layout.fillWidth: true
                visible: false  // 由函数控制
                spacing: Style.marginS

                NTextInput {
                  id: dateInput
                  Layout.fillWidth: true
                  label: I18n.tr("settings.desktop-widgets.countdown.settings.dialog.date.label")
                  placeholderText: I18n.tr("settings.desktop-widgets.countdown.settings.dialog.date.placeholder")
                }

                NTextInput {
                  id: timeInput
                  Layout.fillWidth: true
                  label: I18n.tr("settings.desktop-widgets.countdown.settings.dialog.time.label")
                  placeholderText: I18n.tr("settings.desktop-widgets.countdown.settings.dialog.time.placeholder")
                }
              }

              RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: Style.marginM

                NButton {
                  text: I18n.tr("settings.desktop-widgets.countdown.settings.dialog.cancel.text")
                  Layout.fillWidth: true
                  onClicked: dialogRoot.destroy()
                }

                NButton {
                  text: I18n.tr("settings.desktop-widgets.countdown.settings.saveButton")
                  icon: "check"
                  Layout.fillWidth: true
                  onClicked: {
                    var selectedMode = dialogRoot.currentMode;

                    if (selectedMode === "duration") {
                      var plan = {
                        name: planNameInput.text,
                        mode: selectedMode,
                        durationMinutes: durationInput.value
                      };
                    } else if (selectedMode === "datetime") {
                      // Create date in user's local timezone
                      var year = parseInt(dateInput.text.substring(0, 4));
                      var month = parseInt(dateInput.text.substring(5, 7)) - 1; // JS months are 0-indexed
                      var day = parseInt(dateInput.text.substring(8, 10));
                      var hour = parseInt(timeInput.text.substring(0, 2));
                      var minute = parseInt(timeInput.text.substring(3, 5));

                      // Create a date object representing the user's local time
                      var localDate = new Date(year, month, day, hour, minute);

                      var plan = {
                        name: planNameInput.text,
                        mode: selectedMode,
                        // Store as a format that preserves the local time meaning
                        // Format as YYYY-MM-DDTHH:mm (without timezone conversion)
                        targetDate: dateInput.text + "T" + timeInput.text + ":00"
                      };
                    }

                    if (root.editIndex > -1)
                      root.countdownPlans[root.editIndex] = plan;
                    else
                      root.countdownPlans.push(plan);

                    root.saveSettings();
                    dialogRoot.destroy();
                  }
                }
              }
            }
          }
        }
      }
    }
  }




  function openEditDialog(plan) {

    var dialogData = {
      planData: plan,
      editIndex: root.editIndex
    };
    var dialogInstance = editDialogComponent.createObject(Overlay.overlay, dialogData);
    if (dialogInstance) {
      // Dialog is handled in the component itself
    }
  }
}
