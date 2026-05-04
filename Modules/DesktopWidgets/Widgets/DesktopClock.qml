import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Modules.DesktopWidgets
import qs.Services.UI
import qs.Widgets

DraggableDesktopWidget {
  id: root

  readonly property var now: Time.now
  readonly property var widgetMetadata: DesktopWidgetRegistry.widgetMetadata["Clock"]

  readonly property color clockTextColor: Color.resolveColorKey(clockColor)
  readonly property real fontSize: Math.round(Style.fontSizeXXXL * 2.5 * widgetScale)
  readonly property real widgetOpacity: widgetData.opacity !== undefined ? widgetData.opacity : 1.0
  readonly property string clockStyle: widgetData.clockStyle !== undefined ? widgetData.clockStyle : widgetMetadata.clockStyle
  readonly property string clockColor: widgetData.clockColor !== undefined ? widgetData.clockColor : widgetMetadata.clockColor
  readonly property bool useCustomFont: widgetData.useCustomFont !== undefined ? widgetData.useCustomFont : widgetMetadata.useCustomFont
  readonly property string customFont: widgetData.customFont !== undefined ? widgetData.customFont : widgetMetadata.customFont
  readonly property string format: widgetData.format !== undefined ? widgetData.format : widgetMetadata.format

  readonly property real contentPadding: Math.round((clockStyle === "minimal" ? Style.marginL : Style.marginXL) * widgetScale)
  implicitWidth: contentLoader.item ? Math.round((contentLoader.item.implicitWidth || contentLoader.item.width || 0) + contentPadding * 2) : 0
  implicitHeight: contentLoader.item ? Math.round((contentLoader.item.implicitHeight || contentLoader.item.height || 0) + contentPadding * 2) : 0
  width: implicitWidth
  height: implicitHeight

  Component {
    id: nclockComponent
    NClock {
      now: root.now
      clockStyle: root.clockStyle
      backgroundColor: "transparent"
      clockColor: clockTextColor
      progressColor: Color.mPrimary
      opacity: root.widgetOpacity
      height: Math.round(fontSize * 1.9)
      width: height
      hoursFontSize: fontSize * 0.6
      minutesFontSize: fontSize * 0.4
      scaleRatio: root.widgetScale
    }
  }

  Component {
    id: minimalClockComponent
    ColumnLayout {
      spacing: -2
      opacity: root.widgetOpacity

      Repeater {
        model: I18n.locale.toString(root.now, root.format.trim()).split("\\n")
        delegate: NText {
          visible: text !== ""
          text: modelData
          family: root.useCustomFont && root.customFont ? root.customFont : Settings.data.ui.fontDefault
          pointSize: {
            if (model.length == 1) {
              return Math.round(Style.fontSizeXXL * root.widgetScale);
            } else {
              return Math.round((index == 0) ? Style.fontSizeXXL * root.widgetScale : Style.fontSizeM * root.widgetScale);
            }
          }
          font.weight: Style.fontWeightBold
          color: root.clockTextColor
          wrapMode: Text.WordWrap
          Layout.alignment: Qt.AlignHCenter
        }
      }
    }
  }

  Loader {
    id: contentLoader
    anchors.centerIn: parent
    z: 2
    sourceComponent: clockStyle === "minimal" ? minimalClockComponent : nclockComponent
  }
}
