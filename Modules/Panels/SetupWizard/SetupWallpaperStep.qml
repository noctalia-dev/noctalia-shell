import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../../../Helpers/FuzzySort.js" as FuzzySort
import qs.Commons
import qs.Services.UI
import qs.Widgets

ColumnLayout {
  id: root

  property string selectedDirectory: ""
  property string selectedWallpaper: ""

  signal directoryChanged(string directory)
  signal wallpaperChanged(string wallpaper)

  spacing: Style.marginL

  // Beautiful header with icon
  ColumnLayout {
    Layout.fillWidth: true
    Layout.bottomMargin: Style.marginL
    spacing: Style.marginM

    RowLayout {
      spacing: Style.marginM

      Rectangle {
        width: 40
        height: 40
        radius: Style.radiusL
        color: Color.mSurfaceVariant
        opacity: 0.6

        NIcon {
          icon: "image"
          pointSize: Style.fontSizeL
          color: Color.mPrimary
          anchors.centerIn: parent
        }
      }

      ColumnLayout {
        spacing: Style.marginXS

        NText {
          text: I18n.tr("setup.wallpaper.header")
          pointSize: Style.fontSizeXL
          font.weight: Style.fontWeightBold
          color: Color.mPrimary
        }

        NText {
          text: I18n.tr("setup.wallpaper.subheader")
          pointSize: Style.fontSizeM
          color: Color.mOnSurfaceVariant
        }
      }
    }
  }

  // Large preview area
  Rectangle {
    Layout.fillWidth: true
    Layout.fillHeight: true
    Layout.minimumHeight: 180
    color: Color.mSurfaceVariant
    radius: Style.radiusL

    // Image with rounded corners
    NImageRounded {
      anchors.fill: parent
      visible: selectedWallpaper !== ""
      imagePath: selectedWallpaper !== "" ? "file://" + selectedWallpaper : ""
      radius: Style.radiusL
      borderColor: selectedWallpaper !== "" ? Color.mPrimary : Color.mOutline
      borderWidth: selectedWallpaper !== "" ? 2 : 1
    }

    ColumnLayout {
      anchors.centerIn: parent
      spacing: Style.marginL
      visible: selectedWallpaper === ""

      Rectangle {
        Layout.alignment: Qt.AlignHCenter
        width: 64
        height: 64
        radius: width / 2
        color: Color.mPrimary

        NIcon {
          icon: "sparkles"
          pointSize: Style.fontSizeXXL
          color: Color.mOnPrimary
          anchors.centerIn: parent
        }
      }

      NText {
        text: I18n.tr("setup.wallpaper.select-prompt")
        pointSize: Style.fontSizeL
        color: Color.mOnSurfaceVariant
        Layout.alignment: Qt.AlignHCenter
        font.weight: Style.fontWeightMedium
      }
    }

    Behavior on border.color {
      ColorAnimation {
        duration: Style.animationFast
      }
    }
  }

  // Wallpaper gallery strip
  Item {
    Layout.fillWidth: true
    Layout.preferredHeight: 88
    visible: filteredWallpapers.length > 0

    ScrollView {
      id: galleryScroll
      anchors.fill: parent
      clip: true
      ScrollBar.horizontal.policy: ScrollBar.AsNeeded
      ScrollBar.vertical.policy: ScrollBar.AlwaysOff

      // Enable vertical mouse wheel to scroll the horizontal strip by moving contentX
      WheelHandler {
        target: galleryScroll.contentItem
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: event => {
                   const flick = galleryScroll.contentItem;
                   if (!flick)
                   return;
                   const delta = event.pixelDelta.x !== 0 || event.pixelDelta.y !== 0 ? (event.pixelDelta.y !== 0 ? event.pixelDelta.y : event.pixelDelta.x) : (event.angleDelta.y !== 0 ? event.angleDelta.y : event.angleDelta.x);
                   // Move opposite of wheel to scroll content to the right for wheel down
                   const step = -delta;
                   const maxX = Math.max(0, flick.contentWidth - flick.width);
                   let newX = flick.contentX + step;
                   if (newX < 0)
                   newX = 0;
                   if (newX > maxX)
                   newX = maxX;
                   flick.contentX = newX;
                   event.accepted = true;
                 }
      }

      RowLayout {
        spacing: Style.marginM
        height: parent.height

        Repeater {
          model: filteredWallpapers
          delegate: Item {
            readonly property int borderWidth: Style.borderM
            readonly property int imageMargin: 1
            readonly property int baseWidth: 120
            readonly property int baseHeight: 80

            Layout.preferredWidth: baseWidth + (borderWidth + imageMargin) * 2
            Layout.preferredHeight: baseHeight + (borderWidth + imageMargin) * 2

            // Border container with proper spacing to prevent clipping
            Rectangle {
              anchors.fill: parent
              anchors.margins: imageMargin
              color: Color.transparent
              border.color: selectedWallpaper === modelData ? Color.mPrimary : Color.mOutline
              border.width: borderWidth

              // Cached thumbnail
              NImageCached {
                id: thumbCached
                anchors.fill: parent
                anchors.margins: borderWidth
                source: "file://" + modelData
              }
            }

            // Loading state
            Rectangle {
              anchors.fill: parent
              color: Color.mSurfaceVariant
              visible: thumbCached.status === Image.Loading

              NIcon {
                icon: "image"
                pointSize: Style.fontSizeL
                color: Color.mOnSurfaceVariant
                anchors.centerIn: parent
              }
            }

            // Error state
            Rectangle {
              anchors.fill: parent
              color: Color.mSurfaceVariant
              radius: Style.radiusM
              visible: thumbCached.status === Image.Error

              NIcon {
                icon: "image"
                pointSize: Style.fontSizeL
                color: Color.mOnSurfaceVariant
                anchors.centerIn: parent
              }
            }

            NBusyIndicator {
              anchors.centerIn: parent
              visible: thumbCached.status === Image.Loading || thumbCached.status === Image.Null
              running: visible
              size: 18
            }

            Rectangle {
              anchors.fill: parent
              color: Color.mPrimary
              opacity: hoverHandler.hovered ? 0.1 : 0
              Behavior on opacity {
                NumberAnimation {
                  duration: Style.animationFast
                }
              }
            }

            Rectangle {
              visible: selectedWallpaper === modelData
              anchors.right: parent.right
              anchors.bottom: parent.bottom
              anchors.margins: 6
              width: 24
              height: 24
              radius: width / 2
              color: Color.mPrimary

              NIcon {
                icon: "check"
                pointSize: Style.fontSizeS
                color: Color.mOnPrimary
                anchors.centerIn: parent
              }
            }

            HoverHandler {
              id: hoverHandler
            }

            TapHandler {
              onTapped: {
                selectedWallpaper = modelData;
                wallpaperChanged(modelData);
              }
            }
          }
        }
      }
    }
  }

  // Helpful info card
  Rectangle {
    Layout.fillWidth: true
    Layout.preferredHeight: 80
    color: Color.mSurfaceVariant
    radius: Style.radiusM
    opacity: 0.4
    visible: filteredWallpapers.length === 0

    RowLayout {
      anchors.fill: parent
      anchors.margins: Style.marginL
      spacing: Style.marginM

      NIcon {
        icon: "folder-open"
        pointSize: Style.fontSizeL
        color: Color.mOnSurfaceVariant
      }

      ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.marginXS
        NText {
          text: filteredWallpapers.length === 0 && selectedDirectory !== "" ? I18n.tr("setup.wallpaper.none-in-dir") : I18n.tr("setup.wallpaper.no-dir")
          pointSize: Style.fontSizeM
          font.weight: Style.fontWeightBold
          color: Color.mOnSurfaceVariant
        }
        NText {
          text: selectedDirectory !== "" ? I18n.tr("setup.wallpaper.no-valid", {
                                                     "dir": selectedDirectory
                                                   }) : I18n.tr("setup.wallpaper.choose-dir")
          pointSize: Style.fontSizeS
          color: Color.mOnSurfaceVariant
          wrapMode: Text.WordWrap
          Layout.fillWidth: true
          opacity: 0.8
        }
      }
    }
  }

  // Directory selection
  ColumnLayout {
    Layout.fillWidth: true
    spacing: Style.marginM

    NTextInputButton {
      id: wallpaperPathInput
      label: I18n.tr("setup.wallpaper.dir.label")
      description: I18n.tr("setup.wallpaper.dir.description")
      text: selectedDirectory
      buttonIcon: "folder-open"
      buttonTooltip: I18n.tr("setup.wallpaper.dir.browse")
      Layout.fillWidth: true
      onInputEditingFinished: {
        selectedDirectory = text;
        directoryChanged(text);
      }
      onButtonClicked: directoryPicker.open()
    }
  }

  // Internal properties and functions
  property list<string> wallpapersList: []
  property list<string> filteredWallpapers: []

  function updateFilteredWallpapers() {
    filteredWallpapers = wallpapersList;
  }

  function refreshWallpapers() {
    if (!selectedDirectory || selectedDirectory === "") {
      wallpapersList = [];
      filteredWallpapers = [];
      return;
    }
    if (typeof WallpaperService !== "undefined" && WallpaperService.getWallpapersList) {
      var wallpapers = WallpaperService.getWallpapersList(Screen.name);
      wallpapersList = wallpapers;
      updateFilteredWallpapers();
      if (wallpapersList.length > 0 && selectedWallpaper === "") {
        selectedWallpaper = wallpapersList[0];
      }
    } else {
      readDirectoryImages(selectedDirectory);
    }
  }

  function readDirectoryImages(directoryPath) {
    directoryScanner.command = ["find", directoryPath, "-type", "f", "\\(-iname", "*.jpg", "-o", "-iname", "*.jpeg", "-o", "-iname", "*.png", "-o", "-iname", "*.bmp", "-o", "-iname", "*.webp", "-o", "-iname", "*.svg", "\\)"];
    directoryScanner.running = true;
    return [];
  }

  onSelectedDirectoryChanged: {
    if (typeof Settings !== "undefined" && Settings.data && Settings.data.wallpaper) {
      Settings.data.wallpaper.directory = selectedDirectory;
    }
    if (typeof WallpaperService !== "undefined" && WallpaperService.refreshWallpapersList) {
      WallpaperService.refreshWallpapersList();
    }
    Qt.callLater(refreshWallpapers);
  }

  Connections {
    target: WallpaperService
    enabled: typeof WallpaperService !== "undefined"
    function onWallpaperListChanged(screenName, count) {
      if (screenName === Screen.name) {
        Qt.callLater(refreshWallpapers);
      }
    }
  }

  Timer {
    id: initialRefreshTimer
    interval: 1000
    running: false
    repeat: false
    onTriggered: refreshWallpapers()
  }

  Component.onCompleted: {
    if (typeof Settings !== "undefined" && Settings.data && Settings.data.wallpaper && Settings.data.wallpaper.directory) {
      selectedDirectory = Settings.data.wallpaper.directory;
    } else {
      selectedDirectory = Quickshell.env("HOME") + "/Pictures/Wallpapers";
    }
    if (typeof WallpaperService !== "undefined" && WallpaperService.currentWallpaper) {
      selectedWallpaper = WallpaperService.currentWallpaper;
    }
    initialRefreshTimer.start();
  }

  NFilePicker {
    id: directoryPicker
    selectionMode: "folders"
    title: I18n.tr("setup.wallpaper.dir.select-title")
    initialPath: selectedDirectory || Quickshell.env("HOME") + "/Pictures"
    onAccepted: paths => {
                  if (paths.length > 0) {
                    selectedDirectory = paths[0];
                    directoryChanged(paths[0]);
                  }
                }
  }

  Process {
    id: directoryScanner
    command: ["find", "", "-type", "f", "\\(-iname", "*.jpg", "-o", "-iname", "*.jpeg", "-o", "-iname", "*.png", "-o", "-iname", "*.bmp", "-o", "-iname", "*.webp", "-o", "-iname", "*.svg", "\\)"]
    running: false
    stdout: StdioCollector {}
    stderr: StdioCollector {}
    onExited: function (exitCode) {
      if (exitCode === 0) {
        var lines = stdout.text.split('\n');
        var images = [];
        for (var i = 0; i < lines.length; i++) {
          var line = lines[i].trim();
          if (line !== '') {
            images.push(line);
          }
        }
        wallpapersList = images;
        updateFilteredWallpapers();
        if (wallpapersList.length > 0 && selectedWallpaper === "") {
          selectedWallpaper = wallpapersList[0];
        }
      }
    }
  }
}
