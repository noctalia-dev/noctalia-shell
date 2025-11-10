pragma Singleton

import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Commons

Singleton {
  id: root

  // Expose the font family name for easy access
  readonly property string fontFamily: currentFontLoader ? currentFontLoader.name : ""
  readonly property string defaultIcon: IconsTabler.defaultIcon
  readonly property var icons: IconsTabler.icons
  readonly property var aliases: IconsTabler.aliases
  readonly property string fontPath: "/Assets/Fonts/tabler/tabler-icons.ttf"

  // Current active font loader
  property FontLoader currentFontLoader: null
  property int fontVersion: 0

  // Create a unique cache-busting path
  readonly property string cacheBustingPath: Quickshell.shellDir + fontPath + "?v=" + fontVersion + "&t=" + Date.now()

  // Signal emitted when font is reloaded
  signal fontReloaded

  Component.onCompleted: {
    Logger.i("Icons", "Service started")
    loadFontWithCacheBusting()
  }

  Connections {
    target: Quickshell
    function onReloadCompleted() {
      Logger.d("Icons", "Quickshell reload completed - forcing font reload")
      reloadFont()
    }
  }

  // ---------------------------------------
  function get(iconName) {
    // Check in aliases first
    if (aliases[iconName] !== undefined) {
      iconName = aliases[iconName]
    }

    // Find the appropriate codepoint
    return icons[iconName]
  }

  function loadFontWithCacheBusting() {
    Logger.d("Icons", "Loading font with cache busting")

    // Destroy old loader first
    if (currentFontLoader) {
      currentFontLoader.destroy()
      currentFontLoader = null
    }

    // Create new loader with cache-busting URL
    currentFontLoader = Qt.createQmlObject(`
                                           import QtQuick
                                           FontLoader {
                                           source: "${cacheBustingPath}"
                                           }
                                           `, root, "dynamicFontLoader_" + fontVersion)

    // Connect to the new loader's status changes
    currentFontLoader.statusChanged.connect(function () {
      if (currentFontLoader.status === FontLoader.Ready) {
        Logger.d("Icons", "Font loaded successfully:", currentFontLoader.name, "(version " + fontVersion + ")")
        fontReloaded()
      } else if (currentFontLoader.status === FontLoader.Error) {
        Logger.e("Icons", "Font failed to load (version " + fontVersion + ")")
      }
    })
  }

  function reloadFont() {
    Logger.d("Icons", "Forcing font reload...")
    fontVersion++
    loadFontWithCacheBusting()
  }
}
