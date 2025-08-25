import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services

Item {
  id: root

  property ShellScreen screen: null
  property real scaling: ScalingService.scale(screen)

  property bool isDestroying: false
  property bool hovered: false

  property ListModel localWorkspaces: ListModel {}
  property real masterProgress: 0.0
  property bool effectsActive: false
  property color effectColor: Color.mPrimary

  property int horizontalPadding: Math.round(16 * scaling)
  property int spacingBetweenPills: Math.round(8 * scaling)

  signal workspaceChanged(int workspaceId, color accentColor)

  implicitHeight: Math.round(36 * scaling)
  implicitWidth: {
    let total = 0
    for (var i = 0; i < localWorkspaces.count; i++) {
      const ws = localWorkspaces.get(i)
      if (ws.isFocused)
        total += Math.round(44 * scaling)
      else if (ws.isActive)
        total += Math.round(28 * scaling)
      else
        total += Math.round(16 * scaling)
    }
    total += Math.max(localWorkspaces.count - 1, 0) * spacingBetweenPills
    total += horizontalPadding * 2
    return total
  }

  Component.onCompleted: {
    refreshWorkspaces()
  }

  Component.onDestruction: {
    root.isDestroying = true
  }

  onScreenChanged: refreshWorkspaces()

  Connections {
    target: WorkspaceService
    function onWorkspacesChanged() {
      refreshWorkspaces()
    }
  }

  function refreshWorkspaces() {
    localWorkspaces.clear()
    if (screen !== null) {
      for (var i = 0; i < WorkspaceService.workspaces.count; i++) {
        const ws = WorkspaceService.workspaces.get(i)
        if (ws.output.toLowerCase() === screen.name.toLowerCase()) {
          localWorkspaces.append(ws)
        }
      }
    }
    workspaceRepeater.model = localWorkspaces
    updateWorkspaceFocus()
  }

  function triggerUnifiedWave() {
    effectColor = Color.mPrimary
    masterAnimation.restart()
  }

  function updateWorkspaceFocus() {
    for (var i = 0; i < localWorkspaces.count; i++) {
      const ws = localWorkspaces.get(i)
      if (ws.isFocused === true) {
        root.triggerUnifiedWave()
        root.workspaceChanged(ws.id, Color.mPrimary)
        break
      }
    }
  }

  SequentialAnimation {
    id: masterAnimation
    PropertyAction {
      target: root
      property: "effectsActive"
      value: true
    }
    NumberAnimation {
      target: root
      property: "masterProgress"
      from: 0.0
      to: 1.0
      duration: 1000
      easing.type: Easing.OutQuint
    }
    PropertyAction {
      target: root
      property: "effectsActive"
      value: false
    }
    PropertyAction {
      target: root
      property: "masterProgress"
      value: 0.0
    }
  }

  Rectangle {
    id: workspaceBackground
    width: parent.width - Style.marginS * scaling * 2

    height: Math.round(Style.capsuleHeight * scaling)
    radius: Math.round(Style.radiusM * scaling)
    color: Color.mSurfaceVariant

    anchors.horizontalCenter: parent.horizontalCenter
    anchors.verticalCenter: parent.verticalCenter
    layer.enabled: true
    layer.effect: MultiEffect {
      shadowColor: Color.mShadow
      shadowVerticalOffset: 0
      shadowHorizontalOffset: 0
      shadowOpacity: 0.10
    }
  }

  Row {
    id: pillRow
    spacing: spacingBetweenPills
    anchors.verticalCenter: workspaceBackground.verticalCenter
    width: root.width - horizontalPadding * 2
    x: horizontalPadding
    Repeater {
      id: workspaceRepeater
      model: localWorkspaces
      Item {
        id: workspacePillContainer
        height: Math.round(12 * scaling)
        width: {
          if (model.isFocused)
            return Math.round(44 * scaling)
          else if (model.isActive)
            return Math.round(28 * scaling)
          else
            return Math.round(16 * scaling)
        }

        Rectangle {
          id: workspacePill
          anchors.fill: parent
          radius: {
            if (model.isFocused)
              return Math.round(12 * scaling)
            else
              // half of focused height (if you want to animate this too)
              return Math.round(6 * scaling)
          }
          color: {
            if (model.isFocused)
              return Color.mPrimary
            if (model.isUrgent)
              return Color.mError
            if (model.isActive || model.isOccupied)
              return Color.mSecondary
            if (model.isUrgent)
              return Color.mError

            return Color.mOutline
          }
          scale: model.isFocused ? 1.0 : 0.9
          z: 0

          MouseArea {
            id: pillMouseArea
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              WorkspaceService.switchToWorkspace(model.idx)
            }
            hoverEnabled: true
          }
          // Material 3-inspired smooth animation for width, height, scale, color, opacity, and radius
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
          Behavior on scale {
            NumberAnimation {
              duration: Style.animationNormal
              easing.type: Easing.OutBack
            }
          }
          Behavior on color {
            ColorAnimation {
              duration: Style.animationFast
              easing.type: Easing.InOutCubic
            }
          }
          Behavior on opacity {
            NumberAnimation {
              duration: Style.animationFast
              easing.type: Easing.InOutCubic
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
        // Burst effect overlay for focused pill (smaller outline)
        Rectangle {
          id: pillBurst
          anchors.centerIn: workspacePillContainer
          width: workspacePillContainer.width + 18 * root.masterProgress * scale
          height: workspacePillContainer.height + 18 * root.masterProgress * scale
          radius: width / 2
          color: Color.transparent
          border.color: root.effectColor
          border.width: Math.max(1, Math.round((2 + 6 * (1.0 - root.masterProgress)) * scaling))
          opacity: root.effectsActive && model.isFocused ? (1.0 - root.masterProgress) * 0.7 : 0
          visible: root.effectsActive && model.isFocused
          z: 1
        }
      }
    }
  }
}
