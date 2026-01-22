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

  // Bar orientation (per-screen)
  readonly property string barPosition: Settings.getBarPositionForScreen(screen?.name)
  readonly property bool isVertical: barPosition === "left" || barPosition === "right"

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
  readonly property int artSize: Style.toOdd(Style.capsuleHeight * 0.75)
  readonly property int iconSize: Style.toOdd(Style.capsuleHeight * 0.75)
  readonly property int verticalSize: Style.toOdd(Style.capsuleHeight * 0.85)
  readonly property int progressWidth: 2

  // State
  readonly property bool hasPlayer: !MediaService.currentPlayer
  readonly property bool shouldHideIdle: (hideMode === "idle" || hideWhenIdle) && !MediaService.isPlaying
  readonly property bool shouldHideEmpty: !hasPlayer && hideMode === "hidden"
  readonly property bool isHidden: shouldHideIdle || shouldHideEmpty

  // Title
  readonly property string title: {
    if (!hasPlayer)
      return I18n.tr("bar.media-mini.no-active-player");
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
    controls.push("Left click to open player.");
    controls.push("Right click for options.");
    if (MediaService.canGoPrevious)
      controls.push("Middle click for previous.");
    return controls.length ? `${text}\n\n${controls.join("\n")}` : text;
  }

  // Layout
  // For horizontal bars, height is always capsuleHeight (no animation needed to prevent jitter)
  // For vertical bars, collapse to 0 when hidden
  implicitWidth: isVertical ? (isHidden ? 0 : verticalSize) : (isHidden ? 0 : contentWidth)
  implicitHeight: isVertical ? (isHidden ? 0 : verticalSize) : Style.capsuleHeight
  visible: !shouldHideIdle && (hideMode !== "hidden" || opacity > 0)
  opacity: isHidden ? 0.0 : ((hideMode === "transparent" && !hasPlayer) ? 0.0 : 1.0)

  property real mainContentWidth: 0
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

    var margins = isVertical ? 0 : (Style.marginS * 2);

    // Add spacing and text width
    var textWidth = 0;
    if (titleContainer.measuredWidth > 0) {
      margins += Style.marginS;
      textWidth = titleContainer.measuredWidth + Style.marginXS;
    }

    var total = iconWidth + textWidth + margins;

    // calculate the width of all elements except the scrolling text
    mainContentWidth = total - textWidth;

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

  // Context menu
  NPopupContextMenu {
    id: contextMenu
    model: {
      var items = [];
      if (hasPlayer && MediaService.canPlay) {
        items.push({
                     "label": MediaService.isPlaying ? I18n.tr("common.pause") : I18n.tr("common.play"),
                     "action": "play-pause",
                     "icon": MediaService.isPlaying ? "media-pause" : "media-play"
                   });
      }
      if (hasPlayer && MediaService.canGoPrevious) {
        items.push({
                     "label": I18n.tr("common.previous"),
                     "action": "previous",
                     "icon": "media-prev"
                   });
      }
      if (hasPlayer && MediaService.canGoNext) {
        items.push({
                     "label": I18n.tr("common.next"),
                     "action": "next",
                     "icon": "media-next"
                   });
      }

      // Append available players (like in Control Center) so user can switch from the bar
      var players = MediaService.getAvailablePlayers ? MediaService.getAvailablePlayers() : [];
      if (players && players.length > 1) {
        for (var i = 0; i < players.length; i++) {
          var isCurrent = (i === MediaService.selectedPlayerIndex);
          items.push({
                       "label": players[i].identity,
                       "action": "player-" + i,
                       "icon": isCurrent ? "check" : "disc",
                       "enabled": true,
                       "visible": true
                     });
        }
      }

      items.push({
                   "label": I18n.tr("actions.widget-settings"),
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
                   else if (action && action.indexOf("player-") === 0) {
                     var idx = parseInt(action.split("-")[1]);
                     if (!isNaN(idx)) {
                       MediaService.switchToPlayer(idx);
                     }
                   } else if (action === "widget-settings") {
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
      anchors.leftMargin: isVertical ? 0 : Style.marginS
      anchors.rightMargin: isVertical ? 0 : Style.marginS

      // Visualizer
      Loader {
        x: Style.pixelAlignCenter(parent.width, width)
        y: Style.pixelAlignCenter(parent.height, height)
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
        spacing: Style.marginS
        visible: !isVertical
        z: 1

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
            lineWidth: root.progressWidth
          }

          NImageRounded {
            visible: showAlbumArt && hasPlayer
            anchors.fill: parent
            anchors.margins: showProgressRing ? root.progressWidth * 2 : 0
            radius: width / 2
            imagePath: MediaService.trackArtUrl
            borderWidth: 0
            imageFillMode: Image.PreserveAspectCrop
          }
        }

        // Scrolling title
        NScrollText {
          id: titleContainer
          Layout.fillWidth: true
          Layout.alignment: Qt.AlignVCenter
          Layout.preferredHeight: Style.capsuleHeight

          text: title

          scrollMode: {
            if (scrollingMode === "always")
              return NScrollText.ScrollMode.Always;
            if (scrollingMode === "hover")
              return NScrollText.ScrollMode.Hover;
            return NScrollText.ScrollMode.Never;
          }
          cursorShape: hasPlayer ? Qt.PointingHandCursor : Qt.ArrowCursor
          maxWidth: root.maxWidth - root.mainContentWidth
          NText {
            // anchors.fill: parent
            color: hasPlayer ? Color.mOnSurface : Color.mOnSurfaceVariant
            pointSize: Style.barFontSize
          }
        }
      }

      // Vertical layout
      Item {
        id: verticalLayout
        visible: isVertical
        width: verticalSize
        height: width
        x: Style.pixelAlignCenter(parent.width, width)
        y: Style.pixelAlignCenter(parent.height, height)
        z: 1

        ProgressRing {
          anchors.fill: parent
          visible: showProgressRing
          progress: MediaService.trackLength > 0 ? MediaService.currentPosition / MediaService.trackLength : 0
          lineWidth: root.progressWidth
        }

        NImageRounded {
          visible: showAlbumArt && hasPlayer
          anchors.fill: parent
          anchors.margins: showProgressRing ? root.progressWidth * 2 : 0
          radius: width / 2
          imagePath: MediaService.trackArtUrl
          borderWidth: 0
          imageFillMode: Image.PreserveAspectCrop
        }
      }

      // Mouse interaction
      MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton

        onClicked: mouse => {
                     if (mouse.button === Qt.LeftButton) {
                       PanelService.getPanel("mediaPlayerPanel", screen)?.toggle(container);
                     } else if (mouse.button === Qt.RightButton) {
                       TooltipService.hide();
                       var popupWindow = PanelService.getPopupMenuWindow(screen);
                       if (popupWindow) {
                         popupWindow.showContextMenu(contextMenu);
                         contextMenu.openAtItem(container, screen);
                       }
                     } else if (mouse.button === Qt.MiddleButton && hasPlayer) {
                       MediaService.playPause();
                       TooltipService.hide();
                     }
                   }

        onEntered: {
          if (isVertical || scrollingMode === "never") {
            TooltipService.show(root, title, BarService.getTooltipDirection(root.screen?.name));
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
      barPosition: root.barPosition
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
    property real lineWidth: 2

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
}
