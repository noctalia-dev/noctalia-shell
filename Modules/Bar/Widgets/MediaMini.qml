import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Modules.Bar.Extras
import qs.Services.Media
import qs.Services.UI
import qs.Widgets
import qs.Widgets.AudioSpectrum

Item {
  id: root

  property ShellScreen screen
  property string widgetId: ""
  property string section: ""
  property int sectionWidgetIndex: -1
  property int sectionWidgetsCount: 0
  property real scaling: 1.0

  // Settings
  property var widgetMetadata: BarWidgetRegistry.widgetMetadata[widgetId]
  property var widgetSettings: {
    if (section && sectionWidgetIndex >= 0) {
      var widgets = Settings.data.bar.widgets[section];
      if (widgets && sectionWidgetIndex < widgets.length) {
        return widgets[sectionWidgetIndex];
      }
    }
    return {};
  }

  // Bar orientation
  readonly property bool isVertical: Settings.data.bar.position === "left" || Settings.data.bar.position === "right"

  // Widget settings
  readonly property string hideMode: (widgetSettings.hideMode !== undefined) ? widgetSettings.hideMode : "hidden"
  readonly property bool hideWhenIdle: (widgetSettings.hideWhenIdle !== undefined) ? widgetSettings.hideWhenIdle : (widgetMetadata.hideWhenIdle !== undefined ? widgetMetadata.hideWhenIdle : false)
  readonly property bool showAlbumArt: (widgetSettings.showAlbumArt !== undefined) ? widgetSettings.showAlbumArt : widgetMetadata.showAlbumArt
  readonly property bool showArtistFirst: (widgetSettings.showArtistFirst !== undefined) ? widgetSettings.showArtistFirst : widgetMetadata.showArtistFirst
  readonly property bool showVisualizer: (widgetSettings.showVisualizer !== undefined) ? widgetSettings.showVisualizer : widgetMetadata.showVisualizer
  readonly property string visualizerType: (widgetSettings.visualizerType !== undefined && widgetSettings.visualizerType !== "") ? widgetSettings.visualizerType : widgetMetadata.visualizerType
  readonly property string scrollingMode: (widgetSettings.scrollingMode !== undefined) ? widgetSettings.scrollingMode : widgetMetadata.scrollingMode
  readonly property bool showProgressRing: (widgetSettings.showProgressRing !== undefined) ? widgetSettings.showProgressRing : widgetMetadata.showProgressRing
  readonly property bool useFixedWidth: (widgetSettings.useFixedWidth !== undefined) ? widgetSettings.useFixedWidth : widgetMetadata.useFixedWidth
  readonly property real maxWidth: (widgetSettings.maxWidth !== undefined) ? widgetSettings.maxWidth : Math.max(widgetMetadata.maxWidth, screen ? screen.width * 0.06 : 0)

  // Dimensions
  readonly property int iconSize: Math.round(18 * scaling)
  readonly property int artSize: Math.round(21 * scaling)
  readonly property int verticalSize: Math.round((Style.baseWidgetSize - 5) * scaling)

  // State
  readonly property bool hasPlayer: MediaService.currentPlayer !== null
  readonly property bool shouldHideIdle: (hideMode === "idle" || hideWhenIdle) && !MediaService.isPlaying
  readonly property bool shouldHideEmpty: !hasPlayer && hideMode === "hidden"
  readonly property bool isHidden: shouldHideIdle || shouldHideEmpty

  // Title
  readonly property string title: {
    if (!hasPlayer)
      return I18n.tr("bar.widget-settings.media-mini.no-active-player");
    var artist = MediaService.trackArtist;
    var track = MediaService.trackTitle;
    return showArtistFirst ? (artist ? `${artist} - ${track}` : track) : (artist ? `${track} - ${artist}` : track);
  }

  // CavaService registration for visualizer
  readonly property string cavaComponentId: "bar:mediamini:" + root.screen?.name + ":" + root.section + ":" + root.sectionWidgetIndex
  readonly property bool needsCava: root.showVisualizer && root.visualizerType !== "" && root.visualizerType !== "none"

  onNeedsCavaChanged: {
    if (root.needsCava) {
      CavaService.registerComponent(root.cavaComponentId);
    } else {
      CavaService.unregisterComponent(root.cavaComponentId);
    }
  }

  Component.onDestruction: {
    if (root.needsCava) {
      CavaService.unregisterComponent(root.cavaComponentId);
    }
  }

  readonly property string tooltipText: {
    var text = title;
    var controls = [];
    if (MediaService.canGoNext)
      controls.push("Right click for next.");
    if (MediaService.canGoPrevious)
      controls.push("Middle click for previous.");
    return controls.length ? `${text}\n\n${controls.join("\n")}` : text;
  }

  // Layout
  implicitWidth: visible ? (isVertical ? (isHidden ? 0 : verticalSize) : (isHidden ? 0 : contentWidth)) : 0
  implicitHeight: visible ? (isVertical ? (isHidden ? 0 : verticalSize) : Style.capsuleHeight) : 0
  visible: !shouldHideIdle && (hideMode !== "hidden" || opacity > 0)
  opacity: isHidden ? 0.0 : ((hideMode === "transparent" && !hasPlayer) ? 0.0 : 1.0)

  readonly property real contentWidth: {
    if (useFixedWidth)
      return maxWidth;

    // Calculate icon/art width
    var iconWidth = 0;
    if (!hasPlayer || (!showAlbumArt && !showProgressRing)) {
      iconWidth = iconSize;
    } else if (showAlbumArt || showProgressRing) {
      iconWidth = artSize;
    }

    // Add spacing and text width
    var textWidth = 0;
    if (titleMetrics.contentWidth > 0) {
      textWidth = Style.marginS * scaling + titleMetrics.contentWidth + Style.marginXXS * 2;
    }

    var margins = isVertical ? 0 : (Style.marginS * scaling * 2);
    var total = iconWidth + textWidth + margins;
    return hasPlayer ? Math.min(total, maxWidth) : total;
  }

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

  // Hidden text for measurements
  NText {
    id: titleMetrics
    visible: false
    text: title
    applyUiScale: false
    pointSize: Style.fontSizeS * scaling
    font.weight: Style.fontWeightMedium
  }

  // Context menu
  NPopupContextMenu {
    id: contextMenu
    model: {
      var items = [];
      if (hasPlayer && MediaService.canPlay) {
        items.push({
                     "label": MediaService.isPlaying ? I18n.tr("context-menu.pause") : I18n.tr("context-menu.play"),
                     "action": "play-pause",
                     "icon": MediaService.isPlaying ? "media-pause" : "media-play"
                   });
      }
      if (hasPlayer && MediaService.canGoPrevious) {
        items.push({
                     "label": I18n.tr("context-menu.previous"),
                     "action": "previous",
                     "icon": "media-prev"
                   });
      }
      if (hasPlayer && MediaService.canGoNext) {
        items.push({
                     "label": I18n.tr("context-menu.next"),
                     "action": "next",
                     "icon": "media-next"
                   });
      }
      items.push({
                   "label": I18n.tr("context-menu.widget-settings"),
                   "action": "widget-settings",
                   "icon": "settings"
                 });
      return items;
    }

    onTriggered: action => {
                   var popupWindow = PanelService.getPopupMenuWindow(screen);
                   if (popupWindow)
                   popupWindow.close();

                   if (action === "play-pause")
                   MediaService.playPause();
                   else if (action === "previous")
                   MediaService.previous();
                   else if (action === "next")
                   MediaService.next();
                   else if (action === "widget-settings") {
                     BarService.openWidgetSettings(screen, section, sectionWidgetIndex, widgetId, widgetSettings);
                   }
                 }
  }

  // Main container
  Rectangle {
    id: container
    anchors.left: parent.left
    anchors.verticalCenter: parent.verticalCenter
    width: isVertical ? (isHidden ? 0 : verticalSize) : (isHidden ? 0 : contentWidth)
    height: isVertical ? (isHidden ? 0 : verticalSize) : Style.capsuleHeight
    radius: Style.radiusM
    color: Style.capsuleColor
    border.color: Style.capsuleBorderColor
    border.width: Style.capsuleBorderWidth

    Behavior on width {
      NumberAnimation {
        duration: Style.animationNormal
        easing.type: Easing.InOutCubic
      }
    }
    Behavior on height {
      NumberAnimation {
        duration: Style.animationNormal
        easing.type: Easing.InOutCubic
      }
    }

    Item {
      anchors.fill: parent
      anchors.leftMargin: isVertical ? 0 : Style.marginS * scaling
      anchors.rightMargin: isVertical ? 0 : Style.marginS * scaling
      clip: true

      // Visualizer
      Loader {
        anchors.verticalCenter: parent.verticalCenter
        anchors.horizontalCenter: parent.horizontalCenter
        width: parent.width
        height: parent.height
        active: showVisualizer
        z: 0
        sourceComponent: {
          if (!showVisualizer)
            return null;
          if (visualizerType === "linear")
            return linearSpectrum;
          if (visualizerType === "mirrored")
            return mirroredSpectrum;
          if (visualizerType === "wave")
            return waveSpectrum;
          return null;
        }
      }

      // Horizontal layout
      RowLayout {
        anchors.fill: parent
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.marginS * scaling
        visible: !isVertical
        z: 1

        // Icon (when no player or features disabled)
        NIcon {
          visible: !hasPlayer || (!showAlbumArt && !showProgressRing)
          icon: hasPlayer ? (MediaService.isPlaying ? "media-pause" : "media-play") : "disc"
          color: hasPlayer ? Color.mOnSurface : Color.mOnSurfaceVariant
          pointSize: Style.fontSizeL * scaling
          Layout.preferredWidth: iconSize
          Layout.preferredHeight: iconSize
          Layout.alignment: Qt.AlignVCenter
        }

        // Album art / Progress ring
        Item {
          visible: hasPlayer && (showAlbumArt || showProgressRing)
          Layout.preferredWidth: visible ? artSize : 0
          Layout.preferredHeight: visible ? artSize : 0
          Layout.alignment: Qt.AlignVCenter

          ProgressRing {
            id: progressRing
            anchors.fill: parent
            visible: showProgressRing
            progress: MediaService.trackLength > 0 ? MediaService.currentPosition / MediaService.trackLength : 0
            lineWidth: 2 * scaling
          }

          Item {
            anchors.fill: parent
            anchors.margins: showProgressRing ? (3 * scaling) : 0.5

            NImageRounded {
              visible: showAlbumArt && hasPlayer
              anchors.fill: parent
              anchors.margins: showProgressRing ? 0 : -1 * scaling
              radius: width / 2
              imagePath: MediaService.trackArtUrl
              fallbackIcon: MediaService.isPlaying ? "media-pause" : "media-play"
              fallbackIconSize: showProgressRing ? 10 : 12
              borderWidth: 0
            }

            NIcon {
              visible: !showAlbumArt && showProgressRing && hasPlayer
              anchors.centerIn: parent
              icon: MediaService.isPlaying ? "media-pause" : "media-play"
              color: Color.mOnSurface
              pointSize: 8 * scaling
            }
          }
        }

        // Scrolling title
        Item {
          id: titleContainer
          Layout.fillWidth: true
          Layout.alignment: Qt.AlignVCenter
          Layout.preferredHeight: titleMetrics.height

          ScrollingText {
            anchors.fill: parent
            text: title
            textColor: hasPlayer ? Color.mOnSurface : Color.mOnSurfaceVariant
            fontSize: Style.fontSizeS * scaling
            scrollMode: scrollingMode
            needsScroll: titleMetrics.contentWidth > parent.width
          }
        }
      }

      // Vertical layout
      Item {
        visible: isVertical
        anchors.centerIn: parent
        width: showProgressRing ? (Style.baseWidgetSize * 0.5 * scaling) : (verticalSize - 4 * scaling)
        height: width
        z: 1

        ProgressRing {
          anchors.fill: parent
          anchors.margins: -4
          visible: showProgressRing
          progress: MediaService.trackLength > 0 ? MediaService.currentPosition / MediaService.trackLength : 0
          lineWidth: 2.5 * scaling
        }

        NImageRounded {
          visible: showAlbumArt && hasPlayer
          anchors.fill: parent
          radius: width / 2
          imagePath: MediaService.trackArtUrl
          fallbackIcon: MediaService.isPlaying ? "media-pause" : "media-play"
          fallbackIconSize: 12
          borderWidth: 0
        }

        NIcon {
          visible: !showAlbumArt || !hasPlayer
          anchors.centerIn: parent
          width: parent.width
          height: parent.height
          icon: hasPlayer ? (MediaService.isPlaying ? "media-pause" : "media-play") : "disc"
          color: hasPlayer ? Color.mOnSurface : Color.mOnSurfaceVariant
          pointSize: Style.fontSizeM * scaling
        }
      }

      // Mouse interaction
      MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: hasPlayer ? Qt.PointingHandCursor : Qt.ArrowCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton

        onClicked: mouse => {
                     if (mouse.button === Qt.LeftButton && hasPlayer && MediaService.canPlay) {
                       MediaService.playPause();
                     } else if (mouse.button === Qt.RightButton) {
                       TooltipService.hide();
                       var popupWindow = PanelService.getPopupMenuWindow(screen);
                       if (popupWindow) {
                         popupWindow.showContextMenu(contextMenu);
                         contextMenu.openAtItem(container, screen);
                       }
                     } else if (mouse.button === Qt.MiddleButton && hasPlayer && MediaService.canGoPrevious) {
                       MediaService.previous();
                       TooltipService.hide();
                     }
                   }

        onEntered: {
          if (isVertical || scrollingMode === "never") {
            TooltipService.show(root, title, BarService.getTooltipDirection());
          }
        }
        onExited: TooltipService.hide()
      }
    }
  }

  // Components
  Component {
    id: linearSpectrum
    NLinearSpectrum {
      width: parent.width - Style.marginS
      height: 20
      values: CavaService.values
      fillColor: Color.mPrimary
      opacity: 0.4
      barPosition: Settings.data.bar.position
    }
  }

  Component {
    id: mirroredSpectrum
    NMirroredSpectrum {
      width: parent.width - Style.marginS
      height: parent.height - Style.marginS
      values: CavaService.values
      fillColor: Color.mPrimary
      opacity: 0.4
    }
  }

  Component {
    id: waveSpectrum
    NWaveSpectrum {
      width: parent.width - Style.marginS
      height: parent.height - Style.marginS
      values: CavaService.values
      fillColor: Color.mPrimary
      opacity: 0.4
    }
  }

  // Progress Ring Component
  component ProgressRing: Canvas {
    property real progress: 0
    property real lineWidth: 2.5

    onProgressChanged: requestPaint()
    Component.onCompleted: requestPaint()

    Connections {
      target: Color
      function onMPrimaryChanged() {
        requestPaint();
      }
    }

    onPaint: {
      if (width <= 0 || height <= 0)
        return;

      var ctx = getContext("2d");
      var centerX = width / 2;
      var centerY = height / 2;
      var radius = Math.min(width, height) / 2 - lineWidth;

      ctx.reset();

      // Background
      ctx.beginPath();
      ctx.arc(centerX, centerY, radius, 0, 2 * Math.PI);
      ctx.lineWidth = lineWidth;
      ctx.strokeStyle = Qt.alpha(Color.mOnSurface, 0.4);
      ctx.stroke();

      // Progress
      ctx.beginPath();
      ctx.arc(centerX, centerY, radius, -Math.PI / 2, -Math.PI / 2 + progress * 2 * Math.PI);
      ctx.lineWidth = lineWidth;
      ctx.strokeStyle = Color.mPrimary;
      ctx.lineCap = "round";
      ctx.stroke();
    }
  }

  // Scrolling Text Component
  component ScrollingText: Item {
    id: scrollText
    property string text
    property color textColor
    property real fontSize
    property string scrollMode
    property bool needsScroll

    clip: true
    implicitHeight: titleText.height

    property bool isScrolling: false
    property bool isResetting: false

    Timer {
      id: scrollTimer
      interval: 1000
      onTriggered: {
        if (scrollMode === "always" && needsScroll) {
          scrollText.isScrolling = true;
          scrollText.isResetting = false;
        }
      }
    }

    MouseArea {
      id: hoverArea
      anchors.fill: parent
      hoverEnabled: true
      acceptedButtons: Qt.NoButton
      cursorShape: hasPlayer ? Qt.PointingHandCursor : Qt.ArrowCursor
    }

    function updateState() {
      if (scrollMode === "never") {
        isScrolling = false;
        isResetting = false;
      } else if (scrollMode === "always") {
        if (needsScroll) {
          if (hoverArea.containsMouse) {
            isScrolling = false;
            isResetting = true;
          } else {
            scrollTimer.restart();
          }
        }
      } else if (scrollMode === "hover") {
        isScrolling = hoverArea.containsMouse && needsScroll;
        isResetting = !hoverArea.containsMouse && needsScroll;
      }
    }

    onWidthChanged: updateState()
    Component.onCompleted: updateState()
    Connections {
      target: hoverArea
      function onContainsMouseChanged() {
        scrollText.updateState();
      }
    }

    Item {
      id: scrollContainer
      height: parent.height
      property real scrollX: 0
      x: scrollX

      RowLayout {
        spacing: 50
        NText {
          id: titleText
          text: scrollText.text
          color: textColor
          pointSize: fontSize
          applyUiScale: false
          font.weight: Style.fontWeightMedium
          onTextChanged: {
            scrollText.isScrolling = false;
            scrollText.isResetting = false;
            scrollContainer.scrollX = 0;
            if (scrollText.needsScroll)
              scrollTimer.restart();
          }
        }
        NText {
          text: scrollText.text
          color: textColor
          pointSize: fontSize
          applyUiScale: false
          font.weight: Style.fontWeightMedium
          visible: scrollText.needsScroll && scrollText.isScrolling
        }
      }

      NumberAnimation on scrollX {
        running: scrollText.isResetting
        to: 0
        duration: 300
        easing.type: Easing.OutQuad
        onFinished: scrollText.isResetting = false
      }

      NumberAnimation on scrollX {
        running: scrollText.isScrolling && !scrollText.isResetting
        from: 0
        to: -(titleMetrics.contentWidth + 50)
        duration: Math.max(4000, scrollText.text.length * 120)
        loops: Animation.Infinite
        easing.type: Easing.Linear
      }
    }
  }
}
