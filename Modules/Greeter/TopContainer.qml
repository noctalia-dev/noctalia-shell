import QtQuick
import QtQuick.Layouts

import qs.Commons
import qs.Widgets
import qs.Modules.Bar.Calendar

Rectangle {
  id: root

  required property string userName

  width: Math.max(500, contentRow.implicitWidth + 32)
  height: Math.max(120, contentRow.implicitHeight + 32)

  radius: Style.radiusL
  color: Color.mSurface
  border.color: Qt.alpha(Color.mOutline, 0.2)
  border.width: 1

  RowLayout {
    id: contentRow
    anchors.fill: parent
    anchors.margins: 16
    spacing: 32

    // Left side: Avatar
    Rectangle {
      Layout.preferredWidth: 70
      Layout.preferredHeight: 70
      Layout.alignment: Qt.AlignVCenter
      radius: width * 0.5
      color: Color.transparent

      Rectangle {
        anchors.fill: parent
        radius: parent.radius
        color: Color.transparent
        border.color: Qt.alpha(Color.mPrimary, 0.8)
        border.width: 2

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

      NImageCircled {
        anchors.centerIn: parent
        width: 66
        height: 66
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
      spacing: 2

      // Welcome back + Username on one line
      NText {
        text: I18n.tr("lock-screen.welcome-back") + " " + root.userName + "!"
        pointSize: Style.fontSizeXXL
        font.weight: Font.Medium
        color: Color.mOnSurface
        horizontalAlignment: Text.AlignLeft
      }

      // Date below
      NText {
        text: {
          var lang = Qt.locale().name.split("_")[0]
          var formats = {
            "de": "dddd, d. MMMM",
            "es": "dddd, d 'de' MMMM",
            "fr": "dddd d MMMM",
            "pt": "dddd, d 'de' MMMM",
            "zh": "yyyy年M月d日 dddd"
          }
          return Qt.locale().toString(Time.date, formats[lang] || "dddd, MMMM d")
        }
        pointSize: Style.fontSizeXL
        font.weight: Font.Medium
        color: Color.mOnSurfaceVariant
        horizontalAlignment: Text.AlignLeft
      }
    }

    // Spacer to push time to the right
    Item {
      Layout.fillWidth: true
    }

    ClockLoader {
      now: Time.date
      Layout.preferredWidth: 70
      Layout.preferredHeight: 70
      Layout.alignment: Qt.AlignVCenter
      backgroundColor: Color.mSurface
      clockColor: Color.mOnSurface
      secondHandColor: Color.mPrimary
    }
  }
}
