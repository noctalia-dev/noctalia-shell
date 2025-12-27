import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Modules.DesktopWidgets
import qs.Widgets

DraggableDesktopWidget {
  id: root

  readonly property var now: Time.now

  property color clockTextColor: {
    if (usePrimaryColor) {
      return Color.mPrimary;
    }
    var txtColor = widgetData && widgetData.textColor ? widgetData.textColor : "";
    return (txtColor && txtColor !== "") ? txtColor : Color.mOnSurface;
  }
  property real fontSize: {
    var size = widgetData && widgetData.fontSize ? widgetData.fontSize : 0;
    return (size && size > 0) ? size : Style.fontSizeXXXL * 2.5;
  }
  property real widgetOpacity: (widgetData && widgetData.opacity) ? widgetData.opacity : 1.0
  property bool showSeconds: (widgetData && widgetData.showSeconds !== undefined) ? widgetData.showSeconds : true
  property bool showDate: (widgetData && widgetData.showDate !== undefined) ? widgetData.showDate : true
  property string clockStyle: (widgetData && widgetData.clockStyle) ? widgetData.clockStyle : "digital"
  property bool usePrimaryColor: (widgetData && widgetData.usePrimaryColor !== undefined) ? widgetData.usePrimaryColor : false
  property bool useCustomFont: (widgetData && widgetData.useCustomFont !== undefined) ? widgetData.useCustomFont : false
  property string customFont: (widgetData && widgetData.customFont) ? widgetData.customFont : ""
  property string format: (widgetData && widgetData.format) ? widgetData.format : "HH:mm\\nd MMMM yyyy"

  readonly property real contentPadding: clockStyle === "minimal" ? Style.marginL : Style.marginXL
  implicitWidth: contentLoader.item ? (contentLoader.item.implicitWidth || contentLoader.item.width || 0) + contentPadding * 2 : 0
  implicitHeight: contentLoader.item ? (contentLoader.item.implicitHeight || contentLoader.item.height || 0) + contentPadding * 2 : 0
  width: implicitWidth
  height: implicitHeight

  Component {
    id: nclockComponent
    NClock {
      now: root.now
      clockStyle: root.clockStyle
      backgroundColor: Color.transparent
      clockColor: clockTextColor
      progressColor: Color.mPrimary
      opacity: root.widgetOpacity
      height: Math.round(fontSize * 1.9)
      width: height
      hoursFontSize: fontSize * 0.6
      minutesFontSize: fontSize * 0.4
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
              return Style.fontSizeXXL;
            } else {
              return (index == 0) ? Style.fontSizeXXL : Style.fontSizeM;
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
