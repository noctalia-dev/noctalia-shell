import QtQuick
import qs.Commons
import qs.Services.Compositor
import qs.Widgets

Item {
  id: pillContainer

  required property var workspace
  required property bool isVertical

  // These must be provided by the parent Workspace widget
  required property real baseDimensionRatio
  required property real capsuleHeight
  required property real barHeight
  required property string labelMode
  required property int characterCount
  required property real textRatio
  required property bool showLabelsOnlyWhenOccupied
  required property string focusedColor
  required property string occupiedColor
  required property string emptyColor
  required property real masterProgress
  required property bool effectsActive
  required property color effectColor
  required property var getWorkspaceWidth
  required property var getWorkspaceHeight

  // Fixed dimension (cross-axis) for visual pill
  readonly property real fixedDimension: Style.toOdd(capsuleHeight * baseDimensionRatio)

  // Helper to safely get colors with proper reactivity
  // Accesses Color singleton directly to ensure fresh values
  function getColorPair(colorKey) {
    switch (colorKey) {
    case "primary":
      return [Color.mPrimary, Color.mOnPrimary];
    case "secondary":
      return [Color.mSecondary, Color.mOnSecondary];
    case "tertiary":
      return [Color.mTertiary, Color.mOnTertiary];
    case "onSurface":
      return [Color.mOnSurface, Color.mSurface];
    default:
      return [Color.mPrimary, Color.mOnPrimary];
    }
  }

  // Animated pill dimensions (for visual pill, not container)
  property real pillWidth: isVertical ? fixedDimension : getWorkspaceWidth(workspace, false)
  property real pillHeight: isVertical ? getWorkspaceHeight(workspace, false) : fixedDimension

  // Container uses full barHeight on cross-axis for larger click area
  width: isVertical ? barHeight : getWorkspaceWidth(workspace, false)
  height: isVertical ? getWorkspaceHeight(workspace, false) : barHeight

  states: [
    State {
      name: "active"
      when: workspace.isActive
      PropertyChanges {
        target: pillContainer
        width: isVertical ? barHeight : getWorkspaceWidth(workspace, true)
        height: isVertical ? getWorkspaceHeight(workspace, true) : barHeight
        pillWidth: isVertical ? fixedDimension : getWorkspaceWidth(workspace, true)
        pillHeight: isVertical ? getWorkspaceHeight(workspace, true) : fixedDimension
      }
    }
  ]

  transitions: [
    Transition {
      from: "inactive"
      to: "active"
      NumberAnimation {
        properties: isVertical ? "height,pillHeight" : "width,pillWidth"
        duration: Style.animationNormal
        easing.type: Easing.OutBack
      }
    },
    Transition {
      from: "active"
      to: "inactive"
      NumberAnimation {
        properties: isVertical ? "height,pillHeight" : "width,pillWidth"
        duration: Style.animationNormal
        easing.type: Easing.OutBack
      }
    }
  ]

  Rectangle {
    id: pill
    width: pillContainer.pillWidth
    height: pillContainer.pillHeight
    x: Style.pixelAlignCenter(parent.width, width)
    y: Style.pixelAlignCenter(parent.height, height)
    radius: Style.radiusM
    z: 0

    color: {
      if (pillMouseArea.containsMouse)
        return Color.mHover;
      if (workspace.isFocused)
        return getColorPair(focusedColor)[0];
      if (workspace.isUrgent)
        return Color.mError;
      if (workspace.isOccupied)
        return getColorPair(occupiedColor)[0];
      return Qt.alpha(getColorPair(emptyColor)[0], 0.3);
    }

    Loader {
      active: (labelMode !== "none") && (!showLabelsOnlyWhenOccupied || workspace.isOccupied || workspace.isFocused)
      anchors.fill: parent
      sourceComponent: Component {
        NText {
          text: {
            if (workspace.name && workspace.name.length > 0) {
              if (labelMode === "name") {
                return workspace.name.substring(0, characterCount);
              }
              if (labelMode === "index+name") {
                // Vertical mode: compact format (no space, first char only)
                // Horizontal mode: full format (space, more chars)
                if (isVertical) {
                  return workspace.idx.toString() + workspace.name.substring(0, 1);
                }
                return workspace.idx.toString() + " " + workspace.name.substring(0, characterCount);
              }
            }
            return workspace.idx.toString();
          }
          family: Settings.data.ui.fontFixed
          // Size based on the fixed dimension (cross-axis) of the visual pill
          pointSize: (isVertical ? pillContainer.pillWidth : pillContainer.pillHeight) * textRatio
          applyUiScale: false
          font.capitalization: Font.AllUppercase
          font.weight: Style.fontWeightBold
          horizontalAlignment: Text.AlignHCenter
          verticalAlignment: Text.AlignVCenter
          wrapMode: Text.Wrap
          color: {
            if (pillMouseArea.containsMouse)
              return Color.mOnHover;
            if (workspace.isFocused)
              return getColorPair(focusedColor)[1];
            if (workspace.isUrgent)
              return Color.mOnError;
            if (workspace.isOccupied)
              return getColorPair(occupiedColor)[1];
            return getColorPair(emptyColor)[1];
          }

          Behavior on color {
            enabled: !Color.isTransitioning
            ColorAnimation {
              duration: Style.animationFast
              easing.type: Style.easingTypeSlow
            }
          }
        }
      }
    }

    // Material 3-inspired smooth animations
    Behavior on scale {
      NumberAnimation {
        duration: Style.animationNormal
        easing.type: Easing.OutBack
      }
    }
    Behavior on color {
      enabled: !Color.isTransitioning
      ColorAnimation {
        duration: Style.animationFast
        easing.type: Style.easingTypeSlow
      }
    }
    Behavior on opacity {
      NumberAnimation {
        duration: Style.animationFast
        easing.type: Style.easingTypeSlow
      }
    }
    Behavior on radius {
      NumberAnimation {
        duration: Style.animationNormal
        easing.type: Easing.OutBack
      }
    }
  }

  Behavior on width {
    NumberAnimation {
      duration: Style.animationNormal
      easing.type: Easing.OutBack
    }
  }
  Behavior on height {
    NumberAnimation {
      duration: Style.animationNormal
      easing.type: Easing.OutBack
    }
  }
  Behavior on pillWidth {
    NumberAnimation {
      duration: Style.animationNormal
      easing.type: Easing.OutBack
    }
  }
  Behavior on pillHeight {
    NumberAnimation {
      duration: Style.animationNormal
      easing.type: Easing.OutBack
    }
  }

  // Full-height click area
  MouseArea {
    id: pillMouseArea
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    hoverEnabled: true
    onClicked: {
      CompositorService.switchToWorkspace(workspace);
    }
  }

  // Burst effect overlay for focused pill
  Rectangle {
    id: pillBurst
    anchors.centerIn: pill
    width: pillContainer.pillWidth + 18 * masterProgress * scale
    height: pillContainer.pillHeight + 18 * masterProgress * scale
    radius: width / 2
    color: "transparent"
    border.color: effectColor
    border.width: Math.max(1, Math.round((2 + 6 * (1.0 - masterProgress))))
    opacity: effectsActive && workspace.isFocused ? (1.0 - masterProgress) * 0.7 : 0
    visible: effectsActive && workspace.isFocused
    z: 1
  }
}
