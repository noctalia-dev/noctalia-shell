import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.Noctalia
import qs.Services.System
import qs.Widgets

ColumnLayout {
  id: root

  property string latestVersion: GitHubService.latestVersion
  property string currentVersion: UpdateService.currentVersion
  property var contributors: GitHubService.contributors
  property string commitInfo: ""
  property int avatarCacheVersion: 0

  readonly property int topContributorsCount: 20

  Connections {
    target: GitHubService
    function onCachedAvatarsChanged() {
      root.avatarCacheVersion++;
    }
  }
  readonly property bool isGitVersion: root.currentVersion.endsWith("-git")

  spacing: Style.marginL

  Component.onCompleted: {
    Logger.d("AboutTab", "Component.onCompleted - Current version:", root.currentVersion);
    Logger.d("AboutTab", "Component.onCompleted - Is git version:", root.isGitVersion);
    // Only fetch commit info for -git versions
    if (root.isGitVersion) {
      // On NixOS, extract commit hash from the store path first
      if (HostService.isNixOS) {
        var shellDir = Quickshell.shellDir || "";
        Logger.d("AboutTab", "Component.onCompleted - NixOS detected, shellDir:", shellDir);
        if (shellDir) {
          // Extract commit hash from path like: /nix/store/...-noctalia-shell-2025-11-30_225e6d3/share/noctalia-shell
          // Pattern matches: noctalia-shell-YYYY-MM-DD_<commit_hash>
          var match = shellDir.match(/noctalia-shell-\d{4}-\d{2}-\d{2}_([0-9a-f]{7,})/i);
          if (match && match[1]) {
            // Use first 7 characters of the commit hash
            root.commitInfo = match[1].substring(0, 7);
            Logger.d("AboutTab", "Component.onCompleted - Extracted commit from NixOS path:", root.commitInfo);
            return;
          } else {
            Logger.d("AboutTab", "Component.onCompleted - Could not extract commit from NixOS path, trying fallback");
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
    command: ["which", "pacman"]
    running: false
    onExited: function (exitCode) {
      if (exitCode === 0) {
        Logger.d("AboutTab", "whichPacmanProcess - pacman found, starting query");
        pacmanProcess.running = true;
        gitFallbackTimer.start();
      } else {
        Logger.d("AboutTab", "whichPacmanProcess - pacman not found, falling back to git");
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
      Logger.d("AboutTab", "pacmanProcess - Process exited with code:", exitCode);
      if (exitCode === 0) {
        var output = stdout.text.trim();
        Logger.d("AboutTab", "pacmanProcess - Output:", output);
        var match = output.match(/noctalia-shell-git\s+(.+)/);
        if (match && match[1]) {
          // For Arch packages, the version format might be like: 3.4.0.r112.g3f00bec8-1
          // Extract just the commit hash part if it exists
          var version = match[1];
          var commitMatch = version.match(/\.g([0-9a-f]{7,})/i);
          if (commitMatch && commitMatch[1]) {
            // Show short hash (first 7 characters)
            root.commitInfo = commitMatch[1].substring(0, 7);
            Logger.d("AboutTab", "pacmanProcess - Set commitInfo from Arch package:", root.commitInfo);
            return; // Successfully got commit hash from Arch package
          } else {
            // If no commit hash in version format, still try git repo
            Logger.d("AboutTab", "pacmanProcess - No commit hash in version, trying git");
            fetchGitCommit();
          }
        } else {
          // Unexpected output format, try git
          Logger.d("AboutTab", "pacmanProcess - Unexpected output format, trying git");
          fetchGitCommit();
        }
      } else {
        // If not on Arch, try to get git commit from repository
        Logger.d("AboutTab", "pacmanProcess - Package not found, trying git");
        fetchGitCommit();
      }
    }

    stdout: StdioCollector {}
    stderr: StdioCollector {}
  }

  function fetchGitCommit() {
    var shellDir = Quickshell.shellDir || "";
    Logger.d("AboutTab", "fetchGitCommit - shellDir:", shellDir);
    if (!shellDir) {
      Logger.d("AboutTab", "fetchGitCommit - Cannot determine shell directory, skipping git commit fetch");
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
      Logger.d("AboutTab", "gitProcess - Process exited with code:", exitCode);
      if (exitCode === 0) {
        var gitOutput = stdout.text.trim();
        Logger.d("AboutTab", "gitProcess - gitOutput:", gitOutput);
        if (gitOutput) {
          root.commitInfo = gitOutput;
          Logger.d("AboutTab", "gitProcess - Set commitInfo to:", root.commitInfo);
        }
      } else {
        Logger.d("AboutTab", "gitProcess - Git command failed. Exit code:", exitCode);
      }
    }

    stdout: StdioCollector {}
    stderr: StdioCollector {}
  }

  NHeader {
    label: I18n.tr("settings.about.noctalia.section.label")
    description: I18n.tr("settings.about.noctalia.section.description")
  }

  RowLayout {
    spacing: Style.marginXL

    // Versions
    GridLayout {
      columns: 2
      rowSpacing: Style.marginXS
      columnSpacing: Style.marginS

      NText {
        text: I18n.tr("settings.about.noctalia.latest-version")
        color: Color.mOnSurface
      }

      NText {
        text: root.latestVersion
        color: Color.mOnSurface
        font.weight: Style.fontWeightBold
      }

      NText {
        text: I18n.tr("settings.about.noctalia.installed-version")
        color: Color.mOnSurface
      }

      NText {
        text: root.currentVersion
        color: Color.mOnSurface
        font.weight: Style.fontWeightBold
      }

      NText {
        visible: root.isGitVersion
        text: I18n.tr("settings.about.noctalia.git-commit")
        color: Color.mOnSurface
      }

      NText {
        visible: root.isGitVersion
        text: root.commitInfo || I18n.tr("settings.about.noctalia.git-commit-loading")
        color: Color.mOnSurface
        font.weight: Style.fontWeightBold
        font.family: root.commitInfo ? "monospace" : ""
        pointSize: Style.fontSizeXS
      }
    }
  }

  // Ko-fi support button
  Rectangle {
    Layout.alignment: Qt.AlignHCenter
    Layout.topMargin: Style.marginM
    Layout.bottomMargin: Style.marginM
    width: supportRow.implicitWidth + Style.marginXL
    height: supportRow.implicitHeight + Style.marginM
    radius: Style.radiusS
    color: supportArea.containsMouse ? Qt.alpha(Color.mOnSurface, 0.05) : Color.transparent
    border.width: 0

    Behavior on color {
      ColorAnimation {
        duration: Style.animationFast
      }
    }

    RowLayout {
      id: supportRow
      anchors.centerIn: parent
      spacing: Style.marginS

      NText {
        text: I18n.tr("settings.about.support")
        pointSize: Style.fontSizeXS
        color: Color.mOnSurface
        opacity: supportArea.containsMouse ? Style.opacityFull : Style.opacityMedium
      }

      NIcon {
        icon: supportArea.containsMouse ? "heart-filled" : "heart"
        pointSize: 14
        color: Color.mOnSurface
        opacity: supportArea.containsMouse ? Style.opacityFull : Style.opacityMedium
      }
    }

    MouseArea {
      id: supportArea
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: {
        Quickshell.execDetached(["xdg-open", "https://ko-fi.com/lysec"]);
        ToastService.showNotice(I18n.tr("settings.about.support"), I18n.tr("toast.kofi.opened"));
      }
    }
  }

  NDivider {
    Layout.fillWidth: true
    Layout.topMargin: Style.marginXXXL
    Layout.bottomMargin: Style.marginL
  }

  // Contributors
  NHeader {
    label: I18n.tr("settings.about.contributors.section.label")
    description: root.contributors.length === 1 ? I18n.tr("settings.about.contributors.section.description", {
                                                            "count": root.contributors.length
                                                          }) : I18n.tr("settings.about.contributors.section.description_plural", {
                                                                         "count": root.contributors.length
                                                                       })
    enableDescriptionRichText: true
  }

  // Top 20 contributors with full cards (avoids GridView shader crashes on Qt 6.8)
  Flow {
    id: topContributorsFlow
    Layout.alignment: Qt.AlignHCenter
    Layout.fillWidth: true
    spacing: Style.marginM

    Repeater {
      model: Math.min(root.contributors.length, root.topContributorsCount)

      delegate: Rectangle {
        width: Math.max(Math.round(topContributorsFlow.width / 2 - Style.marginM - 1), Math.round(Style.baseWidgetSize * 4))
        height: Math.round(Style.baseWidgetSize * 2.3)
        radius: Style.radiusM
        color: contributorArea.containsMouse ? Color.mHover : Color.transparent
        border.width: 1
        border.color: contributorArea.containsMouse ? Color.mPrimary : Color.mOutline

        Behavior on color {
          ColorAnimation {
            duration: Style.animationFast
          }
        }

        Behavior on border.color {
          ColorAnimation {
            duration: Style.animationFast
          }
        }

        RowLayout {
          anchors.fill: parent
          anchors.margins: Style.marginM
          spacing: Style.marginM

          // Avatar container with rectangular design (modern, no shader issues)
          Item {
            id: wrapper
            Layout.alignment: Qt.AlignVCenter
            Layout.preferredWidth: Style.baseWidgetSize * 1.8
            Layout.preferredHeight: Style.baseWidgetSize * 1.8

            property bool isRounded: false

            // Background and image container
            Item {
              anchors.fill: parent

              // Simple circular image (pre-rendered, no shaders)
              Image {
                anchors.fill: parent
                source: {
                  // Depend on avatarCacheVersion to trigger re-evaluation
                  var _ = root.avatarCacheVersion;
                  // Try cached circular version first
                  var username = root.contributors[index].login;
                  var cached = GitHubService.getAvatarPath(username);
                  if (cached) {
                    wrapper.isRounded = true;
                    return cached;
                  }

                  // Fall back to original avatar URL
                  return root.contributors[index].avatar_url || "";
                }
                fillMode: Image.PreserveAspectFit // Fit since image is already circular with transparency
                mipmap: true
                smooth: true
                asynchronous: true
                visible: root.contributors[index].avatar_url !== undefined && root.contributors[index].avatar_url !== ""
                opacity: status === Image.Ready ? 1.0 : 0.0

                Behavior on opacity {
                  NumberAnimation {
                    duration: Style.animationFast
                  }
                }
              }

              // Fallback icon
              NIcon {
                anchors.centerIn: parent
                visible: !root.contributors[index].avatar_url || root.contributors[index].avatar_url === ""
                icon: "person"
                pointSize: Style.fontSizeL
                color: Color.mPrimary
              }
            }

            Rectangle {
              visible: wrapper.isRounded
              anchors.fill: parent
              color: Color.transparent
              radius: width * 0.5
              border.width: Style.borderM
              border.color: Color.mPrimary
            }
          }

          // Info column
          ColumnLayout {
            spacing: 2
            Layout.alignment: Qt.AlignVCenter
            Layout.fillWidth: true

            NText {
              text: root.contributors[index].login || "Unknown"
              font.weight: Style.fontWeightBold
              color: contributorArea.containsMouse ? Color.mOnHover : Color.mOnSurface
              elide: Text.ElideRight
              Layout.fillWidth: true
              pointSize: Style.fontSizeS
            }

            RowLayout {
              spacing: Style.marginXS
              Layout.fillWidth: true

              NIcon {
                icon: "git-commit"
                pointSize: Style.fontSizeXS
                color: contributorArea.containsMouse ? Color.mOnHover : Color.mOnSurfaceVariant
              }

              NText {
                text: `${(root.contributors[index].contributions || 0).toString()} commits`
                pointSize: Style.fontSizeXS
                color: contributorArea.containsMouse ? Color.mOnHover : Color.mOnSurfaceVariant
              }
            }
          }

          // Hover indicator
          NIcon {
            Layout.alignment: Qt.AlignVCenter
            icon: "arrow-right"
            pointSize: Style.fontSizeS
            color: Color.mPrimary
            opacity: contributorArea.containsMouse ? 1.0 : 0.0

            Behavior on opacity {
              NumberAnimation {
                duration: Style.animationFast
              }
            }
          }
        }

        MouseArea {
          id: contributorArea
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: {
            if (root.contributors[index].html_url)
              Quickshell.execDetached(["xdg-open", root.contributors[index].html_url]);
          }
        }
      }
    }
  }

  // Remaining contributors (simple text links)
  Flow {
    id: remainingContributorsFlow
    visible: root.contributors.length > root.topContributorsCount
    Layout.alignment: Qt.AlignHCenter
    Layout.fillWidth: true
    Layout.topMargin: Style.marginL
    spacing: Style.marginS

    Repeater {
      model: Math.max(0, root.contributors.length - root.topContributorsCount)

      delegate: Rectangle {
        width: nameText.implicitWidth + Style.marginM * 2
        height: nameText.implicitHeight + Style.marginS * 2
        radius: Style.radiusS
        color: nameArea.containsMouse ? Color.mHover : Color.transparent
        border.width: Style.borderS
        border.color: nameArea.containsMouse ? Color.mPrimary : Color.mOutline

        Behavior on color {
          ColorAnimation {
            duration: Style.animationFast
          }
        }

        Behavior on border.color {
          ColorAnimation {
            duration: Style.animationFast
          }
        }

        NText {
          id: nameText
          anchors.centerIn: parent
          text: root.contributors[index + root.topContributorsCount].login || "Unknown"
          pointSize: Style.fontSizeXS
          color: nameArea.containsMouse ? Color.mOnHover : Color.mOnSurface
          font.weight: Style.fontWeightMedium

          Behavior on color {
            ColorAnimation {
              duration: Style.animationFast
            }
          }
        }

        MouseArea {
          id: nameArea
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: {
            if (root.contributors[index + root.topContributorsCount].html_url)
              Quickshell.execDetached(["xdg-open", root.contributors[index + root.topContributorsCount].html_url]);
          }
        }
      }
    }
  }

  NDivider {
    Layout.fillWidth: true
    Layout.topMargin: Style.marginL
    Layout.bottomMargin: Style.marginL
  }
}
