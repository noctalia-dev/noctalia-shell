pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

Singleton {
  id: root

  // Queue of pending toast messages
  property var messageQueue: []
  property bool isShowingToast: false

  // Reference to all toast instances (set by ToastManager)
  property var allToasts: []

  // Properties for command checking
  property var commandCheckCallback: null
  property string commandCheckSuccessMessage: ""
  property string commandCheckFailMessage: ""

  // Properties for command running
  property var commandRunCallback: null
  property string commandRunSuccessMessage: ""
  property string commandRunFailMessage: ""

  // Properties for delayed toast
  property string delayedToastMessage: ""
  property string delayedToastType: "notice"

  // Process for command checking
  Process {
    id: commandCheckProcess
    command: ["which", "test"]
    onExited: function (exitCode) {
      if (exitCode === 0) {
        showNotice(commandCheckSuccessMessage)
        if (commandCheckCallback)
          commandCheckCallback()
      } else {
        showWarning(commandCheckFailMessage)
      }
    }
    stdout: StdioCollector {}
    stderr: StdioCollector {}
  }

  // Process for command running
  Process {
    id: commandRunProcess
    command: ["echo", "test"]
    onExited: function (exitCode) {
      if (exitCode === 0) {
        showNotice(commandRunSuccessMessage)
        if (commandRunCallback)
          commandRunCallback()
      } else {
        showWarning(commandRunFailMessage)
      }
    }
    stdout: StdioCollector {}
    stderr: StdioCollector {}
  }

  // Timer for delayed toast
  Timer {
    id: delayedToastTimer
    interval: 1000
    repeat: false
    onTriggered: {
      showToast(delayedToastMessage, delayedToastType)
    }
  }

  // Methods to show different types of messages
  function showNotice(label, description = "", persistent = false, duration = 3000) {
    showToast(label, description, "notice", persistent, duration)
  }

  function showWarning(label, description = "", persistent = false, duration = 4000) {
    showToast(label, description, "warning", persistent, duration)
  }

  // Utility function to check if a command exists and show appropriate toast
  function checkCommandAndToast(command, successMessage, failMessage, onSuccess = null) {
    // Store callback for use in the process
    commandCheckCallback = onSuccess
    commandCheckSuccessMessage = successMessage
    commandCheckFailMessage = failMessage

    // Start the command check process
    commandCheckProcess.command = ["which", command]
    commandCheckProcess.running = true
  }

  // Simple function to show a random toast (useful for testing or fun messages)
  function showRandomToast() {
    var messages = [{
                      "type": "notice",
                      "text": "Everything is working smoothly!"
                    }, {
                      "type": "notice",
                      "text": "Noctalia is looking great today!"
                    }, {
                      "type": "notice",
                      "text": "Your desktop setup is amazing!"
                    }, {
                      "type": "warning",
                      "text": "Don't forget to take a break!"
                    }, {
                      "type": "notice",
                      "text": "Configuration saved successfully!"
                    }, {
                      "type": "warning",
                      "text": "Remember to backup your settings!"
                    }]

    var randomMessage = messages[Math.floor(Math.random() * messages.length)]
    showToast(randomMessage.text, randomMessage.type)
  }

  // Convenience function for quick notifications
  function quickNotice(message) {
    showNotice(message, false, 2000) // Short duration
  }

  function quickWarning(message) {
    showWarning(message, false, 3000) // Medium duration
  }

  // Generic command runner with toast feedback
  function runCommandWithToast(command, args, successMessage, failMessage, onSuccess = null) {
    // Store callback for use in the process
    commandRunCallback = onSuccess
    commandRunSuccessMessage = successMessage
    commandRunFailMessage = failMessage

    // Start the command run process
    commandRunProcess.command = [command].concat(args || [])
    commandRunProcess.running = true
  }

  // Check if a file/directory exists
  function checkPathAndToast(path, successMessage, failMessage, onSuccess = null) {
    runCommandWithToast("test", ["-e", path], successMessage, failMessage, onSuccess)
  }

  // Show toast after a delay (useful for delayed feedback)
  function delayedToast(message, type = "notice", delayMs = 1000) {
    delayedToastMessage = message
    delayedToastType = type
    delayedToastTimer.interval = delayMs
    delayedToastTimer.restart()
  }

  // Generic method to show a toast
  function showToast(label, description = "", type = "notice", persistent = false, duration = 3000) {
    var toastData = {
      "label": label,
      "description": description,
      "type": type,
      "persistent": persistent,
      "duration": duration,
      "timestamp": Date.now()
    }

    // Add to queue
    messageQueue.push(toastData)

    // Process queue if not currently showing a toast
    if (!isShowingToast) {
      processQueue()
    }
  }

  // Process the message queue
  function processQueue() {
    if (messageQueue.length === 0 || allToasts.length === 0) {
      isShowingToast = false
      return
    }

    if (isShowingToast) {
      // Wait for current toast to finish
      return
    }

    var toastData = messageQueue.shift()
    isShowingToast = true

    // Configure and show toast on all screens
    for (var i = 0; i < allToasts.length; i++) {
      var toast = allToasts[i]
      toast.label = toastData.label
      toast.description = toastData.description
      toast.type = toastData.type
      toast.persistent = toastData.persistent
      toast.duration = toastData.duration
      toast.show()
    }
  }

  // Called when a toast is dismissed
  function onToastDismissed() {
    // Check if all toasts are dismissed
    var allDismissed = true
    for (var i = 0; i < allToasts.length; i++) {
      if (allToasts[i].visible) {
        allDismissed = false
        break
      }
    }

    if (allDismissed) {
      isShowingToast = false

      // Small delay before showing next toast
      Qt.callLater(function () {
        processQueue()
      })
    }
  }

  // Clear all pending messages
  function clearQueue() {

    messageQueue = []
  }

  // Hide current toast
  function hideCurrentToast() {
    if (isShowingToast) {
      for (var i = 0; i < allToasts.length; i++) {
        allToasts[i].hide()
      }
    }
  }

  Component.onCompleted: {

  }
}
