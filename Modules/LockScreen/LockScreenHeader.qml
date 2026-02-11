import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Services.System
import qs.Widgets

// Time, Date, and User Profile Container
Rectangle {
  id: root

  readonly property bool animationsEnabled: Settings.data.general.lockScreenAnimations || false

  // Use timer-driven properties instead of Time.now to avoid per-frame repaints.
  // Time.now updates every frame (~60+ Hz); these update only when needed.
  property date currentTime: new Date()
  property date currentDate: new Date()

  Timer {
    interval: 1000
    running: true
    repeat: true
    onTriggered: root.currentTime = new Date()
  }

  Timer {
    interval: 60000
    running: true
    repeat: true
    onTriggered: root.currentDate = new Date()
  }

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
          running: root.animationsEnabled
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
          running: root.animationsEnabled
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
            "ko": "yyyy년 M월 d일 dddd",
            "ku": "dddd, dê MMMM",
            "nl": "dddd d MMMM",
            "nn": "dddd d. MMMM",
            "pt": "dddd, d 'de' MMMM",
            "sv": "dddd d MMMM",
            "zh": "yyyy年M月d日 dddd"
          };
          var dateString = I18n.locale.toString(root.currentDate, formats[lang] || "dddd, d MMMM");
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
    Item {
      Layout.preferredWidth: Settings.data.general.clockStyle === "analog" ? 70 : (Settings.data.general.clockStyle === "custom" ? 90 : 70)
      Layout.preferredHeight: Settings.data.general.clockStyle === "analog" ? 70 : (Settings.data.general.clockStyle === "custom" ? 90 : 70)
      Layout.alignment: Qt.AlignVCenter

      // Analog Clock
      NClock {
        anchors.centerIn: parent
        width: 70
        height: 70
        visible: Settings.data.general.clockStyle === "analog"
        now: root.currentTime
        clockStyle: "analog"
        backgroundColor: "transparent"
        clockColor: Color.mOnSurface
        secondHandColor: Color.mPrimary
      }

      // Digital Clock (Standard)
      NClock {
        anchors.centerIn: parent
        width: 70
        height: 70
        visible: Settings.data.general.clockStyle === "digital"
        now: root.currentTime
        clockStyle: "digital"
        showProgress: true
        progressColor: Color.mPrimary
        backgroundColor: "transparent"
        clockColor: Color.mOnSurface
        hoursFontSize: Style.fontSizeL
        minutesFontSize: Style.fontSizeL
        hoursFontWeight: Style.fontWeightBold
        minutesFontWeight: Style.fontWeightBold
      }

      // Custom Clock (Stacked)
      ColumnLayout {
        anchors.centerIn: parent
        visible: Settings.data.general.clockStyle === "custom"
        spacing: -3

        Repeater {
          model: I18n.locale.toString(root.currentTime, (Settings.data.general.clockFormat || "hh\\nmm").replace(/\\n/g, "\n")).split("\n")
          NText {
            text: modelData
            pointSize: Style.fontSizeL
            font.weight: Style.fontWeightBold
            color: Color.mOnSurface
            horizontalAlignment: Text.AlignHCenter
            Layout.alignment: Qt.AlignHCenter
          }
        }
      }
    }
  }
}
