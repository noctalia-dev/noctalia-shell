import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

NPopup {
  id: root
  modal: true
  dim: true
  anchors.centerIn: parent

  // Use a reasonable width/height relative to parent or fixed
  width: Math.min(600 * Style.uiScaleRatio, parent.width * 0.9)
  height: Math.min(contentLayout.implicitHeight + padding * 2, parent.height * 0.9)
  padding: Style.marginL

  property string hookLabel: ""
  property string hookDescription: ""
  property string hookPlaceholder: ""
  property string initialValue: ""

  signal saved(string newValue)
  signal test(string value)

  property var _savedSlot: null
  property var _testSlot: null

  background: Rectangle {
    color: Color.mSurface
    radius: Style.radiusL
    border.color: Color.mOutline
    border.width: Style.borderS
  }

  onOpened: {
    commandInput.text = initialValue;
    commandInput.forceActiveFocus();
  }

  contentItem: ColumnLayout {
    id: contentLayout
    spacing: Style.marginL

    // Header
    RowLayout {
      Layout.fillWidth: true
      NText {
        text: root.hookLabel
        font.weight: Style.fontWeightBold
        pointSize: Style.fontSizeL
        Layout.fillWidth: true
      }
      NIconButton {
        icon: "close"
        onClicked: root.close()
      }
    }

    // Description/Help
    NText {
      text: root.hookDescription
      color: Color.mOnSurfaceVariant
      wrapMode: Text.WordWrap
      Layout.fillWidth: true
    }

    // Input Area
    ColumnLayout {
      Layout.fillWidth: true
      spacing: Style.marginS

      NTextInput {
        id: commandInput
        Layout.fillWidth: true
        placeholderText: root.hookPlaceholder
        // Allow multiline? Hooks are usually oneline commands but can be scripts.
        // NTextInput is likely single line. Let's assume single line for now as per previous implementation.
      }
    }

    // Action Buttons
    RowLayout {
      Layout.fillWidth: true
      spacing: Style.marginM

      NButton {
        text: I18n.tr("common.test")
        icon: "caret-right"
        onClicked: root.test(commandInput.text)
        // Disable test if empty? Or maybe allow testing defined script.
        enabled: commandInput.text !== ""
      }

      Item {
        Layout.fillWidth: true
      } // Spacer

      NButton {
        text: I18n.tr("common.cancel")
        outlined: true
        onClicked: root.close()
      }

      NButton {
        text: I18n.tr("common.save")
        icon: "check"
        backgroundColor: Color.mPrimary
        textColor: Color.mOnPrimary
        onClicked: {
          root.saved(commandInput.text);
          root.close();
        }
      }
    }
  }
}
