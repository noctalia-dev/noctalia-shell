import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.Noctalia
import qs.Services.System
import qs.Services.UI
import qs.Widgets

ColumnLayout {
  id: root

  property string latestVersion: GitHubService.latestVersion
  property string currentVersion: UpdateService.currentVersion
  property string commitInfo: ""

  readonly property bool isGitVersion: root.currentVersion.endsWith("-git")

  spacing: Style.marginL

  Component.onCompleted: {
    Logger.d("VersionSubTab", "Current version:", root.currentVersion);
    Logger.d("VersionSubTab", "Is git version:", root.isGitVersion);
    // Only fetch commit info for -git versions
    if (root.isGitVersion) {
      // On NixOS, extract commit hash from the store path first
      if (HostService.isNixOS) {
        var shellDir = Quickshell.shellDir || "";
        Logger.d("VersionSubTab", "Component.onCompleted - NixOS detected, shellDir:", shellDir);
        if (shellDir) {
          // Extract commit hash from path like: /nix/store/...-noctalia-shell-2025-11-30_225e6d3/share/noctalia-shell
          // Pattern matches: noctalia-shell-YYYY-MM-DD_<commit_hash>
          var match = shellDir.match(/noctalia-shell-\d{4}-\d{2}-\d{2}_([0-9a-f]{7,})/i);
          if (match && match[1]) {
            // Use first 7 characters of the commit hash
            root.commitInfo = match[1].substring(0, 7);
            Logger.d("VersionSubTab", "Component.onCompleted - Extracted commit from NixOS path:", root.commitInfo);
            return;
          } else {
            Logger.d("VersionSubTab", "Component.onCompleted - Could not extract commit from NixOS path, trying fallback");
          }
        }
        fetchGitCommit();
        return;
      } else {
        // On non-NixOS systems, check for pacman first.
        whichPacmanProcess.running = true;
        return;
      }
    }
  }

  Timer {
    id: gitFallbackTimer
    interval: 500
    running: false
    onTriggered: {
      if (!root.commitInfo) {
        fetchGitCommit();
      }
    }
  }

  Process {
    id: whichPacmanProcess
    command: ["sh", "-c", "command -v pacman"]
    running: false
    onExited: function (exitCode) {
      if (exitCode === 0) {
        Logger.d("VersionSubTab", "whichPacmanProcess - pacman found, starting query");
        pacmanProcess.running = true;
        gitFallbackTimer.start();
      } else {
        Logger.d("VersionSubTab", "whichPacmanProcess - pacman not found, falling back to git");
        fetchGitCommit();
      }
    }
  }

  Process {
    id: pacmanProcess
    command: ["pacman", "-Q", "noctalia-shell-git"]
    running: false

    onStarted: {
      gitFallbackTimer.stop();
    }

    onExited: function (exitCode) {
      gitFallbackTimer.stop();
      Logger.d("VersionSubTab", "pacmanProcess - Process exited with code:", exitCode);
      if (exitCode === 0) {
        var output = stdout.text.trim();
        Logger.d("VersionSubTab", "pacmanProcess - Output:", output);
        var match = output.match(/noctalia-shell-git\s+(.+)/);
        if (match && match[1]) {
          // For Arch packages, the version format might be like: 3.4.0.r112.g3f00bec8-1
          // Extract just the commit hash part if it exists
          var version = match[1];
          var commitMatch = version.match(/\.g([0-9a-f]{7,})/i);
          if (commitMatch && commitMatch[1]) {
            // Show short hash (first 7 characters)
            root.commitInfo = commitMatch[1].substring(0, 7);
            Logger.d("VersionSubTab", "pacmanProcess - Set commitInfo from Arch package:", root.commitInfo);
            return; // Successfully got commit hash from Arch package
          } else {
            // If no commit hash in version format, still try git repo
            Logger.d("VersionSubTab", "pacmanProcess - No commit hash in version, trying git");
            fetchGitCommit();
          }
        } else {
          // Unexpected output format, try git
          Logger.d("VersionSubTab", "pacmanProcess - Unexpected output format, trying git");
          fetchGitCommit();
        }
      } else {
        // If not on Arch, try to get git commit from repository
        Logger.d("VersionSubTab", "pacmanProcess - Package not found, trying git");
        fetchGitCommit();
      }
    }

    stdout: StdioCollector {}
    stderr: StdioCollector {}
  }

  function fetchGitCommit() {
    var shellDir = Quickshell.shellDir || "";
    Logger.d("VersionSubTab", "fetchGitCommit - shellDir:", shellDir);
    if (!shellDir) {
      Logger.d("VersionSubTab", "fetchGitCommit - Cannot determine shell directory, skipping git commit fetch");
      return;
    }

    gitProcess.workingDirectory = shellDir;
    gitProcess.running = true;
  }

  Process {
    id: gitProcess
    command: ["git", "rev-parse", "--short", "HEAD"]
    running: false

    onExited: function (exitCode) {
      Logger.d("VersionSubTab", "gitProcess - Process exited with code:", exitCode);
      if (exitCode === 0) {
        var gitOutput = stdout.text.trim();
        Logger.d("VersionSubTab", "gitProcess - gitOutput:", gitOutput);
        if (gitOutput) {
          root.commitInfo = gitOutput;
          Logger.d("VersionSubTab", "gitProcess - Set commitInfo to:", root.commitInfo);
        }
      } else {
        Logger.d("VersionSubTab", "gitProcess - Git command failed. Exit code:", exitCode);
      }
    }

    stdout: StdioCollector {}
    stderr: StdioCollector {}
  }

  NHeader {
    label: I18n.tr("panels.about.noctalia-title")
    description: I18n.tr("panels.about.noctalia-desc")
  }

  RowLayout {
    Layout.alignment: Qt.AlignHCenter
    spacing: Style.marginXL

    // Noctalia logo
    Image {
      source: "../../../../../Assets/noctalia.svg"
      width: Style.fontSizeXXXL * 2.5 * Style.uiScaleRatio
      height: width
      fillMode: Image.PreserveAspectFit
      sourceSize.width: width
      sourceSize.height: height
      mipmap: true
      smooth: true
      Layout.alignment: Qt.AlignVCenter
    }

    // Versions
    GridLayout {
      columns: 2
      rowSpacing: Style.marginXS
      columnSpacing: Style.marginS

      NText {
        text: I18n.tr("panels.about.noctalia-latest-version")
        color: Color.mOnSurface
      }

      NText {
        text: root.latestVersion
        color: Color.mOnSurface
        font.weight: Style.fontWeightBold
      }

      NText {
        text: I18n.tr("panels.about.noctalia-installed-version")
        color: Color.mOnSurface
      }

      NText {
        text: root.currentVersion
        color: Color.mOnSurface
        font.weight: Style.fontWeightBold
      }

      NText {
        visible: root.isGitVersion
        text: I18n.tr("panels.about.noctalia-git-commit")
        color: Color.mOnSurface
      }

      NText {
        visible: root.isGitVersion
        text: root.commitInfo || I18n.tr("common.loading")
        color: Color.mOnSurface
        font.weight: Style.fontWeightBold
        font.family: root.commitInfo ? "monospace" : ""
        pointSize: Style.fontSizeXS
      }
    }
  }

  // Action buttons row
  RowLayout {
    Layout.alignment: Qt.AlignHCenter
    Layout.topMargin: Style.marginM
    Layout.bottomMargin: Style.marginM
    spacing: Style.marginM

    NButton {
      icon: "sparkles"
      text: I18n.tr("panels.about.changelog")
      outlined: true
      onClicked: {
        var screen = PanelService.openedPanel?.screen || Quickshell.screens[0];
        UpdateService.viewChangelog(screen);
      }
    }

    NButton {
      icon: "heart"
      text: I18n.tr("panels.about.support")
      outlined: true
      onClicked: {
        Quickshell.execDetached(["xdg-open", "https://ko-fi.com/lysec"]);
        ToastService.showNotice(I18n.tr("panels.about.support"), I18n.tr("toast.kofi-opened"));
      }
    }
  }
}
