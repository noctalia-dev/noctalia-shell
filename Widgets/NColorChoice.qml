import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Services.UI

RowLayout {
  id: root

  property string label: I18n.tr("common.select-color")
  property string description: I18n.tr("common.select-color-description")
  property string tooltip: ""
  property string currentKey: ""
  property var defaultValue: undefined
  property var noneColor: undefined      // color declared as var so we can nullify
  property var noneOnColor: undefined    // color declared as var so we can nullify

  readonly property bool isValueChanged: (defaultValue !== undefined) && (currentKey !== defaultValue)
  readonly property string indicatorTooltip: {
    I18n.tr("panels.indicator.default-value", {
              "value": defaultValue === "" ? "(empty)" : String(defaultValue)
            });
  }

  readonly property int diameter: Style.baseWidgetSize * 0.9 * Style.uiScaleRatio

  signal selected(string key)

  NLabel {
    label: root.label
    description: root.description
    showIndicator: root.isValueChanged
    indicatorTooltip: root.indicatorTooltip
  }

  RowLayout {
    id: colourRow

    opacity: enabled ? 1.0 : 0.6
    Layout.minimumWidth: root.diameter * Color.colorKeyModel.length

    Repeater {
      model: Color.colorKeyModel

      Rectangle {
        id: colorCircle

        property bool isSelected: root.currentKey === modelData.key
        property bool isHovered: circleMouseArea.containsMouse

        Layout.alignment: Qt.AlignHCenter
        implicitWidth: root.diameter
        implicitHeight: root.diameter
        radius: root.diameter * 0.5
        color: (modelData.key === "none" && root.noneColor !== undefined) ? root.noneColor : Color.resolveColorKey(modelData.key)
        border.color: (isSelected || isHovered) ? Color.mOnSurface : Color.mOutline
        border.width: Style.borderM

        MouseArea {
          id: circleMouseArea

          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onEntered: TooltipService.show(parent, modelData.name)
          onExited: TooltipService.hide()
          onClicked: {
            root.currentKey = modelData.key;
            root.selected(modelData.key);
          }
        }

        NIcon {
          anchors.centerIn: parent
          icon: "check"
          pointSize: Math.max(Style.fontSizeXS, colorCircle.width * 0.4)
          color: (modelData.key === "none" && root.noneOnColor !== undefined) ? root.noneOnColor : Color.resolveOnColorKey(modelData.key)
          font.weight: Style.fontWeightBold
          visible: colorCircle.isSelected
        }

        Behavior on border.color {
          ColorAnimation {
            duration: Style.animationFast
          }
        }
      }
    }

    // Custom hex color slot — opens NColorPickerDialog, stores "#rrggbb" in currentKey
    Rectangle {
      id: customSlot
      readonly property bool isHex: root.currentKey && root.currentKey.length > 0 && root.currentKey.charAt(0) === "#"
      property bool isHovered: customMouseArea.containsMouse

      Layout.alignment: Qt.AlignHCenter
      implicitWidth: root.diameter
      implicitHeight: root.diameter
      radius: root.diameter * 0.5
      color: isHex ? root.currentKey : "transparent"
      border.color: (isHex || isHovered) ? Color.mOnSurface : Color.mOutline
      border.width: Style.borderM

      Rectangle {
        visible: !customSlot.isHex
        anchors.fill: parent
        anchors.margins: Style.borderM
        radius: width * 0.5
        gradient: Gradient {
          orientation: Gradient.Horizontal
          GradientStop { position: 0.0; color: "#ed8796" }
          GradientStop { position: 0.5; color: "#a6da95" }
          GradientStop { position: 1.0; color: "#8aadf4" }
        }
      }

      MouseArea {
        id: customMouseArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onEntered: TooltipService.show(parent, I18n.tr("common.custom-color"))
        onExited: TooltipService.hide()
        onClicked: {
          customColorDialog.selectedColor = customSlot.isHex ? root.currentKey : Color.resolveColorKey(root.currentKey);
          customColorDialog.open();
        }
      }

      NIcon {
        anchors.centerIn: parent
        icon: "check"
        pointSize: Math.max(Style.fontSizeXS, customSlot.width * 0.4)
        color: Color.mOnSurface
        font.weight: Style.fontWeightBold
        visible: customSlot.isHex
      }
    }

    NColorPickerDialog {
      id: customColorDialog
      onColorSelected: function(c) {
        var hex = "#"
          + Math.round(c.r * 255).toString(16).padStart(2, "0")
          + Math.round(c.g * 255).toString(16).padStart(2, "0")
          + Math.round(c.b * 255).toString(16).padStart(2, "0");
        root.currentKey = hex;
        root.selected(hex);
      }
    }
  }
}
