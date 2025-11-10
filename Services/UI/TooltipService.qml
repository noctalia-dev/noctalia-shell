pragma Singleton

import QtQuick
import Quickshell
import qs.Commons
import qs.Modules.Tooltip

Singleton {
  id: root

  property var activeTooltip: null
  property var pendingTooltip: null // Track tooltip being created

  property Component tooltipComponent: Component {
    Tooltip {}
  }

  function show(screen, target, text, direction, delay) {
    if (!Settings.data.ui.tooltipsEnabled) {
      return
    }

    // Don't create if no text
    if (!screen || !target || !text) {
      Logger.i("Tooltip", "No target or text")
      return
    }

    // If we have a pending tooltip for a different target, cancel it
    if (pendingTooltip && pendingTooltip.targetItem !== target) {
      pendingTooltip.hideImmediately()
      pendingTooltip.destroy()
      pendingTooltip = null
    }

    // If we have an active tooltip for a different target, hide it
    if (activeTooltip && activeTooltip.targetItem !== target) {
      activeTooltip.hideImmediately()
      // Don't destroy immediately - let it clean itself up
      activeTooltip = null
    }

    // If we already have a tooltip for this target, just update it
    if (activeTooltip && activeTooltip.targetItem === target) {
      activeTooltip.updateText(text)
      return activeTooltip
    }

    // Create new tooltip instance
    const newTooltip = tooltipComponent.createObject(null)

    if (newTooltip) {
      // Track as pending until it's visible
      pendingTooltip = newTooltip

      // Connect cleanup when tooltip hides
      newTooltip.visibleChanged.connect(() => {
                                          if (!newTooltip.visible) {
                                            // Clean up after a delay to avoid interfering with new tooltips
                                            Qt.callLater(() => {
                                                           if (newTooltip && !newTooltip.visible) {
                                                             if (activeTooltip === newTooltip) {
                                                               activeTooltip = null
                                                             }
                                                             if (pendingTooltip === newTooltip) {
                                                               pendingTooltip = null
                                                             }
                                                             newTooltip.destroy()
                                                           }
                                                         })
                                          } else {
                                            // Tooltip is now visible, move from pending to active
                                            if (pendingTooltip === newTooltip) {
                                              activeTooltip = newTooltip
                                              pendingTooltip = null
                                            }
                                          }
                                        })

      // Show the tooltip
      newTooltip.show(screen, target, text, direction || "auto", delay || Style.tooltipDelay)

      return newTooltip
    } else {
      Logger.e("Tooltip", "Failed to create tooltip instance")
    }

    return null
  }

  function hide() {
    if (pendingTooltip) {
      pendingTooltip.hide()
    }
    if (activeTooltip) {
      activeTooltip.hide()
    }
  }

  function hideImmediately() {
    if (pendingTooltip) {
      pendingTooltip.hideImmediately()
      pendingTooltip.destroy()
      pendingTooltip = null
    }
    if (activeTooltip) {
      activeTooltip.hideImmediately()
      activeTooltip.destroy()
      activeTooltip = null
    }
  }

  function updateText(newText) {
    if (activeTooltip) {
      activeTooltip.updateText(newText)
    }
  }
}
