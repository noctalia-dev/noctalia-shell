import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Widgets.AudioSpectrum
import qs.Commons
import qs.Services.Media
import qs.Services.UI
import qs.Widgets

Item {
  id: root

  property ShellScreen screen

  // Widget properties passed from Bar.qml for per-instance settings
  property string widgetId: ""
  property string section: ""
  property int sectionWidgetIndex: -1
  property int sectionWidgetsCount: 0
  property real scaling: 1.0

  property var widgetMetadata: BarWidgetRegistry.widgetMetadata[widgetId]
  property var widgetSettings: {
    if (section && sectionWidgetIndex >= 0) {
      var widgets = Settings.data.bar.widgets[section]
      if (widgets && sectionWidgetIndex < widgets.length) {
        return widgets[sectionWidgetIndex]
      }
    }
    return {}
  }

  readonly property bool isVerticalBar: (Settings.data.bar.position === "left" || Settings.data.bar.position === "right")

  readonly property string hideMode: (widgetSettings.hideMode !== undefined) ? widgetSettings.hideMode : "hidden" // "visible", "hidden", "transparent", "idle"
  // Backward compatibility: honor legacy hideWhenIdle setting if present
  readonly property bool hideWhenIdle: (widgetSettings.hideWhenIdle !== undefined) ? widgetSettings.hideWhenIdle : (widgetMetadata.hideWhenIdle !== undefined ? widgetMetadata.hideWhenIdle : false)
  readonly property bool showAlbumArt: (widgetSettings.showAlbumArt !== undefined) ? widgetSettings.showAlbumArt : widgetMetadata.showAlbumArt
  readonly property bool showVisualizer: (widgetSettings.showVisualizer !== undefined) ? widgetSettings.showVisualizer : widgetMetadata.showVisualizer
  readonly property string visualizerType: (widgetSettings.visualizerType !== undefined && widgetSettings.visualizerType !== "") ? widgetSettings.visualizerType : widgetMetadata.visualizerType
  readonly property string scrollingMode: (widgetSettings.scrollingMode !== undefined) ? widgetSettings.scrollingMode : widgetMetadata.scrollingMode

  // Maximum widget width with user settings support
  readonly property real maxWidth: (widgetSettings.maxWidth !== undefined) ? widgetSettings.maxWidth : Math.max(widgetMetadata.maxWidth, screen ? screen.width * 0.06 : 0)
  readonly property bool useFixedWidth: (widgetSettings.useFixedWidth !== undefined) ? widgetSettings.useFixedWidth : widgetMetadata.useFixedWidth

  readonly property bool hasActivePlayer: MediaService.currentPlayer !== null
  readonly property string placeholderText: I18n.tr("bar.widget-settings.media-mini.no-active-player")

  readonly property string tooltipText: {
    var title = getTitle()
    var controls = ""
    if (MediaService.canGoNext) {
      controls += "Right click for next.\n"
    }
    if (MediaService.canGoPrevious) {
      controls += "Middle click for previous."
    }
    if (controls !== "") {
      return title + "\n\n" + controls
    }
    return title
  }

  // Hide conditions
  readonly property bool shouldHideIdle: ((hideMode === "idle") || hideWhenIdle) && !MediaService.isPlaying
  readonly property bool isEmptyForHideMode: (!hasActivePlayer) && (hideMode === "hidden" || hideMode === "transparent")

  implicitHeight: visible ? (isVerticalBar ? ((shouldHideIdle || isEmptyForHideMode) ? 0 : calculatedVerticalDimension()) : Style.capsuleHeight) : 0
  implicitWidth: visible ? (isVerticalBar ? ((shouldHideIdle || isEmptyForHideMode) ? 0 : calculatedVerticalDimension()) : ((shouldHideIdle || isEmptyForHideMode) ? 0 : dynamicWidth)) : 0

  // "visible": Always Visible, "hidden": Hide When Empty, "transparent": Transparent When Empty, "idle": Hide When Idle (not playing)
  visible: shouldHideIdle ? false : (hideMode !== "hidden" || opacity > 0)
  opacity: shouldHideIdle ? 0.0 : (((hideMode !== "hidden" || hasActivePlayer) && (hideMode !== "transparent" || hasActivePlayer)) ? 1.0 : 0.0)
  Behavior on opacity {
    NumberAnimation {
      duration: Style.animationNormal
      easing.type: Easing.InOutCubic
    }
  }

  Behavior on implicitWidth {
    NumberAnimation {
      duration: Style.animationNormal
      easing.type: Easing.InOutCubic
    }
  }
  Behavior on implicitHeight {
    NumberAnimation {
      duration: Style.animationNormal
      easing.type: Easing.InOutCubic
    }
  }

  function getTitle() {
    return MediaService.trackTitle + (MediaService.trackArtist !== "" ? ` - ${MediaService.trackArtist}` : "")
  }

  function calculatedVerticalDimension() {
    return Math.round((Style.baseWidgetSize - 5) * scaling)
  }

  function calculateContentWidth() {
    // Calculate the actual content width based on visible elements
    var contentWidth = 0
    var margins = Style.marginS * scaling * 2 // Left and right margins

    // Icon or album art width
    if (!hasActivePlayer || !showAlbumArt) {
      // Icon width
      contentWidth += Math.round(18 * scaling)
    } else if (showAlbumArt && hasActivePlayer) {
      // Album art width
      contentWidth += 21 * scaling
    }

    // Spacing between icon/art and text; only if there is text
    if (fullTitleMetrics.contentWidth > 0) {
      contentWidth += Style.marginS * scaling

      // Text width (use the measured width)
      contentWidth += fullTitleMetrics.contentWidth

      // Additional small margin for text
      contentWidth += Style.marginXXS * 2
    }

    // Add container margins
    contentWidth += margins

    return Math.ceil(contentWidth)
  }

  // Dynamic width: adapt to content but respect maximum width setting
  readonly property real dynamicWidth: {
    // If using fixed width mode, always use maxWidth
    if (useFixedWidth) {
      return maxWidth
    }
    // Otherwise, adapt to content
    if (!hasActivePlayer) {
      // Keep compact when no active player
      return calculateContentWidth()
    }
    // Use content width but don't exceed user-set maximum width
    return Math.min(calculateContentWidth(), maxWidth)
  }

  //  A hidden text element to safely measure the full title width
  NText {
    id: fullTitleMetrics
    visible: false
    text: titleText.text
    font: titleText.font
    applyUiScale: false
    pointSize: Style.fontSizeS * scaling
  }

  Rectangle {
    id: mediaMini
    visible: root.visible
    anchors.left: parent.left
    anchors.verticalCenter: parent.verticalCenter
    width: isVerticalBar ? ((shouldHideIdle || isEmptyForHideMode) ? 0 : calculatedVerticalDimension()) : ((shouldHideIdle || isEmptyForHideMode) ? 0 : dynamicWidth)
    height: isVerticalBar ? ((shouldHideIdle || isEmptyForHideMode) ? 0 : calculatedVerticalDimension()) : Style.capsuleHeight
    radius: isVerticalBar ? width / 2 : Style.radiusM
    color: Settings.data.bar.showCapsule ? Color.mSurfaceVariant : Color.transparent

    // Smooth width transition
    Behavior on width {
      NumberAnimation {
        duration: Style.animationNormal
        easing.type: Easing.InOutCubic
      }
    }

    // Smooth height transition for vertical bar
    Behavior on height {
      NumberAnimation {
        duration: Style.animationNormal
        easing.type: Easing.InOutCubic
      }
    }

    Item {
      id: mainContainer
      anchors.fill: parent
      anchors.leftMargin: isVerticalBar ? 0 : Style.marginS * scaling
      anchors.rightMargin: isVerticalBar ? 0 : Style.marginS * scaling
      clip: true

      Loader {
        anchors.verticalCenter: parent.verticalCenter
        anchors.horizontalCenter: parent.horizontalCenter
        active: showVisualizer && visualizerType == "linear"
        z: 0

        sourceComponent: NLinearSpectrum {
          width: mainContainer.width - Style.marginS
          height: 20
          values: CavaService.values
          fillColor: Color.mPrimary
          opacity: 0.4
        }
      }

      Loader {
        anchors.verticalCenter: parent.verticalCenter
        anchors.horizontalCenter: parent.horizontalCenter
        active: showVisualizer && visualizerType == "mirrored"
        z: 0

        sourceComponent: NMirroredSpectrum {
          width: mainContainer.width - Style.marginS
          height: mainContainer.height - Style.marginS
          values: CavaService.values
          fillColor: Color.mPrimary
          opacity: 0.4
        }
      }

      Loader {
        anchors.verticalCenter: parent.verticalCenter
        anchors.horizontalCenter: parent.horizontalCenter
        active: showVisualizer && visualizerType == "wave"
        z: 0

        sourceComponent: NWaveSpectrum {
          width: mainContainer.width - Style.marginS
          height: mainContainer.height - Style.marginS
          values: CavaService.values
          fillColor: Color.mPrimary
          opacity: 0.4
        }
      }

      // Horizontal layout for top/bottom bars
      RowLayout {
        id: rowLayout

        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.marginS * scaling
        visible: !isVerticalBar
        z: 1 // Above the visualizer

        NIcon {
          id: windowIcon
          icon: hasActivePlayer ? (MediaService.isPlaying ? "media-pause" : "media-play") : "disc"
          color: hasActivePlayer ? Color.mOnSurface : Color.mOnSurfaceVariant
          pointSize: Style.fontSizeL * scaling
          verticalAlignment: Text.AlignVCenter
          Layout.alignment: Qt.AlignVCenter
          visible: !hasActivePlayer || (!showAlbumArt && !trackArt.visible)
        }

        ColumnLayout {
          Layout.alignment: Qt.AlignVCenter
          visible: showAlbumArt && hasActivePlayer
          spacing: 0

          Item {
            Layout.preferredWidth: Math.round(21 * scaling)
            Layout.preferredHeight: Math.round(21 * scaling)

            NImageCircled {
              id: trackArt
              anchors.fill: parent
              imagePath: MediaService.trackArtUrl
              fallbackIcon: MediaService.isPlaying ? "media-pause" : "media-play"
              fallbackIconSize: 10
              borderWidth: 0
              border.color: Color.transparent
            }
          }
        }

        Item {
          id: titleContainer
          Layout.preferredWidth: {
            // Calculate available width based on other elements in the row
            var iconWidth = (windowIcon.visible ? (18 * scaling + Style.marginS * scaling) : 0)
            var albumArtWidth = (hasActivePlayer && showAlbumArt ? (21 * scaling + Style.marginS * scaling) : 0)
            var totalMargins = Style.marginXXS * 2
            var availableWidth = mainContainer.width - iconWidth - albumArtWidth - totalMargins
            return Math.max(20, availableWidth)
          }
          Layout.maximumWidth: Layout.preferredWidth
          Layout.alignment: Qt.AlignVCenter
          Layout.preferredHeight: titleText.height

          clip: true

          property bool isScrolling: false
          property bool isResetting: false
          property real textWidth: fullTitleMetrics.contentWidth
          property real containerWidth: 0
          property bool needsScrolling: textWidth > containerWidth

          // Timer for "always" mode with delay
          Timer {
            id: scrollStartTimer
            interval: 1000
            repeat: false
            onTriggered: {
              if (scrollingMode === "always" && titleContainer.needsScrolling) {
                titleContainer.isScrolling = true
                titleContainer.isResetting = false
              }
            }
          }

          // Update scrolling state based on mode
          property var updateScrollingState: function () {
            if (scrollingMode === "never") {
              isScrolling = false
              isResetting = false
            } else if (scrollingMode === "always") {
              if (needsScrolling) {
                if (mouseArea.containsMouse) {
                  isScrolling = false
                  isResetting = true
                } else {
                  scrollStartTimer.restart()
                }
              } else {
                scrollStartTimer.stop()
                isScrolling = false
                isResetting = false
              }
            } else if (scrollingMode === "hover") {
              if (mouseArea.containsMouse && needsScrolling) {
                isScrolling = true
                isResetting = false
              } else {
                isScrolling = false
                if (needsScrolling) {
                  isResetting = true
                }
              }
            }
          }

          onWidthChanged: {
            containerWidth = width
            updateScrollingState()
          }

          Component.onCompleted: {
            containerWidth = width
            updateScrollingState()
          }

          Connections {
            target: mouseArea
            function onContainsMouseChanged() {
              titleContainer.updateScrollingState()
            }
          }

          // Scrolling content
          Item {
            id: scrollContainer
            height: parent.height
            width: parent.width

            property real scrollX: 0
            x: scrollX

            RowLayout {
              spacing: 50 // Gap between text copies

              NText {
                id: titleText
                text: hasActivePlayer ? getTitle() : placeholderText
                pointSize: Style.fontSizeS * scaling
                applyUiScale: false
                font.weight: Style.fontWeightMedium
                verticalAlignment: Text.AlignVCenter
                horizontalAlignment: hasActivePlayer ? Text.AlignLeft : Text.AlignHCenter
                color: hasActivePlayer ? Color.mOnSurface : Color.mOnSurfaceVariant
                onTextChanged: {
                  titleContainer.isScrolling = false
                  titleContainer.isResetting = false
                  scrollContainer.scrollX = 0
                  if (titleContainer.needsScrolling) {
                    scrollStartTimer.restart()
                  }
                }
              }

              NText {
                text: hasActivePlayer ? getTitle() : placeholderText
                font: titleText.font
                applyUiScale: false
                pointSize: Style.fontSizeS * scaling
                verticalAlignment: Text.AlignVCenter
                horizontalAlignment: hasActivePlayer ? Text.AlignLeft : Text.AlignHCenter
                color: hasActivePlayer ? Color.mOnSurface : Color.mOnSurfaceVariant
                visible: hasActivePlayer && titleContainer.needsScrolling && titleContainer.isScrolling
              }
            }

            // Reset animation
            NumberAnimation on scrollX {
              running: titleContainer.isResetting
              to: 0
              duration: 300
              easing.type: Easing.OutQuad
              onFinished: {
                titleContainer.isResetting = false
              }
            }

            // Seamless infinite scroll
            NumberAnimation on scrollX {
              id: infiniteScroll
              running: titleContainer.isScrolling && !titleContainer.isResetting
              from: 0
              to: -(titleContainer.textWidth + 50) // Scroll one complete text width + gap
              duration: Math.max(4000, getTitle().length * 120)
              loops: Animation.Infinite
              easing.type: Easing.Linear
            }
          }
        }
      }

      // Vertical layout for left/right bars - icon only
      Item {
        id: verticalLayout
        anchors.centerIn: parent
        width: parent.width - Style.marginM * 2
        height: parent.height - Style.marginM * 2
        visible: isVerticalBar
        z: 1 // Above the visualizer

        // Media icon
        Item {
          width: Style.baseWidgetSize * 0.5
          height: width
          anchors.centerIn: parent

          NIcon {
            id: mediaIconVertical
            anchors.fill: parent
            icon: hasActivePlayer ? (MediaService.isPlaying ? "media-pause" : "media-play") : "disc"
            color: hasActivePlayer ? Color.mOnSurface : Color.mOnSurfaceVariant
            pointSize: Style.fontSizeL * scaling
            verticalAlignment: Text.AlignVCenter
            horizontalAlignment: Text.AlignHCenter
          }
        }
      }

      // Mouse area for hover detection
      MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: hasActivePlayer ? Qt.PointingHandCursor : Qt.ArrowCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        onClicked: mouse => {
                     if (!hasActivePlayer || !MediaService.currentPlayer || !MediaService.canPlay) {
                       return
                     }

                     if (mouse.button === Qt.LeftButton) {
                       MediaService.playPause()
                     } else if (mouse.button == Qt.RightButton) {
                       MediaService.next()
                       TooltipService.hide()
                     } else if (mouse.button == Qt.MiddleButton) {
                       MediaService.previous()
                       TooltipService.hide()
                     }
                   }

        onEntered: {
          var textToShow = hasActivePlayer ? tooltipText : placeholderText
          if ((textToShow !== "") && isVerticalBar || (scrollingMode === "never")) {
            TooltipService.show(Screen, root, textToShow, BarService.getTooltipDirection())
          }
        }
        onExited: {
          TooltipService.hide()
        }
      }
    }
  }
}
