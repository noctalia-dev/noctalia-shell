import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

ColumnLayout {
  id: root
  Layout.fillWidth: true

  property alias text: input.text
  property alias placeholderText: input.placeholderText
  property string label: ""
  property string description: ""
  property string inputIconName: ""
  property alias buttonIcon: button.icon
  property alias buttonTooltip: button.tooltipText
  property alias buttonEnabled: button.enabled
  property real maximumWidth: 0

  signal buttonClicked
  signal inputTextChanged(string text)
  signal inputEditingFinished

  spacing: Style.marginS

  // Label and description
  NLabel {
    label: root.label
    description: root.description
    visible: root.label !== "" || root.description !== ""
    Layout.fillWidth: true
  }

  // Input field with button
  RowLayout {
    Layout.fillWidth: true
    spacing: Style.marginM

    NTextInput {
      id: input
      inputIconName: root.inputIconName
      Layout.fillWidth: true
      Layout.alignment: Qt.AlignVCenter
      enabled: root.enabled
      onTextChanged: root.inputTextChanged(text)
      onEditingFinished: root.inputEditingFinished()
    }

    // Button
    NIconButton {
      id: button
      baseSize: Style.baseWidgetSize
      onClicked: root.buttonClicked()
    }
  }
}
