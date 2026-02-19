pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

Singleton {
  id: root

  // Public properties
  property string osPretty: ""
  property string osLogo: ""
  property bool isNixOS: false
  property bool isReady: false

  // User info
  readonly property string username: (Quickshell.env("USER") || "")
  readonly property string envRealName: (Quickshell.env("NOCTALIA_REALNAME") || "")
  property string realName: ""

  // Machine info
  property string hostName: ""

  // Internal: pending logo name for fallback after probe fails
  property string pendingLogoName: ""

  readonly property string displayName: {
    // Explicit override
    if (envRealName && envRealName.length > 0) {
      return envRealName;
    }

    // Name from getent
    if (realName && realName.length > 0) {
      return realName;
    }

    // Fallback: capitalized $USER
    if (username && username.length > 0) {
      return username.charAt(0).toUpperCase() + username.slice(1);
    }

    // Last resort: placeholder
    return "User";
  }

  function init() {
    Logger.i("HostService", "Service started");
  }

  // Internal helpers
  function buildCandidates(name) {
    const n = (name || "").trim();
    if (!n)
      return [];

    const sizes = ["512x512", "256x256", "128x128", "64x64", "48x48", "32x32", "24x24", "22x22", "16x16"];
    const exts = ["svg", "png"];
    const candidates = [];

    // pixmaps
    for (const ext of exts) {
      candidates.push(`/usr/share/pixmaps/${n}.${ext}`);
    }

    // hicolor scalable and raster sizes
    candidates.push(`/usr/share/icons/hicolor/scalable/apps/${n}.svg`);
    for (const s of sizes) {
      for (const ext of exts) {
        candidates.push(`/usr/share/icons/hicolor/${s}/apps/${n}.${ext}`);
      }
    }

    // NixOS hicolor paths
    candidates.push(`/run/current-system/sw/share/icons/hicolor/scalable/apps/${n}.svg`);
    for (const s of sizes) {
      for (const ext of exts) {
        candidates.push(`/run/current-system/sw/share/icons/hicolor/${s}/apps/${n}.${ext}`);
      }
    }

    // Generic icon themes under /usr/share/icons (common cases)
    for (const ext of exts) {
      candidates.push(`/usr/share/icons/${n}.${ext}`);
      candidates.push(`/usr/share/icons/${n}/${n}.${ext}`);
      candidates.push(`/usr/share/icons/${n}/apps/${n}.${ext}`);
    }

    return candidates;
  }

  function resolveLogo(name) {
    const n = (name || "").trim();
    if (!n)
      return;

    // First try Quickshell's icon lookup for direct file paths
    try {
      const path = Quickshell.iconPath(n, "");
      if (path && path !== "" && !path.startsWith("image://")) {
        // Got a direct file path - use it
        const finalPath = path.startsWith("file://") ? path : "file://" + path;
        root.osLogo = finalPath;
        Logger.d("HostService", "Found logo via icon theme:", root.osLogo);
        return;
      }
    } catch (e) {
      // Ignore and continue to manual probe
    }

    // Try manual probing for hicolor/pixmaps paths
    // Store name for fallback to image:// URI if probe fails
    root.pendingLogoName = n;
    const all = buildCandidates(n);
    if (all.length === 0) {
      // No candidates, try image:// URI directly
      root.osLogo = `image://icon/${n}`;
      Logger.d("HostService", "Using theme icon URI:", root.osLogo);
      return;
    }
    const script = all.map(p => `if [ -f "${p}" ]; then echo "${p}"; exit 0; fi`).join("; ") + "; exit 1";
    probe.command = ["sh", "-c", script];
    probe.running = true;
  }

  // Read /etc/os-release and trigger resolution
  FileView {
    id: osInfo
    path: "/etc/os-release"
    onLoaded: {
      try {
        const lines = text().split("\n");
        const val = k => {
          const l = lines.find(x => x.startsWith(k + "="));
          return l ? l.split("=")[1].replace(/"/g, "") : "";
        };
        root.osPretty = val("PRETTY_NAME") || val("NAME");
        Logger.i("HostService", "Detected", root.osPretty);

        const osId = (val("ID") || "").toLowerCase();
        root.isNixOS = osId === "nixos" || (root.osPretty || "").toLowerCase().includes("nixos");
        const logoName = val("LOGO");
        Logger.i("HostService", "Looking for logo icon:", logoName);
        if (logoName) {
          resolveLogo(logoName);
        }
        root.isReady = true;
      } catch (e) {
        Logger.w("HostService", "failed to read os-release", e);
      }
    }
  }

  Process {
    id: probe
    onExited: code => {
      const p = String(stdout.text || "").trim();
      if (code === 0 && p) {
        root.osLogo = `file://${p}`;
        root.pendingLogoName = "";
        Logger.d("HostService", "Found", root.osLogo);
      } else if (root.pendingLogoName) {
        // Manual probe failed, fallback to image:// URI (theme icon)
        root.osLogo = `image://icon/${root.pendingLogoName}`;
        root.pendingLogoName = "";
        Logger.d("HostService", "Using theme icon URI:", root.osLogo);
      } else {
        root.osLogo = "";
        Logger.w("HostService", "No distro logo found");
      }
    }
    stdout: StdioCollector {}
    stderr: StdioCollector {}
  }

  // Resolve GECOS real name once on startup
  Process {
    id: realNameProcess
    command: ["sh", "-c", "getent passwd \"$USER\" | cut -d: -f5 | cut -d, -f1"]
    running: true

    stdout: StdioCollector {
      onStreamFinished: {
        const name = String(text || "").trim();
        if (name.length > 0) {
          root.realName = name;
          Logger.i("HostService", "resolved real name", name);
        }
      }
    }
    stderr: StdioCollector {}
  }

  // Read /etc/hostname
  FileView {
    id: hostName
    path: "/etc/hostname"
    onLoaded: {
      const name = text().trim();
      if (name) {
        root.hostName = name;
        Logger.i("HostService", "resolved hostname", name);
      }
    }
  }
}
