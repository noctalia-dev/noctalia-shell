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
  property bool valueShowBackground: (widgetData && widgetData.showBackground !== undefined)
                                  ? widgetData.showBackground
                                  : (widgetMetadata ? widgetMetadata.showBackground : false)

  function saveSettings() {
    var settings = Object.assign({}, widgetData || {});
    Settings.data.desktopWidgets.countdownPlans = countdownPlans;
    settings.showBackground = valueShowBackground;
    return settings;
  }

  // Helper function to format a date as YYYY-MM-DD string
  function formatDate(date) {
    var year = date.getFullYear();
    var month = (date.getMonth() + 1).toString().padStart(2, '0');
    var day = date.getDate().toString().padStart(2, '0');
    return year + "-" + month + "-" + day;
  }

  // Helper function to format a time as HH:MM string
  function formatTime(date) {
    var hours = date.getHours().toString().padStart(2, '0');
    var minutes = date.getMinutes().toString().padStart(2, '0');
    return hours + ":" + minutes;
  }

  // Helper function to parse date string and create a local date object
  function parseLocalDate(dateStr, timeStr) {
    if (!dateStr || !timeStr) {
      return null;
    }

    // Check if timeStr includes seconds (HH:MM:SS format)
    var timeParts = timeStr.split(':');
    var hour = parseInt(timeParts[0]);
    var minute = parseInt(timeParts[1]);
    var seconds = timeParts.length > 2 ? parseInt(timeParts[2]) : 0;

    var year = parseInt(dateStr.substring(0, 4));
    var month = parseInt(dateStr.substring(5, 7)) - 1;  // Month is 0-indexed in JS
    var day = parseInt(dateStr.substring(8, 10));

    if (isNaN(year) || isNaN(month) || isNaN(day) || isNaN(hour) || isNaN(minute) || isNaN(seconds)) {
      Logger.w("CountdownSettings", "Invalid date or time format:", dateStr, timeStr);
      return null;
    }

    return new Date(year, month, day, hour, minute, seconds);
  }

  // Helper function to set default date and time (current time for datetime mode, current time + 1 minute for duration mode)
  function setDefaultDateTime() {
    var nd = new Date();
    var dateStr = root.formatDate(nd);
    var timeStr = root.formatTime(nd) + ":" + String(nd.getSeconds()).padStart(2, '0');
    return { dateStr: dateStr, timeStr: timeStr };
  }

  // Helper function to format target date for display
  function formatTargetDate(targetDate) {
    if (!targetDate) return "Invalid Date";
    try {
      var date = new Date(targetDate);
      if (isNaN(date.getTime())) {
        return "Invalid Date";
      }
      return root.formatDate(date);
    } catch (e) {
      Logger.w("CountdownSettings", "Error formatting date:", targetDate, e);
      return "Invalid Date";
    }
  }

  // Helper function to show error dialog
  function showErrorDialog(title, message) {
    // Create a simple error dialog using the same pattern as the edit dialog
    var dialogComponent = Qt.createQmlObject('
      import QtQuick
      import QtQuick.Layouts
      import qs.Widgets
      import qs.Commons

      Item {
        id: errorDialogRoot
        anchors.fill: parent

        Rectangle {
          id: errorDialogOverlay
          anchors.fill: parent
          color: "#66000000"

          MouseArea {
            anchors.fill: parent
            onClicked: errorDialogRoot.destroy()
          }

          Item {
            width: 400 * Style.uiScaleRatio
            height: 150
            anchors.centerIn: parent

            Rectangle {
              anchors.fill: parent
              radius: Style.radiusL
              color: Color.mSurface
              border.color: Color.mError
              border.width: 2
              focus: true
              Keys.onEscapePressed: errorDialogRoot.destroy()

              ColumnLayout {
                anchors.fill: parent
                anchors.margins: Style.marginL
                spacing: Style.marginS

                NText {
                  text: "' + title + '"
                  pointSize: Style.fontSizeL
                  font.weight: Style.fontWeightBold
                  color: Color.mError
                  Layout.alignment: Qt.AlignHCenter
                }

                NText {
                  text: "' + message + '"
                  pointSize: Style.fontSizeM
                  Layout.alignment: Qt.AlignHCenter
                  Layout.fillWidth: true
                  wrapMode: Text.WordWrap
                }

                NButton {
                  text: I18n.tr("settings.desktop-widgets.countdown.settings.dialog.ok")
                  Layout.alignment: Qt.AlignHCenter
                  onClicked: errorDialogRoot.destroy()
                }
              }
            }
          }
        }
      }', Overlay.overlay);

    if (dialogComponent) {
      // Dialog is handled in the component itself
    }
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
                text: modelData?.name || "Untitled Plan"
                elide: Text.ElideRight
                font.weight: Style.fontWeightBold
              }

              NText {
                text: {
                  if (modelData?.mode === "duration") {
                    // Calculate hours, minutes, and seconds from total duration
                    var totalSeconds = modelData?.totalDurationSeconds ||
                                      (modelData?.durationMinutes * 60 + (modelData?.durationSeconds || 0));
                    var hours = Math.floor(totalSeconds / 3600);
                    var minutes = Math.floor((totalSeconds % 3600) / 60);
                    var seconds = totalSeconds % 60;

                    var parts = [];
                    if (hours > 0) parts.push(hours + "h");
                    if (minutes > 0) parts.push(minutes + "m");
                    if (seconds > 0) parts.push(seconds + "s");

                    if (parts.length === 0) return "0s";
                    return parts.join(" ");
                  } else {
                    return root.formatTargetDate(modelData?.targetDate);
                  }
                }
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
      property string currentMode: "duration"


      function updateUiForMode(mode) {
        currentMode = mode;
        durationInputsContainer.visible = mode === "duration";
        datetimeInputs.visible = mode === "datetime";
      }

      Component.onCompleted: {
        // Set up the UI based on planData
        if (planData) {
          planNameInput.text = planData.name;
          modeInput.currentKey = planData.mode;

          // Handle duration in hours, minutes, seconds
          var totalDurationMinutes = planData.durationMinutes || 10;
          var totalDurationSeconds = planData.durationSeconds || 0; // If we store seconds separately

          // If duration is stored as total seconds, we can extract hours, minutes, seconds
          if (planData.totalDurationSeconds !== undefined) {
            // If stored as total seconds, convert back to h/m/s
            var totalSecs = planData.totalDurationSeconds;
            durationHoursInput.value = Math.floor(totalSecs / 3600);
            durationMinutesInput.value = Math.floor((totalSecs % 3600) / 60);
            durationSecondsInput.value = totalSecs % 60;
          } else {
            // Legacy: stored as minutes, convert to h/m/s
            durationHoursInput.value = Math.floor(totalDurationMinutes / 60);
            durationMinutesInput.value = totalDurationMinutes % 60;
            durationSecondsInput.value = totalDurationSeconds || 0;
          }

          if (planData.mode === "datetime" && planData.targetDate) {
            var d = new Date(planData.targetDate);
            if (!isNaN(d.getTime())) {
              var dateStr = root.formatDate(d);
              var timeStr = root.formatTime(d);
              dateInput.text = dateStr;
              timeInput.text = timeStr;
            } else {
              // Use default date and time if the targetDate is invalid
              var defaultDateTime = root.setDefaultDateTime();
              dateInput.text = defaultDateTime.dateStr;
              timeInput.text = defaultDateTime.timeStr;
            }
          } else {
            // For non-datetime mode or when no targetDate is provided, use default
            var defaultDateTime = root.setDefaultDateTime();
            dateInput.text = defaultDateTime.dateStr;
            timeInput.text = defaultDateTime.timeStr;
          }

          // Set the visibility based on the mode
          durationInputsContainer.visible = planData.mode === "duration";
          datetimeInputs.visible = planData.mode === "datetime";
        } else {
          // For new plan creation
          planNameInput.text = "";
          modeInput.currentKey = "duration";
          // Set default duration to 1 minute for better UX
          durationHoursInput.value = 0;
          durationMinutesInput.value = 1;
          durationSecondsInput.value = 0;

          var defaultDateTime = root.setDefaultDateTime();
          dateInput.text = defaultDateTime.dateStr;
          timeInput.text = defaultDateTime.timeStr;

          // Set the initial visibility for duration mode
          durationInputsContainer.visible = true;
          datetimeInputs.visible = false;
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

              ColumnLayout {
                id: durationInputsContainer
                Layout.fillWidth: true
                Layout.preferredHeight: visible ? implicitHeight : 0  // Only take space when visible
                visible: false  // Controlled by function
                spacing: Style.marginS

                NSpinBox {
                  id: durationHoursInput
                  Layout.fillWidth: true
                  label: I18n.tr("settings.desktop-widgets.countdown.settings.durationHoursLabel")
                  // description: I18n.tr("settings.desktop-widgets.countdown.settings.durationHoursDescription")
                  from: 0
                  to: 999  // Reasonable upper limit
                  value: 0
                }

                NSpinBox {
                  id: durationMinutesInput
                  Layout.fillWidth: true
                  label: I18n.tr("settings.desktop-widgets.countdown.settings.durationMinutesLabel")
                  // description: I18n.tr("settings.desktop-widgets.countdown.settings.durationMinutesDescription")
                  from: 0
                  to: 59  // Minutes: 0-59
                  value: 10
                }

                NSpinBox {
                  id: durationSecondsInput
                  Layout.fillWidth: true
                  label: I18n.tr("settings.desktop-widgets.countdown.settings.durationSecondsLabel")
                  // description: I18n.tr("settings.desktop-widgets.countdown.settings.durationSecondsDescription")
                  from: 0
                  to: 59  // Seconds: 0-59
                  value: 0
                }
              }

              ColumnLayout {
                id: datetimeInputs
                Layout.fillWidth: true
                Layout.preferredHeight: visible ? implicitHeight : 0  // Only take space when visible
                visible: false
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
                  placeholderText: I18n.tr("settings.desktop-widgets.countdown.settings.dialog.time.placeholder-seconds")
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
                    // Check if plan name is empty
                    if (!planNameInput.text || planNameInput.text.trim() === "") {
                      Logger.w("CountdownSettings", "Plan name is required");
                      // Show error message to user
                      showErrorDialog(
                        I18n.tr("settings.desktop-widgets.countdown.settings.dialog.error-title"),
                        I18n.tr("settings.desktop-widgets.countdown.settings.dialog.name-required")
                      );
                      return; // Don't proceed with saving
                    }

                    var selectedMode = dialogRoot.currentMode;

                    if (selectedMode === "duration") {
                      var totalDurationSeconds = (durationHoursInput.value * 3600) +
                                                (durationMinutesInput.value * 60) +
                                                durationSecondsInput.value;
                      var plan = {
                        name: planNameInput.text,
                        mode: selectedMode,
                        durationMinutes: Math.floor(totalDurationSeconds / 60), // Keep for backward compatibility
                        durationSeconds: totalDurationSeconds % 60,
                        totalDurationSeconds: totalDurationSeconds
                      };
                    } else if (selectedMode === "datetime") {
                      // Parse the input date and time
                      var localDate = root.parseLocalDate(dateInput.text, timeInput.text);

                      if (!localDate) {
                        Logger.w("CountdownSettings", "Invalid date or time input");
                        // Show error message to user - using a simple dialog
                        showErrorDialog(
                          I18n.tr("settings.desktop-widgets.countdown.settings.dialog.error-title"),
                          I18n.tr("settings.desktop-widgets.countdown.settings.dialog.invalid-date-time")
                        );
                        return; // Don't proceed with saving
                      }

                      // Validate the input strings before creating the plan
                      var isValidDateString = /^\d{4}-\d{2}-\d{2}$/.test(dateInput.text);

                      // Check time format and validate ranges
                      var timeMatch = timeInput.text.match(/^(\d{2}):(\d{2})(?::(\d{2}))?$/);
                      var isValidTimeString = !!timeMatch;

                      if (isValidTimeString) {
                          var hours = parseInt(timeMatch[1]);
                          var minutes = parseInt(timeMatch[2]);
                          var seconds = timeMatch[3] ? parseInt(timeMatch[3]) : 0;

                          // Validate ranges: 00-23 for hours, 00-59 for minutes and seconds
                          isValidTimeString = (hours >= 0 && hours <= 23) &&
                                              (minutes >= 0 && minutes <= 59) &&
                                              (seconds >= 0 && seconds <= 59);
                      }

                      if (!isValidDateString || !isValidTimeString) {
                        Logger.w("CountdownSettings", "Invalid date or time format in input fields");
                        // Show error message to user
                        showErrorDialog(
                          I18n.tr("settings.desktop-widgets.countdown.settings.dialog.error-title"),
                          I18n.tr("settings.desktop-widgets.countdown.settings.dialog.invalid-format")
                        );
                        return; // Don't proceed with saving
                      }

                      // Ensure the target date is in the future
                      var now = new Date();
                      if (localDate <= now) {
                        Logger.w("CountdownSettings", "Target date is in the past");
                        // Show error message to user
                        showErrorDialog(
                          I18n.tr("settings.desktop-widgets.countdown.settings.dialog.error-title"),
                          I18n.tr("settings.desktop-widgets.countdown.settings.dialog.past-date-error")
                        );
                        return; // Don't proceed with saving
                      }

                      var plan = {
                        name: planNameInput.text,
                        mode: selectedMode,
                        // Store as a format that preserves the local time meaning
                        // Format as YYYY-MM-DDTHH:mm[:ss] (without timezone conversion)
                        targetDate: dateInput.text + "T" + timeInput.text
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
