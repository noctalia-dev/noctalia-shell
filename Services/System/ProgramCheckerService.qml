pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.Theming

// Service to check if various programs are available on the system
Singleton {
  id: root

  // Program availability properties
  property bool matugenAvailable: false
  property bool nmcliAvailable: false
  property bool wlsunsetAvailable: false
  property bool app2unitAvailable: false
  property bool gnomeCalendarAvailable: false
  property bool wtypeAvailable: false

  // Programs to check - maps property names to commands
  readonly property var programsToCheck: ({
                                            "matugenAvailable": ["sh", "-c", "command -v matugen"],
                                            "nmcliAvailable": ["sh", "-c", "command -v nmcli"],
                                            "wlsunsetAvailable": ["sh", "-c", "command -v wlsunset"],
                                            "app2unitAvailable": ["sh", "-c", "command -v app2unit"],
                                            "gnomeCalendarAvailable": ["sh", "-c", "command -v gnome-calendar"],
                                            "wtypeAvailable": ["sh", "-c", "command -v wtype"]
                                          })

  // Discord client auto-detection
  property var availableDiscordClients: []

  // Code client auto-detection
  property var availableCodeClients: []

  // Signal emitted when all checks are complete
  signal checksCompleted

  // Function to detect Discord client by checking config directories
  function detectDiscordClient() {
    // Build shell script to check each client
    var scriptParts = ["available_clients=\"\";"];

    for (var i = 0; i < TemplateRegistry.discordClients.length; i++) {
      var client = TemplateRegistry.discordClients[i];
      var clientName = client.name;
      var configPath = client.configPath;

      // Use the actual config path from the client, removing ~ prefix
      var checkPath = configPath.startsWith("~") ? configPath.substring(2) : configPath.substring(1);

      // Check if this client requires themes folder to exist
      if (client.requiresThemesFolder) {
        scriptParts.push("if [ -d \"$HOME/" + checkPath + "/themes\" ]; then available_clients=\"$available_clients " + clientName + "\"; fi;");
      } else {
        scriptParts.push("if [ -d \"$HOME/" + checkPath + "\" ]; then available_clients=\"$available_clients " + clientName + "\"; fi;");
      }
    }

    scriptParts.push("echo \"$available_clients\"");

    // Use a Process to check directory existence for all clients
    discordDetector.command = ["sh", "-c", scriptParts.join(" ")];
    discordDetector.running = true;
  }

  // Process to detect Discord client directories
  Process {
    id: discordDetector
    running: false

    onExited: function (exitCode) {
      availableDiscordClients = [];

      if (exitCode === 0) {
        var detectedClients = stdout.text.trim().split(/\s+/).filter(function (client) {
          return client.length > 0;
        });

        if (detectedClients.length > 0) {
          // Build list of available clients
          for (var i = 0; i < detectedClients.length; i++) {
            var clientName = detectedClients[i];
            for (var j = 0; j < TemplateRegistry.discordClients.length; j++) {
              var client = TemplateRegistry.discordClients[j];
              if (client.name === clientName) {
                availableDiscordClients.push(client);
                break;
              }
            }
          }

          Logger.d("ProgramChecker", "Detected Discord clients:", detectedClients.join(", "));
        }
      }

      if (availableDiscordClients.length === 0) {
        Logger.d("ProgramChecker", "No Discord clients detected");
      }
    }

    stdout: StdioCollector {}
    stderr: StdioCollector {}
  }

  // Function to detect Code client by checking config directories
  function detectCodeClient() {
    // Build shell script to check each client
    var scriptParts = ["available_clients=\"\";"];

    for (var i = 0; i < TemplateRegistry.codeClients.length; i++) {
      var client = TemplateRegistry.codeClients[i];
      var clientName = client.name;
      var configPath = client.configPath;

      // Check if the config directory exists
      scriptParts.push("if [ -d \"$HOME" + configPath.substring(1) + "\" ]; then available_clients=\"$available_clients " + clientName + "\"; fi;");
    }

    scriptParts.push("echo \"$available_clients\"");

    // Use a Process to check directory existence for all clients
    codeDetector.command = ["sh", "-c", scriptParts.join(" ")];
    codeDetector.running = true;
  }

  // Process to detect Code client directories
  Process {
    id: codeDetector
    running: false

    onExited: function (exitCode) {
      availableCodeClients = [];

      if (exitCode === 0) {
        var detectedClients = stdout.text.trim().split(/\s+/).filter(function (client) {
          return client.length > 0;
        });

        if (detectedClients.length > 0) {
          // Build list of available clients
          for (var i = 0; i < detectedClients.length; i++) {
            var clientName = detectedClients[i];
            for (var j = 0; j < TemplateRegistry.codeClients.length; j++) {
              var client = TemplateRegistry.codeClients[j];
              if (client.name === clientName) {
                availableCodeClients.push(client);
                break;
              }
            }
          }

          Logger.d("ProgramChecker", "Detected Code clients:", detectedClients.join(", "));
        }
      }

      if (availableCodeClients.length === 0) {
        Logger.d("ProgramChecker", "No Code clients detected");
      }
    }

    stdout: StdioCollector {}
    stderr: StdioCollector {}
  }

  // Internal tracking
  property int completedChecks: 0
  property int totalChecks: Object.keys(programsToCheck).length

  // Single reusable Process object
  Process {
    id: checker
    running: false

    property string currentProperty: ""

    onExited: function (exitCode) {
      // Set the availability property
      root[currentProperty] = (exitCode === 0);

      // Stop the process to free resources
      running = false;

      // Track completion
      root.completedChecks++;

      // Check next program or emit completion signal
      if (root.completedChecks >= root.totalChecks) {
        // Run Discord and Code client detection after all checks are complete
        root.detectDiscordClient();
        root.detectCodeClient();
        root.checksCompleted();
      } else {
        root.checkNextProgram();
      }
    }

    stdout: StdioCollector {}
    stderr: StdioCollector {}
  }

  // Queue of programs to check
  property var checkQueue: []
  property int currentCheckIndex: 0

  // Function to check the next program in the queue
  function checkNextProgram() {
    if (currentCheckIndex >= checkQueue.length)
      return;
    var propertyName = checkQueue[currentCheckIndex];
    var command = programsToCheck[propertyName];

    checker.currentProperty = propertyName;
    checker.command = command;
    checker.running = true;

    currentCheckIndex++;
  }

  // Function to run all program checks
  function checkAllPrograms() {
    // Reset state
    completedChecks = 0;
    currentCheckIndex = 0;
    checkQueue = Object.keys(programsToCheck);

    // Start first check
    if (checkQueue.length > 0) {
      checkNextProgram();
    }
  }

  // Function to check a specific program
  function checkProgram(programProperty) {
    if (!programsToCheck.hasOwnProperty(programProperty)) {
      Logger.w("ProgramChecker", "Unknown program property:", programProperty);
      return;
    }

    checker.currentProperty = programProperty;
    checker.command = programsToCheck[programProperty];
    checker.running = true;
  }

  // Manual function to test Discord detection (for debugging)
  function testDiscordDetection() {
    Logger.d("ProgramChecker", "Testing Discord detection...");
    Logger.d("ProgramChecker", "HOME:", Quickshell.env("HOME"));

    // Test each client directory
    for (var i = 0; i < TemplateRegistry.discordClients.length; i++) {
      var client = TemplateRegistry.discordClients[i];
      var configDir = client.configPath.replace("~", Quickshell.env("HOME"));
      Logger.d("ProgramChecker", "Checking:", configDir);
    }

    detectDiscordClient();
  }

  // Initialize checks when service is created
  Component.onCompleted: {
    checkAllPrograms();
  }
}
