import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Services
import qs.Widgets

// ToastManager creates toast overlays on each screen
Variants {
  model: Quickshell.screens

  delegate: PanelWindow {
    id: root

    required property ShellScreen modelData
    readonly property real scaling: ScalingService.scale(screen)
    screen: modelData

    // Only show on screens that have notifications enabled
    visible: modelData ? (Settings.data.notifications.monitors.includes(modelData.name)
                         || (Settings.data.notifications.monitors.length === 0)) : false

    // Position based on bar location, like Notification popup does
    anchors {
      top: Settings.data.bar.position === "top"
      bottom: Settings.data.bar.position === "bottom"
      left: true
      right: true
    }

    // Set margins based on bar position
    margins.top: Settings.data.bar.position === "top" ? (Style.barHeight + Style.marginS) * scaling : 0
    margins.bottom: Settings.data.bar.position === "bottom" ? (Style.barHeight + Style.marginS) * scaling : 0

    // Small height when hidden, appropriate height when visible
    implicitHeight: toast.visible ? toast.height + Style.marginS * scaling : 1

    // Transparent background
    color: Color.transparent

    // High layer to appear above other panels
    //WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: PanelWindow.ExclusionMode.Ignore

    NToast {
      id: toast
      scaling: root.scaling

      // Simple positioning - margins already account for bar
      targetY: Style.marginS * scaling

      // Hidden position based on bar location
      hiddenY: Settings.data.bar.position === "top" ? -toast.height - 20 : toast.height + 20

      Component.onCompleted: {
        // Only register toasts for screens that have notifications enabled
        if (modelData ? (Settings.data.notifications.monitors.includes(modelData.name)
                        || (Settings.data.notifications.monitors.length === 0)) : false) {
          // Register this toast with the service
          ToastService.allToasts.push(toast)

          // Connect dismissal signal
          toast.dismissed.connect(ToastService.onToastDismissed)
        }
      }
    }
  }
}
