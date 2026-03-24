import QtQuick
import qs.Commons

Item {
  id: root

  property Component sourceComponent
  property bool animationsEnabled: true
  property int duration: Style.animationNormal
  property real transitionGap: Style.marginXL
  property real incomingStartOpacity: 0.0
  property real outgoingTargetOpacity: 0.25

  readonly property var item: contentLoader.item
  readonly property bool running: _running

  property bool _running: false
  property var _pendingApplyChange: null
  property real _contentOffset: 0
  property real _contentOpacity: 1
  property real _snapshotOffset: 0
  property real _snapshotOpacity: 0
  property real _snapshotTargetOffset: 0

  clip: true

  function resetVisuals() {
    _running = false;
    _pendingApplyChange = null;
    _contentOffset = 0;
    _contentOpacity = 1;
    _snapshotOffset = 0;
    _snapshotOpacity = 0;
    snapshot.visible = false;
    transition.stop();
  }

  function swap(direction, applyChange) {
    if (!animationsEnabled || width <= 0 || height <= 0 || direction === 0) {
      if (applyChange)
        applyChange();
      return;
    }

    if (_running)
      resetVisuals();

    const slideDistance = Math.max(1, width + transitionGap);
    const movingForward = direction > 0;

    snapshot.visible = true;
    _snapshotOffset = 0;
    _snapshotOpacity = 1;
    _snapshotTargetOffset = movingForward ? -slideDistance : slideDistance;

    _contentOffset = movingForward ? slideDistance : -slideDistance;
    _contentOpacity = incomingStartOpacity;

    _pendingApplyChange = applyChange || null;
    _running = true;
    snapshot.scheduleUpdate();

    Qt.callLater(() => {
                   if (!_running) {
                     return;
                   }

                   const applyFn = _pendingApplyChange;
                   _pendingApplyChange = null;
                   const shouldAnimate = applyFn ? applyFn() !== false : true;
                   if (!shouldAnimate) {
                     resetVisuals();
                     return;
                   }
                   transition.restart();
                 });
  }

  ShaderEffectSource {
    id: snapshot
    visible: false
    width: parent.width
    height: parent.height
    y: 0
    sourceItem: contentLoader
    hideSource: false
    live: false
    smooth: true
    z: 2
    x: root._snapshotOffset
    opacity: root._snapshotOpacity
  }

  Loader {
    id: contentLoader
    width: parent.width
    height: parent.height
    x: root._contentOffset
    opacity: root._contentOpacity
    sourceComponent: root.sourceComponent
  }

  ParallelAnimation {
    id: transition
    NumberAnimation {
      target: root
      property: "_contentOffset"
      to: 0
      duration: root.duration
      easing.type: Easing.OutCubic
    }
    NumberAnimation {
      target: root
      property: "_contentOpacity"
      to: 1
      duration: root.duration
      easing.type: Easing.OutCubic
    }
    NumberAnimation {
      target: root
      property: "_snapshotOffset"
      to: root._snapshotTargetOffset
      duration: root.duration
      easing.type: Easing.OutCubic
    }
    NumberAnimation {
      target: root
      property: "_snapshotOpacity"
      to: root.outgoingTargetOpacity
      duration: root.duration
      easing.type: Easing.OutCubic
    }
    onFinished: root.resetVisuals()
  }
}
