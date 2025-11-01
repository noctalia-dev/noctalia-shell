import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Services
import qs.Widgets

Item {
  id: root

  required property ShellScreen screen

  // Local queue for this screen only (bounded to prevent memory issues)
  property var messageQueue: []
  property int maxQueueSize: 10
  property bool isShowingToast: false

  // If true, immediately show new toasts
  property bool replaceOnNew: true

  Connections {
    target: ToastService

    function onNotify(message, description, icon, type, duration) {
      root.enqueueToast({
                          "message": message,
                          "description": description,
                          "icon": icon,
                          "type": type,
                          "duration": duration,
                          "timestamp": Date.now()
                        })
    }
  }

  // Clear queue on component destruction to prevent orphaned toasts
  Component.onDestruction: {
    messageQueue = []
    isShowingToast = false
    hideTimer.stop()
    quickSwitchTimer.stop()
  }

  function enqueueToast(toastData) {
    // Safe logging - fix the substring bug
    var descPreview = (toastData.description || "").substring(0, 100).replace(/\n/g, " ")
    Logger.i("ToastScreen", "Queuing", toastData.type, ":", toastData.message, descPreview)

    // Bounded queue to prevent unbounded memory growth
    if (messageQueue.length >= maxQueueSize) {
      Logger.i("ToastScreen", "Queue full, dropping oldest toast")
      messageQueue.shift()
    }

    if (replaceOnNew && isShowingToast) {
      // Cancel current toast and clear queue for latest toast
      messageQueue = [] // Clear existing queue
      messageQueue.push(toastData)

      // Hide current toast immediately
      if (windowLoader.item) {
        hideTimer.stop()
        windowLoader.item.hideToast()
      }

      // Process new toast after a brief delay
      isShowingToast = false
      quickSwitchTimer.restart()
    } else {
      // Queue the toast
      messageQueue.push(toastData)
      processQueue()
    }
  }

  Timer {
    id: quickSwitchTimer
    interval: 50 // Brief delay for smooth transition
    onTriggered: root.processQueue()
  }

  function processQueue() {
    if (messageQueue.length === 0 || isShowingToast) {
      return
    }

    var data = messageQueue.shift()
    isShowingToast = true

    // Store the toast data for when loader is ready
    windowLoader.pendingToast = data

    // Activate the loader - onStatusChanged will handle showing the toast
    windowLoader.active = true
  }

  function onToastHidden() {
    isShowingToast = false

    // Deactivate the loader to completely remove the window and free memory
    windowLoader.active = false

    // Small delay before processing next toast
    hideTimer.restart()
  }

  Timer {
    id: hideTimer
    interval: 200
    onTriggered: root.processQueue()
  }

  // The loader that creates/destroys the PanelWindow as needed
  // This is good for RAM efficiency when toasts are infrequent
  Loader {
    id: windowLoader
    active: false // Only active when showing a toast

    // Store pending toast data
    property var pendingToast: null

    onStatusChanged: {
      // When loader becomes ready, show the pending toast
      if (status === Loader.Ready && pendingToast !== null) {
        item.showToast(pendingToast.message, pendingToast.description, pendingToast.icon, pendingToast.type, pendingToast.duration)
        pendingToast = null
      }
    }

    sourceComponent: PanelWindow {
      id: panel

      property alias toastItem: toastItem

      screen: root.screen

      readonly property string location: (Settings.data.notifications && Settings.data.notifications.location) ? Settings.data.notifications.location : "top_right"
      readonly property bool isTop: (location === "top") || (location.length >= 3 && location.substring(0, 3) === "top")
      readonly property bool isBottom: (location === "bottom") || (location.length >= 6 && location.substring(0, 6) === "bottom")
      readonly property bool isLeft: location.indexOf("_left") >= 0
      readonly property bool isRight: location.indexOf("_right") >= 0
      readonly property bool isCentered: (location === "top" || location === "bottom")

      // Anchor selection based on location (window edges)
      anchors.top: isTop
      anchors.bottom: isBottom
      anchors.left: isLeft
      anchors.right: isRight

      // Margins depending on bar position and chosen location
      margins.top: {
        if (!(anchors.top))
          return 0
        var base = Style.marginM
        if (Settings.data.bar.position === "top") {
          var floatExtraV = Settings.data.bar.floating ? Settings.data.bar.marginVertical * Style.marginXL : 0
          return (Style.barHeight) + base + floatExtraV
        }
        return base
      }

      margins.bottom: {
        if (!(anchors.bottom))
          return 0
        var base = Style.marginM
        if (Settings.data.bar.position === "bottom") {
          var floatExtraV = Settings.data.bar.floating ? Settings.data.bar.marginVertical * Style.marginXL : 0
          return (Style.barHeight) + base + floatExtraV
        }
        return base
      }

      margins.left: {
        if (!(anchors.left))
          return 0
        var base = Style.marginM
        if (Settings.data.bar.position === "left") {
          var floatExtraH = Settings.data.bar.floating ? Settings.data.bar.marginHorizontal * Style.marginXL : 0
          return (Style.barHeight) + base + floatExtraH
        }
        return base
      }

      margins.right: {
        if (!(anchors.right))
          return 0
        var base = Style.marginM
        if (Settings.data.bar.position === "right") {
          var floatExtraH = Settings.data.bar.floating ? Settings.data.bar.marginHorizontal * Style.marginXL : 0
          return (Style.barHeight) + base + floatExtraH
        }
        return base
      }

      implicitWidth: 420
      implicitHeight: toastItem.height

      color: Color.transparent

      WlrLayershell.layer: (Settings.data.notifications && Settings.data.notifications.overlayLayer) ? WlrLayer.Overlay : WlrLayer.Top
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      exclusionMode: PanelWindow.ExclusionMode.Ignore

      function showToast(message, description, icon, type, duration) {
        toastItem.show(message, description, icon, type, duration)
      }

      function hideToast() {
        toastItem.hideImmediately()
      }

      SimpleToast {
        id: toastItem

        anchors.horizontalCenter: parent.horizontalCenter
        onHidden: root.onToastHidden()
      }
    }
  }
}
