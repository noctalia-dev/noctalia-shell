import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.Compositor
import qs.Services.Noctalia
import qs.Services.System
import qs.Services.UI
import qs.Widgets

ColumnLayout {
  id: root
  opacity: 0

  onSystemInfoLoadingChanged: {
    if (!systemInfoLoading)
      tabAppearAnim.start();
  }

  NumberAnimation on opacity {
    id: tabAppearAnim
    from: 0
    to: 1
    duration: Style.animationSlowest
    easing.type: Easing.OutCubic
    running: false
  }

  property string latestVersion: GitHubService.latestVersion
  property string currentVersion: UpdateService.currentVersion
  property string commitInfo: ""

  readonly property bool isGitVersion: root.currentVersion.endsWith("-git")
  readonly property int giga: (1024 * 1024 * 1024)

  // Update status: compare versions (strip -git suffix for comparison)
  readonly property string installedBase: root.currentVersion.replace("-git", "")
  readonly property bool updateAvailable: {
    if (!root.latestVersion || !root.installedBase)
      return false;
    return root.latestVersion !== root.installedBase && !root.isGitVersion;
  }
  readonly property bool isUpToDate: {
    if (!root.latestVersion || !root.installedBase)
      return false;
    return root.latestVersion === root.installedBase;
  }

  // System info properties
  property var systemInfo: null
  property bool systemInfoLoading: true
  property bool systemInfoAvailable: true

  spacing: Style.marginL

  function getModule(type) {
    if (!root.systemInfo)
      return null;
    return root.systemInfo.find(m => m.type === type);
  }

  function getMonitorsText(separator) {
    const sep = separator || "\n";
    const screens = Quickshell.screens || [];
    const scales = CompositorService.displayScales || {};
    let lines = [];
    for (let i = 0; i < screens.length; i++) {
      const screen = screens[i];
      const name = screen.name || "Unknown";
      const scaleData = scales[name];
      const scaleValue = (typeof scaleData === "object" && scaleData !== null) ? (scaleData.scale || 1.0) : (scaleData || 1.0);
      lines.push(name + ": " + screen.width + "x" + screen.height + " @ " + scaleValue + "x");
    }
    return lines.join(sep);
  }

  function getTelemetryPayload() {
    const screens = Quickshell.screens || [];
    const scales = CompositorService.displayScales || {};
    const monitors = [];
    for (let i = 0; i < screens.length; i++) {
      const screen = screens[i];
      const name = screen.name || "Unknown";
      const scaleData = scales[name];
      const scaleValue = (typeof scaleData === "object" && scaleData !== null) ? (scaleData.scale || 1.0) : (scaleData || 1.0);
      monitors.push({
        width: screen.width || 0,
        height: screen.height || 0,
        scale: scaleValue
      });
    }
    return {
      instanceId: TelemetryService.getInstanceId(),
      version: UpdateService.currentVersion,
      compositor: CompositorService.isHyprland ? "Hyprland" : CompositorService.isNiri ? "Niri" : CompositorService.isSway ? "Sway" : CompositorService.isMango ? "MangoWC" : CompositorService.isLabwc ? "LabWC" : "Unknown",
      os: HostService.osPretty || "Unknown",
      ramGb: Math.round((root.getModule("Memory")?.result?.total || 0) / root.giga),
      monitors: monitors,
      ui: {
        scaleRatio: Settings.data.general.scaleRatio,
        fontDefaultScale: Settings.data.ui.fontDefaultScale,
        fontFixedScale: Settings.data.ui.fontFixedScale
      }
    };
  }

  function copyTelemetryData() {
    const payload = getTelemetryPayload();
    const json = JSON.stringify(payload, null, 2);
    Quickshell.execDetached(["wl-copy", json]);
    ToastService.showNotice(I18n.tr("panels.about.telemetry-title"), I18n.tr("panels.about.telemetry-data-copied"));
  }

  function copyInfoToClipboard() {
    let info = "Noctalia Shell\n";
    info += "==============\n";
    info += "Installed version: " + root.currentVersion + "\n";
    if (root.isGitVersion && root.commitInfo) {
      info += "Git commit: " + root.commitInfo + "\n";
    }
    info += "\nSystem Information\n";
    info += "==================\n";
    if (root.systemInfo) {
      const os = root.getModule("OS");
      const kernel = root.getModule("Kernel");
      const title = root.getModule("Title");
      const product = root.getModule("Host");
      const cpu = root.getModule("CPU");
      const gpu = root.getModule("GPU");
      const mem = root.getModule("Memory");
      const wm = root.getModule("WM");
      info += "OS: " + (os?.result?.prettyName || "N/A") + "\n";
      info += "Kernel: " + (kernel?.result?.release || "N/A") + "\n";
      info += "Host: " + (title?.result?.hostName || "N/A") + "\n";
      info += "Product: " + (product?.result?.name || "N/A") + "\n";
      info += "CPU: " + (cpu?.result?.cpu || "N/A") + "\n";
      if (gpu?.result && Array.isArray(gpu.result) && gpu.result.length > 0) {
        info += "GPU: " + gpu.result.map(g => g.name || "Unknown").join(", ") + "\n";
      }
      if (mem?.result) {
        info += "Memory: " + SystemStatService.formatMemoryGb(mem.result.total / root.giga) + "\n";
      }
      if (wm?.result) {
        info += "WM: " + (wm.result.prettyName || wm.result.processName || "N/A") + "\n";
      }
    }
    const monitors = getMonitorsText("\n").split("\n");
    for (const mon of monitors) {
      info += "Monitor: " + mon + "\n";
    }
    info += "\nSettings\n";
    info += "========\n";
    info += "UI Scale: " + Settings.data.general.scaleRatio + "\n";
    info += "Default Font: " + (Settings.data.ui.fontDefault || "default") + " @ " + Settings.data.ui.fontDefaultScale + "x\n";
    info += "Fixed Font: " + (Settings.data.ui.fontFixed || "default") + " @ " + Settings.data.ui.fontFixedScale + "x\n";
    Quickshell.execDetached(["wl-copy", info]);
    ToastService.showNotice(I18n.tr("panels.about.title"), I18n.tr("panels.about.info-copied"));
  }

  Component.onCompleted: {
    // Check if fastfetch is available before trying to run it
    checkFastfetchProcess.running = true;

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

  // Check if fastfetch is available before attempting to run it
  Process {
    id: checkFastfetchProcess
    command: ["sh", "-c", "command -v fastfetch"]
    running: false

    onExited: function (exitCode) {
      if (exitCode === 0) {
        // fastfetch is available, run it
        Logger.d("VersionSubTab", "fastfetch found, running it");
        fastfetchProcess.running = true;
      } else {
        // fastfetch not found, show error state immediately
        Logger.w("VersionSubTab", "fastfetch not found");
        root.systemInfoLoading = false;
        root.systemInfoAvailable = false;
      }
    }

    stdout: StdioCollector {}
    stderr: StdioCollector {}
  }

  Process {
    id: fastfetchProcess
    command: ["fastfetch", "--format", "json", "--config", "none"]
    running: false

    onExited: function (exitCode) {
      root.systemInfoLoading = false;
      if (exitCode === 0) {
        try {
          root.systemInfo = JSON.parse(stdout.text);
          root.systemInfoAvailable = true;
        } catch (e) {
          Logger.w("VersionSubTab", "Failed to parse fastfetch JSON: " + e);
          root.systemInfoAvailable = false;
        }
      } else {
        root.systemInfoAvailable = false;
      }
    }

    stdout: StdioCollector {}
    stderr: StdioCollector {}
  }

  RowLayout {
    Layout.alignment: Qt.AlignHCenter
    spacing: Style.marginXL

    // Noctalia logo
    Item {
      id: themedLogoContainer
      width: 96 * Style.uiScaleRatio
      height: width
      Layout.alignment: Qt.AlignBottom

      // Stack the 4 layers in order (Back to Front)
      LogoLayer {
        source: "../../../../../Assets/noctalia1.svg"
        darkColor: Color.mOnPrimary
        lightColor: Color.mTertiary
      }
      LogoLayer {
        source: "../../../../../Assets/noctalia2.svg"
        darkColor: Color.mPrimary
        lightColor: Color.mOnTertiary
      }
      LogoLayer {
        source: "../../../../../Assets/noctalia3.svg"
        darkColor: Color.mOnSurface
        lightColor: Color.mSurfaceVariant
      }
      LogoLayer {
        source: "../../../../../Assets/noctalia4.svg"
        darkColor: Color.mSecondary
        lightColor: Color.mSecondary
      }
    }
    ColumnLayout {
      NHeader {
        label: I18n.tr("panels.about.noctalia-title")
        // description: I18n.tr("panels.about.noctalia-desc")
      }

      // Versions
      GridLayout {
        columns: 2
        rowSpacing: Style.marginXS
        columnSpacing: Style.marginM

        NText {
          text: I18n.tr("panels.about.noctalia-latest-version")
          color: Color.mOnSurfaceVariant
          Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
        }

        NText {
          text: root.latestVersion
          color: Color.mOnSurface
          font.weight: Style.fontWeightBold
        }

        NText {
          text: I18n.tr("panels.about.noctalia-installed-version")
          color: Color.mOnSurfaceVariant
          Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
        }

        RowLayout {
          spacing: Style.marginS

          NText {
            text: root.currentVersion
            color: Color.mOnSurface
            font.weight: Style.fontWeightBold
          }

          // Update status indicator
          NIcon {
            id: upToDateIcon
            visible: root.isUpToDate
            icon: "circle-check"
            pointSize: Style.fontSizeM
            color: Color.mPrimary

            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              onEntered: TooltipService.show(upToDateIcon, I18n.tr("panels.about.up-to-date"))
              onExited: TooltipService.hide()
            }
          }

          NIcon {
            id: updateAvailableIcon
            visible: root.updateAvailable
            icon: "arrow-up-circle"
            pointSize: Style.fontSizeS
            color: Color.mPrimary

            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              onEntered: TooltipService.show(updateAvailableIcon, I18n.tr("panels.about.update-available"))
              onExited: TooltipService.hide()
            }
          }
        }

        NText {
          visible: root.isGitVersion
          text: I18n.tr("panels.about.noctalia-git-commit")
          color: Color.mOnSurfaceVariant
          Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
        }

        // Clickable git commit
        NText {
          id: commitText
          visible: root.isGitVersion
          text: root.commitInfo || I18n.tr("common.loading")
          color: root.commitInfo ? Color.mPrimary : Color.mOnSurface
          pointSize: Style.fontSizeXS
          font.underline: commitMouseArea.containsMouse && root.commitInfo

          MouseArea {
            id: commitMouseArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: root.commitInfo ? Qt.PointingHandCursor : Qt.ArrowCursor
            onEntered: {
              if (root.commitInfo) {
                TooltipService.show(commitText, I18n.tr("panels.about.view-commit"));
              }
            }
            onExited: TooltipService.hide()
            onClicked: {
              if (root.commitInfo) {
                Quickshell.execDetached(["xdg-open", "https://github.com/noctalia-dev/noctalia-shell/commit/" + root.commitInfo]);
              }
            }
          }
        }
      }
    }
  }

  // Helper component to apply theme colors to each layer
  component LogoLayer: Item {
    property alias source: layerImage.source
    property color lightColor: "white"
    property color darkColor: "black"
    readonly property color activeColor: Settings.data.colorSchemes.darkMode ? darkColor : lightColor

    anchors.fill: parent

    Image {
      id: layerImage
      anchors.fill: parent
      visible: false // Source must be hidden or MultiEffect renders twice
      smooth: true
      fillMode: Image.PreserveAspectFit
    }

    MultiEffect {
      source: layerImage
      anchors.fill: layerImage
      colorization: 1.0
      colorizationColor: activeColor
      brightness: 0.5
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
      icon: "copy"
      text: I18n.tr("panels.about.copy-info")
      outlined: true
      onClicked: root.copyInfoToClipboard()
    }

    NButton {
      icon: "heart"
      text: I18n.tr("panels.about.support")
      outlined: true
      onClicked: {
        Quickshell.execDetached(["xdg-open", "https://buymeacoffee.com/noctalia"]);
        ToastService.showNotice(I18n.tr("panels.about.support"), I18n.tr("toast.kofi-opened"));
      }
    }
  }

  // System Information Section
  NDivider {
    Layout.fillWidth: true
  }

  NHeader {
    label: I18n.tr("panels.about.system-title")
  }

  // Error state (fastfetch not installed)
  ColumnLayout {
    visible: !root.systemInfoAvailable
    Layout.fillWidth: true
    spacing: Style.marginS

    NText {
      text: I18n.tr("panels.about.system-not-installed")
      color: Color.mOnSurfaceVariant
    }

    NText {
      text: I18n.tr("panels.about.system-install-hint")
      color: Color.mOnSurfaceVariant
      pointSize: Style.fontSizeXS
    }
  }

  // System info grid
  GridLayout {
    id: sysInfo
    readonly property real textSize: Style.fontSizeS

    visible: root.systemInfoAvailable && root.systemInfo
    Layout.fillWidth: true
    columns: 2
    rowSpacing: Style.marginXS
    columnSpacing: Style.marginM

    // OS
    NText {
      text: I18n.tr("panels.about.system-os")
      color: Color.mOnSurfaceVariant
      pointSize: sysInfo.textSize
    }
    NText {
      text: {
        const os = root.getModule("OS");
        return os?.result?.prettyName || "N/A";
      }
      color: Color.mOnSurface
      pointSize: sysInfo.textSize
      Layout.fillWidth: true
      wrapMode: Text.Wrap
    }

    // Kernel
    NText {
      text: I18n.tr("panels.about.system-kernel")
      color: Color.mOnSurfaceVariant
      pointSize: sysInfo.textSize
    }
    NText {
      text: {
        const kernel = root.getModule("Kernel");
        return kernel?.result?.release || "N/A";
      }
      color: Color.mOnSurface
      pointSize: sysInfo.textSize
      Layout.fillWidth: true
      wrapMode: Text.Wrap
    }

    // Host
    NText {
      text: I18n.tr("panels.about.system-host")
      color: Color.mOnSurfaceVariant
      pointSize: sysInfo.textSize
    }
    NText {
      text: {
        const title = root.getModule("Title");
        return title?.result?.hostName || "N/A";
      }
      color: Color.mOnSurface
      pointSize: sysInfo.textSize
      Layout.fillWidth: true
      wrapMode: Text.Wrap
    }

    // Product name
    NText {
      text: I18n.tr("panels.about.system-product")
      color: Color.mOnSurfaceVariant
      pointSize: sysInfo.textSize
    }
    NText {
      text: {
        const title = root.getModule("Host");
        return title?.result?.name || "N/A";
      }
      color: Color.mOnSurface
      pointSize: sysInfo.textSize
      Layout.fillWidth: true
      wrapMode: Text.Wrap
    }

    // Uptime
    NText {
      text: I18n.tr("panels.about.system-uptime")
      color: Color.mOnSurfaceVariant
      pointSize: sysInfo.textSize
    }
    NText {
      text: {
        const value = root.getModule("Uptime")?.result?.uptime;
        return value ? Time.formatVagueHumanReadableDuration(value / 1000) : "-";
      }
      color: Color.mOnSurface
      pointSize: sysInfo.textSize
      Layout.fillWidth: true
      wrapMode: Text.Wrap
    }

    // CPU
    NText {
      text: I18n.tr("panels.about.system-cpu")
      color: Color.mOnSurfaceVariant
      pointSize: sysInfo.textSize
    }
    NText {
      text: {
        const cpu = root.getModule("CPU");
        if (!cpu?.result)
          return "N/A";
        let cpuText = cpu.result.cpu || "N/A";
        const cores = cpu.result.cores;
        if (cores?.logical) {
          cpuText += " (" + cores.logical + " threads)";
        }
        return cpuText;
      }
      color: Color.mOnSurface
      pointSize: sysInfo.textSize
      Layout.fillWidth: true
      wrapMode: Text.Wrap
    }

    // GPU
    NText {
      text: I18n.tr("panels.about.system-gpu")
      color: Color.mOnSurfaceVariant
      pointSize: sysInfo.textSize
    }
    NText {
      text: {
        const gpu = root.getModule("GPU");
        if (!gpu?.result || !Array.isArray(gpu.result) || gpu.result.length === 0)
          return "N/A";
        return gpu.result.map(g => g.name || "Unknown").join(", ");
      }
      color: Color.mOnSurface
      pointSize: sysInfo.textSize
      Layout.fillWidth: true
      wrapMode: Text.Wrap
    }

    // Memory
    NText {
      text: I18n.tr("panels.about.system-memory")
      color: Color.mOnSurfaceVariant
      pointSize: sysInfo.textSize
    }
    NText {
      text: {
        const mem = root.getModule("Memory");
        if (!mem?.result)
          return "N/A";
        const used = SystemStatService.formatMemoryGb(mem.result.used / root.giga);
        const total = SystemStatService.formatMemoryGb(mem.result.total / root.giga);
        return used + " / " + total;
      }
      color: Color.mOnSurface
      pointSize: sysInfo.textSize
      Layout.fillWidth: true
      wrapMode: Text.Wrap
    }

    // Disk
    NText {
      text: I18n.tr("panels.about.system-disk")
      color: Color.mOnSurfaceVariant
      pointSize: sysInfo.textSize
    }
    NText {
      text: {
        const disk = root.getModule("Disk");
        if (!disk?.result || !Array.isArray(disk.result) || disk.result.length === 0)
          return "N/A";
        const rootDisk = disk.result.find(d => d.mountpoint === "/");
        if (!rootDisk?.bytes)
          return "N/A";
        const used = SystemStatService.formatMemoryGb(rootDisk.bytes.used / root.giga);
        const total = SystemStatService.formatMemoryGb(rootDisk.bytes.total / root.giga);
        return used + " / " + total + " (" + rootDisk.filesystem + ")";
      }
      color: Color.mOnSurface
      pointSize: sysInfo.textSize
      Layout.fillWidth: true
      wrapMode: Text.Wrap
    }

    // WM
    NText {
      text: I18n.tr("panels.about.system-wm")
      color: Color.mOnSurfaceVariant
      pointSize: sysInfo.textSize
    }
    NText {
      text: {
        const wm = root.getModule("WM");
        if (!wm?.result)
          return "N/A";
        let wmText = wm.result.prettyName || wm.result.processName || "N/A";
        if (wm.result.protocolName) {
          wmText += " (" + wm.result.protocolName + ")";
        }
        return wmText;
      }
      color: Color.mOnSurface
      pointSize: sysInfo.textSize
      Layout.fillWidth: true
      wrapMode: Text.Wrap
    }

    // Packages
    NText {
      text: I18n.tr("panels.about.system-packages")
      color: Color.mOnSurfaceVariant
      pointSize: sysInfo.textSize
    }
    NText {
      text: {
        const pkg = root.getModule("Packages");
        if (!pkg?.result)
          return "N/A";
        const result = pkg.result;
        if (result.all) {
          const managers = [];
          if (result.rpm > 0)
            managers.push("rpm: " + result.rpm);
          if (result.pacman > 0)
            managers.push("pacman: " + result.pacman);
          if (result.dpkg > 0)
            managers.push("dpkg: " + result.dpkg);
          if (result.flatpakSystem > 0 || result.flatpakUser > 0) {
            const flatpak = (result.flatpakSystem || 0) + (result.flatpakUser || 0);
            managers.push("flatpak: " + flatpak);
          }
          if (result.snap > 0)
            managers.push("snap: " + result.snap);
          if (result.nixSystem > 0 || result.nixUser > 0 || result.nixDefault > 0) {
            const nix = (result.nixSystem || 0) + (result.nixUser || 0) + (result.nixDefault || 0);
            managers.push("nix: " + nix);
          }
          if (result.brew > 0)
            managers.push("brew: " + result.brew);
          if (managers.length > 0) {
            return result.all + " (" + managers.join(", ") + ")";
          }
          return result.all.toString();
        }
        return "N/A";
      }
      color: Color.mOnSurface
      pointSize: sysInfo.textSize
      Layout.fillWidth: true
      wrapMode: Text.Wrap
    }

    // Monitors (2 items per screen: label + value)
    Repeater {
      model: Quickshell.screens.length * 2

      NText {
        readonly property int screenIndex: Math.floor(index / 2)
        readonly property bool isLabel: index % 2 === 0
        readonly property var screen: Quickshell.screens[screenIndex]

        text: {
          if (isLabel)
            return I18n.tr("panels.about.system-monitor");
          const name = screen?.name || "Unknown";
          const scales = CompositorService.displayScales || {};
          const scaleData = scales[name];
          const scaleValue = (typeof scaleData === "object" && scaleData !== null) ? (scaleData.scale || 1.0) : (scaleData || 1.0);
          return name + ": " + (screen?.width || 0) + "x" + (screen?.height || 0) + " @ " + scaleValue + "x";
        }
        color: isLabel ? Color.mOnSurfaceVariant : Color.mOnSurface
        pointSize: sysInfo.textSize
        Layout.fillWidth: !isLabel
        wrapMode: Text.Wrap
      }
    }
  }

  // Telemetry Section
  NDivider {
    Layout.fillWidth: true
    Layout.topMargin: Style.marginL
  }

  NHeader {
    label: I18n.tr("panels.about.telemetry-title")
  }

  NToggle {
    Layout.fillWidth: true
    label: I18n.tr("panels.about.telemetry-enabled")
    description: I18n.tr("panels.about.telemetry-desc")
    checked: Settings.data.general.telemetryEnabled
    onToggled: checked => Settings.data.general.telemetryEnabled = checked
  }

  RowLayout {
    spacing: Style.marginM

    NButton {
      icon: "eye"
      text: I18n.tr("panels.about.telemetry-show-data")
      outlined: true
      onClicked: root.copyTelemetryData()
    }

    NButton {
      icon: "shield-lock"
      text: I18n.tr("panels.about.privacy-policy")
      outlined: true
      onClicked: Quickshell.execDetached(["xdg-open", "https://noctalia.dev/privacy"])
    }
  }
}
