import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Services.System
import qs.Widgets

// Time, Date, and User Profile Container
Rectangle {
  id: root
  width: Math.max(500, contentRow.implicitWidth + 32)
  height: Math.max(120, contentRow.implicitHeight + 32)
  anchors.horizontalCenter: parent.horizontalCenter
  anchors.top: parent.top
  anchors.topMargin: 100
  radius: Style.radiusL
  color: Color.mSurface
  border.color: Qt.alpha(Color.mOutline, 0.2)
  border.width: Style.borderS

  RowLayout {
    id: contentRow
    anchors.fill: parent
    anchors.margins: Style.marginL
    spacing: Style.marginXL * 2

    // Left side: Avatar
    Rectangle {
      Layout.preferredWidth: 70
      Layout.preferredHeight: 70
      Layout.alignment: Qt.AlignVCenter
      radius: width / 2
      color: "transparent"

      Rectangle {
        anchors.fill: parent
        radius: parent.radius
        color: "transparent"
        border.color: Qt.alpha(Color.mPrimary, 0.8)
        border.width: Style.borderM

        SequentialAnimation on border.color {
          loops: Animation.Infinite
          ColorAnimation {
            to: Qt.alpha(Color.mPrimary, 1.0)
            duration: 2000
            easing.type: Easing.InOutQuad
          }
          ColorAnimation {
            to: Qt.alpha(Color.mPrimary, 0.8)
            duration: 2000
            easing.type: Easing.InOutQuad
          }
        }
      }

      NImageRounded {
        anchors.centerIn: parent
        width: 66
        height: 66
        radius: width / 2
        imagePath: Settings.preprocessPath(Settings.data.general.avatarImage)
        fallbackIcon: "person"

        SequentialAnimation on scale {
          loops: Animation.Infinite
          NumberAnimation {
            to: 1.02
            duration: 4000
            easing.type: Easing.InOutQuad
          }
          NumberAnimation {
            to: 1.0
            duration: 4000
            easing.type: Easing.InOutQuad
          }
        }
      }
    }

    // Center: User Info Column (left-aligned text)
    ColumnLayout {
      Layout.alignment: Qt.AlignVCenter
      spacing: Style.marginXXS

      // Welcome back + Username on one line
      NText {
        text: I18n.tr("system.welcome-back") + " " + HostService.displayName + "!"
        pointSize: Style.fontSizeXXL
        color: Color.mOnSurface
        horizontalAlignment: Text.AlignLeft
      }

      // Date below
      NText {
        text: {
          var lang = I18n.locale.name.split("_")[0];
          var formats = {
            "de": "dddd, d. MMMM",
            "en": "dddd, MMMM d",
            "es": "dddd, d 'de' MMMM",
            "fr": "dddd d MMMM",
            "hu": "dddd, MMMM d.",
            "ja": "yyyy年M月d日 dddd",
            "ku": "dddd, dê MMMM",
            "nl": "dddd d MMMM",
            "pt": "dddd, d 'de' MMMM",
            "zh": "yyyy年M月d日 dddd"
          };
          var dateString = I18n.locale.toString(Time.now, formats[lang] || "dddd, d MMMM");
          return dateString.charAt(0).toUpperCase() + dateString.slice(1);
        }
        pointSize: Style.fontSizeXL
        color: Color.mOnSurfaceVariant
        horizontalAlignment: Text.AlignLeft
      }
    }

    // Spacer to push time to the right
    Item {
      Layout.fillWidth: true
    }

    // Clock
    NClock {
      now: Time.now
      clockStyle: Settings.data.location.analogClockInCalendar ? "analog" : "digital"
      Layout.preferredWidth: 70
      Layout.preferredHeight: 70
      Layout.alignment: Qt.AlignVCenter
      backgroundColor: Color.mSurface
      clockColor: Color.mOnSurface
      secondHandColor: Color.mPrimary
      hoursFontSize: Style.fontSizeL
      minutesFontSize: Style.fontSizeL
    }
  }
}
