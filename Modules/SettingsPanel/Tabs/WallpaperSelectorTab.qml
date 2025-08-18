import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Qt.labs.folderlistmodel
import qs.Commons
import qs.Services
import qs.Widgets

Item {
  property real scaling: 1
  readonly property string tabIcon: "photo_library"
  readonly property string tabLabel: "Wallpaper Selector"
  readonly property int tabIndex: 7
  Layout.fillWidth: true
  Layout.fillHeight: true

  ScrollView {
    anchors.fill: parent
    clip: true
    ScrollBar.vertical.policy: ScrollBar.AsNeeded
    ScrollBar.horizontal.policy: ScrollBar.AsNeeded
    contentWidth: parent.width

    ColumnLayout {
      width: parent.width
      ColumnLayout {
        spacing: Style.marginLarge * scaling
        Layout.margins: Style.marginLarge * scaling
        Layout.fillWidth: true

        // Current wallpaper display
        NText {
          text: "Current Wallpaper"
          font.pointSize: Style.fontSizeXL * scaling
          font.weight: Style.fontWeightBold
          color: Color.mOnSurface
        }

        Rectangle {
          Layout.fillWidth: true
          Layout.preferredHeight: 120 * scaling
          radius: Style.radiusMedium * scaling
          color: Color.mSurface
          border.color: Color.mOutline
          border.width: Math.max(1, Style.borderThin * scaling)
          clip: true

          NImageRounded {
            id: currentWallpaperImage
            anchors.fill: parent
            anchors.margins: Style.marginSmall * scaling
            imagePath: WallpaperService.currentWallpaper
            fallbackIcon: "image"
            borderColor: Color.mOutline
            borderWidth: Math.max(1, Style.borderThin * scaling)
            imageRadius: Style.radiusMedium * scaling
          }
        }

        NDivider {
          Layout.fillWidth: true
          Layout.topMargin: Style.marginLarge * scaling
          Layout.bottomMargin: Style.marginLarge * scaling
        }

        RowLayout {
          Layout.fillWidth: true

          ColumnLayout {
            Layout.fillWidth: true

            // Wallpaper grid
            NText {
              text: "Wallpaper Selector"
              font.pointSize: Style.fontSizeXL * scaling
              font.weight: Style.fontWeightBold
              color: Color.mOnSurface
            }

            NText {
              text: "Click on a wallpaper to set it as your current wallpaper"
              color: Color.mOnSurface
              wrapMode: Text.WordWrap
              Layout.fillWidth: true
            }

            NText {
              text: Settings.data.wallpaper.swww.enabled ? "Wallpapers will change with " + Settings.data.wallpaper.swww.transitionType
                                                           + " transition" : "Wallpapers will change instantly"
              color: Color.mOnSurface
              font.pointSize: Style.fontSizeSmall * scaling
              visible: Settings.data.wallpaper.swww.enabled
            }
          }

          NIconButton {
            icon: "refresh"
            tooltipText: "Refresh wallpaper list"
            onClicked: {
              WallpaperService.listWallpapers()
            }
            Layout.alignment: Qt.AlignTop | Qt.AlignRight
          }
        }

        // Wallpaper grid container
        Item {
          Layout.fillWidth: true
          Layout.preferredHeight: {
            return Math.ceil(
                  WallpaperService.wallpaperList.length / wallpaperGridView.columns) * wallpaperGridView.cellHeight
          }

          GridView {
            id: wallpaperGridView
            anchors.fill: parent
            clip: true
            model: WallpaperService.wallpaperList

            boundsBehavior: Flickable.StopAtBounds
            flickableDirection: Flickable.AutoFlickDirection
            interactive: false

            property int columns: 5
            property int itemSize: Math.floor(
                                     (width - leftMargin - rightMargin - (4 * Style.marginSmall * scaling)) / columns)

            cellWidth: Math.floor((width - leftMargin - rightMargin) / columns)
            cellHeight: Math.floor(itemSize * 0.67) + Style.marginSmall * scaling

            leftMargin: Style.marginSmall * scaling
            rightMargin: Style.marginSmall * scaling
            topMargin: Style.marginSmall * scaling
            bottomMargin: Style.marginSmall * scaling

            delegate: Rectangle {
              id: wallpaperItem

              property string wallpaperPath: modelData
              property bool isSelected: wallpaperPath === WallpaperService.currentWallpaper

              width: wallpaperGridView.itemSize
              height: Math.floor(wallpaperGridView.itemSize * 0.67)
              color: Color.transparent

              // NImageCached relies on the image being visible to work properly.
              // MultiEffect relies on the image being invisible to apply effects.
              // That's why we don't have rounded corners here, as we don't want to bring back qt5compat.
              NImageCached {
                id: img
                imagePath: wallpaperPath
                anchors.fill: parent
              }

              // Borders on top
              Rectangle {
                anchors.fill: parent
                color: Color.transparent
                border.color: isSelected ? Color.mPrimary : Color.mOutline
                border.width: Math.max(1, Style.borderThick * scaling)
              }

              // Selection tick-mark
              Rectangle {
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.margins: Style.marginTiny * scaling
                width: 20 * scaling
                height: 20 * scaling
                radius: width / 2
                color: Color.mPrimary
                border.color: Color.mOutline
                border.width: Math.max(1, Style.borderThin * scaling)
                visible: isSelected

                NIcon {
                  text: "check"
                  font.pointSize: Style.fontSizeSmall * scaling
                  color: Color.mOnPrimary
                  anchors.centerIn: parent
                }
              }

              // Hover effect
              Rectangle {
                anchors.fill: parent
                color: Color.mOnSurface
                opacity: mouseArea.containsMouse ? 0.1 : 0
                radius: parent.radius

                Behavior on opacity {
                  NumberAnimation {
                    duration: Style.animationFast
                  }
                }
              }

              MouseArea {
                id: mouseArea
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton
                hoverEnabled: true
                onClicked: {
                  WallpaperService.changeWallpaper(wallpaperPath)
                }
              }
            }
          }

          // Empty state
          Rectangle {
            anchors.fill: parent
            color: Color.mSurface
            radius: Style.radiusMedium * scaling
            border.color: Color.mOutline
            border.width: Math.max(1, Style.borderThin * scaling)
            visible: WallpaperService.wallpaperList.length === 0 && !WallpaperService.scanning

            ColumnLayout {
              anchors.centerIn: parent
              spacing: Style.marginMedium * scaling

              NIcon {
                text: "folder_open"
                font.pointSize: Style.fontSizeLarge * scaling
                color: Color.mOnSurface
                Layout.alignment: Qt.AlignHCenter
              }

              NText {
                text: "No wallpapers found"
                color: Color.mOnSurface
                font.weight: Style.fontWeightBold
                Layout.alignment: Qt.AlignHCenter
              }

              NText {
                text: "Make sure your wallpaper directory is configured and contains image files"
                color: Color.mOnSurface
                wrapMode: Text.WordWrap
                horizontalAlignment: Text.AlignHCenter
                Layout.preferredWidth: Style.sliderWidth * 1.5 * scaling
              }
            }
          }
        }
      }
    }
  }
}
