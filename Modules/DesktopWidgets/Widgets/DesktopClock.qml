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

  // Direct access to settings like bar widgets do - this ensures reactivity
  property var widgetSettings: {
    if (screen && screen.name && widgetIndex >= 0) {
      var monitorWidgets = Settings.data.desktopWidgets.monitorWidgets || [];
      for (var i = 0; i < monitorWidgets.length; i++) {
        if (monitorWidgets[i].name === screen.name) {
          var widgets = monitorWidgets[i].widgets || [];
          if (widgetIndex < widgets.length) {
            return widgets[widgetIndex];
          }
          break;
        }
      }
    }
    return {};
  }

  property var widgetMetadata: DesktopWidgetRegistry.widgetMetadata["Clock"]

  readonly property color clockTextColor: {
    if (usePrimaryColor) {
      return Color.mPrimary;
    }
    var txtColor = widgetData && widgetData.textColor ? widgetData.textColor : "";
    return (txtColor && txtColor !== "") ? txtColor : Color.mOnSurface;
  }
  readonly property real fontSize: {
    var size = widgetData && widgetData.fontSize ? widgetData.fontSize : 0;
    return (size && size > 0) ? size : Style.fontSizeXXXL * 2.5;
  }
  readonly property real widgetOpacity: (widgetSettings.opacity !== undefined) ? widgetSettings.opacity : 1.0
  readonly property bool showSeconds: (widgetSettings.showSeconds !== undefined) ? widgetSettings.showSeconds : true
  readonly property bool showDate: (widgetSettings.showDate !== undefined) ? widgetSettings.showDate : true
  readonly property string clockStyle: (widgetSettings.clockStyle !== undefined) ? widgetSettings.clockStyle : (widgetMetadata.clockStyle !== undefined ? widgetMetadata.clockStyle : "digital")
  readonly property bool usePrimaryColor: (widgetSettings.usePrimaryColor !== undefined) ? widgetSettings.usePrimaryColor : (widgetMetadata.usePrimaryColor !== undefined ? widgetMetadata.usePrimaryColor : false)
  readonly property bool useCustomFont: (widgetSettings.useCustomFont !== undefined) ? widgetSettings.useCustomFont : (widgetMetadata.useCustomFont !== undefined ? widgetMetadata.useCustomFont : false)
  readonly property string customFont: (widgetSettings.customFont !== undefined) ? widgetSettings.customFont : ""
  readonly property string format: (widgetSettings.format !== undefined) ? widgetSettings.format : (widgetMetadata.format !== undefined ? widgetMetadata.format : "HH:mm\\nd MMMM yyyy")

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
