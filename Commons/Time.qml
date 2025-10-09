pragma Singleton

import Quickshell
import QtQuick
import qs.Commons
import qs.Services

Singleton {
  id: root

  // Current date
  property var date: new Date()

  // Returns a Unix Timestamp (in seconds)
  readonly property int timestamp: {
    return Math.floor(date / 1000)
  }

  Timer {
    interval: 1000
    repeat: true
    running: true
    onTriggered: root.date = new Date()
  }

  // Formats a Date object into a YYYYMMDD-HHMMSS string.
  function getFormattedTimestamp(date) {
    if (!date) {
      date = new Date()
    }
    const year = date.getFullYear()

    // getMonth() is zero-based, so we add 1
    const month = String(date.getMonth() + 1).padStart(2, '0')
    const day = String(date.getDate()).padStart(2, '0')

    const hours = String(date.getHours()).padStart(2, '0')
    const minutes = String(date.getMinutes()).padStart(2, '0')
    const seconds = String(date.getSeconds()).padStart(2, '0')

    return `${year}${month}${day}-${hours}${minutes}${seconds}`
  }

  // Format an easy to read approximate duration ex: 4h 32m
  // Used to display the time remaining on the Battery widget, computer uptime, etc..
  function formatVagueHumanReadableDuration(totalSeconds) {
    if (typeof totalSeconds !== 'number' || totalSeconds < 0) {
      return '0s'
    }

    // Floor the input to handle decimal seconds
    totalSeconds = Math.floor(totalSeconds)

    const days = Math.floor(totalSeconds / 86400)
    const hours = Math.floor((totalSeconds % 86400) / 3600)
    const minutes = Math.floor((totalSeconds % 3600) / 60)
    const seconds = totalSeconds % 60

    const parts = []
    if (days)
      parts.push(`${days}d`)
    if (hours)
      parts.push(`${hours}h`)
    if (minutes)
      parts.push(`${minutes}m`)

    // Only show seconds if no hours and no minutes
    if (!hours && !minutes) {
      parts.push(`${seconds}s`)
    }

    return parts.join(' ')
  }

  // Format a date into
  function formatRelativeTime(date) {
    if (!date)
      return ""
    const diff = Date.now() - date.getTime()
    if (diff < 60000)
      return "now"
    if (diff < 3600000)
      return `${Math.floor(diff / 60000)}m ago`
    if (diff < 86400000)
      return `${Math.floor(diff / 3600000)}h ago`
    return `${Math.floor(diff / 86400000)}d ago`
  }
}
