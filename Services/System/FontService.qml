pragma Singleton

import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons

Singleton {
  id: root

  property ListModel availableFonts: ListModel {}
  property ListModel monospaceFonts: ListModel {}
  property ListModel displayFonts: ListModel {}
  property bool fontsLoaded: false
  property bool isLoading: false

  // Use objects for O(1) lookup instead of arrays
  property var fontconfigMonospaceFonts: ({})

  // Cache for font classification to avoid repeated checks
  property var fontCache: ({})

  // Chunk size for async processing
  readonly property int chunkSize: 100

  // -------------------------------------------
  function init() {
    Logger.i("Font", "Service started")
    loadFontconfigMonospaceFonts()
  }

  function loadFontconfigMonospaceFonts() {
    fontconfigProcess.command = ["fc-list", ":mono", "family"]
    fontconfigProcess.running = true
  }

  function loadSystemFonts() {
    if (isLoading)
      return

    Logger.d("Font", "Loading system fonts...")
    isLoading = true

    var fontFamilies = Qt.fontFamilies()

    // Pre-sort fonts before processing to ensure consistent order
    fontFamilies.sort(function (a, b) {
      return a.localeCompare(b)
    })

    // Clear existing models
    availableFonts.clear()
    monospaceFonts.clear()
    displayFonts.clear()
    fontCache = {}

    // Process fonts in chunks to avoid blocking
    processFontsAsync(fontFamilies, 0)
  }

  function processFontsAsync(fontFamilies, startIndex) {
    var endIndex = Math.min(startIndex + chunkSize, fontFamilies.length)
    var hasMore = endIndex < fontFamilies.length

    // Batch arrays to append all at once (much faster than individual appends)
    var availableBatch = []
    var monospaceBatch = []
    var displayBatch = []

    for (var i = startIndex; i < endIndex; i++) {
      var fontName = fontFamilies[i]
      if (!fontName || fontName.trim() === "")
        continue

      // Add to available fonts
      var fontObj = {
        "key": fontName,
        "name": fontName
      }
      availableBatch.push(fontObj)

      // Check monospace (with caching)
      if (isMonospaceFont(fontName)) {
        monospaceBatch.push(fontObj)
      }

      // Check display font (with caching)
      if (isDisplayFont(fontName)) {
        displayBatch.push(fontObj)
      }
    }

    // Batch append to models
    batchAppendToModel(availableFonts, availableBatch)
    batchAppendToModel(monospaceFonts, monospaceBatch)
    batchAppendToModel(displayFonts, displayBatch)

    if (hasMore) {
      // Continue processing in next frame
      Qt.callLater(function () {
        processFontsAsync(fontFamilies, endIndex)
      })
    } else {
      // Finished loading all fonts
      finalizeFontLoading()
    }
  }

  function batchAppendToModel(model, items) {
    for (var i = 0; i < items.length; i++) {
      model.append(items[i])
    }
  }

  function finalizeFontLoading() {
    // Add fallbacks if needed (models are already sorted)
    if (monospaceFonts.count === 0) {
      addFallbackFonts(monospaceFonts, ["DejaVu Sans Mono"])
    }

    if (displayFonts.count === 0) {
      addFallbackFonts(displayFonts, ["Inter", "Roboto", "DejaVu Sans"])
    }

    fontsLoaded = true
    isLoading = false
    Logger.d("Font", "Loaded", availableFonts.count, "fonts:", monospaceFonts.count, "monospace,", displayFonts.count, "display")
  }

  function isMonospaceFont(fontName) {
    // Check cache first
    if (fontCache.hasOwnProperty(fontName)) {
      return fontCache[fontName].isMonospace
    }

    var result = false

    // O(1) lookup using object instead of indexOf
    if (fontconfigMonospaceFonts.hasOwnProperty(fontName)) {
      result = true
    } else {
      // Fallback: check for basic monospace patterns
      var lowerFontName = fontName.toLowerCase()
      if (lowerFontName.includes("mono") || lowerFontName.includes("monospace")) {
        result = true
      }
    }

    // Cache the result
    if (!fontCache[fontName]) {
      fontCache[fontName] = {}
    }
    fontCache[fontName].isMonospace = result

    return result
  }

  function isDisplayFont(fontName) {
    // Check cache first
    if (fontCache.hasOwnProperty(fontName) && fontCache[fontName].hasOwnProperty('isDisplay')) {
      return fontCache[fontName].isDisplay
    }

    var result = false
    var lowerFontName = fontName.toLowerCase()

    if (lowerFontName.includes("display") || lowerFontName.includes("headline") || lowerFontName.includes("title")) {
      result = true
    }

    // Essential fallback fonts only
    var essentialFonts = ["Inter", "Roboto", "DejaVu Sans"]
    if (essentialFonts.indexOf(fontName) !== -1) {
      result = true
    }

    // Cache the result
    if (!fontCache[fontName]) {
      fontCache[fontName] = {}
    }
    fontCache[fontName].isDisplay = result

    return result
  }

  function sortModel(model) {
    // Convert to array
    var fontsArray = []
    for (var i = 0; i < model.count; i++) {
      fontsArray.push({
                        "key": model.get(i).key,
                        "name": model.get(i).name
                      })
    }

    // Sort
    fontsArray.sort(function (a, b) {
      return a.name.localeCompare(b.name)
    })

    // Clear and rebuild
    model.clear()
    batchAppendToModel(model, fontsArray)
  }

  function addFallbackFonts(model, fallbackFonts) {
    // Build a set of existing fonts for O(1) lookup
    var existingFonts = {}
    for (var i = 0; i < model.count; i++) {
      existingFonts[model.get(i).name] = true
    }

    var toAdd = []
    for (var j = 0; j < fallbackFonts.length; j++) {
      var fontName = fallbackFonts[j]
      if (!existingFonts[fontName]) {
        toAdd.push({
                     "key": fontName,
                     "name": fontName
                   })
      }
    }

    if (toAdd.length > 0) {
      batchAppendToModel(model, toAdd)
      sortModel(model)
    }
  }

  function searchFonts(query) {
    if (!query || query.trim() === "")
      return availableFonts

    var results = []
    var lowerQuery = query.toLowerCase()

    for (var i = 0; i < availableFonts.count; i++) {
      var font = availableFonts.get(i)
      if (font.name.toLowerCase().includes(lowerQuery)) {
        results.push(font)
      }
    }

    return results
  }

  // Process for fontconfig commands
  Process {
    id: fontconfigProcess
    running: false

    stdout: StdioCollector {
      onStreamFinished: {
        if (this.text !== "") {
          var lines = this.text.split('\n')
          // Use object for O(1) lookup instead of array
          var monospaceLookup = {}

          for (var i = 0; i < lines.length; i++) {
            var line = lines[i].trim()
            if (line && line !== "") {
              monospaceLookup[line] = true
            }
          }

          fontconfigMonospaceFonts = monospaceLookup
        }
        loadSystemFonts()
      }
    }

    onExited: function (exitCode, exitStatus) {
      if (exitCode !== 0) {
        fontconfigMonospaceFonts = {}
      }
      loadSystemFonts()
    }
  }
}
