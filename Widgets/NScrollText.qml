import QtQuick
import QtQuick.Layouts
import qs.Commons

/*
NScrollText {
NText {
pointSize: Style.fontSizeS
// here any NText properties can be used
}
maxWidth: 200
text: "Some long long long text"
scrollMode: NScrollText.ScrollMode.Always
}
*/

Item {
  id: root

  required property string text
  default property Component delegate: NText {
    pointSize: Style.fontSizeS
  }

  property real maxWidth: Infinity

  enum ScrollMode {
    Never = 0,
    Always = 1,
    Hover = 2
  }

  property int scrollMode: NScrollText.ScrollMode.Never
  property bool alwaysMaxWidth: false
  property bool forcedHover: false
  property int cursorShape: Qt.ArrowCursor

  // animation controls
  property real waitBeforeScrolling: 1000
  property real scrollCycleDuration: Math.max(4000, root.text.length * 120)
  property real resettingDuration: 300

  readonly property real contentWidth: {
    if (!titleText.item)
      return 0;
    const implicit = titleText.item.implicitWidth;
    return implicit > 0 ? implicit : titleText.item.width;
  }
  readonly property real measuredWidth: scrollContainer.width

  clip: true
  implicitWidth: alwaysMaxWidth ? maxWidth : Math.min(maxWidth, contentWidth)
  implicitHeight: titleText.height

  enum ScrollState {
    None = 0,
    Scrolling = 1,
    Resetting = 2
  }

  property int state: NScrollText.ScrollState.None

  onTextChanged: {
    if (titleText.item)
      titleText.item.text = text;
    if (loopingText.item)
      loopingText.item.text = text;

    // reset state
    resetState();
  }
  onMaxWidthChanged: resetState()
  onContentWidthChanged: root.updateState()
  onForcedHoverChanged: updateState()

  function resetState() {
    root.state = NScrollText.ScrollState.None;
    scrollContainer.x = 0;
    scrollTimer.restart();
    root.updateState();
  }

  Timer {
    id: scrollTimer
    interval: root.waitBeforeScrolling
    onTriggered: {
      root.state = NScrollText.ScrollState.Scrolling;
      root.updateState();
    }
  }

  MouseArea {
    id: hoverArea
    anchors.fill: parent
    hoverEnabled: true
    acceptedButtons: Qt.NoButton
    onEntered: root.updateState()
    onExited: root.updateState()
    cursorShape: root.cursorShape
  }

  function ensureReset() {
    if (state === NScrollText.ScrollState.Scrolling)
      state = NScrollText.ScrollState.Resetting;
  }

  function updateState() {
    if (contentWidth <= root.maxWidth || scrollMode === NScrollText.ScrollMode.Never) {
      state = NScrollText.ScrollState.None;
      return;
    }
    if (scrollMode === NScrollText.ScrollMode.Always) {
      if (hoverArea.containsMouse) {
        ensureReset();
      } else {
        scrollTimer.restart();
      }
    } else if (scrollMode === NScrollText.ScrollMode.Hover) {
      if (hoverArea.containsMouse || forcedHover)
        state = NScrollText.ScrollState.Scrolling;
      else
        ensureReset();
    }
  }

  RowLayout {
    id: scrollContainer
    height: parent.height
    x: 0
    spacing: 50

    Loader {
      id: titleText
      sourceComponent: root.delegate
      Layout.fillHeight: true
      onLoaded: {
        this.item.text = root.text;
        // Bind height to container to enable vertical centering of overly high text
        this.item.height = Qt.binding(() => titleText.height);
      }
    }

    Loader {
      id: loopingText
      sourceComponent: root.delegate
      Layout.fillHeight: true
      visible: root.state !== NScrollText.ScrollState.None
      onLoaded: {
        this.item.text = root.text;
        this.item.height = Qt.binding(() => loopingText.height);
      }
    }

    NumberAnimation on x {
      running: root.state === NScrollText.ScrollState.Resetting
      to: 0
      duration: root.resettingDuration
      easing.type: Easing.OutQuad
      onFinished: {
        root.state = NScrollText.ScrollState.None;
        root.updateState();
      }
    }

    NumberAnimation on x {
      running: root.state === NScrollText.ScrollState.Scrolling
      to: -(titleText.width + scrollContainer.spacing)
      duration: root.scrollCycleDuration
      loops: Animation.Infinite
      easing.type: Easing.Linear
    }
  }
}
