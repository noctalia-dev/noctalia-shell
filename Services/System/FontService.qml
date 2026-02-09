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
  property bool fontsLoaded: false
  property bool isLoading: false

  function init() {
    if (fontsLoaded || isLoading)
      return;
    Logger.i("Font", "Service started");
    loadFontsViaFcList();
  }

  // Load all fonts using fc-list in background - no main thread blocking
  function loadFontsViaFcList() {
    if (isLoading)
      return;
    isLoading = true;
    allFontsProcess.running = true;
  }

  function populateModels(allFontsText, monoFontsText) {
    // Parse monospace fonts into a lookup set
    // fc-list returns comma-separated family names for fonts with multiple families
    var monoLookup = {};
    var monoLines = monoFontsText.split('\n');
    for (var i = 0; i < monoLines.length; i++) {
      var line = monoLines[i].trim();
      if (line) {
        var monoFamilies = line.split(',');
        for (var mi = 0; mi < monoFamilies.length; mi++) {
          var monoName = monoFamilies[mi].trim();
          if (monoName)
            monoLookup[monoName] = true;
        }
      }
    }

    // Parse all fonts - split comma-separated family names
    var allLines = allFontsText.split('\n');
    var fontSet = {}; // Deduplicate font families

    for (var j = 0; j < allLines.length; j++) {
      var line = allLines[j].trim();
      if (line) {
        var families = line.split(',');
        for (var fi = 0; fi < families.length; fi++) {
          var fontName = families[fi].trim();
          if (fontName && !fontSet[fontName]) {
            fontSet[fontName] = true;
          }
        }
      }
    }

    // Sort font names
    var sortedFonts = Object.keys(fontSet).sort(function (a, b) {
      return a.localeCompare(b);
    });

    // Build arrays for batch insert
    var allBatch = [];
    var monoBatch = [];

    for (var k = 0; k < sortedFonts.length; k++) {
      var name = sortedFonts[k];
      var fontObj = {
        "key": name,
        "name": name
      };
      allBatch.push(fontObj);

      // Check if monospace
      if (monoLookup[name] || name.toLowerCase().includes("mono")) {
        monoBatch.push(fontObj);
      }
    }

    // Clear and populate models (single batch operation)
    availableFonts.clear();
    monospaceFonts.clear();

    availableFonts.append({
                            "key": Qt.application.font.family,
                            "name": I18n.tr("panels.indicator.system-default")
                          });
    monospaceFonts.append({
                            "key": "monospace",
                            "name": I18n.tr("panels.indicator.system-default")
                          });

    for (var m = 0; m < allBatch.length; m++)
      availableFonts.append(allBatch[m]);
    for (var n = 0; n < monoBatch.length; n++)
      monospaceFonts.append(monoBatch[n]);

    fontsLoaded = true;
    isLoading = false;
    Logger.i("Font", "Loaded", availableFonts.count, "fonts,", monospaceFonts.count, "monospace");
  }

  // Temporary storage for process outputs
  property string _allFontsOutput: ""
  property string _monoFontsOutput: ""
  property bool _allFontsDone: false
  property bool _monoFontsDone: false

  function checkBothProcessesDone() {
    if (_allFontsDone && _monoFontsDone) {
      populateModels(_allFontsOutput, _monoFontsOutput);
      // Clear temp storage
      _allFontsOutput = "";
      _monoFontsOutput = "";
      _allFontsDone = false;
      _monoFontsDone = false;
    }
  }

  // Process to get all font families (runs in background)
  Process {
    id: allFontsProcess
    command: ["fc-list", "--format", "%{family}\\n"]
    running: false

    stdout: StdioCollector {
      onStreamFinished: {
        root._allFontsOutput = this.text;
        root._allFontsDone = true;
        root.checkBothProcessesDone();
      }
    }

    onRunningChanged: {
      if (running) {
        // Start mono fonts process in parallel
        monoFontsProcess.running = true;
      }
    }

    onExited: function (exitCode, exitStatus) {
      if (exitCode !== 0) {
        Logger.w("Font", "fc-list failed with exit code", exitCode);
        root._allFontsOutput = "";
        root._allFontsDone = true;
        root.checkBothProcessesDone();
      }
    }
  }

  // Process to get monospace font families (runs in background, parallel)
  Process {
    id: monoFontsProcess
    command: ["fc-list", ":mono", "--format", "%{family}\\n"]
    running: false

    stdout: StdioCollector {
      onStreamFinished: {
        root._monoFontsOutput = this.text;
        root._monoFontsDone = true;
        root.checkBothProcessesDone();
      }
    }

    onExited: function (exitCode, exitStatus) {
      if (exitCode !== 0) {
        root._monoFontsOutput = "";
        root._monoFontsDone = true;
        root.checkBothProcessesDone();
      }
    }
  }
}
