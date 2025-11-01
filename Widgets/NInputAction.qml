import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Widgets
import qs.Services

// Input and button row
RowLayout {
  id: root

  // Public properties
  property string label: ""
  property string description: ""
  property string placeholderText: ""
  property string text: ""
  property string actionButtonText: I18n.tr("placeholders.test")
  property string actionButtonIcon: "media-play"
  property bool actionButtonEnabled: text !== ""

  // Signals
  signal editingFinished
  signal actionClicked

  // Internal properties
  spacing: Style.marginM

  NTextInput {
    id: textInput
    label: root.label
    description: root.description
    placeholderText: root.placeholderText
    text: root.text
    onEditingFinished: {
      root.text = text
      root.editingFinished()
    }
    Layout.fillWidth: true
  }

  NButton {
    Layout.fillWidth: false
    Layout.alignment: Qt.AlignBottom

    text: root.actionButtonText
    icon: root.actionButtonIcon
    backgroundColor: Color.mSecondary
    textColor: Color.mOnSecondary
    hoverColor: Color.mHover
    enabled: root.actionButtonEnabled

    onClicked: {
      root.actionClicked()
    }
  }
}
