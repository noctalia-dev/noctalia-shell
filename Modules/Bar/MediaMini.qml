import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Services
import qs.Widgets

Row {
  id: root
  anchors.verticalCenter: parent.verticalCenter
  spacing: Style.marginSmall * scaling
  visible: Settings.data.bar.showMedia && (MediaService.canPlay || MediaService.canPause)

  function getTitle() {
    return MediaService.trackTitle + (MediaService.trackArtist !== "" ? ` - ${MediaService.trackArtist}` : "")
  }

  //  A hidden text element to safely measure the full title width
  NText {
    id: fullTitleMetrics
    visible: false
    text: titleText.text
    font: titleText.font
  }

  Rectangle {
    // Let the Rectangle size itself based on its content (the Row)
    width: row.width + Style.marginMedium * scaling * 2
    height: row.height
    color: Color.mSurfaceVariant
    radius: Style.radiusSmall * scaling
    anchors.verticalCenter: parent.verticalCenter

    Item {
      id: mainContainer
      anchors.fill: parent
      anchors.leftMargin: Style.marginSmall * scaling
      anchors.rightMargin: Style.marginSmall * scaling

      Row {
        id: row
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.marginTiny * scaling

        // Window icon
        NIcon {
          id: windowIcon
          text: MediaService.isPlaying ? "pause" : "play_arrow"
          font.pointSize: Style.fontSizeLarge * scaling
          verticalAlignment: Text.AlignVCenter
          anchors.verticalCenter: parent.verticalCenter
          visible: getTitle() !== ""
        }

        NText {
          id: titleText

          // If hovered or just switched window, show up to 300 pixels
          // If not hovered show up to 150 pixels
          width: (mouseArea.containsMouse) ? Math.min(fullTitleMetrics.contentWidth,
                                                      400 * scaling) : Math.min(fullTitleMetrics.contentWidth,
                                                                                150 * scaling)
          text: getTitle()
          font.pointSize: Style.fontSizeReduced * scaling
          font.weight: Style.fontWeightMedium
          elide: Text.ElideRight
          anchors.verticalCenter: parent.verticalCenter
          verticalAlignment: Text.AlignVCenter
          color: Color.mTertiary

          Behavior on width {
            NumberAnimation {
              duration: Style.animationSlow
              easing.type: Easing.InOutCubic
            }
          }
        }
      }

      // Mouse area for hover detection
      MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: MediaService.playPause()
      }
    }
  }
}
