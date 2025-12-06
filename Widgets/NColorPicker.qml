import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

Rectangle {
  id: root

  property color selectedColor: Color.black

  signal colorSelected(color color)

  implicitWidth: 150
  implicitHeight: Math.round(Style.baseWidgetSize * 1.1)

  radius: Style.iRadiusM
  color: Color.mSurface
  border.color: Color.mOutline
  border.width: Style.borderS

  // Minimized Look
  MouseArea {
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    onClicked: {
      var dialog = Qt.createComponent("NColorPickerDialog.qml").createObject(root, {
                                                                               "selectedColor": selectedColor,
                                                                               "parent": Overlay.overlay
                                                                             });
      // Connect the dialog's signal to the picker's signal
      dialog.colorSelected.connect(function (color) {
        root.selectedColor = color;
        root.colorSelected(color);
      });

      dialog.open();
    }

    RowLayout {
      anchors.fill: parent
      anchors {
        leftMargin: Style.marginL
        rightMargin: Style.marginL
      }
      spacing: Style.marginS

      // Color preview circle
      Rectangle {
        Layout.preferredWidth: root.height * 0.6
        Layout.preferredHeight: root.height * 0.6
        radius: Math.min(Style.iRadiusL, Layout.preferredWidth / 2)
        color: root.selectedColor
        border.color: Color.mOutline
        border.width: Style.borderS
      }

      NText {
        text: root.selectedColor.toString().toUpperCase()
        family: Settings.data.ui.fontFixed
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignVCenter
      }

      NIcon {
        icon: "color-picker"
        color: Color.mOnSurfaceVariant
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignVCenter
      }
    }
  }
}
