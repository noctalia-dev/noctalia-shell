import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

// Session Menu Entry Settings Dialog Component
Popup {
  id: root

  property int entryIndex: -1
  property var entryData: null
  property string entryId: ""
  property string entryText: ""

  signal updateEntryCommand(int index, string command)

  // Default commands mapping
  readonly property var defaultCommands: {
    "lock": I18n.tr("panels.session-menu.entry-settings-default-command-lock"),
    "suspend": "systemctl suspend || loginctl suspend",
    "hibernate": "systemctl hibernate || loginctl hibernate",
    "reboot": "systemctl reboot || loginctl reboot",
    "logout": I18n.tr("panels.session-menu.entry-settings-default-command-logout"),
    "shutdown": "systemctl poweroff || loginctl poweroff"
  }

  readonly property string defaultCommand: defaultCommands[entryId] || ""

  width: Math.max(content.implicitWidth + padding * 2, 500)
  height: content.implicitHeight + padding * 2
  padding: Style.marginXL
  modal: true
  dim: false
  anchors.centerIn: parent

  onOpened: {
    // Load command when popup opens
    if (entryData) {
      commandInput.text = entryData.command || "";
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
        Layout.fillWidth: true

        NText {
          text: I18n.tr("panels.session-menu.entry-settings-title", {
                          "entry": root.entryText
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
        Layout.fillWidth: true
        Layout.preferredHeight: 1
        color: Color.mOutline
      }

      // Command input
      NTextInput {
        id: commandInput
        Layout.fillWidth: true
        label: I18n.tr("common.command")
        description: I18n.tr("panels.session-menu.entry-settings-command-description")
        placeholderText: I18n.tr("panels.session-menu.entry-settings-command-placeholder")
        onEditingFinished: {
          // Auto-focus on Enter
          applyButton.forceActiveFocus();
        }
        Keys.onReturnPressed: {
          applyButton.clicked();
        }
        Keys.onEnterPressed: {
          applyButton.clicked();
        }
      }

      // Default command info
      ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.marginXS

        NLabel {
          label: I18n.tr("panels.session-menu.entry-settings-default-info-label")
          description: I18n.tr("panels.session-menu.entry-settings-default-info-description")
          Layout.fillWidth: true
        }

        // Default command display
        Rectangle {
          Layout.fillWidth: true
          Layout.preferredHeight: defaultCommandText.implicitHeight + Style.marginM * 2
          radius: Style.radiusM
          color: Color.mSurfaceVariant
          border.color: Color.mOutline
          border.width: Style.borderS

          RowLayout {
            anchors.fill: parent
            anchors.margins: Style.marginM
            spacing: Style.marginS

            NIcon {
              icon: "info-circle"
              color: Color.mOnSurfaceVariant
              pointSize: Style.fontSizeM
            }

            NText {
              id: defaultCommandText
              Layout.fillWidth: true
              text: root.defaultCommand
              color: Color.mOnSurfaceVariant
              font.family: "monospace"
              font.pointSize: Style.fontSizeS
              wrapMode: Text.Wrap
            }
          }
        }
      }

      // Action buttons
      RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: Style.marginM
        spacing: Style.marginM

        Item {
          Layout.fillWidth: true
        }

        NButton {
          id: cancelButton
          text: I18n.tr("common.cancel")
          outlined: true
          onClicked: root.close()
        }

        NButton {
          id: applyButton
          text: I18n.tr("common.apply")
          icon: "check"
          onClicked: {
            root.updateEntryCommand(root.entryIndex, commandInput.text);
            root.close();
          }
        }
      }
    }
  }
}
